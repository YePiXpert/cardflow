"""rules-protocol v1 adapter: JSON documents <-> engine objects (T-004).

Schemas: ``packages/rules-protocol/schema/v1/``. This module is part of the engine and uses
only the standard library -- no JSON Schema library. It therefore re-checks every rule it
relies on (types, ranges, patterns, unknown fields, and the cross-reference rules JSON Schema
cannot express), so the engine never receives a value it would silently misread, whether or
not the caller validated the document against the schemas first. Integer fields reject
booleans and every float (``1.0`` included); money is integer minor units, rates are decimal
strings. Violations raise :class:`ProtocolError` (invalid INPUT -> API ``VALIDATION_ERROR``,
fixture runner exit 2), which is deliberately not the engine's ``ModelInvalid`` (a
``MODEL_INVALID`` business outcome of a valid input).

Main entry points:

* :func:`inputs_from_protocol` -- PlanInput -> ``(ModelInputs, scenarios, PlanOptions)``;
* :func:`plan_from_protocol` -- run :func:`~cardflow.planner.engine.plan.plan` on a PlanInput
  and return a PlanOutcome document whose ``input_hash`` is :func:`protocol_input_hash`;
* :func:`outcome_to_protocol` -- engine ``PlanOutcome`` -> PlanOutcome document;
* :func:`verify_from_protocol`, :func:`card_cycles_to_protocol` -- solver-free outputs;
* :func:`canonical_json`, :func:`protocol_input_hash` -- the language-neutral input hash;
* :func:`parse_json` -- strict JSON reader (duplicate keys, NaN/Infinity, BOM rejected).

T-004c (engine-spec §12, model 1.1.0): rates and scale factors in canonical text only (and
``inputs_to_protocol`` writes database NUMERICs canonically); ``includes_event_ids`` up to the
snapshot day; an event's ``at`` on its ``on``; one available credit and one pool per credit
account; error messages name the path and the rule, never the value; the solver-free verifier
reports data issues instead of raising; outcomes carry an allocation only when actionable
(``diagnostics`` otherwise) and the baseline's global-floor breaches.
"""

from __future__ import annotations

import hashlib
import json
import math
import re
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from datetime import date, datetime
from decimal import Decimal
from typing import Any

from cardflow.planner.engine.allocation import (
    BIG,
    CardOption,
    ModelInputs,
    PlanRequest,
    derive_card_info,
)
from cardflow.planner.engine.billing import BillingRule, DueRule
from cardflow.planner.engine.cash import CashAccount, CashEvent, EventClass, Scenario, Snapshot
from cardflow.planner.engine.money import decimal_text
from cardflow.planner.engine.plan import PlanOutcome, data_issues, plan
from cardflow.planner.engine.verifier import ScenarioCheck, Verification, verify

PROTOCOL_VERSION = "1"

INT32_MAX = 2**31 - 1
RESERVED_EVENT_PREFIX = "plan_repay_"  # the verifier's own repayment events

# Supported numeric range (T-004b; derivation in packages/rules-protocol/README.md): with these
# limits every CP-SAT constraint the engine builds stays below CP-SAT's overflow bound.
MONEY_LIMIT = BIG  # |money| <= 10^13 minor units, the engine's variable bound
MAX_CARDS = 200
MAX_CASH_ACCOUNTS = 100
MAX_EVENTS = 10_000

_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}")
_CURRENCY = re.compile(r"[A-Z]{3}")
_CHANNEL = re.compile(r"[a-z][a-z0-9_]{0,31}")
_YEAR = r"(19[7-9][0-9]|2[0-9]{3})"  # 1970..2999
_MONTH_DAY = r"-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])"
_DATE = re.compile(_YEAR + _MONTH_DAY)
# hours 00-23, minutes and seconds 00-59 (no leap second), offset up to 23:59 (R3E-20)
_TIMESTAMP = re.compile(
    _YEAR
    + _MONTH_DAY
    + r"T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.[0-9]{1,6})?"
    + r"(Z|[+-]([01][0-9]|2[0-3]):[0-5][0-9])"
)
# Canonical decimal texts only -- no trailing fractional zeros, no superfluous leading zero:
# one value, one text, one input hash (R3E-11).
_RATE = re.compile(r"0|1|0\.[0-9]{0,4}[1-9]")  # 0..1, at most 5 decimals
_SCALE = re.compile(r"10|[0-9]|[0-9]\.[0-9]{0,9}[1-9]")  # 0..10, at most 10 decimals
TEXT_MAX = 1000
TIME_LIMIT_MAX_S = 3600

PROFILES = ("cash_safety", "verified_benefit", "fewer_cards")
EVENT_CATEGORIES = (
    "income",
    "bill",
    "living",
    "repayment",
    "transfer_in",
    "transfer_out",
    "fee",
    "other",
)

type Json = Any
type Conv = Callable[[object, str], Any]


class ProtocolError(ValueError):
    """A document violates protocol v1.

    ``path`` is an RFC 6901 JSON Pointer to the offending value (``""`` = the document).
    """

    def __init__(self, path: str, message: str) -> None:
        super().__init__(f"{path or '<document>'}: {message}")
        self.path = path
        self.message = message


@dataclass(frozen=True)
class PlanOptions:
    """PlanInput.options without ``global_reserve_floor_minor`` (that one is in ModelInputs)."""

    profile: str
    decision_scenario: str
    time_limit_s: float
    workers: int
    seed: int
    stale_after_days: int


# --- strict JSON reading -------------------------------------------------------------------


def parse_json(data: bytes | str) -> Json:
    """Parse JSON text strictly: UTF-8 without BOM, no duplicate object keys, no
    NaN/Infinity (also not as an overflowing literal such as ``1e400``)."""
    if isinstance(data, bytes):
        if data.startswith(b"\xef\xbb\xbf"):
            raise ProtocolError("", "a UTF-8 byte order mark is not allowed")
        try:
            data = data.decode("utf-8")
        except UnicodeDecodeError as e:
            raise ProtocolError("", f"not UTF-8 (invalid byte at offset {e.start})") from None

    def pairs(items: list[tuple[str, Json]]) -> dict[str, Json]:
        out: dict[str, Json] = {}
        for key, value in items:
            if key in out:
                raise ProtocolError("", "duplicate object key")
            out[key] = value
        return out

    def constant(name: str) -> float:
        raise ProtocolError("", f"{name} is not a JSON number")

    def finite(text: str) -> float:
        value = float(text)
        if not math.isfinite(value):
            raise ProtocolError("", "a number is out of the double range")
        return value

    try:
        return json.loads(
            data, object_pairs_hook=pairs, parse_constant=constant, parse_float=finite
        )
    except ProtocolError:
        raise
    except json.JSONDecodeError as e:  # the grammar rule (never the offending text) + position
        rule = e.msg.split(":")[0]
        raise ProtocolError(
            "", f"invalid JSON: {rule} (line {e.lineno}, column {e.colno})"
        ) from None
    except ValueError:  # an integer literal beyond Python's digit limit
        raise ProtocolError("", "invalid JSON: an integer literal is too long") from None
    except RecursionError:
        raise ProtocolError("", "invalid JSON: nested too deeply") from None


