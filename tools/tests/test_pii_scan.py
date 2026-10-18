"""Tests for tools/pii_scan.py and the end-to-end log probe tools/pii_log_probe.py (T-014).

Run from the repository root (the end-to-end tests import the cardflow package):

    uv run --project services/api pytest tools/tests
"""

import json
import logging
import os
import re
import subprocess
import sys
import uuid
from pathlib import Path
from typing import Final

import pytest
from starlette.types import Scope

import pii_log_probe
import pii_scan
from cardflow.api.middleware import request_context
from cardflow.settings import SECRET_FIELDS, LogFormat, Settings

TOOLS: Final = Path(__file__).resolve().parents[1]
SCANNER: Final = TOOLS / "pii_scan.py"
CLEAN_LOG: Final = TOOLS / "pii_samples" / "clean.log"
DIRTY_LOG: Final = TOOLS / "pii_samples" / "dirty.log"

FULLWIDTH_COLON: Final = chr(0xFF1A)
JWT: Final = pii_log_probe.SAMPLE_JWT

# FILE:LINE:FIELD:RULE where FIELD only ever holds ASCII identifier characters, dots,
# list indexes, "<key>" or "-": no room for any logged text.
OUTPUT_LINE: Final = re.compile(
    r"(?P<source>.+):(?P<line>\d+):(?P<field>-|[A-Za-z0-9_.<>\[\]-]+):(?P<rule>[a-z0-9_]+)"
)


def found(line: str) -> set[tuple[str, str]]:
    """``(field, rule)`` pairs hit by one line."""
    return {(hit.field, hit.rule) for hit in pii_scan.scan_line(line)}


def rules(line: str) -> set[str]:
    """Rule names hit by one line."""
    return {hit.rule for hit in pii_scan.scan_line(line)}


def example_ids(examples: list[tuple[str, str]]) -> list[str]:
    """``rule-1``, ``rule-2``...: test ids that do not repeat the (synthetic) sample text."""
    seen: dict[str, int] = {}
    ids: list[str] = []
    for rule, _ in examples:
        seen[rule] = seen.get(rule, 0) + 1
        ids.append(f"{rule}-{seen[rule]}")
    return ids


# --------------------------------------------------------------------- rules: positives

