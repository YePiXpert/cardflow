"""Independent reference semantics for the engine's differential test (T-004c).

Written from engine-spec §3/§5/§12, bank-rules-spec §3/§5 and the rules-protocol README -- not
from the engine code: it imports nothing from ``cardflow``. It reads protocol v1 PlanInput
documents (plain dicts) and works out, by brute force over every allocation of a small
instance, what the engine must answer: data issues, baselines (with the global floor),
eligibility, the scenario checks of the independent verifier, the lexicographic optimum and its
canonical tie-break, the business status, rejection reasons and the sensitivity results. Money
is ``int``; rates and factors are :class:`fractions.Fraction` of their decimal strings.

The second half holds the seeded generators of small random PlanInput documents:
:func:`gen_review_doc` reproduces the generator of the wave-3 review (same random calls, so the
review's seeds give the review's documents); :func:`gen_doc` adds what §12 changed (cards that
share a credit account, holds/reservations in pools, snapshot inclusion of earlier events,
re-dated timestamped events, repayments after ``horizon_end``, near-identical cards).

Semantics implemented here (the engine-spec §12 rulings, model 1.1.0):

* snapshot reflection is judged on the ORIGINAL event, before the scenario; a scenario event
  moved before the snapshot counts on the snapshot day; a re-dated event loses ``at``;
* a day is ordered by timestamp when the scenario says so and every existing event of the day
  has ``at``; planned repayments then come first; otherwise outflows (repayments included)
  precede inflows;
* a planned repayment is amount + fee, on ``repay_on`` (on the snapshot day if earlier);
* capacity layers: card, credit account (cards sharing ``credit_account_id``; the account's
  available minus every member's holds and reservations), pool (available minus every member's
  holds and reservations);
* exclusions, in this order: CARD_STATUS, CURRENCY_NOT_SUPPORTED, CHANNEL_NOT_SUPPORTED,
  REPAY_ACCOUNT_MISSING, REPAY_ACCOUNT_RESTRICTED, NO_CAPACITY (card, account, pool),
  MIN_SPLIT_ABOVE_AMOUNT, REPAY_BEFORE_TXN_DATE, REPAY_AFTER_HORIZON; the horizon is never
  extended;
* the baseline check includes the global floor; ties after the last objective tier are broken
  by the lexicographically largest allocation in card input order.
"""

from __future__ import annotations

import calendar
import random
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from fractions import Fraction
from itertools import pairwise
from typing import Any

type Doc = dict[str, Any]
type Alloc = dict[str, int]

ACTIONABLE = ("FEASIBLE_ROBUST", "CONDITIONALLY_FEASIBLE")
TIERS = {
    "cash_safety": [
        ("min_margin", "max"),
        ("fees", "min"),
        ("net_verified_benefit", "max"),
        ("buffer", "max"),
        ("cards", "min"),
    ],
    "verified_benefit": [
        ("net_verified_benefit", "max"),
        ("min_margin", "max"),
        ("buffer", "max"),
        ("cards", "min"),
    ],
    "fewer_cards": [
        ("cards", "min"),
        ("min_margin", "max"),
        ("net_verified_benefit", "max"),
        ("buffer", "max"),
    ],
}
MAX_SHIFT_DAYS = 45


def day(text: str) -> date:
    return date.fromisoformat(text)


# --- billing (bank-rules-spec §3) ------------------------------------------------------------


class RuleError(Exception):
    """The rule gives no cycle for this posting date."""


def _clamp(year: int, month: int, dom: int) -> date:
    return date(year, month, min(dom, calendar.monthrange(year, month)[1]))


def _add_months(year: int, month: int, n: int) -> tuple[int, int]:
    k = month - 1 + n
    return year + k // 12, k % 12 + 1


def cycle(rule: dict[str, Any], posting: date) -> tuple[date, date]:
    if "effective_from" in rule and posting < day(rule["effective_from"]):
        raise RuleError("not yet effective")
    if "effective_to" in rule and posting >= day(rule["effective_to"]):
        raise RuleError("no longer effective")
    stmt = _clamp(posting.year, posting.month, rule["statement_day"])
    if not (posting < stmt or (posting == stmt and rule["statement_day_inclusive"])):
        stmt = _clamp(*_add_months(posting.year, posting.month, 1), rule["statement_day"])
    due_rule = rule["due"]
    if due_rule["kind"] == "fixed_day":
        due = _clamp(*_add_months(stmt.year, stmt.month, due_rule["month_offset"]), due_rule["day"])
        if due <= stmt:
            raise RuleError("due not after the statement")
    else:
        if due_rule["day_kind"] != "calendar":
            raise RuleError("business days need a calendar")
        due = stmt + timedelta(days=due_rule["days"])
    if rule["holiday_rollover"] != "none":
        raise RuleError("rollover needs a calendar")
    return stmt, due


def conservative_cycle(card: dict[str, Any], txn: date) -> tuple[date, date]:
    """Earliest due date within the posting window; any failing posting date fails the card."""
    delays = range(card["posting_delay_min_days"], card["posting_delay_max_days"] + 1)
    cycles = [cycle(card["billing_rule"], txn + timedelta(days=k)) for k in delays]
    return min(cycles, key=lambda c: c[1])


# --- cards on a transaction date -------------------------------------------------------------


@dataclass
class Card:
    id: str
    credit_account: str
    capacity: int  # card layer: max(0, raw - holds - reservations)
    cap: int  # min(card, per-transaction cap, credit account layer, pool layer)
    min_split: int
    pool: str | None
    repay_from: str
    repay_on: date
    buffer: int
    fee_rate: Fraction
    fee_fixed: int
    ben_rate: Fraction
    ben_cap: int | None
    pot_rate: Fraction
    per_txn_cap: int | None
    reason: str | None  # exclusion code; None = eligible