# --- canonical JSON and the input hash -----------------------------------------------------


def canonical_json(obj: Json) -> bytes:
    """Canonical UTF-8 serialisation used for :func:`protocol_input_hash`.

    No whitespace; object members sorted by key (UTF-16 code units, RFC 8785 §3.2.3 -- for the
    ASCII keys of protocol v1 this is plain ``sort_keys``); strings as ``json.dumps(...,
    ensure_ascii=False)`` (only ``"``, ``\\`` and U+0000..U+001F escaped; ``\\b \\t \\n \\f \\r``
    short forms, others ``\\u00xx`` lowercase); integers as exact decimal digits; non-integer
    numbers as ECMAScript ``Number.prototype.toString`` (RFC 8785 §3.2.2.3), so ``10.0``
    becomes ``10``. NaN, Infinity, lone surrogates, non-string keys and non-JSON values raise
    :class:`ProtocolError`.
    """
    parts: list[str] = []
    _canon(obj, "", parts)
    return "".join(parts).encode("utf-8")


def protocol_input_hash(doc: Json) -> str:
    """sha256 hex of :func:`canonical_json` of a PlanInput document (language-neutral)."""
    return hashlib.sha256(canonical_json(doc)).hexdigest()


def _canon(value: Json, path: str, out: list[str]) -> None:
    if value is None:
        out.append("null")
    elif value is True:
        out.append("true")
    elif value is False:
        out.append("false")
    elif isinstance(value, int):
        out.append(int.__repr__(value))
    elif isinstance(value, float):
        out.append(_es_number(value, path))
    elif isinstance(value, str):
        out.append(_canon_str(value, path))
    elif isinstance(value, (list, tuple)):
        out.append("[")
        for i, item in enumerate(value):
            if i:
                out.append(",")
            _canon(item, f"{path}/{i}", out)
        out.append("]")
    elif isinstance(value, dict):
        for key in value:
            if not isinstance(key, str):
                raise ProtocolError(path, "object keys must be strings")
        out.append("{")
        for i, key in enumerate(sorted(value, key=lambda k: k.encode("utf-16-be"))):
            if i:
                out.append(",")
            out.append(_canon_str(key, path))
            out.append(":")
            _canon(value[key], _pointer(path, key), out)
        out.append("}")
    else:
        raise ProtocolError(path, f"{type(value).__name__} is not a JSON value")


def _canon_str(text: str, path: str) -> str:
    if any(0xD800 <= ord(ch) <= 0xDFFF for ch in text):
        raise ProtocolError(path, "string contains a lone surrogate (not valid Unicode)")
    return json.dumps(text, ensure_ascii=False)


def _es_number(x: float, path: str) -> str:
    """ECMAScript Number::toString of a finite double (RFC 8785 §3.2.2.3)."""
    if not math.isfinite(x):
        raise ProtocolError(path, "NaN and Infinity are not JSON numbers")
    if x == 0:
        return "0"  # also -0.0
    if x < 0:
        return "-" + _es_number(-x, path)
    # Shortest round-trip digits of x (Python's repr, David Gay's algorithm, as ECMAScript
    # requires): x = int(all_digits) * 10**exp. Strip trailing zeros, then x = 0.d1..dk * 10**n.
    _, digit_tuple, exp = Decimal(repr(x)).as_tuple()
    all_digits = "".join(map(str, digit_tuple))
    digits = all_digits.rstrip("0")
    k = len(digits)
    n = int(exp) + len(all_digits)
    if k <= n <= 21:
        return digits + "0" * (n - k)
    if 0 < n <= 21:
        return f"{digits[:n]}.{digits[n:]}"
    if -6 < n <= 0:
        return "0." + "0" * (-n) + digits
    e = n - 1
    mantissa = digits if k == 1 else f"{digits[0]}.{digits[1:]}"
    return f"{mantissa}e{'+' if e >= 0 else '-'}{abs(e)}"


def _pointer(path: str, key: str | int) -> str:
    return f"{path}/{str(key).replace('~', '~0').replace('/', '~1')}"


# --- field converters ----------------------------------------------------------------------


def _kind(value: object) -> str:
    if isinstance(value, bool):
        return "a boolean"
    if isinstance(value, float):
        return "a float"
    if isinstance(value, int):
        return "an integer"
    if isinstance(value, str):
        return "a string"
    if isinstance(value, list):
        return "an array"
    if isinstance(value, dict):
        return "an object"
    return "null" if value is None else type(value).__name__


def _int(lo: int, hi: int) -> Conv:
    def conv(value: object, path: str) -> int:
        if isinstance(value, bool) or not isinstance(value, int):
            raise ProtocolError(path, f"expected an integer, got {_kind(value)}")
        if not lo <= value <= hi:  # the value itself is not echoed (may be an amount)
            raise ProtocolError(path, f"must be an integer in [{lo}, {hi}]")
        return value

    return conv


_MINOR = _int(-MONEY_LIMIT, MONEY_LIMIT)
_NONNEG_MINOR = _int(0, MONEY_LIMIT)
_POS_MINOR = _int(1, MONEY_LIMIT)
_DAYS = _int(0, 366)


def _bool(value: object, path: str) -> bool:
    if not isinstance(value, bool):
        raise ProtocolError(path, f"expected a boolean, got {_kind(value)}")
    return value


def _string(value: object, path: str) -> str:
    if not isinstance(value, str):
        raise ProtocolError(path, f"expected a string, got {_kind(value)}")
    return value


def _matching(pattern: re.Pattern[str], what: str) -> Conv:
    def conv(value: object, path: str) -> str:
        text = _string(value, path)
        if not pattern.fullmatch(text):  # the value itself is never echoed (R3E-12)
            raise ProtocolError(path, f"not a valid {what}")
        return text

    return conv


_id = _matching(_ID, "id (ASCII letters, digits and . _ : -, at most 128)")
_currency = _matching(_CURRENCY, "ISO 4217 currency code (3 capital letters)")
_channel = _matching(_CHANNEL, "channel (lowercase letters, digits and _)")