POSITIVE: Final = [
    # amount: currency marker before or after a number
    ("amount", '{"message":"repayment recorded ¥8,000.00"}'),
    ("amount", '{"message":"refund ￥1,234.56"}'),
    ("amount", "paid CNY 8000 today"),
    ("amount", "paid rmb8000"),
    ("amount", "还款 8000元"),
    ("amount", "额度提升至 1.2万元"),
    ("amount", "转入 100 人民币"),
    ("amount", '{"note":"8,000.00 CNY"}'),
    ("amount", "GET /healthz?amount=%C2%A58%2C000.00"),
    # amount_field: numeric value in an amount-like field
    ("amount_field", '{"amount_minor":800000}'),
    ("amount_field", '{"amount":"8,000.00"}'),
    ("amount_field", '{"creditLimit":5000000}'),
    ("amount_field", '{"balance_after":-12.5}'),
    ("amount_field", '{"fee":0}'),
    ("amount_field", '{"limit":50000}'),
    ("amount_field", '{"amount":{"value":800000,"currency":"CNY"}}'),
    ("amount_field", '{"amounts":[100,200]}'),
    ("amount_field", "repayment amount_minor=800000"),
    ("amount_field", f"金额{FULLWIDTH_COLON}8000"),
    ("amount_field", '{"message":"retry amount_minor=800000"}'),
    # card_number: 13-19 digits, separators allowed, Luhn-valid
    ("card_number", '{"message":"card 4111 1111 1111 1111"}'),
    ("card_number", "pan=5555555555554444"),
    ("card_number", "card 4012-8888-8888-1881 added"),
    ("card_number", '{"amex":"3782 822463 10005"}'),
    ("card_number", '{"n":6011111111111117}'),
    ("card_number", "卡号6200000000000005已绑定"),
    ("card_number", "GET /x?card=4111+1111+1111+1111"),
    ("card_number", "card 4111 1111 1111 1111 2026"),
    # card_last4: card tail in context
    ("card_last4", "尾号1234的卡"),
    ("card_last4", f"卡片末四位{FULLWIDTH_COLON}0042"),
    ("card_last4", '{"message":"Visa ending in 1881"}'),
    ("card_last4", "last4=4444"),
    ("card_last4", '{"last_four":"0042"}'),
    ("card_last4", '{"cardLast4":4444}'),
    ("card_last4", "**** **** **** 4444"),
    ("card_last4", "XXXX-XXXX-XXXX-1111"),
    # jwt
    ("jwt", f'{{"detail":"{JWT}"}}'),
    ("jwt", f"issued {JWT} to device"),
    # authorization
    ("authorization", "Authorization: Bearer 9f8e7d6c5b4a39281706f5e4d3c2b1a0"),
    ("authorization", '{"headers":{"Authorization":"Basic dGVzdHVzZXI6dGVzdHBhc3M="}}'),
    ("authorization", "sent with bearer abc123.def456"),
    ("authorization", '{"authorization":"opaque"}'),
    ("authorization", "proxy-authorization=Digest 0123abcd"),
    # credential_field
    ("credential_field", '{"password":"hunter2-not-real"}'),
    ("credential_field", "refresh_token=r3fr35h-t0k3n-n0t-r34l"),
    ("credential_field", '{"X-Api-Key":"test-key-1"}'),
    ("credential_field", '{"cvv":"123"}'),
    ("credential_field", '{"短信验证码":"654321"}'),
    # sensitive_field
    ("sensitive_field", '{"merchant":"虚构测试商户"}'),
    ("sensitive_field", '{"payee_name":"Fictional Shop"}'),
    ("sensitive_field", "phone=13800138000"),
    ("sensitive_field", '{"email":"someone"}'),
    ("sensitive_field", '{"收款方":"测试"}'),
    # cn_id_card
    ("cn_id_card", '{"id":"11010519491231002X"}'),
    ("cn_id_card", "身份证 11010519491231002x 已登记"),
    ("cn_id_card", "id=440300199001010016"),
    # cn_mobile
    ("cn_mobile", '{"message":"sms to 13800138000"}'),
    ("cn_mobile", "tel +86 138-0013-8000"),
    ("cn_mobile", "0086 150 0000 0000"),
    ("cn_mobile", "手机15000000000"),
    # email
    ("email", '{"message":"statement mailed to zhang.san@example.com"}'),
    ("email", "reply-to: li.si+bills@mail.example.org"),
    # secret_string
    ("secret_string", '{"message":"kek MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY="}'),
    ("secret_string", '{"value":"c0ffee00deadbeef0123456789abcdef0a1b2c3d"}'),
    ("secret_string", "key=9f8e7d6c5b4a39281706f5e4d3c2b1a0"),
    ("secret_string", "Q2FyZEZsb3dUZXN0S2V5MDEyMzQ1Njc4OWFiY2RlZg"),
    ("secret_string", "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7"),
]

# -------------------------------------------------------------------- rules: negatives

NEGATIVE: Final = [
    ("amount", "3元组 and 元数据"),
    ("amount", '{"currency":"CNY"}'),
    ("amount", "version 1.2.3 build 8000"),
    ("amount", "RMBX100"),
    ("amount_field", '{"amount":"pending"}'),
    ("amount_field", '{"amount_mismatch":true}'),
    ("amount_field", '{"minor_version":2}'),
    ("amount_field", '{"rate_limit_window_s":600}'),
    ("amount_field", '{"feedback_count":3}'),
    ("amount_field", '{"limited":5}'),
    ("card_number", "4111111111111112"),  # Luhn fails
    ("card_number", "1760627496829"),  # Luhn-valid epoch milliseconds: first digit 1
    ("card_number", "411111111111"),  # 12 digits
    ("card_number", "41111111111111111111"),  # 20 digits
    ("card_number", "2026-10-16 15:11:36"),
    ("card_number", "id a4111111111111111b"),  # glued to letters
    ("card_number", "138 0013 8000"),
    ("card_last4", "尾号未知"),
    ("card_last4", "last4 missing"),
    ("card_last4", "ending in 12345"),
    ("card_last4", '{"last4":"12345"}'),
    ("card_last4", '{"last4":"abcd"}'),
    ("card_last4", '{"path":"/v1/cards/{card_id}/last4"}'),
    ("jwt", "eyJhbGciOiJIUzI1NiJ9"),
    ("jwt", "cardflow.api.middleware"),
    ("authorization", "uses Bearer authentication"),
    ("authorization", "authorization denied for device"),  # no key=value: plain words
    ("authorization", "Basic dGVzdA=="),  # base64 of "test": not user:pass
    ("authorization", '{"authorization":"[REDACTED]"}'),
    ("credential_field", '{"token":""}'),
    ("credential_field", '{"password":"***"}'),
    ("credential_field", '{"token_type":"Bearer"}'),
    ("credential_field", '{"max_tokens":5}'),
    ("credential_field", '{"dek_wrapped":true}'),
    ("sensitive_field", '{"merchant_id":"0f0e0d0c-0b0a-4908-8706-050403020100"}'),
    ("sensitive_field", '{"phone_verified":true}'),
    ("sensitive_field", '{"email":null}'),
    ("cn_id_card", "110105194912310021"),  # wrong check character
    ("cn_id_card", "11010519490230002X"),  # 30 February
    ("cn_id_card", "1101051949123100"),
    ("cn_mobile", "12800138000"),
    ("cn_mobile", "1380013800"),
    ("cn_mobile", "138001380001"),
    ("cn_mobile", "010-12345678"),
    ("cn_mobile", "hex a13800138000b"),
    ("email", "user@localhost"),
    ("email", "@example.com"),
    ("email", "decorator @app.get"),
    ("secret_string", "550e8400-e29b-41d4-a716-446655440000"),
    ("secret_string", "42263f7e401d4aec923537a3dc3a0eca"),  # uuid4().hex
    ("secret_string", "0123456789abcdef0123456789abcde"),  # 31 hex digits
    ("secret_string", "test_access_log_has_route_template_and_whitelisted_fields_only"),
    ("secret_string", "/projects/cardflow/services/api/.venv/lib/python3.13/site-packages"),
    ("secret_string", "abcdefghijklmnopqrstuvwxyzabcdefghij"),
]


