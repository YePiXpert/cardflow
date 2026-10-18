"""Convert a hand-written golden fixture into a rules-protocol v1 fixture (deterministic).

Usage, from the repository root::

    uv run --project services/api python \\
        packages/rules-protocol/runner_py/convert_legacy_fixture.py \\
        packages/rules-protocol/fixtures/regression_2026-10-16_10000.json [-o OUT] [--check]

Writes ``<name>.v1.json`` next to the input (or ``OUT``). ``--check`` regenerates in memory
and compares bytes with the existing file instead (exit 0 identical, 1 different).
Exit 2 = the input cannot be converted.

The hand-written format (``regression_2026-10-16_10000.json``) writes money as decimal strings
of major units; it is read with the same defaults as the T-003 loader
(``cardflow.planner.engine.fixture.load_fixture``). Conversion rules:

* every amount -> integer minor units of the request currency (``money.to_minor``: the
  currency's minor-unit digits; more precision than the minor unit is an ERROR, nothing is
  rounded); only plain decimal strings are accepted (no exponent, no float);
* rates and scale factors stay decimal strings; defaults of the loader are written explicitly;
* options not present in the hand-written format get the engine defaults: profile
  ``cash_safety``, time limit 10 s, 8 workers, seed 0, stale after 7 days;
* an unknown member anywhere is an ERROR (the loader would ignore it; a v1 document must not
  silently lose meaning);
* ``expected``: every key becomes one case, in file order, every value one or more assertions
  whose ``from`` names the source key -- see ``_expected`` for the rules.

Output: JSON with sorted keys, 2-space indentation, UTF-8 without escaping, final newline. The
result is checked with the protocol adapter before it is written.
"""

import argparse
import hashlib
import json
import re
import sys
from collections.abc import Callable
from pathlib import Path
from typing import Any

from cardflow.planner.engine.money import to_minor
from cardflow.planner.engine.protocol import (
    PROFILES,
    PROTOCOL_VERSION,
    ProtocolError,
    inputs_from_protocol,
    parse_json,
)

PROTOCOL_ROOT = Path(__file__).resolve().parents[1]  # packages/rules-protocol
CONVERTER = "runner_py/convert_legacy_fixture.py"
DEFAULT_OPTIONS = {
    "profile": "cash_safety",
    "time_limit_s": 10,
    "workers": 8,
    "seed": 0,
    "stale_after_days": 7,
}
_AMOUNT = re.compile(r"-?(0|[1-9][0-9]*)(\.[0-9]+)?")
# v1 Rate / ScaleFactor in canonical form: no trailing fractional zeros (T-004c, R3E-11)
_RATE = re.compile(r"0|1|0\.[0-9]{0,4}[1-9]")  # 0..1, at most 5 decimals
_SCALE = re.compile(r"10|[0-9]|[0-9]\.[0-9]{0,9}[1-9]")  # 0..10, at most 10 decimals
_DATE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")

type Json = Any


class ConversionError(ValueError):
    """The hand-written fixture cannot be converted faithfully."""


def _members(obj: Json, where: str, allowed: set[str], required: set[str]) -> dict[str, Json]:
    if not isinstance(obj, dict):
        raise ConversionError(f"{where}: expected an object")
    unknown = sorted(set(obj) - allowed)
    if unknown:
        raise ConversionError(f"{where}.{unknown[0]}: no conversion rule for this member")
    missing = sorted(required - set(obj))
    if missing:
        raise ConversionError(f"{where}: missing {missing[0]!r}")
    return obj


def _typed(value: Json, kind: type, where: str) -> Json:
    if kind is int and isinstance(value, bool):
        raise ConversionError(f"{where}: expected int, got bool")
    if not isinstance(value, kind):
        raise ConversionError(f"{where}: expected {kind.__name__}, got {type(value).__name__}")
    return value