def _event_id(value: object, path: str) -> str:
    text = _id(value, path)
    if text.startswith(RESERVED_EVENT_PREFIX):
        raise ProtocolError(path, f"event ids starting with {RESERVED_EVENT_PREFIX!r} are reserved")
    return text


def _text(value: object, path: str) -> str:
    text = _string(value, path)
    if len(text) > TEXT_MAX:
        raise ProtocolError(path, f"longer than {TEXT_MAX} characters")
    if any(0xD800 <= ord(ch) <= 0xDFFF for ch in text):
        raise ProtocolError(path, "string contains a lone surrogate")
    return text


def _date(value: object, path: str) -> date:
    text = _string(value, path)
    if not _DATE.fullmatch(text):
        raise ProtocolError(path, "not a YYYY-MM-DD date in 1970..2999")
    try:
        return date.fromisoformat(text)
    except ValueError:
        raise ProtocolError(path, "not a valid calendar date") from None


def _timestamp(value: object, path: str) -> datetime:
    text = _string(value, path)
    if not _TIMESTAMP.fullmatch(text):
        raise ProtocolError(path, "not an RFC 3339 timestamp with an offset in 1970..2999")
    try:
        return datetime.fromisoformat(text)
    except ValueError:
        raise ProtocolError(path, "not a valid calendar date and time") from None


def _decimal_in(pattern: re.Pattern[str], what: str) -> Conv:
    def conv(value: object, path: str) -> Decimal:
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            raise ProtocolError(path, "rates and factors are decimal strings, not JSON numbers")
        text = _string(value, path)
        if not pattern.fullmatch(text):
            raise ProtocolError(path, f"not a {what}")
        return Decimal(text)

    return conv


_rate = _decimal_in(
    _RATE, "rate (canonical decimal string 0..1, at most 5 decimals, no trailing zeros)"
)
_scale = _decimal_in(
    _SCALE, "scale factor (canonical decimal string 0..10, at most 10 decimals, no trailing zeros)"
)


def _enum(*values: str) -> Conv:
    def conv(value: object, path: str) -> str:
        if not isinstance(value, str) or value not in values:
            raise ProtocolError(path, f"must be one of {list(values)}")
        return value

    return conv


def _array(item: Conv, min_items: int = 0, max_items: int | None = None) -> Conv:
    def conv(value: object, path: str) -> list[Any]:
        if not isinstance(value, list):
            raise ProtocolError(path, f"expected an array, got {_kind(value)}")
        if len(value) < min_items:
            raise ProtocolError(path, f"needs at least {min_items} item(s)")
        if max_items is not None and len(value) > max_items:
            raise ProtocolError(path, f"more than {max_items} items (supported range)")
        return [item(v, f"{path}/{i}") for i, v in enumerate(value)]

    return conv