def layers(doc: Doc) -> tuple[dict[str, int], dict[str, int]]:
    """(credit-account layer for accounts with two or more cards, pool layer per pool)."""
    by_account: dict[str, list[dict[str, Any]]] = {}
    for c in doc["cards"]:
        by_account.setdefault(c["credit_account_id"], []).append(c)
    account = {
        aid: max(
            0,
            min(c["raw_available_minor"] for c in cs)
            - sum(c["holds_uncounted_minor"] + c["reservations_minor"] for c in cs),
        )
        for aid, cs in by_account.items()
        if len(cs) > 1
    }
    pool = {}
    for p in doc["pools"]:
        members = [c for c in doc["cards"] if c.get("pool_id") == p["pool_id"]]
        used = sum(c["holds_uncounted_minor"] + c["reservations_minor"] for c in members)
        pool[p["pool_id"]] = max(0, p["available_minor"] - used)
    return account, pool


def cards_at(doc: Doc, txn: date, *, strict: bool = True) -> list[Card]:
    """Every card with its facts on ``txn``. A rule that gives no cycle raises RuleError if
    ``strict`` (a data issue on the real transaction date) or drops the card (a shifted date of
    the date-shift search: the card is unavailable that day)."""
    req = doc["request"]
    amount = req["amount_minor"]
    horizon = day(doc["horizon_end"])
    accounts = {a["cash_account_id"]: a for a in doc["cash_accounts"]}
    account_layer, pool_layer = layers(doc)
    out = []
    for c in doc["cards"]:
        try:
            _, due = conservative_cycle(c, txn)
        except RuleError:
            if strict:
                raise
            continue
        repay_on = due - timedelta(days=req["payment_lead_days"])
        capacity = max(
            0, c["raw_available_minor"] - c["holds_uncounted_minor"] - c["reservations_minor"]
        )
        caps = [capacity]
        if "per_txn_cap_minor" in c:
            caps.append(c["per_txn_cap_minor"])
        if c["credit_account_id"] in account_layer:
            caps.append(account_layer[c["credit_account_id"]])
        pool = c.get("pool_id")
        if pool in pool_layer:
            caps.append(pool_layer[pool])
        min_split = c.get("min_split_minor", req["min_split_minor"])
        acct = accounts.get(c["repay_from_cash_account_id"])
        if not c["status_ok"]:
            reason = "CARD_STATUS"
        elif not c["currency_ok"]:
            reason = "CURRENCY_NOT_SUPPORTED"
        elif not c["channel_ok"]:
            reason = "CHANNEL_NOT_SUPPORTED"
        elif acct is None:
            reason = "REPAY_ACCOUNT_MISSING"
        elif not acct["usable_for_repayment"]:
            reason = "REPAY_ACCOUNT_RESTRICTED"
        elif (
            capacity <= 0
            or account_layer.get(c["credit_account_id"], 1) <= 0
            or pool_layer.get(pool, 1) <= 0
        ):
            reason = "NO_CAPACITY"
        elif min_split > amount:
            reason = "MIN_SPLIT_ABOVE_AMOUNT"
        elif repay_on < txn:
            reason = "REPAY_BEFORE_TXN_DATE"
        elif repay_on > horizon:
            reason = "REPAY_AFTER_HORIZON"
        else:
            reason = None
        out.append(
            Card(
                id=c["card_id"],
                credit_account=c["credit_account_id"],
                capacity=capacity,
                cap=min(caps),
                min_split=min_split,
                pool=pool,
                repay_from=c["repay_from_cash_account_id"],
                repay_on=repay_on,
                buffer=(repay_on - txn).days,
                fee_rate=Fraction(c["fee_rate"]),
                fee_fixed=c["fee_fixed_minor"],
                ben_rate=Fraction(c["verified_benefit_rate"]),
                ben_cap=c.get("verified_benefit_cap_minor"),
                pot_rate=Fraction(c["potential_benefit_rate"]),
                per_txn_cap=c.get("per_txn_cap_minor"),
                reason=reason,
            )
        )
    return out


