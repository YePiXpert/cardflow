from datetime import date, datetime
from decimal import Decimal
from cardflow_ref.cash import CashAccount, CashEvent, EventClass, Scenario, Snapshot, build_timeline, evaluate

ACC = CashAccount("m", "main", reserve_floor=200000)
SC = Scenario("base")


def ev(i, on, amt, cls=EventClass.CONFIRMED, cat="bill", at=None):
    return CashEvent(i, "m", on, amt, cls, cat, at=at)


def test_same_day_event_not_in_snapshot_is_applied():
    snap = Snapshot("m", 500000, date(2026, 10, 16))
    tl = build_timeline(ACC, snap, [ev("x", date(2026, 10, 16), -100000)], SC, date(2026, 12, 31))
    assert [p.balance for p in tl.points if p.phase == "low"] == [400000]
    assert any("快照当天" in a for a in tl.assumptions)


def test_same_day_event_marked_included_is_skipped():
    snap = Snapshot("m", 500000, date(2026, 10, 16), includes_event_ids=frozenset({"x"}))
    tl = build_timeline(ACC, snap, [ev("x", date(2026, 10, 16), -100000)], SC, date(2026, 12, 31))
    assert tl.skipped_event_ids == ["x"] and tl.points[-1].balance == 500000


def test_conservative_same_day_order_captures_intraday_low():
    snap = Snapshot("m", 100000, date(2026, 10, 1))
    evs = [ev("in", date(2026, 10, 5), 300000, cat="income"), ev("out", date(2026, 10, 5), -250000)]
    tl = build_timeline(ACC, snap, evs, SC, date(2026, 12, 31))
    lows = {p.on: p.balance for p in tl.points if p.phase == "low"}
    assert lows[date(2026, 10, 5)] == -150000 and tl.points[-1].balance == 150000
    assert any("同日收支顺序未知" in a for a in tl.assumptions)


def test_timestamp_order_when_all_events_timed():
    snap = Snapshot("m", 100000, date(2026, 10, 1))
    evs = [ev("in", date(2026, 10, 5), 300000, cat="income", at=datetime(2026, 10, 5, 9)),
           ev("out", date(2026, 10, 5), -250000, at=datetime(2026, 10, 5, 15))]
    tl = build_timeline(ACC, snap, evs, Scenario("ts", same_day_order="timestamp"), date(2026, 12, 31))
    lows = {p.on: p.balance for p in tl.points if p.phase == "low"}
    assert lows[date(2026, 10, 5)] == 100000 and not tl.assumptions


def test_expected_income_excluded_in_confirmed_scenario_and_delay_scale_in_stress():
    snap = Snapshot("m", 100000, date(2026, 10, 1))
    evs = [ev("pay", date(2026, 11, 6), 850000, EventClass.EXPECTED, "income"), ev("b", date(2026, 11, 8), -500000)]
    conf = build_timeline(ACC, snap, evs, Scenario("c", include_expected=False), date(2026, 12, 31))
    assert conf.points[-1].balance == -400000
    stress = build_timeline(ACC, snap, evs, Scenario("s", income_delay_days=3, income_scale=Decimal("0.5")), date(2026, 12, 31))
    assert [(p.on, p.balance) for p in stress.points if p.phase == "end"] == [(date(2026, 11, 8), -400000), (date(2026, 11, 9), 25000)]


def test_evaluate_reports_every_breach_and_both_gaps():
    snap = Snapshot("m", 300000, date(2026, 10, 1))
    evs = [ev("a", date(2026, 10, 5), -200000), ev("b", date(2026, 10, 9), -300000), ev("c", date(2026, 10, 12), 100000, cat="income")]
    rep = evaluate(build_timeline(ACC, snap, evs, SC, date(2026, 12, 31)), ACC.reserve_floor)
    assert not rep.ok and [b.on for b in rep.breaches] == [date(2026, 10, 5), date(2026, 10, 9)]
    assert rep.breaches[0].gap_to_zero == 0 and rep.breaches[0].gap_to_reserve == 100000
    assert rep.breaches[1].gap_to_zero == 200000 and rep.breaches[1].gap_to_reserve == 400000
    assert rep.min_balance == -200000 and rep.first_zero_breach.on == date(2026, 10, 9)


def test_accounts_are_isolated():
    other = CashAccount("o", "other", reserve_floor=0)
    snaps = {"m": Snapshot("m", 100000, date(2026, 10, 1)), "o": Snapshot("o", 10000000, date(2026, 10, 1))}
    from cardflow_ref.cash import evaluate_accounts
    reps = evaluate_accounts([ACC, other], snaps, [ev("x", date(2026, 10, 3), -500000)], SC, date(2026, 12, 31))
    assert not reps["m"].ok and reps["o"].ok   # other account's balance never covers m's debit


def test_snapshot_below_reserve_is_a_baseline_breach_even_without_events():
    snap = Snapshot("m", 100000, date(2026, 10, 1))
    rep = evaluate(build_timeline(ACC, snap, [], SC, date(2026, 12, 31)), ACC.reserve_floor)
    assert not rep.ok and rep.breaches[0].phase == "snapshot" and rep.breaches[0].gap_to_reserve == 100000
    assert rep.ok_zero


def test_inflow_only_day_does_not_add_breach_entry_but_min_and_end_are_visible():
    snap = Snapshot("m", 300000, date(2026, 10, 1))
    evs = [ev("a", date(2026, 10, 5), -600000), ev("c", date(2026, 10, 12), 100000, cat="income")]
    rep = evaluate(build_timeline(ACC, snap, evs, SC, date(2026, 12, 31)), ACC.reserve_floor)
    assert [b.on for b in rep.breaches] == [date(2026, 10, 5)]
    assert rep.min_balance == -300000 and rep.end_balance == -200000 and not rep.ok