def _time_limit(value: object, path: str) -> float:
    """``time_limit_s``: a JSON number (int or finite float) in (0, 3600]."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ProtocolError(path, f"expected a number, got {_kind(value)}")
    if not math.isfinite(value) or not 0 < value <= TIME_LIMIT_MAX_S:
        raise ProtocolError(path, f"must be in (0, {TIME_LIMIT_MAX_S}]")
    return value


class _Obj:
    """Strict reader of one JSON object: unknown members are errors."""

    def __init__(self, value: object, path: str, allowed: Iterable[str]) -> None:
        if not isinstance(value, dict):
            raise ProtocolError(path, f"expected an object, got {_kind(value)}")
        if not all(isinstance(key, str) for key in value):
            raise ProtocolError(path, "object keys must be strings")
        unknown = sorted(set(value) - set(allowed))
        if unknown:
            raise ProtocolError(_pointer(path, unknown[0]), "unknown member (not in protocol v1)")
        self.value: dict[str, object] = value
        self.path = path

    def req(self, key: str, conv: Conv) -> Any:  # noqa: ANN401 -- converter-defined type
        if key not in self.value:
            raise ProtocolError(self.path, f"missing required member {key!r}")
        return conv(self.value[key], _pointer(self.path, key))

    def opt(self, key: str, conv: Conv, default: object = None) -> Any:  # noqa: ANN401
        if key not in self.value:
            return default
        return conv(self.value[key], _pointer(self.path, key))


# --- PlanInput -> engine -------------------------------------------------------------------

_REQUEST = (
    "amount_minor",
    "currency",
    "txn_date",
    "allow_split",
    "max_cards",
    "min_split_minor",
    "payment_lead_days",
    "channel",
)
_RULE = (
    "rule_id",
    "statement_day",
    "statement_day_inclusive",
    "due",
    "holiday_rollover",
    "effective_from",
    "effective_to",
    "source",
    "verified_on",
    "status",
)
_CARD = (
    "card_id",
    "credit_account_id",
    "name",
    "raw_available_minor",
    "holds_uncounted_minor",
    "reservations_minor",
    "pool_id",
    "per_txn_cap_minor",
    "min_split_minor",
    "billing_rule",
    "repay_from_cash_account_id",
    "channel_ok",
    "currency_ok",
    "status_ok",
    "fee_rate",
    "fee_fixed_minor",
    "verified_benefit_rate",
    "verified_benefit_cap_minor",
    "potential_benefit_rate",
    "posting_delay_min_days",
    "posting_delay_max_days",
)
_ACCOUNT = ("cash_account_id", "name", "currency", "reserve_floor_minor", "usable_for_repayment")
_SNAPSHOT = ("cash_account_id", "balance_minor", "as_of", "observed_at", "includes_event_ids")
_EVENT = ("event_id", "cash_account_id", "on", "at", "amount_minor", "cls", "category", "label")
_SCENARIO = (
    "scenario_id",
    "include_expected",
    "income_delay_days",
    "income_scale",
    "expense_scale",
    "event_overrides",
    "same_day_order",
    "description",
)
_OPTIONS = (
    "profile",
    "decision_scenario",
    "time_limit_s",
    "workers",
    "seed",
    "stale_after_days",
    "global_reserve_floor_minor",
)
_PLAN_INPUT = (
    "protocol_version",
    "request",
    "cards",
    "pools",
    "cash_accounts",
    "snapshots",
    "events",
    "scenarios",
    "horizon_end",
    "options",
)


def _protocol_version(value: object, path: str) -> str:
    if value != PROTOCOL_VERSION or not isinstance(value, str):
        raise ProtocolError(path, f"unsupported protocol_version (expected {PROTOCOL_VERSION!r})")
    return value


def _request(value: object, path: str) -> PlanRequest:
    o = _Obj(value, path, _REQUEST)
    return PlanRequest(
        amount=o.req("amount_minor", _POS_MINOR),
        currency=o.req("currency", _currency),
        txn_date=o.req("txn_date", _date),
        allow_split=o.req("allow_split", _bool),
        max_cards=o.req("max_cards", _int(1, INT32_MAX)),
        min_split=o.req("min_split_minor", _POS_MINOR),
        payment_lead_days=o.req("payment_lead_days", _DAYS),
        channel=o.req("channel", _channel),
    )


def _due_rule(value: object, path: str) -> DueRule:
    kind = value.get("kind") if isinstance(value, dict) else None
    if kind == "fixed_day":
        o = _Obj(value, path, ("kind", "day", "month_offset"))
        return DueRule(
            "fixed_day",
            day=o.req("day", _int(1, 31)),
            month_offset=o.req("month_offset", _int(0, 2)),
        )
    if kind == "days_after_statement":
        o = _Obj(value, path, ("kind", "days", "day_kind"))
        return DueRule(
            "days_after_statement",
            days=o.req("days", _int(1, 60)),
            day_kind=o.req("day_kind", _enum("calendar", "business")),
        )
    o = _Obj(value, path, ("kind", "day", "month_offset", "days", "day_kind"))
    o.req("kind", _enum("fixed_day", "days_after_statement"))
    raise ProtocolError(path, "unreachable")  # pragma: no cover -- req() raised above


def _billing_rule(value: object, path: str) -> BillingRule:
    o = _Obj(value, path, _RULE)
    return BillingRule(
        rule_id=o.req("rule_id", _id),
        statement_day=o.req("statement_day", _int(1, 31)),
        due=o.req("due", _due_rule),
        statement_day_inclusive=o.req("statement_day_inclusive", _bool),
        holiday_rollover=o.req("holiday_rollover", _enum("none", "next_business_day")),
        effective_from=o.opt("effective_from", _date),
        effective_to=o.opt("effective_to", _date),
        source=o.opt("source", _text, ""),
        verified_on=o.opt("verified_on", _date),
        status=o.opt("status", _enum("draft", "verified", "user_declared"), "user_declared"),
    )


def _card(value: object, path: str) -> CardOption:
    o = _Obj(value, path, _CARD)
    card_id = o.req("card_id", _id)
    delay_min = o.req("posting_delay_min_days", _DAYS)
    delay_max = o.req("posting_delay_max_days", _DAYS)
    if delay_min > delay_max:
        raise ProtocolError(
            _pointer(path, "posting_delay_max_days"), "must be >= posting_delay_min_days"
        )
    return CardOption(
        id=card_id,
        account_id=o.req("credit_account_id", _id),
        name=o.opt("name", _text, card_id),
        raw_available=o.req("raw_available_minor", _MINOR),
        billing_rule=o.req("billing_rule", _billing_rule),
        repay_from=o.req("repay_from_cash_account_id", _id),
        uncounted_holds=o.req("holds_uncounted_minor", _NONNEG_MINOR),
        plan_reservations=o.req("reservations_minor", _NONNEG_MINOR),
        pool_id=o.opt("pool_id", _id),
        per_txn_cap=o.opt("per_txn_cap_minor", _NONNEG_MINOR),
        min_split=o.opt("min_split_minor", _POS_MINOR),
        channel_ok=o.req("channel_ok", _bool),
        currency_ok=o.req("currency_ok", _bool),
        status_ok=o.req("status_ok", _bool),
        fee_rate=o.req("fee_rate", _rate),
        fee_fixed=o.req("fee_fixed_minor", _NONNEG_MINOR),
        verified_benefit_rate=o.req("verified_benefit_rate", _rate),
        verified_benefit_cap=o.opt("verified_benefit_cap_minor", _NONNEG_MINOR),
        potential_benefit_rate=o.req("potential_benefit_rate", _rate),
        posting_delay_min=delay_min,
        posting_delay_max=delay_max,
    )


def _pool(value: object, path: str) -> tuple[str, int]:
    o = _Obj(value, path, ("pool_id", "available_minor"))
    return o.req("pool_id", _id), o.req("available_minor", _MINOR)


def _account(value: object, path: str) -> CashAccount:
    o = _Obj(value, path, _ACCOUNT)
    account_id = o.req("cash_account_id", _id)
    return CashAccount(
        id=account_id,
        name=o.opt("name", _text, account_id),
        currency=o.req("currency", _currency),
        reserve_floor=o.req("reserve_floor_minor", _NONNEG_MINOR),
        usable_for_repayment=o.req("usable_for_repayment", _bool),
    )


def _includes(value: object, path: str) -> list[str]:
    ids = _array(_event_id)(value, path)
    for i, event_id in enumerate(ids):
        if event_id in ids[:i]:
            raise ProtocolError(f"{path}/{i}", "duplicate event id")
    return ids


def _snapshot(value: object, path: str) -> Snapshot:
    o = _Obj(value, path, _SNAPSHOT)
    return Snapshot(
        account=o.req("cash_account_id", _id),
        balance=o.req("balance_minor", _MINOR),
        as_of=o.req("as_of", _date),
        observed_at=o.opt("observed_at", _timestamp),
        includes_event_ids=frozenset(o.req("includes_event_ids", _includes)),
    )


def _event(value: object, path: str) -> CashEvent:
    o = _Obj(value, path, _EVENT)
    return CashEvent(
        id=o.req("event_id", _event_id),
        account=o.req("cash_account_id", _id),
        on=o.req("on", _date),
        amount=o.req("amount_minor", _MINOR),
        cls=EventClass(o.req("cls", _enum("confirmed", "expected", "planned"))),
        category=o.req("category", _enum(*EVENT_CATEGORIES)),
        label=o.opt("label", _text, ""),
        at=o.opt("at", _timestamp),
    )


def _override(value: object, path: str) -> tuple[str, dict[str, Any]]:
    o = _Obj(value, path, ("event_id", "on", "amount_minor"))
    event_id = o.req("event_id", _event_id)
    change: dict[str, Any] = {}
    if "on" in o.value:
        change["on"] = o.req("on", _date)
    if "amount_minor" in o.value:
        change["amount"] = o.req("amount_minor", _MINOR)
    if not change:
        raise ProtocolError(path, "an override needs 'on' and/or 'amount_minor'")
    return event_id, change


def _scenario(value: object, path: str) -> tuple[Scenario, list[str]]:
    o = _Obj(value, path, _SCENARIO)
    scenario_id = o.req("scenario_id", _id)
    overrides = o.req("event_overrides", _array(_override))
    ordered = [event_id for event_id, _ in overrides]
    for i, event_id in enumerate(ordered):
        if event_id in ordered[:i]:
            raise ProtocolError(f"{path}/event_overrides/{i}/event_id", "event overridden twice")
    scenario = Scenario(
        id=scenario_id,
        include_expected=o.req("include_expected", _bool),
        income_delay_days=o.req("income_delay_days", _DAYS),
        income_scale=o.req("income_scale", _scale),
        expense_scale=o.req("expense_scale", _scale),
        event_overrides=dict(overrides),
        same_day_order=o.req("same_day_order", _enum("conservative", "timestamp")),
        description=o.opt("description", _text, ""),
    )
    return scenario, ordered


def _options(value: object, path: str) -> tuple[PlanOptions, int]:
    o = _Obj(value, path, _OPTIONS)
    options = PlanOptions(
        profile=o.req("profile", _enum(*PROFILES)),
        decision_scenario=o.req("decision_scenario", _id),
        time_limit_s=o.req("time_limit_s", _time_limit),
        workers=o.req("workers", _int(1, 64)),
        seed=o.req("seed", _int(0, INT32_MAX)),
        stale_after_days=o.req("stale_after_days", _DAYS),
    )
    return options, o.req("global_reserve_floor_minor", _NONNEG_MINOR)


def _unique(ids: list[str], path: str, member: str) -> None:
    seen: set[str] = set()
    for i, item_id in enumerate(ids):
        if item_id in seen:
            raise ProtocolError(f"{path}/{i}/{member}", f"duplicate {member}")
        seen.add(item_id)


def inputs_from_protocol(doc: Json) -> tuple[ModelInputs, dict[str, Scenario], PlanOptions]:
    """Validate a PlanInput document and build the engine's inputs.

    Raises :class:`ProtocolError` on any violation, including the cross-reference rules
    listed in ``PlanInput.schema.json``. Absent optional members map to the engine's "none"
    (``None``); absent display texts map to the id (names) or ``""`` (labels, descriptions,
    rule source) and an absent rule status to ``user_declared``.
    """
    o = _Obj(doc, "", _PLAN_INPUT)
    o.req("protocol_version", _protocol_version)
    request: PlanRequest = o.req("request", _request)
    cards: list[CardOption] = o.req("cards", _array(_card, 1, MAX_CARDS))
    pools: list[tuple[str, int]] = o.req("pools", _array(_pool))
    accounts: list[CashAccount] = o.req("cash_accounts", _array(_account, 1, MAX_CASH_ACCOUNTS))
    snapshots: list[Snapshot] = o.req("snapshots", _array(_snapshot))
    events: list[CashEvent] = o.req("events", _array(_event, 0, MAX_EVENTS))
    scenarios: list[tuple[Scenario, list[str]]] = o.req("scenarios", _array(_scenario, min_items=1))
    horizon_end: date = o.req("horizon_end", _date)
    options, global_floor = o.req("options", _options)

    _unique([c.id for c in cards], "/cards", "card_id")
    _unique([p for p, _ in pools], "/pools", "pool_id")
    _unique([a.id for a in accounts], "/cash_accounts", "cash_account_id")
    _unique([s.account for s in snapshots], "/snapshots", "cash_account_id")
    _unique([e.id for e in events], "/events", "event_id")
    _unique([s.id for s, _ in scenarios], "/scenarios", "scenario_id")
    account_ids = {a.id for a in accounts}
    for i, a in enumerate(accounts):
        if a.currency != request.currency:
            raise ProtocolError(
                f"/cash_accounts/{i}/currency",
                "differs from the request currency (protocol v1 plans are single-currency)",
            )
    first_of_account: dict[str, CardOption] = {}
    for i, c in enumerate(cards):
        if c.repay_from not in account_ids:
            raise ProtocolError(f"/cards/{i}/repay_from_cash_account_id", "unknown cash account")
        # Cards of one credit account share its available credit (engine-spec §12.3): they
        # report that one value and belong to the same pool (R3E-04).
        host = first_of_account.setdefault(c.account_id, c)
        if c.raw_available != host.raw_available:
            raise ProtocolError(
                f"/cards/{i}/raw_available_minor",
                "differs from another card of the same credit account "
                "(the account's available credit is one value)",
            )
        if c.pool_id != host.pool_id:
            raise ProtocolError(
                f"/cards/{i}/pool_id", "differs from another card of the same credit account"
            )
    for i, e in enumerate(events):
        if e.account not in account_ids:
            raise ProtocolError(f"/events/{i}/cash_account_id", "unknown cash account")
        if e.at is not None and e.at.date() != e.on:  # R3E-14: in the timestamp's own offset
            raise ProtocolError(f"/events/{i}/at", "its date (in its own offset) is not 'on'")
    event_of = {e.id: e for e in events}
    raw_snapshots: list[dict[str, Any]] = doc["snapshots"]
    for i, s in enumerate(snapshots):
        if s.account not in account_ids:
            raise ProtocolError(f"/snapshots/{i}/cash_account_id", "unknown cash account")
        for j, event_id in enumerate(raw_snapshots[i]["includes_event_ids"]):
            event = event_of.get(event_id)
            if event is None or event.account != s.account:
                raise ProtocolError(
                    f"/snapshots/{i}/includes_event_ids/{j}",
                    "not an event of this snapshot's cash account",
                )
            if event.on > s.as_of:  # a balance cannot contain a later event (R3E-14)
                raise ProtocolError(
                    f"/snapshots/{i}/includes_event_ids/{j}", "lists an event dated after as_of"
                )
    for i, (_, overridden) in enumerate(scenarios):
        for j, event_id in enumerate(overridden):
            if event_id not in event_of:
                raise ProtocolError(f"/scenarios/{i}/event_overrides/{j}/event_id", "unknown event")

    inputs = ModelInputs(
        request=request,
        cards=cards,
        pools=dict(pools),
        accounts=accounts,
        snapshots={s.account: s for s in snapshots},
        events=events,
        horizon_end=horizon_end,
        global_reserve_floor=global_floor,
    )
    return inputs, {s.id: s for s, _ in scenarios}, options


def allocation_from_protocol(items: Json, path: str = "/allocation") -> dict[str, int]:
    """``[{card_id, amount_minor}, ...]`` -> ``{card_id: amount}`` (card ids unique)."""

    def item(value: object, item_path: str) -> tuple[str, int]:
        o = _Obj(value, item_path, ("card_id", "amount_minor"))
        return o.req("card_id", _id), o.req("amount_minor", _POS_MINOR)

    pairs = _array(item, min_items=1)(items, path)
    _unique([card_id for card_id, _ in pairs], path, "card_id")
    return dict(pairs)


# --- engine -> PlanInput (round trip) ------------------------------------------------------


def _iso(value: date) -> str:
    return value.isoformat()


def _decimal_text(value: Decimal, path: str, pattern: re.Pattern[str] = _RATE) -> str:
    """The canonical text of an engine Decimal -- a NUMERIC(20,10) read from the database such
    as ``Decimal('0.0060000000')`` becomes ``"0.006"`` (R3E-11); a value outside the v1 range
    or with more digits than v1 carries is an error, never rounded."""
    try:
        text = decimal_text(Decimal(value))
    except (ValueError, ArithmeticError):
        raise ProtocolError(path, "not a finite decimal") from None
    if not pattern.fullmatch(text):
        raise ProtocolError(path, "outside the v1 range for this field")
    return text


def inputs_to_protocol(
    inputs: ModelInputs, scenarios: dict[str, Scenario], options: PlanOptions
) -> dict[str, Json]:
    """Engine inputs -> PlanInput document; the result is re-validated, so values protocol v1
    cannot represent raise :class:`ProtocolError`. Optional members that are ``None`` are
    omitted; display texts are always written."""
    req = inputs.request

    def card(c: CardOption, path: str) -> dict[str, Json]:
        rule = c.billing_rule
        due = rule.due
        if due.kind == "fixed_day":
            due_doc: dict[str, Json] = {
                "kind": "fixed_day",
                "day": due.day,
                "month_offset": due.month_offset,
            }
        else:
            due_doc = {"kind": due.kind, "days": due.days, "day_kind": due.day_kind}
        rule_doc: dict[str, Json] = {
            "rule_id": rule.rule_id,
            "statement_day": rule.statement_day,
            "statement_day_inclusive": rule.statement_day_inclusive,
            "due": due_doc,
            "holiday_rollover": rule.holiday_rollover,
            "source": rule.source,
            "status": rule.status,
        }
        for key in ("effective_from", "effective_to", "verified_on"):
            if getattr(rule, key) is not None:
                rule_doc[key] = _iso(getattr(rule, key))
        out: dict[str, Json] = {
            "card_id": c.id,
            "credit_account_id": c.account_id,
            "name": c.name,
            "raw_available_minor": c.raw_available,
            "holds_uncounted_minor": c.uncounted_holds,
            "reservations_minor": c.plan_reservations,
            "billing_rule": rule_doc,
            "repay_from_cash_account_id": c.repay_from,
            "channel_ok": c.channel_ok,
            "currency_ok": c.currency_ok,
            "status_ok": c.status_ok,
            "fee_rate": _decimal_text(c.fee_rate, f"{path}/fee_rate"),
            "fee_fixed_minor": c.fee_fixed,
            "verified_benefit_rate": _decimal_text(
                c.verified_benefit_rate, f"{path}/verified_benefit_rate"
            ),
            "potential_benefit_rate": _decimal_text(
                c.potential_benefit_rate, f"{path}/potential_benefit_rate"
            ),
            "posting_delay_min_days": c.posting_delay_min,
            "posting_delay_max_days": c.posting_delay_max,
        }
        for key, attr in (
            ("pool_id", "pool_id"),
            ("per_txn_cap_minor", "per_txn_cap"),
            ("min_split_minor", "min_split"),
            ("verified_benefit_cap_minor", "verified_benefit_cap"),
        ):
            if getattr(c, attr) is not None:
                out[key] = getattr(c, attr)
        return out

    def snapshot(s: Snapshot) -> dict[str, Json]:
        out: dict[str, Json] = {
            "cash_account_id": s.account,
            "balance_minor": s.balance,
            "as_of": _iso(s.as_of),
            "includes_event_ids": sorted(s.includes_event_ids),
        }
        if s.observed_at is not None:
            out["observed_at"] = s.observed_at.isoformat()
        return out

    def event(e: CashEvent) -> dict[str, Json]:
        out: dict[str, Json] = {
            "event_id": e.id,
            "cash_account_id": e.account,
            "on": _iso(e.on),
            "amount_minor": e.amount,
            "cls": EventClass(e.cls).value,
            "category": e.category,
            "label": e.label,
        }
        if e.at is not None:
            out["at"] = e.at.isoformat()
        return out

    def scenario(s: Scenario, path: str) -> dict[str, Json]:
        overrides = []
        for event_id, change in s.event_overrides.items():
            item: dict[str, Json] = {"event_id": event_id}
            if "on" in change:
                item["on"] = _iso(change["on"])
            if "amount" in change:
                item["amount_minor"] = change["amount"]
            overrides.append(item)
        return {
            "scenario_id": s.id,
            "include_expected": s.include_expected,
            "income_delay_days": s.income_delay_days,
            "income_scale": _decimal_text(s.income_scale, f"{path}/income_scale", _SCALE),
            "expense_scale": _decimal_text(s.expense_scale, f"{path}/expense_scale", _SCALE),
            "event_overrides": overrides,
            "same_day_order": s.same_day_order,
            "description": s.description,
        }

    doc: dict[str, Json] = {
        "protocol_version": PROTOCOL_VERSION,
        "request": {
            "amount_minor": req.amount,
            "currency": req.currency,
            "txn_date": _iso(req.txn_date),
            "allow_split": req.allow_split,
            "max_cards": req.max_cards,
            "min_split_minor": req.min_split,
            "payment_lead_days": req.payment_lead_days,
            "channel": req.channel,
        },
        "cards": [card(c, f"/cards/{i}") for i, c in enumerate(inputs.cards)],
        "pools": [{"pool_id": k, "available_minor": v} for k, v in inputs.pools.items()],
        "cash_accounts": [
            {
                "cash_account_id": a.id,
                "name": a.name,
                "currency": a.currency,
                "reserve_floor_minor": a.reserve_floor,
                "usable_for_repayment": a.usable_for_repayment,
            }
            for a in inputs.accounts
        ],
        "snapshots": [snapshot(s) for s in inputs.snapshots.values()],
        "events": [event(e) for e in inputs.events],
        "scenarios": [scenario(s, f"/scenarios/{i}") for i, s in enumerate(scenarios.values())],
        "horizon_end": _iso(inputs.horizon_end),
        "options": {
            "profile": options.profile,
            "decision_scenario": options.decision_scenario,
            "time_limit_s": options.time_limit_s,
            "workers": options.workers,
            "seed": options.seed,
            "stale_after_days": options.stale_after_days,
            "global_reserve_floor_minor": inputs.global_reserve_floor,
        },
    }
    inputs_from_protocol(doc)  # everything written must be a valid v1 document
    return doc


# --- engine -> outputs ---------------------------------------------------------------------


def _mapped(record: dict[str, Any], names: dict[str, str], where: str) -> dict[str, Any]:
    """Rename the members of an engine dict; a member the protocol does not know is an error
    (a new engine field must be added to the schema, never dropped silently)."""
    unknown = sorted(set(record) - set(names))
    if unknown:
        raise ProtocolError(where, f"engine produced members {unknown} unknown to protocol v1")
    return {names[k]: v for k, v in record.items()}


def _breach(b: dict[str, Any], where: str) -> dict[str, Json]:
    out = _mapped(
        b,
        {
            "account": "cash_account_id",
            "on": "on",
            "balance": "balance",
            "gap_to_zero": "gap_to_zero",
            "gap_to_reserve": "gap_to_reserve",
            "events": "events",
        },
        where,
    )
    out["on"] = _iso(out["on"])
    out["events"] = list(out["events"])
    return out


def _check(c: ScenarioCheck, where: str) -> dict[str, Json]:
    return {
        "ok": c.ok,
        "ok_zero": c.ok_zero,
        "min_balance_by_account": dict(c.min_balance_by_account),
        "min_on_by_account": {aid: _iso(d) for aid, d in c.min_on_by_account.items()},
        "end_balance_by_account": dict(c.end_balance_by_account),
        "breaches": [_breach(b, f"{where}/breaches") for b in c.breaches],
        "first_breach": None if c.first_breach is None else _breach(c.first_breach, where),
        "global_breaches": _global_breaches(c.global_breaches),
        "assumptions": list(c.assumptions),
    }


def verification_to_protocol(ver: Verification) -> dict[str, Json]:
    """Verifier result -> ``Verification`` (allocation lines are separate, see below)."""
    return {
        "ok": ver.ok,
        "structural_ok": ver.structural_ok,
        "violations": list(ver.violations),
        "decision_scenario": ver.decision_scenario,
        "weighted_buffer_days": str(ver.weighted_buffer_days),
        "fees": ver.fees,
        "verified_benefit": ver.verified_benefit,
        "potential_benefit": ver.potential_benefit,
        "checks": {
            sid: _check(chk, f"/verification/checks/{sid}") for sid, chk in ver.checks.items()
        },
    }


def allocation_lines_to_protocol(ver: Verification) -> list[dict[str, Json]]:
    """The verifier's per-card lines -> ``AllocationLine`` documents (API-52 names)."""
    out = []
    for line in ver.lines:
        doc = _mapped(
            line,
            {
                "card": "card_id",
                "amount": "amount_minor",
                "statement_date": "statement_date",
                "due_date": "due_date",
                "repay_on": "repay_on",
                "repay_from": "repay_from_cash_account_id",
                "buffer_days": "buffer_days",
                "fee": "fee_minor",
                "verified_benefit": "verified_benefit_minor",
                "potential_benefit": "potential_benefit_minor",
                "cycle_assumptions": "cycle_assumptions",
                "alternative_cycles": "alternative_cycles",
            },
            "/allocation",
        )
        for key in ("statement_date", "due_date", "repay_on"):
            doc[key] = _iso(doc[key])
        doc["cycle_assumptions"] = list(doc["cycle_assumptions"])
        doc["alternative_cycles"] = [
            {"statement_date": _iso(s), "due_date": _iso(d)} for s, d in doc["alternative_cycles"]
        ]
        out.append(doc)
    return out