@pytest.mark.parametrize(("rule", "line"), POSITIVE, ids=example_ids(POSITIVE))
def test_rule_detects_positive_example(rule: str, line: str) -> None:
    assert rule in rules(line)


@pytest.mark.parametrize(("rule", "line"), NEGATIVE, ids=example_ids(NEGATIVE))
def test_rule_ignores_near_miss(rule: str, line: str) -> None:
    assert rule not in rules(line)


def test_every_rule_has_positive_and_negative_examples() -> None:
    assert {rule for rule, _ in POSITIVE} == set(pii_scan.RULE_NAMES)
    assert {rule for rule, _ in NEGATIVE} == set(pii_scan.RULE_NAMES)


# ----------------------------------------------------------- whitelist and false positives

REAL_LOG_LINES: Final = [
    '{"ts":"2026-10-16T15:11:36.929+00:00","level":"info","logger":"cardflow.access",'
    '"message":"http_request","request_id":"42263f7e401d4aec923537a3dc3a0eca","method":"GET",'
    '"path":"/healthz","status":200,"duration_ms":0.987}',
    '{"ts":"2026-10-16T15:11:36.826+00:00","level":"info","logger":"uvicorn.error",'
    '"message":"Uvicorn running on http://127.0.0.1:18081 (Press CTRL+C to quit)"}',
    '{"ts":"2026-10-16T15:11:36.826+00:00","level":"info","logger":"uvicorn.error",'
    '"message":"Started server process [21880]"}',
    "2026-10-16T15:26:34.438+00:00 INFO     cardflow.access: http_request "
    'request_id="5bab78464d6444f4889adc83043f2934" method="GET" path="/v1/plans/{plan_id}" '
    "status=200 duration_ms=1.539",
    "2026-10-16T15:26:34.441+00:00 ERROR    cardflow.api: unhandled_exception "
    'request_id="e92129d3ea9048c3a68e85b526a64b55" exc_type="RuntimeError" '
    'exc_frames=["middleware/request_context.py:84:__call__", '
    '"starlette/_exception_handler.py:53:wrapped_app"]',
]


@pytest.mark.parametrize(
    "line",
    REAL_LOG_LINES,
    ids=["access-json", "uvicorn-running", "uvicorn-started", "access-text", "error-text"],
)
def test_real_log_lines_have_no_hits(line: str) -> None:
    assert pii_scan.scan_line(line) == []


def test_whitelisted_field_skips_rules_only_for_its_expected_shape() -> None:
    # The same digits: skipped in duration_ms (a number), a mobile number elsewhere.
    assert found('{"duration_ms":13800138000,"status":200,"method":"GET"}') == set()
    assert found('{"elapsed_ms":13800138000}') == {("elapsed_ms", "cn_mobile")}
    # A whitelisted field holding something else is scanned like any other field.
    assert found('{"status":"4111 1111 1111 1111"}') == {("status", "card_number")}
    assert found('{"request_id":"4111111111111111"}') == {("request_id", "card_number")}
    assert found('{"method":"13800138000"}') == {("method", "cn_mobile")}
    assert found('{"request_id":"9f8e7d6c5b4a39281706f5e4d3c2b1a0"}') == {
        ("request_id", "secret_string")
    }