def _ceil(q: Fraction) -> int:
    return -(-q.numerator // q.denominator)


def fee_of(c: Card, x: int) -> int:
    return 0 if x == 0 else _ceil(c.fee_rate * x) + c.fee_fixed


def ben_of(c: Card, x: int) -> int:
    v = c.ben_rate * x
    b = v.numerator // v.denominator
    return b if c.ben_cap is None else min(b, c.ben_cap)


def pot_of(c: Card, x: int) -> int:
    v = c.pot_rate * x
    return v.numerator // v.denominator


# --- data issues -----------------------------------------------------------------------------


def data_issues(doc: Doc) -> set[str]:
    txn = day(doc["request"]["txn_date"])
    snaps = {s["cash_account_id"]: s for s in doc["snapshots"]}
    codes = set()
    for a in doc["cash_accounts"]:
        s = snaps.get(a["cash_account_id"])
        if s is None:
            codes.add("MISSING_SNAPSHOT")
        elif day(s["as_of"]) > txn:
            codes.add("SNAPSHOT_AFTER_TXN_DATE")
        elif (txn - day(s["as_of"])).days > doc["options"]["stale_after_days"]:
            codes.add("STALE_SNAPSHOT")
    try:
        cards_at(doc, txn)
    except RuleError:
        codes.add("BILLING_RULE_INVALID")
    pools = {p["pool_id"] for p in doc["pools"]}
    if any(c.get("pool_id") and c["pool_id"] not in pools for c in doc["cards"]):
        codes.add("MISSING_POOL_SNAPSHOT")
    if doc["options"]["decision_scenario"] not in {s["scenario_id"] for s in doc["scenarios"]}:
        codes.add("UNKNOWN_DECISION_SCENARIO")
    return codes


# --- scenarios and timelines -----------------------------------------------------------------


def _scale(amount: int, factor: str) -> int:
    sign = -1 if amount < 0 else 1
    q, r = divmod(abs(amount) * Fraction(factor), 1)
    return sign * (int(q) + (1 if 2 * r >= 1 else 0))  # half up on the magnitude


@dataclass
class Point:
    on: date
    phase: str  # snapshot | low | end
    balance: int
    has_outflow: bool


def account_points(
    doc: Doc,
    sc: dict[str, Any],
    account_id: str,
    planned: list[tuple[date, int]] = (),  # type: ignore[assignment]
    extra_days: set[date] = frozenset(),  # type: ignore[assignment]
) -> list[Point]:
    snap = next(s for s in doc["snapshots"] if s["cash_account_id"] == account_id)
    as_of, horizon = day(snap["as_of"]), day(doc["horizon_end"])
    includes = set(snap["includes_event_ids"])
    overrides = {o["event_id"]: o for o in sc["event_overrides"]}
    days: dict[date, list[tuple[str, int, datetime | None]]] = {}
    for e in doc["events"]:
        if e["cash_account_id"] != account_id:
            continue
        original = day(e["on"])
        if original < as_of or (original == as_of and e["event_id"] in includes):
            continue  # reflected in the snapshot: judged before any scenario change
        if e["cls"] == "expected" and not sc["include_expected"]:
            continue
        on, amount = original, e["amount_minor"]
        o = overrides.get(e["event_id"], {})
        on = day(o["on"]) if "on" in o else on
        amount = o.get("amount_minor", amount)
        if e["cls"] == "expected" and amount > 0:
            on += timedelta(days=sc["income_delay_days"])
            amount = _scale(amount, sc["income_scale"])
        if amount < 0 and e["category"] == "living":
            amount = _scale(amount, sc["expense_scale"])
        at = datetime.fromisoformat(e["at"]) if "at" in e and on == original else None
        if on < as_of:
            on, at = as_of, None  # moved before the snapshot: counted on the snapshot day
        if on <= horizon:
            days.setdefault(on, []).append(("event", amount, at))
    for on, amount in planned:
        if on <= horizon:
            days.setdefault(on, []).append(("plan", amount, None))
    for d in extra_days:
        if as_of <= d <= horizon:
            days.setdefault(d, [])
    balance = snap["balance_minor"]
    points = [Point(as_of, "snapshot", balance, False)]
    for d in sorted(days):
        items = days[d]
        events = [i for i in items if i[0] == "event"]
        plans = [i for i in items if i[0] == "plan"]
        if sc["same_day_order"] == "timestamp" and all(at is not None for _, _, at in events):
            running = balance + sum(a for _, a, _ in plans)
            low = min(balance, running)
            for _, a, _ in sorted(events, key=lambda i: i[2]):  # stable for equal instants
                running += a
                low = min(low, running)
            end = running
        else:
            low = balance + sum(a for _, a, _ in items if a < 0)
            end = low + sum(a for _, a, _ in items if a > 0)
        points.append(Point(d, "low", low, any(a < 0 for _, a, _ in items)))
        points.append(Point(d, "end", end, False))
        balance = end
    return points


def value_on(points: list[Point], d: date) -> int:
    """Balance seen at checkpoint ``d``: the intraday low if the account has a point that day,
    else the end balance of its last earlier day (or the snapshot)."""
    value = points[0].balance
    for p in points[1:]:
        if p.on == d and p.phase == "low":
            return p.balance
        if p.on < d and p.phase == "end":
            value = p.balance
    return value


@dataclass
class Check:
    ok: bool
    min_balance: dict[str, int]
    breaches: list[tuple[str, str, int]]  # (on, account, balance)
    global_breaches: list[tuple[str, int]]


def planned_repayments(doc: Doc, cards: dict[str, Card], alloc: Alloc) -> dict[str, list]:
    snaps = {s["cash_account_id"]: day(s["as_of"]) for s in doc["snapshots"]}
    out: dict[str, list[tuple[date, int]]] = {}
    for cid, x in alloc.items():
        if x == 0 or cid not in cards:
            continue
        c = cards[cid]
        on = max(c.repay_on, snaps.get(c.repay_from, c.repay_on))
        out.setdefault(c.repay_from, []).append((on, -(x + fee_of(c, x))))
    return out


def check(doc: Doc, sc: dict[str, Any], cards: dict[str, Card], alloc: Alloc) -> Check:
    """The verifier's scenario check of ``alloc`` (the baseline when ``alloc`` is empty)."""
    planned = planned_repayments(doc, cards, alloc)
    points, mins, breaches = {}, {}, []
    for a in doc["cash_accounts"]:
        aid = a["cash_account_id"]
        pts = account_points(doc, sc, aid, planned.get(aid, []))
        points[aid] = pts
        floor = a["reserve_floor_minor"]
        mins[aid] = min(p.balance for p in pts if p.phase != "end")
        for p in pts:
            if p.balance < floor and (
                p.phase == "snapshot" or (p.phase == "low" and p.has_outflow)
            ):
                breaches.append((p.on.isoformat(), aid, p.balance))
    global_breaches = []
    floor = doc["options"]["global_reserve_floor_minor"]
    if floor > 0:  # every snapshot day and every day with a low point (§12.8)
        dates = sorted(
            {p.on for pts in points.values() for p in pts if p.phase in ("snapshot", "low")}
        )
        for d in dates:
            total = sum(value_on(pts, d) for pts in points.values())
            if total < floor:
                global_breaches.append((d.isoformat(), total))
    breaches.sort()
    return Check(not breaches and not global_breaches, mins, breaches, global_breaches)


def structural(doc: Doc, cards: dict[str, Card], alloc: Alloc, target: int | None = None) -> list:
    """Structural violations of ``alloc`` (the verifier's, by kind)."""
    req = doc["request"]
    target = req["amount_minor"] if target is None else target
    account_layer, pool_layer = layers(doc)
    pools = {p["pool_id"] for p in doc["pools"]}
    snaps = {s["cash_account_id"]: day(s["as_of"]) for s in doc["snapshots"]}
    used = {k: x for k, x in alloc.items() if x != 0}
    found = []
    for cid, x in used.items():
        c = cards.get(cid)
        if c is None:
            found.append(f"unknown {cid}")
            continue
        if x < 0:
            found.append(f"negative {cid}")
        if c.reason:
            found.append(f"ineligible {cid}")
        if x > c.capacity:
            found.append(f"capacity {cid}")
        if c.per_txn_cap is not None and x > c.per_txn_cap:
            found.append(f"per-txn {cid}")
        if x < c.min_split:
            found.append(f"min-split {cid}")
        if cid in cards and c.repay_from in snaps and c.repay_on < snaps[c.repay_from]:
            found.append(f"before-snapshot {cid}")
    if sum(used.values()) != target:
        found.append("conservation")
    if len(used) > (req["max_cards"] if req["allow_split"] else 1):
        found.append("max-cards")
    sums: dict[tuple[str, str], int] = {}
    for cid, x in used.items():
        c = cards.get(cid)
        if c is None:
            continue
        if c.credit_account in account_layer:
            key = ("account", c.credit_account)
            sums[key] = sums.get(key, 0) + x
        if c.pool:
            sums[("pool", c.pool)] = sums.get(("pool", c.pool), 0) + x
    for (kind, ident), s in sums.items():
        if kind == "account" and s > account_layer[ident]:
            found.append(f"account {ident}")
        if kind == "pool" and (ident not in pools or s > pool_layer[ident]):
            found.append(f"pool {ident}")
    return found


def allocations(doc: Doc, cards: list[Card], target: int) -> list[Alloc]:
    """Every structurally valid allocation of exactly ``target`` over the ELIGIBLE cards."""
    req = doc["request"]
    k_max = req["max_cards"] if req["allow_split"] else 1
    eligible = [c for c in cards if c.reason is None]
    by_id = {c.id: c for c in cards}
    out: list[Alloc] = []

    def rec(i: int, rest: int, used: int, cur: list[int]) -> None:
        if i == len(eligible):
            if rest == 0:
                alloc = {c.id: x for c, x in zip(eligible, cur, strict=True) if x}
                if not structural(doc, by_id, alloc, target):
                    out.append(alloc)
            return
        c = eligible[i]
        for x in [0, *range(max(1, c.min_split), min(c.cap, rest) + 1)]:
            if x and used >= k_max:
                break
            cur.append(x)
            rec(i + 1, rest - x, used + (1 if x else 0), cur)
            cur.pop()

    rec(0, target, 0, [])
    return out


# --- objectives, optimum and canonical tie-break ---------------------------------------------


def checkpoint_dates(doc: Doc, sc: dict[str, Any], cards: list[Card]) -> dict[str, list[Point]]:
    """Model timelines without the plan: every account's points, with the repayment days of the
    eligible cards as checkpoints of their repayment account."""
    extra: dict[str, set[date]] = {}
    for c in cards:
        if c.reason is None:
            extra.setdefault(c.repay_from, set()).add(c.repay_on)
    return {
        a["cash_account_id"]: account_points(
            doc, sc, a["cash_account_id"], extra_days=extra.get(a["cash_account_id"], set())
        )
        for a in doc["cash_accounts"]
    }


def objectives(doc: Doc, sc: dict[str, Any], cards: list[Card], alloc: Alloc) -> dict[str, int]:
    by_id = {c.id: c for c in cards}
    timelines = checkpoint_dates(doc, sc, cards)
    dates = sorted({p.on for pts in timelines.values() for p in pts if p.phase == "low"})
    margin = None
    for a in doc["cash_accounts"]:
        aid = a["cash_account_id"]
        for d in dates:
            spent = sum(
                x + fee_of(by_id[cid], x)
                for cid, x in alloc.items()
                if by_id[cid].repay_from == aid and by_id[cid].repay_on <= d
            )
            value = value_on(timelines[aid], d) - spent - a["reserve_floor_minor"]
            margin = value if margin is None else min(margin, value)
    fees = sum(fee_of(by_id[k], x) for k, x in alloc.items())
    return {
        "min_margin": margin if margin is not None else 0,
        "fees": fees,
        "net_verified_benefit": sum(ben_of(by_id[k], x) for k, x in alloc.items()) - fees,
        "buffer": sum(x * by_id[k].buffer for k, x in alloc.items()),
        "cards": sum(1 for x in alloc.values() if x),
    }


def lex_key(obj: dict[str, int], profile: str) -> tuple[int, ...]:
    return tuple(-obj[n] if s == "max" else obj[n] for n, s in TIERS[profile])


def canonical(cards: list[Card], candidates: list[Alloc]) -> Alloc:
    """The lexicographically largest allocation vector in card input order (§12.5)."""
    order = [c.id for c in cards]
    best = max(candidates, key=lambda a: tuple(a.get(cid, 0) for cid in order))
    return {cid: best[cid] for cid in order if best.get(cid)}


# --- the expected outcome --------------------------------------------------------------------


@dataclass
class Expected:
    status: str
    issues: set[str]
    baseline_ok: dict[str, bool]
    baseline_global: dict[str, bool]
    allocation: Alloc
    tiers: dict[str, int]
    failing: set[str]
    checks: dict[str, Check]
    rejections: dict[str, str]
    cards: list[Card]
    feasible: list[Alloc]


def expected(doc: Doc) -> Expected:
    issues = data_issues(doc)
    nothing: dict[str, Any] = {}
    if issues:
        return Expected("NEEDS_DATA", issues, {}, {}, {}, nothing, set(), {}, {}, [], [])
    txn = day(doc["request"]["txn_date"])
    cards = cards_at(doc, txn)
    by_id = {c.id: c for c in cards}
    scenarios = {s["scenario_id"]: s for s in doc["scenarios"]}
    decision = doc["options"]["decision_scenario"]
    base = {sid: check(doc, sc, by_id, {}) for sid, sc in scenarios.items()}
    base_ok = {sid: b.ok for sid, b in base.items()}
    base_global = {sid: bool(b.global_breaches) for sid, b in base.items()}
    if not base_ok[decision]:
        return Expected(
            "BASELINE_SHORTFALL", issues, base_ok, base_global, {}, {}, set(), {}, {}, cards, []
        )
    if all(c.reason for c in cards):
        rejections = {c.id: c.reason or "" for c in cards}
        return Expected(
            "INFEASIBLE", issues, base_ok, base_global, {}, {}, set(), {}, rejections, cards, []
        )
    amount = doc["request"]["amount_minor"]
    dec = scenarios[decision]
    feasible = [a for a in allocations(doc, cards, amount) if check(doc, dec, by_id, a).ok]
    if not feasible:
        rejections = rejection_reasons(doc, cards, {}, compared=False)
        return Expected(
            "INFEASIBLE", issues, base_ok, base_global, {}, {}, set(), {}, rejections, cards, []
        )
    profile = doc["options"]["profile"]
    scored = [(lex_key(objectives(doc, dec, cards, a), profile), a) for a in feasible]
    best_key = min(k for k, _ in scored)
    alloc = canonical(cards, [a for k, a in scored if k == best_key])
    tiers = objectives(doc, dec, cards, alloc)
    checks = {sid: check(doc, sc, by_id, alloc) for sid, sc in scenarios.items()}
    failing = {sid for sid in scenarios if not checks[sid].ok or not base_ok[sid]}
    status = "CONDITIONALLY_FEASIBLE" if failing else "FEASIBLE_ROBUST"
    rejections = rejection_reasons(doc, cards, alloc, compared=True)
    return Expected(
        status, issues, base_ok, base_global, alloc, tiers, failing, checks, rejections, cards,
        feasible,
    )  # fmt: skip


def rejection_reasons(doc: Doc, cards: list[Card], alloc: Alloc, *, compared: bool) -> dict:
    amount = doc["request"]["amount_minor"]
    scenarios = {s["scenario_id"]: s for s in doc["scenarios"]}
    dec = scenarios[doc["options"]["decision_scenario"]]
    by_id = {c.id: c for c in cards}
    out = {}
    for c in cards:
        if c.id in alloc:
            continue
        if c.reason:
            out[c.id] = c.reason
        elif c.cap < amount:
            out[c.id] = "INSUFFICIENT_LIMIT_ALONE"
        elif not check(doc, dec, by_id, {c.id: amount}).ok:
            out[c.id] = "CASH_BREACH_ALONE"
        else:
            out[c.id] = "DOMINATED" if compared else "NOT_COMPARED"
    return out


# --- sensitivity -----------------------------------------------------------------------------


def min_extra_cash(doc: Doc, sc: dict[str, Any], cards: list[Card]) -> dict[str, Any]:
    """Least additional confirmed cash (per account, from the snapshot date) for some
    structurally valid allocation; canonical allocation, then the extra cash lexicographically
    largest in account order."""
    by_id = {c.id: c for c in cards}
    timelines = checkpoint_dates(doc, sc, cards)
    dates = sorted({p.on for pts in timelines.values() for p in pts if p.phase == "low"})
    accounts = doc["cash_accounts"]
    floor = doc["options"]["global_reserve_floor_minor"]
    best: tuple[int, list[Alloc], dict[str, dict[str, int]]] | None = None
    for alloc in allocations(doc, cards, doc["request"]["amount_minor"]):
        need: dict[str, int] = {}
        totals = dict.fromkeys(dates, 0)
        for a in accounts:
            aid = a["cash_account_id"]
            worst = 0
            for d in dates:
                spent = sum(
                    x + fee_of(by_id[cid], x)
                    for cid, x in alloc.items()
                    if by_id[cid].repay_from == aid and by_id[cid].repay_on <= d
                )
                value = value_on(timelines[aid], d) - spent
                totals[d] += value
                worst = max(worst, a["reserve_floor_minor"] - value)
            need[aid] = worst
        total = sum(need.values())
        if floor > 0 and dates:
            total = max(total, max(floor - totals[d] for d in dates))
        key = tuple(sorted(need.items()))
        if best is None or total < best[0]:
            best = (total, [alloc], {key_text(key): need})
        elif total == best[0]:
            best[1].append(alloc)
            best[2][key_text(key)] = need
    if best is None:
        return {"status": "INFEASIBLE"}
    total, candidates, _ = best
    alloc = canonical(cards, candidates)
    # recompute the per-account need of the chosen allocation, then spread the rest lexmax
    need = {}
    for a in accounts:
        aid = a["cash_account_id"]
        worst = 0
        for d in dates:
            spent = sum(
                x + fee_of(by_id[cid], x)
                for cid, x in alloc.items()
                if by_id[cid].repay_from == aid and by_id[cid].repay_on <= d
            )
            worst = max(worst, a["reserve_floor_minor"] - (value_on(timelines[aid], d) - spent))
        need[aid] = worst
    extra = dict(need)
    first = accounts[0]["cash_account_id"]
    extra[first] += total - sum(need.values())
    return {
        "status": "OPTIMAL",
        "extra_cash_by_account": extra,
        "total": total,
        "allocation": alloc,
    }


def key_text(key: tuple[tuple[str, int], ...]) -> str:
    return ",".join(f"{k}={v}" for k, v in key)


def max_affordable(doc: Doc, sc: dict[str, Any], cards: list[Card]) -> dict[str, Any]:
    by_id = {c.id: c for c in cards}
    for target in range(doc["request"]["amount_minor"], -1, -1):
        ok = [a for a in allocations(doc, cards, target) if check(doc, sc, by_id, a).ok]
        if ok:
            return {"status": "OPTIMAL", "amount": target, "allocation": canonical(cards, ok)}
    return {"status": "INFEASIBLE"}


def date_shift(doc: Doc, sc: dict[str, Any]) -> dict[str, Any] | None:
    txn = day(doc["request"]["txn_date"])
    for k in range(1, MAX_SHIFT_DAYS + 1):
        shifted = txn + timedelta(days=k)
        cards = cards_at(doc, shifted, strict=False)
        if all(c.reason for c in cards):
            continue
        by_id = {c.id: c for c in cards}
        for alloc in allocations(doc, cards, doc["request"]["amount_minor"]):
            if check(doc, sc, by_id, alloc).ok:
                return {"shift_days": k, "txn_date": shifted.isoformat(), "status": "OPTIMAL"}
    return None


# --- generators ------------------------------------------------------------------------------


def _iso(d: date) -> str:
    return d.isoformat()


def gen_review_doc(rng: random.Random, *, timestamp_rate: float = 0.25) -> Doc:
    """The wave-3 review's generator (``scripts/gen.py``), call for call: the same seed gives
    the same document (used to replay the instances the review found nondeterministic)."""
    txn = date(2026, 1, 1) + timedelta(days=rng.randrange(0, 400))
    n_acc = rng.randint(1, 3)
    acc_ids = [f"cash-{i}" for i in range(n_acc)]
    accounts, snapshots = [], []
    for aid in acc_ids:
        accounts.append(
            {
                "cash_account_id": aid,
                "currency": "CNY",
                "reserve_floor_minor": rng.choice([0, 0, 0, 1, 3, 5]),
                "usable_for_repayment": rng.random() > 0.08,
            }
        )
        if rng.random() > 0.03:
            age = rng.choice([0, 0, 0, 1, 2, 3] + ([9] if rng.random() < 0.05 else []))
            snapshots.append(
                {
                    "cash_account_id": aid,
                    "balance_minor": rng.randint(-2, 60)
                    if rng.random() < 0.1
                    else rng.randint(8, 60),
                    "as_of": _iso(txn - timedelta(days=age)),
                    "includes_event_ids": [],
                }
            )
    events = []
    n_ev = rng.randint(0, 20)
    use_ts = rng.random() < timestamp_rate
    for k in range(n_ev):
        aid = rng.choice(acc_ids)
        on = txn + timedelta(days=rng.randint(-4, 75))
        amt = -rng.randint(1, 12) if rng.random() < 0.55 else rng.randint(1, 20)
        cls = rng.choices(["confirmed", "expected", "planned"], [6, 4, 1])[0]
        cat = rng.choices(
            ["living", "bill", "income", "other", "transfer_in", "fee"], [4, 3, 3, 1, 1, 1]
        )[0]
        e = {
            "event_id": f"e{k}",
            "cash_account_id": aid,
            "on": _iso(on),
            "amount_minor": amt,
            "cls": cls,
            "category": cat,
        }
        if use_ts and rng.random() < 0.9:
            t = datetime(on.year, on.month, on.day, tzinfo=timezone.utc) + timedelta(  # noqa: UP017
                minutes=rng.randrange(0, 1440)
            )
            t += timedelta(seconds=k)
            e["at"] = t.isoformat().replace("+00:00", "Z")
        events.append(e)
    for s in snapshots:
        same_day = [
            e["event_id"]
            for e in events
            if e["cash_account_id"] == s["cash_account_id"] and e["on"] == s["as_of"]
        ]
        s["includes_event_ids"] = [x for x in same_day if rng.random() < 0.5]
    n_cards = rng.randint(1, 4)
    pools_used = set()
    cards = []
    for i in range(n_cards):
        cid = "ABCD"[i]
        due_kind = rng.random() < 0.8
        if due_kind:
            sd = rng.randint(1, 31)
            off = rng.choice([0, 1, 1, 2])
            dom = rng.randint(1, 31)
            if off == 0 and rng.random() < 0.9:
                if sd >= 28:
                    off = 1
                else:
                    dom = rng.randint(sd + 1, 31)
            due = {"kind": "fixed_day", "day": dom, "month_offset": off}
        else:
            due = {
                "kind": "days_after_statement",
                "days": rng.randint(1, 60),
                "day_kind": "calendar" if rng.random() > 0.03 else "business",
            }
        if not due_kind:
            sd = rng.randint(1, 31)
        rule = {
            "rule_id": f"r{cid}",
            "statement_day": sd,
            "statement_day_inclusive": rng.random() < 0.7,
            "due": due,
            "holiday_rollover": "none" if rng.random() > 0.02 else "next_business_day",
        }
        c = {
            "card_id": cid,
            "credit_account_id": f"acc-{cid}",
            "raw_available_minor": rng.randint(-3, 30),
            "holds_uncounted_minor": rng.choice([0, 0, 0, 1, 3]),
            "reservations_minor": rng.choice([0, 0, 0, 2]),
            "billing_rule": rule,
            "repay_from_cash_account_id": rng.choice(acc_ids),
            "channel_ok": rng.random() > 0.05,
            "currency_ok": rng.random() > 0.05,
            "status_ok": rng.random() > 0.05,
            "fee_rate": rng.choice(["0", "0", "0", "0.006", "0.1", "0.33333", "0.5"]),
            "fee_fixed_minor": rng.choice([0, 0, 0, 1, 2]),
            "verified_benefit_rate": rng.choice(["0", "0", "0.01", "0.25", "0.33333"]),
            "potential_benefit_rate": rng.choice(["0", "0.05", "0.5"]),
            "posting_delay_min_days": 0,
            "posting_delay_max_days": 0,
        }
        if rng.random() < 0.2:
            lo = rng.randint(0, 3)
            c["posting_delay_min_days"], c["posting_delay_max_days"] = lo, lo + rng.randint(0, 3)
        if rng.random() < 0.3:
            c["pool_id"] = rng.choice(["p1", "p2"])
            pools_used.add(c["pool_id"])
        if rng.random() < 0.25:
            c["per_txn_cap_minor"] = rng.randint(0, 25)
        if rng.random() < 0.25:
            c["min_split_minor"] = rng.randint(1, 8)
        if rng.random() < 0.2:
            c["verified_benefit_cap_minor"] = rng.randint(0, 3)
        cards.append(c)
    pools = [
        {"pool_id": p, "available_minor": rng.randint(-4, 30)}
        for p in sorted(pools_used)
        if rng.random() > 0.03
    ]
    request = {
        "amount_minor": rng.randint(1, 16),
        "currency": "CNY",
        "txn_date": _iso(txn),
        "allow_split": rng.random() < 0.7,
        "max_cards": rng.randint(1, 4),
        "min_split_minor": rng.choice([1, 1, 1, 2, 3, 5]),
        "payment_lead_days": rng.choice([0, 0, 0, 1, 3, 7, 15, 30]),
        "channel": "pos",
    }
    order = "timestamp" if use_ts and rng.random() < 0.7 else "conservative"
    scenarios = [_scenario("confirmed", False, order), _scenario("baseline", True, order)]
    for j in range(rng.randint(0, 2)):
        ov = []
        for e in rng.sample(events, k=min(len(events), rng.randint(0, 2))):
            o: dict[str, Any] = {"event_id": e["event_id"]}
            if rng.random() < 0.6:
                o["on"] = _iso(day(e["on"]) + timedelta(days=rng.randint(-3, 6)))
            if rng.random() < 0.6 or "on" not in o:
                o["amount_minor"] = rng.randint(-25, 25)
            ov.append(o)
        # same call order as the review generator: delay, scales, then the day order
        delay = rng.choice([0, 1, 3, 7])
        income_scale = rng.choice(["1", "0.5", "0.8", "0.33"])
        expense_scale = rng.choice(["1", "1.2", "1.5", "2"])
        sc = _scenario(f"stress{j}", True, rng.choice([order, "conservative"]))
        sc.update(
            income_delay_days=delay,
            income_scale=income_scale,
            expense_scale=expense_scale,
            event_overrides=ov,
        )
        scenarios.append(sc)
    decision = rng.choices(
        [s["scenario_id"] for s in scenarios], [1, 4, *([2] * (len(scenarios) - 2))]
    )[0]
    if rng.random() < 0.01:
        decision = "nope"
    options = {
        "profile": rng.choice(["cash_safety", "verified_benefit", "fewer_cards"]),
        "decision_scenario": decision,
        "time_limit_s": 10,
        "workers": 8,
        "seed": 0,
        "stale_after_days": 7,
        "global_reserve_floor_minor": rng.choice([0, 0, 0, 0, 5, 20]),
    }
    return {
        "protocol_version": "1",
        "request": request,
        "cards": cards,
        "pools": pools,
        "cash_accounts": accounts,
        "snapshots": snapshots,
        "events": events,
        "scenarios": scenarios,
        "horizon_end": _iso(txn + timedelta(days=rng.randint(5, 80))),
        "options": options,
    }


def _scenario(sid: str, include_expected: bool, order: str) -> dict[str, Any]:
    return {
        "scenario_id": sid,
        "include_expected": include_expected,
        "income_delay_days": 0,
        "income_scale": "1",
        "expense_scale": "1",
        "event_overrides": [],
        "same_day_order": order,
    }


def gen_doc(rng: random.Random) -> Doc:
    """Small random PlanInput exercising the §12 semantics (valid protocol v1 by construction,
    with business-level problems at low rates)."""
    txn = date(2026, 1, 1) + timedelta(days=rng.randrange(0, 400))
    acc_ids = [f"cash-{i}" for i in range(rng.randint(1, 3))]
    tz = rng.choice([timezone.utc, timezone(timedelta(hours=8)), timezone(timedelta(hours=-5))])  # noqa: UP017
    accounts, snapshots = [], []
    for aid in acc_ids:
        accounts.append(
            {
                "cash_account_id": aid,
                "currency": "CNY",
                "reserve_floor_minor": rng.choice([0, 0, 0, 1, 3, 5]),
                "usable_for_repayment": rng.random() > 0.03,
            }
        )
        if rng.random() > 0.02:
            age = rng.choice([0, 0, 0, 1, 2, 3] + ([9] if rng.random() < 0.04 else []))
            snapshots.append(
                {
                    "cash_account_id": aid,
                    "balance_minor": rng.randint(-2, 60)
                    if rng.random() < 0.08
                    else rng.randint(8, 60),
                    "as_of": _iso(txn - timedelta(days=age)),
                    "includes_event_ids": [],
                }
            )
    timed = rng.random() < 0.35
    events = []
    for k in range(rng.randint(0, 16)):
        on = txn + timedelta(days=rng.randint(-5, 70))
        e = {
            "event_id": f"e{k}",
            "cash_account_id": rng.choice(acc_ids),
            "on": _iso(on),
            "amount_minor": -rng.randint(1, 12) if rng.random() < 0.55 else rng.randint(1, 20),
            "cls": rng.choices(["confirmed", "expected", "planned"], [6, 4, 1])[0],
            "category": rng.choices(["living", "bill", "income", "other", "fee"], [4, 3, 3, 1, 1])[
                0
            ],
        }
        if timed and rng.random() < 0.9:
            local = datetime(on.year, on.month, on.day, tzinfo=tz)
            e["at"] = (local + timedelta(minutes=rng.randrange(0, 1440))).isoformat()
        events.append(e)
    for s in snapshots:  # inclusion: events on or before as_of of the account (§12.2)
        own = [
            e["event_id"]
            for e in events
            if e["cash_account_id"] == s["cash_account_id"] and e["on"] <= s["as_of"]
        ]
        s["includes_event_ids"] = [x for x in own if rng.random() < 0.5]
    cards: list[dict[str, Any]] = []
    pools_used = set()
    twin = rng.random() < 0.2  # near-identical cards: ties for the tie-break
    for i in range(rng.choice([1, 2, 2, 3, 3, 4])):
        cid = "ABCD"[i]
        if twin and cards:
            c = dict(cards[0], card_id=cid, credit_account_id=f"acc-{cid}")
            cards.append(c)
            continue
        sd = rng.randint(1, 31)
        if rng.random() < 0.8:
            off = rng.choice([0, 1, 1, 2])
            dom = rng.randint(1, 31)
            if off == 0 and rng.random() < 0.9:
                off, dom = (1, dom) if sd >= 28 else (0, rng.randint(sd + 1, 31))
            due: dict[str, Any] = {"kind": "fixed_day", "day": dom, "month_offset": off}
        else:
            due = {"kind": "days_after_statement", "days": rng.randint(1, 60)}
            due["day_kind"] = "calendar" if rng.random() > 0.02 else "business"
        rule: dict[str, Any] = {
            "rule_id": f"r{cid}",
            "statement_day": sd,
            "statement_day_inclusive": rng.random() < 0.7,
            "due": due,
            "holiday_rollover": "none",
        }
        if rng.random() < 0.15:  # a rule version that ends soon after the transaction
            rule["effective_to"] = _iso(txn + timedelta(days=rng.randint(4, 40)))
        c = {
            "card_id": cid,
            "credit_account_id": f"acc-{cid}",
            "raw_available_minor": rng.randint(4, 40)
            if rng.random() < 0.85
            else rng.randint(-3, 3),
            "holds_uncounted_minor": rng.choice([0, 0, 0, 1, 3]),
            "reservations_minor": rng.choice([0, 0, 0, 2, 5]),
            "billing_rule": rule,
            "repay_from_cash_account_id": rng.choice(acc_ids),
            "channel_ok": rng.random() > 0.02,
            "currency_ok": rng.random() > 0.02,
            "status_ok": rng.random() > 0.02,
            "fee_rate": rng.choice(["0", "0", "0", "0.006", "0.1", "0.33333", "0.5"]),
            "fee_fixed_minor": rng.choice([0, 0, 0, 1, 2]),
            "verified_benefit_rate": rng.choice(["0", "0", "0.01", "0.25", "0.33333"]),
            "potential_benefit_rate": rng.choice(["0", "0.05", "0.5"]),
            "posting_delay_min_days": 0,
            "posting_delay_max_days": 0,
        }
        if rng.random() < 0.15:
            lo = rng.randint(0, 3)
            c["posting_delay_min_days"], c["posting_delay_max_days"] = lo, lo + rng.randint(0, 3)
        if rng.random() < 0.3:
            c["pool_id"] = rng.choice(["p1", "p2"])
        if rng.random() < 0.2:
            c["per_txn_cap_minor"] = rng.randint(0, 25)
        if rng.random() < 0.2:
            c["min_split_minor"] = rng.randint(1, 12)
        if rng.random() < 0.2:
            c["verified_benefit_cap_minor"] = rng.randint(0, 3)
        if cards and rng.random() < 0.25:  # a supplementary card of an earlier card's account
            host = rng.choice(cards)
            c["credit_account_id"] = host["credit_account_id"]
            c["raw_available_minor"] = host["raw_available_minor"]
            if "pool_id" in host:
                c["pool_id"] = host["pool_id"]
            else:
                c.pop("pool_id", None)
        cards.append(c)
    for c in cards:
        if "pool_id" in c:
            pools_used.add(c["pool_id"])
    pools = [
        {
            "pool_id": p,
            "available_minor": rng.randint(6, 45) if rng.random() < 0.85 else rng.randint(-4, 5),
        }
        for p in sorted(pools_used)
        if rng.random() > 0.02
    ]
    request = {
        "amount_minor": rng.randint(1, 16),
        "currency": "CNY",
        "txn_date": _iso(txn),
        "allow_split": rng.random() < 0.7,
        "max_cards": rng.randint(1, 4),
        "min_split_minor": rng.choice([1, 1, 1, 2, 3, 5]),
        "payment_lead_days": rng.choice([0, 0, 0, 1, 3, 7, 15, 30]),
        "channel": "pos",
    }
    order = "timestamp" if timed and rng.random() < 0.75 else "conservative"
    scenarios = [_scenario("confirmed", False, order), _scenario("baseline", True, order)]
    for j in range(rng.randint(0, 2)):
        overrides = []
        for e in rng.sample(events, k=min(len(events), rng.randint(0, 3))):
            o: dict[str, Any] = {"event_id": e["event_id"]}
            if rng.random() < 0.6:  # may move an event before the snapshot (§12.2)
                o["on"] = _iso(day(e["on"]) + timedelta(days=rng.randint(-8, 6)))
            if rng.random() < 0.5 or "on" not in o:
                o["amount_minor"] = rng.randint(-25, 25)
            overrides.append(o)
        sc = _scenario(f"stress{j}", True, rng.choice([order, "conservative"]))
        sc.update(
            income_delay_days=rng.choice([0, 1, 3, 7]),
            income_scale=rng.choice(["1", "0.5", "0.8", "0.33"]),
            expense_scale=rng.choice(["1", "1.2", "1.5", "2"]),
            event_overrides=overrides,
        )
        scenarios.append(sc)
    decision = rng.choices(
        [s["scenario_id"] for s in scenarios], [1, 4, *([2] * (len(scenarios) - 2))]
    )[0]
    options = {
        "profile": rng.choice(["cash_safety", "verified_benefit", "fewer_cards"]),
        "decision_scenario": decision,
        "time_limit_s": 10,
        "workers": rng.choice([8, 8, 1]),
        "seed": 0,
        "stale_after_days": 7,
        "global_reserve_floor_minor": rng.choice([0, 0, 0, 0, 0, 5, 20, 40]),
    }
    return {
        "protocol_version": "1",
        "request": request,
        "cards": cards,
        "pools": pools,
        "cash_accounts": accounts,
        "snapshots": snapshots,
        "events": events,
        "scenarios": scenarios,
        # mostly the API's horizon (>= txn + 180 days, §12.7), sometimes a short one that cuts
        # off repayments (REPAY_AFTER_HORIZON)
        "horizon_end": _iso(
            txn
            + timedelta(days=rng.randint(5, 60) if rng.random() < 0.25 else rng.randint(150, 200))
        ),
        "options": options,
    }


def consecutive(values: list[date]) -> bool:
    """Whether ``values`` are strictly increasing (helper for timeline sanity checks)."""
    return all(a < b for a, b in pairwise(values))