def verification_result_to_protocol(ver: Verification) -> dict[str, Json]:
    """``VerificationResult``: what a solver-free runner (the Dart client) can compute."""
    return {
        "data_issues": [],
        "allocation": allocation_lines_to_protocol(ver),
        "verification": verification_to_protocol(ver),
    }


_ISSUE = {
    "code": "code",
    "account": "cash_account_id",
    "card": "card_id",
    "pool": "pool_id",
    "scenario": "scenario_id",
    "as_of": "as_of",
    "age_days": "age_days",
    "detail": "detail",
}
_REJECTION = {
    "card": "card_id",
    "reason": "reason",
    "capacity": "capacity",
    "amount": "amount",
    "note": "note",
    "detail": "detail",
    "first_breach": "first_breach",
    "all_breaches": "all_breaches",
    "min_balance": "min_balance",
    "buffer_days": "buffer_days",
}


def _sensitivity(entry: dict[str, Any], where: str) -> dict[str, Json]:
    if set(entry) == {"note"}:
        return {"note": entry["note"]}
    out = _mapped(
        entry,
        {
            "min_extra_confirmed_cash": "min_extra_confirmed_cash",
            "max_affordable_amount": "max_affordable_amount",
            "first_feasible_date_shift": "first_feasible_date_shift",
        },
        where,
    )
    same = {k: k for k in ("status", "extra_cash_by_account", "total", "allocation", "detail")}
    out["min_extra_confirmed_cash"] = _mapped(
        out["min_extra_confirmed_cash"], same, f"{where}/min_extra_confirmed_cash"
    )
    same = {k: k for k in ("status", "amount", "allocation", "detail")}
    out["max_affordable_amount"] = _mapped(
        out["max_affordable_amount"], same, f"{where}/max_affordable_amount"
    )
    shift = out["first_feasible_date_shift"]
    if shift is not None:
        same = {k: k for k in ("shift_days", "txn_date", "status", "detail")}
        out["first_feasible_date_shift"] = _mapped(
            shift, same, f"{where}/first_feasible_date_shift"
        )
    return out