def test_whitelist_applies_to_text_format_lines() -> None:
    head = "2026-10-16T15:26:34.438+00:00 INFO     cardflow.access: http_request"
    assert found(f"{head} status=200 duration_ms=13800138000") == set()
    assert found(f"{head} status=200 elapsed=13800138000") == {("elapsed", "cn_mobile")}


@pytest.mark.parametrize(
    "request_id",
    [uuid.uuid4().hex, str(uuid.uuid4()), "01928c4e7a3b7cde8f0123456789abcd"],
    ids=["uuid4-hex", "uuid4-canonical", "uuid7-hex"],
)
def test_request_ids_are_never_hits(request_id: str) -> None:
    assert found(json.dumps({"request_id": request_id})) == set()
    assert found(json.dumps({"message": f"retrying {request_id}"})) == set()


ROUTE_TEMPLATES: Final = [
    "/healthz",
    "<unmatched>",
    "/v1/plans/{plan_id}",
    "/v1/plans/{plan_id}/allocations",
    "/v1/workspaces/{workspace_id}/cards/{card_id}/statements/{statement_id}",
    "/v1/cards/{card_id}/last4",
    "/v1/files/{file_path:path}",
    "/_probe/items/{item_id}",
]


@pytest.mark.parametrize("template", ROUTE_TEMPLATES)
def test_route_templates_are_not_hits(template: str) -> None:
    assert found(json.dumps({"path": template})) == set()
    assert found(f'... INFO     cardflow.access: http_request path="{template}" status=200') == (
        set()
    )


def test_concrete_paths_are_scanned() -> None:
    assert found('{"path":"/v1/cards/4111111111111111"}') == {("path", "card_number")}
    assert found('{"path":"/v1/users/zhang.san@example.com"}') == {("path", "email")}


def test_overlapping_generic_matches_are_folded_into_the_specific_rule() -> None:
    assert found(json.dumps({"detail": JWT})) == {("detail", "jwt")}
    assert found("Authorization: Bearer 9f8e7d6c5b4a39281706f5e4d3c2b1a0") == {
        ("Authorization", "authorization")
    }


# ------------------------------------------------------------------- fields and line forms


def test_field_paths_for_nested_json_and_lists() -> None:
    line = json.dumps(
        {"error": {"details": {"errors": [{"msg": "ok"}, {"msg": "to 13800138000"}]}}}
    )
    assert found(line) == {("error.details.errors[1].msg", "cn_mobile")}


def test_keys_are_scanned_and_never_printed_when_unsafe() -> None:
    assert found('{"counts":{"li.si@example.org":3}}') == {("counts.<key>", "email")}
    assert found('{"金额":8000}') == {("<key>", "amount_field")}


def test_compose_prefix_and_text_pairs() -> None:
    line = 'api-1  | {"logger":"cardflow.payments","message":"refund ￥66.00 queued"}'
    assert found(line) == {("message", "amount")}
    assert found("card: ending in 1234") == {("card", "card_last4")}
    # The rest of the line is one JSON object: scanned as a document after a prefix.
    assert found('payload={"amount_minor":800000,"note":"ok"}') == {
        ("amount_minor", "amount_field")
    }
    # A JSON value inside a text line: scanned as the value of its key.
    assert found('payload={"amount_minor":800000} retry=1') == {
        ("payload.amount_minor", "amount_field")
    }


def test_any_value_in_a_credential_field_counts() -> None:
    # Field rules do not judge the value: a password or Authorization field is never
    # expected in a log, whatever it holds (only redaction markers are accepted).
    assert found('{"authorization":"denied"}') == {("authorization", "authorization")}
    assert found("authorization: denied") == {("authorization", "authorization")}
    assert found('{"password":"[redacted]","token":"***"}') == set()


def test_url_encoded_query_values_are_decoded() -> None:
    line = "GET /healthz?amount=%C2%A58%2C000.00&card=4111+1111+1111+1111 HTTP/1.1"
    assert found(line) == {("amount", "amount"), ("card", "card_number")}


def test_each_hit_is_reported_once_per_field() -> None:
    line = '{"message":"cards 4111111111111111 and 5555 5555 5555 4444"}'
    assert pii_scan.scan_line(line) == [pii_scan.Hit("message", "card_number")]


