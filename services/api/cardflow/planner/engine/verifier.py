"""Independent plan verifier. Pure Python, no solver: recomputes every hard constraint and the
per-account cash timeline from the allocation. The solver's answer is never trusted unverified.

Model 1.1.0 (engine-spec §12): the timeline ends at ``horizon_end`` (never extended; a card
repaying later is ineligible, REPAY_AFTER_HORIZON); a planned repayment is the amount plus the
card's fee (§12.6) and, on a timestamp-ordered day, comes before the day's timed events (§12.4,
the model's own rule); the credit-account and pool layers are checked with the members' holds
and reservations deducted (§12.3); the global floor is checked as in the baseline (§12.8)."""

from __future__ import annotations

from dataclasses import dataclass, replace
from decimal import ROUND_HALF_UP, Decimal

from cardflow.planner.engine.allocation import (
    CardOption,
    ModelInputs,
    _low_series,
    capacity_layers,
    classify,
    derive_card_info,
)
from cardflow.planner.engine.cash import (
    CashEvent,
    CashReport,
    EventClass,
    Scenario,
    evaluate_accounts,
)
from cardflow.planner.engine.money import apply_rate


@dataclass
class ScenarioCheck:
    scenario_id: str
    ok: bool  # no reserve breach on any account, and global floor holds
    ok_zero: bool  # no sub-zero balance on any account
    min_balance_by_account: dict
    min_on_by_account: dict
    end_balance_by_account: dict
    breaches: list  # [{account, on, balance, gap_to_zero, gap_to_reserve, events}]
    first_breach: dict | None
    global_breaches: list
    assumptions: list


@dataclass
class Verification:
    ok: bool  # structural checks + decision-scenario cash
    structural_ok: bool
    violations: list
    decision_scenario: str
    checks: dict  # scenario_id -> ScenarioCheck
    weighted_buffer_days: Decimal
    fees: int
    verified_benefit: int
    potential_benefit: int
    lines: list


def global_floor_breaches(reports: dict[str, CashReport], floor: int) -> list[dict]:
    """Days on which the SUM over all cash accounts is below the global floor (``floor`` 0 =
    disabled): every snapshot day and every day with a low point in some account, each account
    at its low that day or carried from its last day before (its snapshot balance before its
    first day). The starting total counts like a snapshot below an account's reserve does. One
    rule for the baseline and the verifier (engine-spec §12.8, R3E-09)."""
    if floor <= 0:
        return []
    timelines = {aid: r.timeline for aid, r in reports.items()}
    dates = sorted(
        {p.on for tl in timelines.values() for p in tl.points if p.phase in ("snapshot", "low")}
    )
    series = {aid: _low_series(tl, dates) for aid, tl in timelines.items()}
    out = []
    for idx, d in enumerate(dates):
        total = sum(series[aid][idx] for aid in series)
        if total < floor:
            out.append({"on": d, "total": total, "gap": floor - total})
    return out


def card_fee(card: CardOption, amount: int) -> int:
    """Fee of ``amount`` on ``card``: the rate part rounded UP, plus the fixed fee when the card
    is used (a positive amount)."""
    rate_part = apply_rate(amount, card.fee_rate, "UP") if card.fee_rate else 0
    return rate_part + (card.fee_fixed if amount > 0 else 0)


def planned_repayment_events(infos: dict, allocation: dict, fees: dict | None = None) -> list:
    """The plan's cash repayments: amount + fee per card (engine-spec §12.6), on repay_on."""
    evs = []
    for cid, amt in allocation.items():
        i = infos[cid]
        fee = (fees or {}).get(cid, 0)
        evs.append(
            CashEvent(
                f"plan_repay_{cid}",
                i.card.repay_from,
                i.repay_on,
                -(int(amt) + fee),
                EventClass.PLANNED,
                "repayment",
                f"计划还款 {cid}",
            )
        )
    return evs


def check_scenario(
    inputs: ModelInputs,
    infos: dict,
    allocation: dict,
    scenario: Scenario,
    fees: dict | None = None,
) -> ScenarioCheck:
    breaches, assumptions = [], []
    planned = []
    for event in planned_repayment_events(infos, allocation, fees):
        snap = inputs.snapshots.get(event.account)
        if snap is not None and event.on < snap.as_of:
            # The timeline treats anything dated before the snapshot as already reflected in
            # the balance; a PLANNED repayment never is. Apply it on the snapshot day instead of
            # skipping it (conservative); verify() reports it as a violation.
            assumptions.append(
                f"{event.account}: {event.id} dated {event.on} precedes the snapshot of "
                f"{snap.as_of}; applied on the snapshot day"
            )
            planned.append(replace(event, on=snap.as_of))
        else:
            planned.append(event)
    reports = evaluate_accounts(
        inputs.accounts,
        inputs.snapshots,
        inputs.events,
        scenario,
        inputs.horizon_end,
        planned=planned,
    )
    for aid, r in reports.items():
        assumptions += [f"{aid}: {a}" for a in r.assumptions]
        for b in r.breaches:
            breaches.append(
                {
                    "account": aid,
                    "on": b.on,
                    "balance": b.balance,
                    "gap_to_zero": b.gap_to_zero,
                    "gap_to_reserve": b.gap_to_reserve,
                    "events": list(b.event_ids),
                }
            )
    breaches.sort(key=lambda b: (b["on"], b["account"]))
    global_breaches = global_floor_breaches(reports, inputs.global_reserve_floor)
    ok = not breaches and not global_breaches
    return ScenarioCheck(
        scenario.id,
        ok,
        all(r.ok_zero for r in reports.values()),
        {aid: r.min_balance for aid, r in reports.items()},
        {aid: r.min_on for aid, r in reports.items()},
        {aid: r.end_balance for aid, r in reports.items()},
        breaches,
        breaches[0] if breaches else None,
        global_breaches,
        assumptions,
    )