class _Context:
    def __init__(self, raw: dict[str, Json]) -> None:
        self.currency: str = raw["request"]["currency"]
        self.card_ids = [c["id"] for c in raw["cards"]]
        self.scenario_ids = list(raw["scenarios"])
        self.decision: str = raw["decision_scenario"]
        accounts = [a["id"] for a in raw["cash_accounts"]]
        self.account: str | None = accounts[0] if len(accounts) == 1 else None

    def money(self, value: Json, where: str) -> int:
        if not isinstance(value, str) or not _AMOUNT.fullmatch(value):
            raise ConversionError(f"{where}: {value!r} is not a plain decimal string")
        try:
            return to_minor(value, self.currency)
        except ValueError as e:
            raise ConversionError(f"{where}: {e}") from None

    def only_account(self, where: str) -> str:
        if self.account is None:
            raise ConversionError(f"{where}: ambiguous with more than one cash account")
        return self.account

    def scenario(self, prefix: str, where: str) -> str:
        """'' -> decision scenario; an id -> itself; 'stress' -> the one scenario 'stress_*'."""
        if prefix == "":
            return self.decision
        if prefix in self.scenario_ids:
            return prefix
        matches = [s for s in self.scenario_ids if s.startswith(f"{prefix}_")]
        if len(matches) != 1:
            raise ConversionError(f"{where}: {prefix!r} names no single scenario ({matches})")
        return matches[0]


def _rate(value: Json, where: str, pattern: re.Pattern[str] = _RATE) -> str:
    if not isinstance(value, str) or not pattern.fullmatch(value):
        raise ConversionError(f"{where}: {value!r} is outside the v1 range for this field")
    return value


def _date(value: Json, where: str) -> str:
    if not isinstance(value, str) or not _DATE.fullmatch(value):
        raise ConversionError(f"{where}: {value!r} is not a YYYY-MM-DD date")
    return value


def _pointer(*parts: str) -> str:
    return "".join("/" + p.replace("~", "~0").replace("/", "~1") for p in parts)


# --- input ---------------------------------------------------------------------------------


def _request(rq: Json, ctx: _Context) -> dict[str, Json]:
    keys = {"amount", "currency", "txn_date", "allow_split", "max_cards", "min_split"}
    keys |= {"payment_lead_days", "channel"}
    rq = _members(rq, "request", keys, {"amount", "currency", "txn_date"})
    return {
        "amount_minor": ctx.money(rq["amount"], "request.amount"),
        "currency": _typed(rq["currency"], str, "request.currency"),
        "txn_date": _date(rq["txn_date"], "request.txn_date"),
        "allow_split": _typed(rq.get("allow_split", False), bool, "request.allow_split"),
        "max_cards": _typed(rq.get("max_cards", 1), int, "request.max_cards"),
        "min_split_minor": ctx.money(rq.get("min_split", "0.01"), "request.min_split"),
        "payment_lead_days": _typed(rq.get("payment_lead_days", 0), int, "request.lead_days"),
        "channel": _typed(rq.get("channel", "pos"), str, "request.channel"),
    }


_CARD_KEYS = {
    "id",
    "account_id",
    "name",
    "available",
    "statement_day",
    "due",
    "repay_from",
    "rule_id",
    "statement_day_inclusive",
    "holiday_rollover",
    "rule_source",
    "rule_status",
    "uncounted_holds",
    "plan_reservations",
    "pool_id",
    "per_txn_cap",
    "min_split",
    "channel_ok",
    "currency_ok",
    "status_ok",
    "fee_rate",
    "fee_fixed",
    "verified_benefit_rate",
    "verified_benefit_cap",
    "potential_benefit_rate",
    "posting_delay_min",
    "posting_delay_max",
}


