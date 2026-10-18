"""Counterexample for the bounded search's candidate cuts: a global reserve floor makes the
feasible split of a 2-card plan a narrow band that no cut point hits."""
import json, sys
from pathlib import Path
from cardflow.planner.engine.protocol import plan_from_protocol, verify_from_protocol, protocol_input_hash

def card(cid, stmt_day, due_day, repay_from, fee_rate):
    return {"card_id": cid, "credit_account_id": f"acc-{cid}", "raw_available_minor": 10_000_000,
            "holds_uncounted_minor": 0, "reservations_minor": 0,
            "billing_rule": {"rule_id": f"r{cid}", "statement_day": stmt_day, "statement_day_inclusive": True,
                             "due": {"kind": "fixed_day", "day": due_day, "month_offset": 1}, "holiday_rollover": "none"},
            "repay_from_cash_account_id": repay_from, "channel_ok": True, "currency_ok": True, "status_ok": True,
            "fee_rate": fee_rate, "fee_fixed_minor": 0, "verified_benefit_rate": "0", "potential_benefit_rate": "0",
            "posting_delay_min_days": 0, "posting_delay_max_days": 0}

def scen(sid, inc):
    return {"scenario_id": sid, "include_expected": inc, "income_delay_days": 0, "income_scale": "1",
            "expense_scale": "1", "event_overrides": [], "same_day_order": "conservative"}

doc = {
    "protocol_version": "1",
    "request": {"amount_minor": 1_000_000, "currency": "CNY", "txn_date": "2026-10-16", "allow_split": True,
                "max_cards": 2, "min_split_minor": 1, "payment_lead_days": 0, "channel": "pos"},
    # A: statement 10-20 -> due 11-25 (fee 1%), repaid from cash-1; B: statement 10-18 -> due 11-05, from cash-2
    "cards": [card("A", 20, 25, "cash-1", "0.01"), card("B", 18, 5, "cash-2", "0")],
    "pools": [],
    "cash_accounts": [
        {"cash_account_id": "cash-1", "currency": "CNY", "reserve_floor_minor": 0, "usable_for_repayment": True},
        {"cash_account_id": "cash-2", "currency": "CNY", "reserve_floor_minor": 0, "usable_for_repayment": True},
    ],
    "snapshots": [
        {"cash_account_id": "cash-1", "balance_minor": 10_000_000, "as_of": "2026-10-16", "includes_event_ids": []},
        {"cash_account_id": "cash-2", "balance_minor": 10_000_000, "as_of": "2026-10-16", "includes_event_ids": []},
    ],
    "events": [{"event_id": "salary", "cash_account_id": "cash-2", "on": "2026-11-10", "amount_minor": 606_500,
                "cls": "confirmed", "category": "income"}],
    "scenarios": [scen("confirmed", False), scen("baseline", True)],
    "horizon_end": "2027-04-30",
    "options": {"profile": "cash_safety", "decision_scenario": "baseline", "time_limit_s": 10, "workers": 8,
                "seed": 0, "stale_after_days": 7, "global_reserve_floor_minor": 19_600_000},
}
Path(sys.argv[1]).write_text(json.dumps(doc, indent=1) + "\n")
out = plan_from_protocol(doc, with_sensitivity=False)
print("input_hash", protocol_input_hash(doc))
print("python plan():", out["business_status"], out["solver_status"], "proven_optimal", out["proven_optimal"],
      [(a["card_id"], a["amount_minor"], a["repay_on"], a["fee_minor"]) for a in out["allocation"]])
print("python baseline ok:", {k: v["ok"] for k, v in out["baseline"].items()})
for split in ([(1, 999_999)], [(999_999, 1)], [(500_000, 500_000)], [(600_000, 400_000)], [(650_000, 350_000)],
              [(651_000, 349_000)], [(599_999, 400_001)]):
    a, b = split[0]
    v = verify_from_protocol(doc, [{"card_id": "A", "amount_minor": a}, {"card_id": "B", "amount_minor": b}], "baseline")
    ver = v["verification"]
    print(f"verify A {a} + B {b}: ok={ver['ok']} global_breaches={[(g['on'], g['gap']) for g in ver['checks']['baseline']['global_breaches']]}")