def _rejection(r: dict[str, Any], where: str) -> dict[str, Json]:
    out = _mapped(r, _REJECTION, where)
    if out.get("first_breach") is not None:
        out["first_breach"] = _breach(out["first_breach"], f"{where}/first_breach")
    if "all_breaches" in out:
        out["all_breaches"] = [_breach(b, f"{where}/all_breaches") for b in out["all_breaches"]]
    if "min_balance" in out:
        out["min_balance"] = dict(out["min_balance"])
    return out


def _issues_to_protocol(data_issues: list[dict[str, Any]]) -> list[dict[str, Json]]:
    issues = []
    for i, issue in enumerate(data_issues):
        doc = _mapped(issue, _ISSUE, f"/data_issues/{i}")
        if "as_of" in doc:
            doc["as_of"] = _iso(doc["as_of"])
        issues.append(doc)
    return issues


def _global_breaches(breaches: list[dict[str, Any]]) -> list[dict[str, Json]]:
    return [{"on": _iso(g["on"]), "total": g["total"], "gap": g["gap"]} for g in breaches]


def _diagnostics(diagnostics: dict[str, Any] | None) -> dict[str, Json] | None:
    """Non-actionable outcomes only (engine-spec §12.1): a verifier-rejected allocation with its
    verification, for defect reports. Never a plan to show or adopt."""
    if diagnostics is None:
        return None
    names = ("code", "rejected_allocation", "rejected_verification")
    _mapped(diagnostics, {k: k for k in names}, "/diagnostics")  # no member is dropped silently
    out: dict[str, Json] = {"code": diagnostics["code"]}
    ver = diagnostics.get("rejected_verification")
    if ver is not None:
        lines = allocation_lines_to_protocol(ver)
        rejected = {line["card_id"]: line["amount_minor"] for line in lines}
        if rejected != dict(diagnostics.get("rejected_allocation", {})):
            raise ProtocolError("/diagnostics", "rejected allocation and its lines disagree")
        out["rejected_allocation"] = lines
        out["rejected_verification"] = verification_to_protocol(ver)
    return out