def _card(c: Json, i: int, ctx: _Context) -> dict[str, Json]:
    w = f"cards[{i}]"
    c = _members(
        c, w, _CARD_KEYS, {"id", "account_id", "available", "statement_day", "due", "repay_from"}
    )
    card_id = _typed(c["id"], str, f"{w}.id")
    due = _members(c["due"], f"{w}.due", {"kind", "day", "month_offset", "days"}, {"kind"})
    if due["kind"] == "fixed_day":
        if "days" in due:
            raise ConversionError(f"{w}.due.days: not used by a fixed_day rule")
        due_doc = {
            "kind": "fixed_day",
            "day": _typed(due.get("day"), int, f"{w}.due.day"),
            "month_offset": _typed(due.get("month_offset", 0), int, f"{w}.due.month_offset"),
        }
    elif due["kind"] == "days_after_statement":
        if "day" in due or "month_offset" in due:
            raise ConversionError(f"{w}.due: day/month_offset not used by days_after_statement")
        # the T-003 loader never reads day_kind: calendar days
        due_doc = {
            "kind": "days_after_statement",
            "days": _typed(due.get("days"), int, f"{w}.due.days"),
            "day_kind": "calendar",
        }
    else:
        raise ConversionError(f"{w}.due.kind: {due['kind']!r} is unknown")
    out: dict[str, Json] = {
        "card_id": card_id,
        "credit_account_id": _typed(c["account_id"], str, f"{w}.account_id"),
        "name": _typed(c.get("name", card_id), str, f"{w}.name"),
        "raw_available_minor": ctx.money(c["available"], f"{w}.available"),
        "holds_uncounted_minor": ctx.money(c.get("uncounted_holds", "0"), f"{w}.uncounted_holds"),
        "reservations_minor": ctx.money(c.get("plan_reservations", "0"), f"{w}.plan_reservations"),
        "billing_rule": {
            "rule_id": _typed(c.get("rule_id", f"rule-{card_id}"), str, f"{w}.rule_id"),
            "statement_day": _typed(c["statement_day"], int, f"{w}.statement_day"),
            "statement_day_inclusive": _typed(
                c.get("statement_day_inclusive", True), bool, f"{w}.statement_day_inclusive"
            ),
            "due": due_doc,
            "holiday_rollover": _typed(
                c.get("holiday_rollover", "none"), str, f"{w}.holiday_rollover"
            ),
            "source": _typed(c.get("rule_source", "fixture"), str, f"{w}.rule_source"),
            "status": _typed(c.get("rule_status", "user_declared"), str, f"{w}.rule_status"),
        },
        "repay_from_cash_account_id": _typed(c["repay_from"], str, f"{w}.repay_from"),
        "channel_ok": _typed(c.get("channel_ok", True), bool, f"{w}.channel_ok"),
        "currency_ok": _typed(c.get("currency_ok", True), bool, f"{w}.currency_ok"),
        "status_ok": _typed(c.get("status_ok", True), bool, f"{w}.status_ok"),
        "fee_rate": _rate(c.get("fee_rate", "0"), f"{w}.fee_rate"),
        "fee_fixed_minor": ctx.money(c.get("fee_fixed", "0"), f"{w}.fee_fixed"),
        "verified_benefit_rate": _rate(
            c.get("verified_benefit_rate", "0"), f"{w}.verified_benefit_rate"
        ),
        "potential_benefit_rate": _rate(
            c.get("potential_benefit_rate", "0"), f"{w}.potential_benefit_rate"
        ),
        "posting_delay_min_days": _typed(c.get("posting_delay_min", 0), int, f"{w}.delay_min"),
        "posting_delay_max_days": _typed(c.get("posting_delay_max", 0), int, f"{w}.delay_max"),
    }
    if c.get("pool_id") is not None:
        out["pool_id"] = _typed(c["pool_id"], str, f"{w}.pool_id")
    # the loader treats a missing or empty value of these as "none"
    for key, target in (
        ("per_txn_cap", "per_txn_cap_minor"),
        ("min_split", "min_split_minor"),
        ("verified_benefit_cap", "verified_benefit_cap_minor"),
    ):
        if c.get(key):
            out[target] = ctx.money(c[key], f"{w}.{key}")
    return out