def test_deeply_nested_json_is_scanned_without_recursion() -> None:
    deep = '{"a":' * 500 + '"13800138000"' + "}" * 500
    assert rules(deep) == {"cn_mobile"}
    assert pii_scan.scan_line("[" * 100_000) == []  # too deep for json: scanned as text


# Inputs that make naive patterns backtrack exponentially or quadratically (runs of *,
# whitespace between a keyword and a missing number, comma-grouped digits, nested pairs).
PATHOLOGICAL_LINES: Final = [
    "*" * 50_000 + "x",
    "尾号" + " " * 50_000 + "x",
    "last4" + " " * 50_000 + "x",
    "ending in" + " " * 50_000 + "x",
    "1" + " " * 50_000 + "x",
    "1," * 50_000,
    "a=" * 50_000,
    "a:" * 50_000,
    "1 " * 50_000,
    "a=1 ¥5 " * 10_000,
    "A1b" * 100_000,
]


def test_pathological_lines_finish_quickly() -> None:
    # In a subprocess with a timeout, so a regression fails instead of hanging CI.
    result = run_script("-", stdin="\n".join(PATHOLOGICAL_LINES) + "\n", timeout=60)
    assert result.returncode == pii_scan.EXIT_HITS, result.stderr
    hit_lines = {int(line.split(":")[1]) for line in result.stdout.splitlines()}
    assert hit_lines == {10, 11}  # the amounts in "a=1 ¥5 ..." and the long A1b... token


def test_validators() -> None:
    assert pii_scan.luhn_valid("4111111111111111")
    assert not pii_scan.luhn_valid("4111111111111112")
    assert pii_scan.cn_id_valid("11010519491231002X")
    assert pii_scan.cn_id_valid("11010519491231002x")
    assert not pii_scan.cn_id_valid("110105194912310021")
    assert pii_scan.is_uuid(uuid.uuid4().hex)
    assert pii_scan.is_uuid(str(uuid.uuid4()).upper())
    assert not pii_scan.is_uuid("9f8e7d6c5b4a39281706f5e4d3c2b1a0")
    assert pii_scan.normalize_key("creditLimit") == "credit_limit"
    assert pii_scan.normalize_key("X-Api-Key") == "x_api_key"


# ----------------------------------------------------------------------- samples


def scan_file(path: Path) -> list[pii_scan.Finding]:
    """All findings in ``path``, with ``path.name`` as the source."""
    lines = path.read_text(encoding="utf-8").splitlines()
    return list(pii_scan.scan_lines(lines, path.name))


def test_clean_log_has_no_hits() -> None:
    assert scan_file(CLEAN_LOG) == []


def test_clean_log_is_a_full_probe_capture() -> None:
    # Guards against an empty or hand-trimmed sample: one access line per probe request
    # in each format, with the expected statuses, plus the 500's cardflow.api line.
    expected = sorted(request.expected_status for request in pii_log_probe.PROBE_REQUESTS)
    json_statuses: list[int] = []
    text_statuses: list[int] = []
    errors = 0
    for line in CLEAN_LOG.read_text(encoding="utf-8").splitlines():
        if line.startswith("{"):
            record = json.loads(line)
            if record["logger"] == "cardflow.access":
                json_statuses.append(record["status"])
            errors += record["logger"] == "cardflow.api"
        else:
            status = re.search(r" status=(\d+)", line)
            if " cardflow.access: " in line and status is not None:
                text_statuses.append(int(status.group(1)))
            errors += " cardflow.api: " in line
    assert sorted(json_statuses) == expected
    assert sorted(text_statuses) == expected
    assert errors == len(pii_log_probe.LOG_FORMATS)