def outcome_to_protocol(outcome: PlanOutcome) -> dict[str, Json]:
    """Engine ``PlanOutcome`` -> PlanOutcome document (schema ``PlanOutcome.schema.json``).

    ``allocation`` and ``verification`` are filled for FEASIBLE_ROBUST and
    CONDITIONALLY_FEASIBLE only; a verifier-rejected allocation appears under ``diagnostics``
    (engine-spec §12.1)."""
    solve = outcome.solve
    ver = outcome.verification
    lines = allocation_lines_to_protocol(ver) if ver is not None else []
    if {line["card_id"]: line["amount_minor"] for line in lines} != dict(outcome.allocation):
        raise ProtocolError("/allocation", "engine allocation and verification lines disagree")
    issues = _issues_to_protocol(outcome.data_issues)
    baseline = {}
    for sid, b in outcome.baseline.items():
        accounts = {}
        for aid, acc in b["accounts"].items():
            accounts[aid] = {
                "min_balance": acc["min_balance"],
                "min_on": _iso(acc["min_on"]),
                "end_balance": acc["end_balance"],
                "breaches": [
                    {
                        "on": _iso(br["on"]),
                        "balance": br["balance"],
                        "gap_to_zero": br["gap_to_zero"],
                        "gap_to_reserve": br["gap_to_reserve"],
                    }
                    for br in acc["breaches"]
                ],
            }
        baseline[sid] = {
            "ok": b["ok"],
            "accounts": accounts,
            "global_breaches": _global_breaches(b["global_breaches"]),
            "assumptions": list(b["assumptions"]),
        }
    return {
        "protocol_version": PROTOCOL_VERSION,
        "run_id": outcome.run_id,
        "created_at": outcome.created_at,
        "input_hash": outcome.input_hash,
        "model_version": outcome.model_version,
        "solver_version": outcome.solver_version,
        "profile": outcome.profile,
        "decision_scenario": outcome.decision_scenario,
        "time_limit_s": outcome.time_limit_s,
        "workers": outcome.workers,
        "seed": outcome.seed,
        "solver_status": solve.status if solve is not None else "NOT_RUN",
        "business_status": outcome.business_status,
        "proven_optimal": solve.proven_optimal if solve is not None else False,
        "wall_time_s": solve.wall_time_s if solve is not None else None,
        "checkpoints": solve.checkpoints if solve is not None else 0,
        "tiers": [
            {
                "name": t.name,
                "sense": t.sense,
                "status": t.status,
                "value": t.value,
                "bound": t.bound,
                "wall_time_s": t.wall_time_s,
            }
            for t in (solve.tiers if solve is not None else [])
        ],
        "data_issues": issues,
        "baseline": baseline,
        "allocation": lines,
        "verification": verification_to_protocol(ver) if ver is not None else None,
        "failing_scenarios": list(outcome.failing_scenarios),
        "rejections": [_rejection(r, f"/rejections/{i}") for i, r in enumerate(outcome.rejections)],
        "sensitivity": {
            sid: _sensitivity(s, f"/sensitivity/{sid}") for sid, s in outcome.sensitivity.items()
        },
        "assumptions": list(outcome.assumptions),
        "notes": list(outcome.notes),
        "diagnostics": _diagnostics(outcome.diagnostics),
    }