def _plan_input(raw: dict[str, Json], ctx: _Context) -> dict[str, Json]:
    accounts = []
    for i, a in enumerate(raw["cash_accounts"]):
        keys = {"id", "name", "currency", "reserve_floor", "usable_for_repayment"}
        a = _members(a, f"cash_accounts[{i}]", keys, {"id"})
        accounts.append(
            {
                "cash_account_id": a["id"],
                "name": a.get("name", a["id"]),
                "currency": a.get("currency", ctx.currency),
                "reserve_floor_minor": ctx.money(a.get("reserve_floor", "0"), f"accounts[{i}]"),
                "usable_for_repayment": _typed(
                    a.get("usable_for_repayment", True), bool, f"cash_accounts[{i}].usable"
                ),
            }
        )
    snapshots = []
    for i, s in enumerate(raw["snapshots"]):
        keys = {"account", "balance", "as_of", "includes_event_ids"}
        s = _members(s, f"snapshots[{i}]", keys, {"account", "balance", "as_of"})
        snapshots.append(
            {
                "cash_account_id": s["account"],
                "balance_minor": ctx.money(s["balance"], f"snapshots[{i}].balance"),
                "as_of": _date(s["as_of"], f"snapshots[{i}].as_of"),
                "includes_event_ids": list(s.get("includes_event_ids", [])),
            }
        )
    events = []
    for i, e in enumerate(raw["events"]):
        keys = {"id", "account", "on", "amount", "cls", "category", "label"}
        # v1 requires a category (the loader defaults to "", which v1 does not accept)
        e = _members(e, f"events[{i}]", keys, {"id", "on", "amount", "cls", "category"})
        events.append(
            {
                "event_id": e["id"],
                "cash_account_id": e.get("account", raw["cash_accounts"][0]["id"]),
                "on": _date(e["on"], f"events[{i}].on"),
                "amount_minor": ctx.money(e["amount"], f"events[{i}].amount"),
                "cls": e["cls"],
                "category": e["category"],
                "label": e.get("label", ""),
            }
        )
    scenarios = []
    for sid, s in raw["scenarios"].items():
        keys = {"include_expected", "income_delay_days", "income_scale", "expense_scale"}
        keys |= {"event_overrides", "same_day_order", "description"}
        s = _members(s, f"scenarios.{sid}", keys, set())
        overrides = []
        for eid, ov in s.get("event_overrides", {}).items():
            ov = _members(ov, f"scenarios.{sid}.event_overrides.{eid}", {"on", "amount"}, set())
            item: dict[str, Json] = {"event_id": eid}
            if "on" in ov:
                item["on"] = _date(ov["on"], f"scenarios.{sid}.event_overrides.{eid}.on")
            if "amount" in ov:
                item["amount_minor"] = ctx.money(ov["amount"], f"scenarios.{sid}.{eid}.amount")
            overrides.append(item)
        scenarios.append(
            {
                "scenario_id": sid,
                "include_expected": _typed(s.get("include_expected", True), bool, sid),
                "income_delay_days": _typed(s.get("income_delay_days", 0), int, sid),
                "income_scale": _rate(s.get("income_scale", "1"), f"{sid}.income_scale", _SCALE),
                "expense_scale": _rate(s.get("expense_scale", "1"), f"{sid}.expense_scale", _SCALE),
                "event_overrides": overrides,
                "same_day_order": s.get("same_day_order", "conservative"),
                "description": s.get("description", ""),
            }
        )
    pools = [
        {"pool_id": pid, "available_minor": ctx.money(v, f"pools.{pid}")}
        for pid, v in raw.get("pools", {}).items()
    ]
    return {
        "protocol_version": PROTOCOL_VERSION,
        "request": _request(raw["request"], ctx),
        "cards": [_card(c, i, ctx) for i, c in enumerate(raw["cards"])],
        "pools": pools,
        "cash_accounts": accounts,
        "snapshots": snapshots,
        "events": events,
        "scenarios": scenarios,
        "horizon_end": _date(raw["horizon_end"], "horizon_end"),
        "options": {
            **DEFAULT_OPTIONS,
            "decision_scenario": ctx.decision,
            "global_reserve_floor_minor": ctx.money(
                raw.get("global_reserve_floor", "0"), "global_reserve_floor"
            ),
        },
    }