EXPECTED_DIRTY: Final[dict[int, set[tuple[str, str]]]] = {
    3: {("message", "amount")},
    4: {("amount_minor", "amount_field")},
    5: {("credit_limit", "amount_field"), ("balance", "amount_field")},
    6: {("balance_minor", "amount_field"), ("note", "amount")},
    7: {("message", "card_number")},
    8: {("pan", "sensitive_field"), ("pan", "card_number")},
    9: {("card_last4", "card_last4")},
    10: {("-", "card_last4")},
    11: {("message", "card_last4")},
    12: {("message", "card_last4")},
    13: {("detail", "jwt")},
    14: {("Authorization", "authorization")},
    15: {("headers.authorization", "authorization")},
    16: {("password", "credential_field")},
    17: {("refresh_token", "credential_field")},
    18: {("merchant", "sensitive_field")},
    19: {("id_number", "sensitive_field"), ("id_number", "cn_id_card")},
    20: {("-", "cn_id_card")},
    21: {("message", "cn_mobile")},
    22: {("phone", "sensitive_field"), ("phone", "cn_mobile")},
    23: {("message", "email")},
    24: {("message", "secret_string")},
    25: {("value", "secret_string")},
    26: {("message", "amount")},
    27: {("counts.<key>", "email")},
    28: {("amount", "amount_field"), ("phone", "sensitive_field"), ("phone", "cn_mobile")},
    29: {("amount", "amount"), ("card", "card_number")},
    30: {("path", "card_number")},
    31: {("status", "card_number"), ("request_id", "cn_mobile")},
    32: {("message", "amount_field"), ("message", "card_last4")},
    33: {("amount", "amount"), ("card", "card_number")},
    34: {("message", "card_number")},
}


def test_dirty_log_hits_exactly_as_designed() -> None:
    actual: dict[int, set[tuple[str, str]]] = {}
    for finding in scan_file(DIRTY_LOG):
        actual.setdefault(finding.line, set()).add((finding.field, finding.rule))
    assert actual == EXPECTED_DIRTY


def test_dirty_log_covers_every_rule_and_every_sample_line() -> None:
    findings = scan_file(DIRTY_LOG)
    assert {finding.rule for finding in findings} == set(pii_scan.RULE_NAMES)
    sample_lines = {
        number
        for number, line in enumerate(DIRTY_LOG.read_text(encoding="utf-8").splitlines(), 1)
        if line.strip() and not line.startswith("#")
    }
    assert {finding.line for finding in findings} == sample_lines


# ---------------------------------------------------------------- command line and output

# Every sensitive value injected into dirty.log; none may appear in the scanner's output.
INJECTED_VALUES: Final = [
    "8,000.00",
    "800000",
    "5000000",
    "12,345.67",
    "1234567",
    "3500",
    "4111",
    "5555555555554444",
    "4444",
    "1111",
    "1881",
    "eyJ",
    "9f8e7d6c",
    "dGVzdHVzZXI6dGVzdHBhc3M",
    "hunter2",
    "r3fr35h",
    "虚构",
    "11010519491231002X",
    "13800138000",
    "0013",
    "zhang.san",
    "li.si",
    "example",
    "MDEyMzQ1",
    "c0ffee",
    "66.00",
    "1,234.56",
    "6011111111111117",
    "%C2%A5",
    "Bearer",
    "Basic",
]


def test_output_never_contains_the_matched_text(capsys: pytest.CaptureFixture[str]) -> None:
    assert pii_scan.main([str(DIRTY_LOG)]) == pii_scan.EXIT_HITS
    out, err = capsys.readouterr()
    lines = out.splitlines()
    assert len(lines) == sum(len(hits) for hits in EXPECTED_DIRTY.values())
    for line in lines:
        match = OUTPUT_LINE.fullmatch(line)
        assert match is not None, line
        assert match["source"] == str(DIRTY_LOG)
        assert match["rule"] in pii_scan.RULE_NAMES
    for value in INJECTED_VALUES:
        assert value not in out
        assert value not in err


def test_exit_0_and_summary_for_clean_input(capsys: pytest.CaptureFixture[str]) -> None:
    assert pii_scan.main([str(CLEAN_LOG)]) == pii_scan.EXIT_CLEAN
    out, err = capsys.readouterr()
    assert out == ""
    assert err == "pii_scan: 1 file(s), 26 line(s), 0 hit(s)\n"