def verify(
    inputs: ModelInputs, allocation: dict, scenarios: dict, decision_scenario_id: str
) -> Verification:
    req = inputs.request
    cards = {c.id: c for c in inputs.cards}
    layers = capacity_layers(inputs)
    violations = []
    for cid, amt in allocation.items():
        # money is integer minor units: a float, bool, Decimal or str is refused, never int()-ed
        if isinstance(amt, bool) or not isinstance(amt, int):
            raise TypeError(
                f"allocation amount of {cid!r} must be an int (minor units), "
                f"got {type(amt).__name__}"
            )
    alloc = {k: v for k, v in allocation.items() if v != 0}
    for cid, amt in alloc.items():
        if cid not in cards:
            violations.append(f"UNKNOWN_CARD: {cid!r} is not one of the plan's cards")
            continue
        if amt < 0:
            violations.append(f"{cid}: negative amount")
        _, exclusion = classify(cards[cid], inputs, layers=layers)
        if exclusion:
            violations.append(f"{cid}: ineligible ({exclusion.code})")
        if amt > cards[cid].capacity:
            violations.append(f"{cid}: amount {amt} exceeds capacity {cards[cid].capacity}")
        if cards[cid].per_txn_cap is not None and amt > cards[cid].per_txn_cap:
            violations.append(
                f"{cid}: amount {amt} exceeds per-transaction cap {cards[cid].per_txn_cap}"
            )
        ms = cards[cid].min_split if cards[cid].min_split is not None else req.min_split
        if amt < ms:
            violations.append(f"{cid}: amount {amt} below minimum split {ms}")
    if sum(alloc.values()) != req.amount:
        violations.append(f"amount conservation violated: {sum(alloc.values())} != {req.amount}")
    if len(alloc) > req.k:
        violations.append(f"uses {len(alloc)} cards > allowed {req.k}")
    account_sums: dict = {}
    pool_sums: dict = {}
    for cid, amt in alloc.items():
        if cid not in cards:
            continue
        if cards[cid].account_id in layers.account:
            aid = cards[cid].account_id
            account_sums[aid] = account_sums.get(aid, 0) + amt
        if cards[cid].pool_id:
            pool_sums[cards[cid].pool_id] = pool_sums.get(cards[cid].pool_id, 0) + amt
    for aid, s in account_sums.items():  # cards sharing a credit account (§12.3)
        if s > layers.account[aid]:
            violations.append(
                f"credit account {aid}: {s} exceeds shared capacity {layers.account[aid]}"
            )
    for pid, s in pool_sums.items():
        cap = layers.pool.get(pid)
        if cap is None:
            violations.append(f"pool {pid}: no capacity snapshot")
        elif s > cap:  # net of the members' holds and reservations, clamped at 0 (§12.3)
            violations.append(f"pool {pid}: {s} exceeds shared capacity {cap}")
    # A card outside the plan has no billing rule and no repayment account; it is already an
    # UNKNOWN_CARD violation (the allocation is rejected), and everything below -- cash checks,
    # buffer, fees, lines -- covers the known cards only instead of raising KeyError.
    known = {cid: amt for cid, amt in alloc.items() if cid in cards}
    infos = {cid: derive_card_info(cards[cid], req) for cid in known}
    for cid, info in infos.items():
        snap = inputs.snapshots.get(info.card.repay_from)
        if snap is not None and info.repay_on < snap.as_of:
            violations.append(
                f"PLANNED_REPAYMENT_BEFORE_SNAPSHOT: {cid} repays on {info.repay_on}, before "
                f"the {info.card.repay_from} snapshot of {snap.as_of} (applied on that day)"
            )
    structural_ok = not violations
    fees_by_card = {cid: card_fee(cards[cid], amt) for cid, amt in known.items()}
    checks = {
        sid: check_scenario(inputs, infos, known, sc, fees_by_card) for sid, sc in scenarios.items()
    }
    buffer_num = sum(known[cid] * infos[cid].buffer_days for cid in infos)
    wbuf = (
        (Decimal(buffer_num) / Decimal(req.amount)).quantize(Decimal("0.1"), rounding=ROUND_HALF_UP)
        if req.amount
        else Decimal(0)
    )
    fees = ben = pot = 0
    lines = []
    for cid, amt in known.items():
        c = cards[cid]
        fee = fees_by_card[cid]
        b = apply_rate(amt, c.verified_benefit_rate, "DOWN") if c.verified_benefit_rate else 0
        if c.verified_benefit_cap is not None:
            b = min(b, c.verified_benefit_cap)
        p = apply_rate(amt, c.potential_benefit_rate, "DOWN") if c.potential_benefit_rate else 0
        fees += fee
        ben += b
        pot += p
        i = infos[cid]
        lines.append(
            {
                "card": cid,
                "amount": amt,
                "statement_date": i.cycle.statement_date,
                "due_date": i.cycle.due_date,
                "repay_on": i.repay_on,
                "repay_from": c.repay_from,
                "buffer_days": i.buffer_days,
                "fee": fee,
                "verified_benefit": b,
                "potential_benefit": p,
                "cycle_assumptions": list(i.cycle.assumptions),
                "alternative_cycles": [(x.statement_date, x.due_date) for x in i.all_cycles[1:]],
            }
        )
    ok = structural_ok and checks[decision_scenario_id].ok
    return Verification(
        ok, structural_ok, violations, decision_scenario_id, checks, wbuf, fees, ben, pot, lines
    )