# --- expected ------------------------------------------------------------------------------


def _assert(path: str, source: str, **check: Json) -> dict[str, Json]:
    return {"path": path, **check, "from": source}


def _cycles_case(key: str, value: Json, ctx: _Context) -> dict[str, Json]:
    """cycles: {card: [statement_date, due_date]} -> 'cycles' case on CardCycles."""
    if not isinstance(value, dict):
        raise ConversionError(f"expected.{key}: expected an object")
    checks = []
    for card, dates in value.items():
        if card not in ctx.card_ids or not isinstance(dates, list) or len(dates) != 2:
            raise ConversionError(f"expected.{key}.{card}: expected [statement, due] of a card")
        stmt, due = (_date(d, f"expected.{key}.{card}") for d in dates)
        checks.append(_assert(_pointer(card, "statement_date"), f"{key}.{card}[0]", equals=stmt))
        checks.append(_assert(_pointer(card, "due_date"), f"{key}.{card}[1]", equals=due))
    return {"name": key, "kind": "cycles", "assertions": checks}


def _verify_case(key: str, value: Json, ctx: _Context) -> dict[str, Json]:
    """plan_<card><major units>[_<card><major units>...]: verify that allocation (no solver).

    Members: weighted_buffer_days; [<scenario>_]min_cash; [<scenario>_]balance_<date> (the
    breach point of that date); [<scenario>_]gap_to_zero / gap_to_reserve (of the breach point
    named by the single balance_<date> member with the same scenario prefix). No prefix = the
    fixture's decision scenario.
    """
    allocation = []
    for token in key.removeprefix("plan_").split("_"):
        cards = [c for c in ctx.card_ids if token.startswith(c) and token[len(c) :].isdigit()]
        if len(cards) != 1:
            raise ConversionError(f"expected.{key}: cannot read {token!r} as <card><amount>")
        major = token[len(cards[0]) :]
        allocation.append({"card_id": cards[0], "amount_minor": ctx.money(major, key)})
    if not isinstance(value, dict):
        raise ConversionError(f"expected.{key}: expected an object")
    account = ctx.only_account(f"expected.{key}")
    balance_dates: dict[str, list[str]] = {}
    for member in value:
        m = re.fullmatch(r"(?:(.+)_)?balance_([0-9]{4}-[0-9]{2}-[0-9]{2})", member)
        if m:
            balance_dates.setdefault(m.group(1) or "", []).append(m.group(2))
    checks = []
    for member, expected in value.items():
        source = f"{key}.{member}"
        if member == "weighted_buffer_days":
            if not isinstance(expected, str) or not re.fullmatch(r"-?[0-9]+(\.[0-9]+)?", expected):
                raise ConversionError(f"expected.{source}: not a decimal string")
            checks.append(_assert("/verification/weighted_buffer_days", source, equals=expected))
            continue
        if member == "min_cash" or member.endswith("_min_cash"):
            sc = ctx.scenario(member.removesuffix("min_cash").removesuffix("_"), source)
            path = _pointer("verification", "checks", sc, "min_balance_by_account", account)
            checks.append(_assert(path, source, equals=ctx.money(expected, source)))
            continue
        m_balance = re.fullmatch(r"(?:(.+)_)?balance_([0-9]{4}-[0-9]{2}-[0-9]{2})", member)
        m_gap = re.fullmatch(r"(?:(.+)_)?gap_to_(zero|reserve)", member)
        if m_balance:
            prefix, on, field = m_balance.group(1) or "", m_balance.group(2), "balance"
        elif m_gap:
            prefix, field = m_gap.group(1) or "", f"gap_to_{m_gap.group(2)}"
            dates = balance_dates.get(prefix, [])
            if len(dates) != 1:
                raise ConversionError(f"expected.{source}: needs one {prefix}_balance_<date>")
            on = dates[0]
        else:
            raise ConversionError(f"expected.{source}: no conversion rule for this member")
        sc = ctx.scenario(prefix, source)
        checks.append(
            _assert(
                _pointer("verification", "checks", sc, "breaches"),
                source,
                where={"cash_account_id": account, "on": on},
                then=_pointer(field),
                equals=ctx.money(expected, source),
            )
        )
    return {
        "name": key,
        "kind": "verify",
        "allocation": allocation,
        "decision_scenario": ctx.decision,
        "assertions": checks,
    }