def test_exit_2_for_missing_path(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert pii_scan.main([str(tmp_path / "absent.log")]) == pii_scan.EXIT_ERROR
    assert "no such file or directory" in capsys.readouterr().err


def test_exit_2_for_non_utf8_file(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    log = tmp_path / "binary.log"
    log.write_bytes(b'{"message":"ok"}\n\xff\xfe\x00broken\n')
    assert pii_scan.main([str(log)]) == pii_scan.EXIT_ERROR
    assert "not valid UTF-8" in capsys.readouterr().err


def test_undecodable_line_is_an_error_and_the_rest_is_still_scanned(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    log = tmp_path / "partly-binary.log"
    hit = b'{"message":"sms to 13800138000"}\n'
    log.write_bytes(hit + b"x" * 20_000 + b"\n\xff\n" + hit)
    assert pii_scan.main([str(log)]) == pii_scan.EXIT_ERROR
    out, err = capsys.readouterr()
    assert out == f"{log}:1:message:cn_mobile\n{log}:4:message:cn_mobile\n"
    assert f"pii_scan: error: {log}: not valid UTF-8 on 1 line(s): 3\n" in err
    assert "1 file(s), 4 line(s), 2 hit(s) [cn_mobile]; 1 error(s)" in err


def test_byte_order_mark_is_ignored(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    log = tmp_path / "bom.log"
    log.write_bytes(b"\xef\xbb\xbf" + b'{"message":"sms to 13800138000"}\n')
    assert pii_scan.main([str(log)]) == pii_scan.EXIT_HITS
    assert capsys.readouterr().out == f"{log}:1:message:cn_mobile\n"


def test_exit_2_for_empty_directory(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert pii_scan.main([str(tmp_path)]) == pii_scan.EXIT_ERROR
    assert "no files to scan" in capsys.readouterr().err


@pytest.mark.parametrize("argv", [[], ["--no-such-option", str(CLEAN_LOG)]])
def test_exit_2_for_usage_errors(argv: list[str]) -> None:
    with pytest.raises(SystemExit) as exited:
        pii_scan.main(argv)
    assert exited.value.code == pii_scan.EXIT_ERROR


def test_error_wins_over_hits_but_hits_are_still_reported(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    status = pii_scan.main([str(DIRTY_LOG), str(tmp_path / "absent.log")])
    out, err = capsys.readouterr()
    assert status == pii_scan.EXIT_ERROR
    assert out.count("\n") == sum(len(hits) for hits in EXPECTED_DIRTY.values())
    assert "1 error(s)" in err


def test_directories_are_scanned_recursively(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    (tmp_path / "a").mkdir()
    (tmp_path / "a" / "b").mkdir()
    (tmp_path / "a" / "clean.log").write_text('{"message":"http_request"}\n', encoding="utf-8")
    (tmp_path / "a" / "b" / "api.jsonl").write_text(
        '{"message":"ok"}\n{"message":"sms to 13800138000"}\n', encoding="utf-8"
    )
    (tmp_path / "empty.log").write_text("", encoding="utf-8")
    assert pii_scan.main([str(tmp_path)]) == pii_scan.EXIT_HITS
    out, err = capsys.readouterr()
    assert out == f"{tmp_path / 'a' / 'b' / 'api.jsonl'}:2:message:cn_mobile\n"
    assert "3 file(s), 3 line(s), 1 hit(s)" in err


def test_list_rules(capsys: pytest.CaptureFixture[str]) -> None:
    assert pii_scan.main(["--list-rules"]) == pii_scan.EXIT_CLEAN
    listed = {line.split("\t")[0] for line in capsys.readouterr().out.splitlines()}
    assert listed == set(pii_scan.RULE_NAMES)


def run_script(
    *args: str, stdin: str | None = None, timeout: float = 120
) -> subprocess.CompletedProcess[str]:
    """Run the scanner as CI does, but with -I -S: no site-packages, so stdlib only."""
    command = [sys.executable, "-I", "-S", str(SCANNER), *args]
    # Fixed argv: this interpreter and this repository's script, no shell.
    return subprocess.run(  # noqa: S603
        command,
        input=stdin,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=timeout,
        check=False,
    )


@pytest.mark.parametrize(
    ("target", "status"),
    [(CLEAN_LOG, 0), (DIRTY_LOG, 1), (TOOLS / "pii_samples" / "absent.log", 2)],
    ids=["clean-0", "dirty-1", "missing-2"],
)
def test_script_exit_status(target: Path, status: int) -> None:
    result = run_script(str(target))
    assert result.returncode == status, result.stderr


def test_script_reads_standard_input() -> None:
    result = run_script("-", stdin=DIRTY_LOG.read_text(encoding="utf-8"))
    assert result.returncode == pii_scan.EXIT_HITS
    assert result.stdout.splitlines()[0] == "<stdin>:3:message:amount"


# ------------------------------------------------------------ end to end: real app logs


@pytest.fixture
def probe_settings(monkeypatch: pytest.MonkeyPatch) -> Settings:
    """Default settings, unaffected by the environment (as services/api's conftest does)."""
    names = {name.upper() for name in Settings.model_fields}
    names |= {f"{name.upper()}_FILE" for name in SECRET_FIELDS}
    for key in list(os.environ):
        if key.upper() in names:
            monkeypatch.delenv(key)
    return Settings()


@pytest.fixture(params=pii_log_probe.LOG_FORMATS)
def probe_run(request: pytest.FixtureRequest, probe_settings: Settings) -> pii_log_probe.ProbeRun:
    """One probe run against the real app, in the parametrised log format."""
    app = pii_log_probe.build_probe_app(probe_settings)
    return pii_log_probe.run_probe(request.param, app)


def test_e2e_probe_reaches_every_status_path(probe_run: pii_log_probe.ProbeRun) -> None:
    expected = tuple(request.expected_status for request in pii_log_probe.PROBE_REQUESTS)
    assert probe_run.statuses == expected
    loggers = [line.logger for line in probe_run.lines if line.from_cardflow]
    assert loggers.count("cardflow.access") == len(pii_log_probe.PROBE_REQUESTS)
    assert loggers.count("cardflow.api") == 1  # the 500, reduced to exception type and frames


def test_e2e_server_log_does_not_leak_request_data(probe_run: pii_log_probe.ProbeRun) -> None:
    cardflow_lines = probe_run.cardflow_lines()
    assert cardflow_lines
    assert list(pii_scan.scan_lines(cardflow_lines, "cardflow.*")) == []
    # Stricter: every line except the test client's own httpx/httpcore lines.
    assert list(pii_scan.scan_lines(probe_run.server_lines(), "server")) == []


def test_e2e_requests_carried_detectable_pii() -> None:
    # Non-vacuity: the scanner flags the very data the probe sends.
    sent: set[str] = set()
    for request in pii_log_probe.PROBE_REQUESTS:
        rendered = json.dumps(
            {
                "url": request.url,
                "params": dict(request.params),
                "json": request.json_body,
                "content": request.content,
                "headers": dict(request.headers),
            },
            ensure_ascii=False,
        )
        sent |= rules(rendered)
    assert {
        "amount",
        "amount_field",
        "card_number",
        "card_last4",
        "jwt",
        "authorization",
        "cn_id_card",
        "cn_mobile",
        "email",
        "sensitive_field",
    } <= sent


@pytest.mark.parametrize(
    ("fmt", "field"), [("json", "message"), ("text", pii_scan.FREE_TEXT)], ids=["json", "text"]
)
def test_e2e_leaky_handler_is_caught(probe_settings: Settings, fmt: LogFormat, field: str) -> None:
    # Positive control on the real logging pipeline: a handler that logs request data in
    # its message (which the field whitelist cannot remove) is reported by the scanner.
    app = pii_log_probe.build_probe_app(probe_settings)
    leaky_logger = logging.getLogger("cardflow.probe")

    @app.get("/v1/_probe/leaky")
    async def leaky(card: str) -> dict[str, bool]:
        leaky_logger.info("charging %s on card %s", pii_log_probe.AMOUNT_YUAN, card)
        return {"ok": True}

    request = pii_log_probe.ProbeRequest(
        "leaky handler", "GET", "/v1/_probe/leaky", 200, {"card": pii_log_probe.CARD_VISA_SPACED}
    )
    run = pii_log_probe.run_probe(fmt, app, [request])
    assert run.statuses == (200,)
    findings = pii_scan.scan_lines(run.cardflow_lines(), "capture")
    assert {(finding.field, finding.rule) for finding in findings} == {
        (field, "amount"),
        (field, "card_number"),
    }


def raw_url(scope: Scope) -> str:
    """What a naive access log would record: the concrete path plus the query string."""
    query = bytes(scope.get("query_string", b"")).decode("latin-1")
    return f"{scope['path']}?{query}" if query else str(scope["path"])


@pytest.mark.parametrize("fmt", pii_log_probe.LOG_FORMATS)
def test_e2e_raw_url_in_the_access_log_would_be_caught(
    probe_settings: Settings, monkeypatch: pytest.MonkeyPatch, fmt: LogFormat
) -> None:
    # Mutation check of the end-to-end test: if the access log recorded the raw URL
    # instead of the route template (the regression it guards against), the same probe
    # and scan report it. Test-only patch, undone by monkeypatch after the test.
    monkeypatch.setattr(request_context, "route_template", raw_url)
    run = pii_log_probe.run_probe(fmt, pii_log_probe.build_probe_app(probe_settings))
    found_rules = {finding.rule for finding in pii_scan.scan_lines(run.cardflow_lines(), "x")}
    assert {"amount", "amount_field", "card_number", "cn_mobile", "email"} <= found_rules