def card_cycles_to_protocol(inputs: ModelInputs) -> dict[str, Json]:
    """``CardCycles``: conservative billing cycle of every card for the transaction date."""
    out: dict[str, Json] = {}
    for c in inputs.cards:
        try:
            info = derive_card_info(c, inputs.request)
        except (ValueError, OverflowError) as e:  # invalid rule, or a date past the calendar
            out[c.id] = {"error": str(e)}
            continue
        out[c.id] = {
            "statement_date": _iso(info.cycle.statement_date),
            "due_date": _iso(info.cycle.due_date),
            "repay_on": _iso(info.repay_on),
            "buffer_days": info.buffer_days,
            "cycle_assumptions": list(info.cycle.assumptions),
            "alternative_cycles": [
                {"statement_date": _iso(x.statement_date), "due_date": _iso(x.due_date)}
                for x in info.all_cycles[1:]
            ],
        }
    return out


# --- one-call entry points -----------------------------------------------------------------


def plan_from_protocol(
    doc: Json, *, run_id: str | None = None, with_sensitivity: bool = True
) -> dict[str, Json]:
    """Validate a PlanInput, run the engine with its options and return the PlanOutcome
    document. ``input_hash`` = :func:`protocol_input_hash` of ``doc``; ``run_id`` defaults to
    a fresh uuid4 (API-51 passes the one it pre-allocated)."""
    inputs, scenarios, options = inputs_from_protocol(doc)
    outcome = plan(
        inputs,
        scenarios,
        options.decision_scenario,
        options.profile,
        options.time_limit_s,
        options.stale_after_days,
        with_sensitivity,
        workers=options.workers,
        seed=options.seed,
        input_hash=protocol_input_hash(doc),
        run_id=run_id,
    )
    return outcome_to_protocol(outcome)


def verify_from_protocol(doc: Json, allocation: Json, decision_scenario: Json) -> dict[str, Json]:
    """Run the independent verifier (no solver) on a given allocation of a PlanInput.

    The same data checks as ``plan()`` come first (review R3E-13): a valid document that the
    engine answers with NEEDS_DATA (missing or stale snapshot, a rule that needs a calendar, a
    pool without an entry) gives ``data_issues`` and no verification instead of an exception.
    Only an invalid document or request raises (:class:`ProtocolError`)."""
    inputs, scenarios, options = inputs_from_protocol(doc)
    alloc = allocation_from_protocol(allocation)
    scenario_id = _id(decision_scenario, "/decision_scenario")
    if scenario_id not in scenarios:
        raise ProtocolError("/decision_scenario", "unknown scenario")
    issues = data_issues(inputs, options.stale_after_days)
    if issues:
        return {"data_issues": _issues_to_protocol(issues), "allocation": [], "verification": None}
    return verification_result_to_protocol(verify(inputs, alloc, scenarios, scenario_id))