def _shortfall_case(key: str, value: Json, ctx: _Context) -> dict[str, Json]:
    """<scenario>_scenario: {baseline_shortfall_on, balance} -> plan with that scenario as the
    decision scenario: BASELINE_SHORTFALL whose FIRST baseline breach is on that date."""
    sc = key.removesuffix("_scenario")
    if sc not in ctx.scenario_ids:
        raise ConversionError(f"expected.{key}: {sc!r} is not a scenario")
    value = _members(
        value, f"expected.{key}", {"baseline_shortfall_on", "balance"}, {"baseline_shortfall_on"}
    )
    account = ctx.only_account(f"expected.{key}")
    first = _pointer("baseline", sc, "accounts", account, "breaches", "0")
    on = _date(value["baseline_shortfall_on"], f"expected.{key}.baseline_shortfall_on")
    checks = [
        _assert(
            "/business_status",
            f"{key}.baseline_shortfall_on (implies the status)",
            equals="BASELINE_SHORTFALL",
        ),
        _assert(f"{first}/on", f"{key}.baseline_shortfall_on", equals=on),
    ]
    if "balance" in value:
        source = f"{key}.balance"
        checks.append(
            _assert(f"{first}/balance", source, equals=ctx.money(value["balance"], source))
        )
    return {
        "name": key,
        "kind": "plan",
        "profile": DEFAULT_OPTIONS["profile"],
        "decision_scenario": sc,
        "assertions": checks,
    }


def _optimum_case(key: str, value: Json, ctx: _Context) -> dict[str, Json]:
    """<profile>_optimum: {card: amount} -> plan with that profile: proven optimal and the
    allocation consists of exactly these cards and amounts."""
    profile = key.removesuffix("_optimum")
    if profile not in PROFILES:
        raise ConversionError(f"expected.{key}: {profile!r} is not a profile")
    if not isinstance(value, dict) or not value:
        raise ConversionError(f"expected.{key}: expected {{card: amount}}")
    checks = [
        _assert("/solver_status", f"{key} (implies proven optimality)", equals="OPTIMAL"),
        _assert("/allocation", f"{key} (the cards listed, no others)", length=len(value)),
    ]
    for card, amount in value.items():
        if card not in ctx.card_ids:
            raise ConversionError(f"expected.{key}.{card}: not a card")
        source = f"{key}.{card}"
        checks.append(
            _assert(
                "/allocation",
                source,
                where={"card_id": card},
                then="/amount_minor",
                equals=ctx.money(amount, source),
            )
        )
    return {
        "name": key,
        "kind": "plan",
        "profile": profile,
        "decision_scenario": ctx.decision,
        "assertions": checks,
    }


def _sensitivity_case(key: str, value: Json, ctx: _Context) -> dict[str, Json]:
    """<scenario prefix>_sensitivity: sensitivity of that (failing) scenario in the plan of the
    fixture's decision scenario."""
    source_key = f"expected.{key}"
    sc = ctx.scenario(key.removesuffix("_sensitivity"), source_key)
    targets = {
        "min_extra_confirmed_cash": "total",
        "max_affordable_amount": "amount",
    }
    value = _members(value, source_key, set(targets), set())
    checks = []
    for member, expected in value.items():
        source = f"{key}.{member}"
        path = _pointer("sensitivity", sc, member, targets[member])
        checks.append(_assert(path, source, equals=ctx.money(expected, source)))
    return {
        "name": key,
        "kind": "plan",
        "profile": DEFAULT_OPTIONS["profile"],
        "decision_scenario": ctx.decision,
        "assertions": checks,
    }


