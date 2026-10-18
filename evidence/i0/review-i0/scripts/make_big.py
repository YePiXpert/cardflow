"""A PlanInput at the protocol's size limits (200 cards, 100 cash accounts, 10,000 events, 5 scenarios)."""
import json, random, sys
from datetime import date, timedelta
from pathlib import Path
from cardflow.planner.engine.protocol import inputs_from_protocol
rng = random.Random(1)
txn = date(2026, 10, 16)
accs = [f"cash-{i}" for i in range(100)]
doc = {"protocol_version": "1",
       "request": {"amount_minor": 5_000_000, "currency": "CNY", "txn_date": txn.isoformat(), "allow_split": True,
                   "max_cards": 3, "min_split_minor": 100, "payment_lead_days": 2, "channel": "pos"},
       "cards": [], "pools": [], "cash_accounts": [], "snapshots": [], "events": [], "scenarios": [],
       "horizon_end": (txn + timedelta(days=200)).isoformat(),
       "options": {"profile": "cash_safety", "decision_scenario": "baseline", "time_limit_s": 10, "workers": 8,
                   "seed": 0, "stale_after_days": 7, "global_reserve_floor_minor": int(sys.argv[2])}}
for a in accs:
    doc["cash_accounts"].append({"cash_account_id": a, "currency": "CNY", "reserve_floor_minor": 100_000, "usable_for_repayment": True})
    doc["snapshots"].append({"cash_account_id": a, "balance_minor": 50_000_000, "as_of": txn.isoformat(), "includes_event_ids": []})
for i in range(10_000):
    on = txn + timedelta(days=rng.randint(0, 199))
    e = {"event_id": f"e{i}", "cash_account_id": rng.choice(accs), "on": on.isoformat(),
         "amount_minor": rng.choice([-1, 1]) * rng.randint(1, 200_000), "cls": rng.choice(["confirmed", "expected"]),
         "category": rng.choice(["income", "living", "bill"]), "at": f"{on.isoformat()}T{rng.randint(0,23):02d}:{rng.randint(0,59):02d}:00+08:00"}
    doc["events"].append(e)
for i in range(200):
    doc["cards"].append({"card_id": f"c{i:03d}", "credit_account_id": f"acc-{i:03d}", "raw_available_minor": rng.randint(1_000_000, 4_000_000),
        "holds_uncounted_minor": 0, "reservations_minor": 0,
        "billing_rule": {"rule_id": f"r{i}", "statement_day": rng.randint(1, 28), "statement_day_inclusive": True,
                         "due": {"kind": "fixed_day", "day": rng.randint(1, 28), "month_offset": 1}, "holiday_rollover": "none"},
        "repay_from_cash_account_id": rng.choice(accs), "channel_ok": True, "currency_ok": True, "status_ok": True,
        "fee_rate": rng.choice(["0", "0.006", "0.01"]), "fee_fixed_minor": 0, "verified_benefit_rate": rng.choice(["0", "0.005"]),
        "potential_benefit_rate": "0", "posting_delay_min_days": 0, "posting_delay_max_days": rng.choice([0, 2])})
def scen(sid, inc, **kw):
    s = {"scenario_id": sid, "include_expected": inc, "income_delay_days": 0, "income_scale": "1", "expense_scale": "1",
         "event_overrides": [], "same_day_order": "timestamp"}
    s.update(kw); return s
doc["scenarios"] = [scen("confirmed", False), scen("baseline", True),
                    scen("stress1", True, income_delay_days=3, income_scale="0.8"),
                    scen("stress2", True, expense_scale="1.5"),
                    scen("stress3", True, income_delay_days=7, event_overrides=[{"event_id": f"e{i}", "amount_minor": -1000} for i in range(50)])]
inputs_from_protocol(doc)
Path(sys.argv[1]).write_text(json.dumps(doc) + "\n")
print("ok", sys.argv[1])