def _expected(raw_expected: Json, ctx: _Context) -> list[dict[str, Json]]:
    if not isinstance(raw_expected, dict) or not raw_expected:
        raise ConversionError("expected: expected a non-empty object")
    rules: list[tuple[Callable[[str], bool], Callable[..., dict[str, Json]]]] = [
        (lambda k: k == "cycles", _cycles_case),
        (lambda k: k.startswith("plan_"), _verify_case),
        (lambda k: k.endswith("_scenario"), _shortfall_case),
        (lambda k: k.endswith("_optimum"), _optimum_case),
        (lambda k: k.endswith("_sensitivity"), _sensitivity_case),
    ]
    cases = []
    for key, value in raw_expected.items():
        rule = next((convert for match, convert in rules if match(key)), None)
        if rule is None:
            raise ConversionError(f"expected.{key}: no conversion rule for this key")
        cases.append(rule(key, value, ctx))
    return cases


# --- driver --------------------------------------------------------------------------------


def convert(source: bytes, source_path: str) -> dict[str, Json]:
    """Hand-written fixture bytes -> v1 Fixture document (validated with the adapter)."""
    try:
        raw = parse_json(source)
    except ProtocolError as e:
        raise ConversionError(f"not strict JSON: {e}") from None
    top = {"fixture_id", "description", "request", "cards", "cash_accounts", "snapshots"}
    top |= {"events", "horizon_end", "scenarios", "decision_scenario", "expected", "pools"}
    top |= {"global_reserve_floor"}
    required = top - {"description", "pools", "global_reserve_floor"}
    raw = _members(raw, "<fixture>", top, required)
    ctx = _Context(raw)
    plan_input = _plan_input(raw, ctx)
    try:
        inputs_from_protocol(plan_input)
    except ProtocolError as e:
        raise ConversionError(f"converted input is not valid protocol v1: {e}") from None
    doc: dict[str, Json] = {
        "protocol_version": PROTOCOL_VERSION,
        "fixture_id": raw["fixture_id"],
        "source": {
            "path": source_path,
            "sha256": hashlib.sha256(source).hexdigest(),
            "converter": CONVERTER,
        },
        "input": plan_input,
        "expected": _expected(raw["expected"], ctx),
    }
    if "description" in raw:
        doc["description"] = raw["description"]
    return doc


def serialise(doc: dict[str, Json]) -> bytes:
    """Sorted keys, 2-space indentation, UTF-8 without escaping, final newline."""
    return (json.dumps(doc, sort_keys=True, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def default_output(path: Path) -> Path:
    return path.with_name(path.name.removesuffix(".json") + ".v1.json")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("legacy", type=Path, help="hand-written fixture (.json)")
    parser.add_argument("-o", "--output", type=Path, help="default: <name>.v1.json alongside")
    parser.add_argument("--check", action="store_true", help="compare instead of writing")
    args = parser.parse_args(argv)
    legacy: Path = args.legacy.resolve()
    output: Path = (args.output or default_output(args.legacy)).resolve()
    try:
        relative = legacy.relative_to(PROTOCOL_ROOT).as_posix()
    except ValueError:
        relative = legacy.name
    try:
        data = serialise(convert(legacy.read_bytes(), relative))
    except (OSError, ConversionError) as e:
        sys.stderr.write(f"conversion failed: {e}\n")
        return 2
    if args.check:
        current = output.read_bytes() if output.exists() else b""
        same = current == data
        verdict = "identical" if same else "DIFFERENT"
        sys.stdout.write(f"{output}: regenerated output is {verdict} ({len(data)} bytes)\n")
        return 0 if same else 1
    output.write_bytes(data)
    sys.stdout.write(f"wrote {output} ({len(data)} bytes)\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
