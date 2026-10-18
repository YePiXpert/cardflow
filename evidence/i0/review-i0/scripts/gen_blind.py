"""Blind-spot fixtures for Python-vs-Dart parity (review I-0): leap years and month ends, large
amounts, 5-decimal rates, 10-decimal scale factors, mixed timestamp offsets, rule effectivity
windows, calendar-requiring rules, snapshot after the transaction date, horizon before the
transaction / snapshot, long posting windows, shared accounts and pools, big global floors."""
import json, random, sys
from datetime import date, timedelta
from pathlib import Path

sys.path.insert(0, "/projects/cardflow/packages/rules-protocol/runner_py")
import run_fixtures as runner  # noqa: E402
from cardflow.planner.engine.protocol import ProtocolError, inputs_from_protocol  # noqa: E402

out_dir = Path(sys.argv[1]); out_dir.mkdir(parents=True, exist_ok=True)
count = int(sys.argv[2]); seed = int(sys.argv[3])
rng = random.Random(seed)
CLEAN = len(sys.argv) > 4 and sys.argv[4] == "clean"
AGES = [0, 0, 0, 1, 2, 3] + ([7] if CLEAN else [6, 7, 8, -1, -3])
BUSINESS_OK = 0.98 if CLEAN else 0.9
ROLL_OK = 0.99 if CLEAN else 0.93
EFF = 0.05 if CLEAN else 0.2
OFFSETS_M = [1, 1, 2] + ([0] if not CLEAN else [])
SNAP = 0.995 if CLEAN else 0.95
POOL = 0.995 if CLEAN else 0.95
REG = runner.load_registry()
BIG = 10**13

def amt(scale):
    """Random magnitude: small, medium or huge (up to the protocol limit)."""
    r = rng.random()
    if r < 0.3:
        return rng.randint(1, min(50, scale))
    if r < 0.6:
        return rng.randint(1, min(10**6, scale))
    if r < 0.85:
        return rng.randint(1, min(10**11, scale))
    return rng.randint(max(1, scale // 10), scale)

def rate():
    r = rng.random()
    if r < 0.3:
        return "0"
    if r < 0.35:
        return "1"
    d = rng.randint(1, 5)
    v = rng.randint(1, 10**d - 1)
    s = f"0.{v:0{d}d}".rstrip("0")
    return s

def scale():
    r = rng.random()
    if r < 0.25:
        return "1"
    if r < 0.3:
        return "10"
    if r < 0.35:
        return "0"
    i = rng.randint(0, 9)
    d = rng.randint(1, 10)
    f = rng.randint(1, 10**d - 1)
    s = f"{i}.{f:0{d}d}".rstrip("0")
    return s

OFFSETS = ["Z", "+00:00", "-00:00", "+08:00", "-05:00", "+14:00", "-12:00", "+05:45", "+23:59", "-23:59", "+09:30"]

def stamp(day: date):
    h, m, s = rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 59)
    frac = "" if rng.random() < 0.6 else "." + str(rng.randint(0, 999999)).zfill(6)[: rng.randint(1, 6)]
    return f"{day.isoformat()}T{h:02d}:{m:02d}:{s:02d}{frac}{rng.choice(OFFSETS)}"

def pick_txn():
    y = rng.choice([1972, 2000, 2024, 2028, 2100, 2400, 2026, 2027, 2096, 2999])
    if y == 2999:
        m = rng.choice([1, 2, 6])
    else:
        m = rng.choice([1, 2, 2, 2, 3, 11, 12, 12])
    last = (date(y + (m // 12), m % 12 + 1, 1) - timedelta(days=1)).day
    d = rng.choice([1, 15, last - 2, last - 1, last])
    return date(y, m, d)

def doc_once():
    txn = pick_txn()
    n_acc = rng.randint(1, 4)
    acc_ids = [f"cash-{i}" for i in range(n_acc)]
    accounts, snapshots = [], []
    for a in acc_ids:
        acc = {"cash_account_id": a, "currency": "CNY",
               "reserve_floor_minor": rng.choice([0, 0, amt(BIG)]),
               "usable_for_repayment": rng.random() < 0.95}
        if rng.random() < 0.3:
            acc["name"] = rng.choice(["主账户", "a😀b", "x" * 10])
        accounts.append(acc)
        if rng.random() < SNAP:
            age = rng.choice(AGES)  # negative: snapshot after txn
            snapshots.append({"cash_account_id": a,
                              "balance_minor": rng.choice([1, -1]) * amt(BIG) if rng.random() < 0.2 else amt(BIG),
                              "as_of": (txn - timedelta(days=age)).isoformat(),
                              "includes_event_ids": []})
            if rng.random() < 0.3:
                snapshots[-1]["observed_at"] = stamp(txn - timedelta(days=max(age, 0)))
    timed_all = rng.random() < 0.6
    events = []
    for k in range(rng.randint(0, 25)):
        on = txn + timedelta(days=rng.randint(-10, 120))
        if on.year > 2999:
            on = date(2999, 12, 31)
        e = {"event_id": f"e{k}", "cash_account_id": rng.choice(acc_ids), "on": on.isoformat(),
             "amount_minor": rng.choice([-1, 1]) * amt(BIG // 1000),
             "cls": rng.choice(["confirmed", "expected", "planned"]),
             "category": rng.choice(["income", "bill", "living", "living", "repayment", "transfer_in", "transfer_out", "fee", "other"])}
        if rng.random() < 0.2:
            e["amount_minor"] = 0
        if timed_all or rng.random() < 0.3:
            e["at"] = stamp(on)
        if rng.random() < 0.2:
            e["label"] = rng.choice(["工资", "rent", "😀" * 3])
        events.append(e)
    for s in snapshots:
        s["includes_event_ids"] = [e["event_id"] for e in events
                                   if e["cash_account_id"] == s["cash_account_id"] and e["on"] <= s["as_of"] and rng.random() < 0.5]
    cards = []
    pools_used = set()
    for i in range(rng.randint(1, 7)):
        cid = "ABCDEFG"[i]
        sd = rng.choice([1, 5, 15, 27, 28, 29, 30, 31])
        if rng.random() < 0.75:
            due = {"kind": "fixed_day", "day": rng.choice([1, 5, 20, 28, 29, 30, 31]), "month_offset": rng.choice(OFFSETS_M)}
        else:
            due = {"kind": "days_after_statement", "days": rng.randint(1, 60), "day_kind": "calendar" if rng.random() < BUSINESS_OK else "business"}
        rule = {"rule_id": f"r{cid}", "statement_day": sd, "statement_day_inclusive": rng.random() < 0.6,
                "due": due, "holiday_rollover": "none" if rng.random() < ROLL_OK else "next_business_day"}
        if rng.random() < EFF:
            rule["effective_from"] = (txn + timedelta(days=rng.randint(-30, 5))).isoformat()
        if rng.random() < EFF:
            rule["effective_to"] = (txn + timedelta(days=rng.randint(-2, 40))).isoformat()
        if rng.random() < 0.2:
            rule["source"] = "银行公告"; rule["status"] = rng.choice(["draft", "verified", "user_declared"]); rule["verified_on"] = txn.isoformat()
        dmin = rng.choice([0, 0, 0, 1, 2, 5, 20])
        card = {"card_id": cid, "credit_account_id": f"acc-{cid}", "raw_available_minor": rng.choice([1, 1, 1, -1]) * amt(BIG),
                "holds_uncounted_minor": rng.choice([0, 0, amt(BIG // 10)]), "reservations_minor": rng.choice([0, 0, amt(BIG // 10)]),
                "billing_rule": rule, "repay_from_cash_account_id": rng.choice(acc_ids),
                "channel_ok": rng.random() < 0.97, "currency_ok": rng.random() < 0.97, "status_ok": rng.random() < 0.97,
                "fee_rate": rate(), "fee_fixed_minor": rng.choice([0, 0, 0, rng.randint(1, 10**8)]),
                "verified_benefit_rate": rate(), "potential_benefit_rate": rate(),
                "posting_delay_min_days": dmin, "posting_delay_max_days": dmin + rng.choice([0, 0, 1, 3, 10, 40])}
        if rng.random() < 0.3:
            card["pool_id"] = rng.choice(["p1", "p2"]); pools_used.add(card["pool_id"])
        if rng.random() < 0.25:
            card["per_txn_cap_minor"] = rng.choice([0, amt(BIG)])
        if rng.random() < 0.25:
            card["min_split_minor"] = amt(BIG)
        if rng.random() < 0.25:
            card["verified_benefit_cap_minor"] = rng.choice([0, amt(BIG)])
        if cards and rng.random() < 0.3:
            host = rng.choice(cards)
            card["credit_account_id"] = host["credit_account_id"]
            card["raw_available_minor"] = host["raw_available_minor"]
            if "pool_id" in host:
                card["pool_id"] = host["pool_id"]
            else:
                card.pop("pool_id", None)
        cards.append(card)
    pools_used = {c["pool_id"] for c in cards if "pool_id" in c}
    pools = [{"pool_id": p, "available_minor": rng.choice([1, 1, -1]) * amt(BIG)} for p in sorted(pools_used) if rng.random() < POOL]
    amount = amt(BIG)
    request = {"amount_minor": amount, "currency": "CNY", "txn_date": txn.isoformat(), "allow_split": rng.random() < 0.7,
               "max_cards": rng.randint(1, 7), "min_split_minor": rng.choice([1, 1, amt(BIG)]),
               "payment_lead_days": rng.choice([0, 0, 1, 3, 15, 60, 366]), "channel": "pos"}
    order = "timestamp" if rng.random() < 0.6 else "conservative"
    def scen(sid, inc):
        return {"scenario_id": sid, "include_expected": inc, "income_delay_days": 0, "income_scale": "1",
                "expense_scale": "1", "event_overrides": [], "same_day_order": order}
    scenarios = [scen("confirmed", False), scen("baseline", True)]
    for j in range(rng.randint(0, 3)):
        s = scen(f"stress{j}", rng.random() < 0.8)
        s["income_delay_days"] = rng.choice([0, 1, 7, 30, 366])
        s["income_scale"] = scale(); s["expense_scale"] = scale()
        s["same_day_order"] = rng.choice(["timestamp", "conservative"])
        ovs = []
        for e in rng.sample(events, min(len(events), rng.randint(0, 4))):
            o = {"event_id": e["event_id"]}
            if rng.random() < 0.6:
                nd = date.fromisoformat(e["on"]) + timedelta(days=rng.randint(-20, 30))
                if nd.year > 2999: nd = date(2999, 12, 31)
                if nd.year < 1970: nd = date(1970, 1, 1)
                o["on"] = nd.isoformat()
            if rng.random() < 0.5 or "on" not in o:
                o["amount_minor"] = rng.choice([-1, 1]) * amt(BIG // 1000)
            ovs.append(o)
        s["event_overrides"] = ovs
        if rng.random() < 0.3:
            s["description"] = "压力情景"
        scenarios.append(s)
    horizon = txn + timedelta(days=rng.choice([-5, 0, 10, 60, 180, 200, 400]))
    if horizon.year > 2999:
        horizon = date(2999, 12, 31)
    decision = rng.choice([s["scenario_id"] for s in scenarios])
    return {"protocol_version": "1", "request": request, "cards": cards, "pools": pools, "cash_accounts": accounts,
            "snapshots": snapshots, "events": events, "scenarios": scenarios, "horizon_end": horizon.isoformat(),
            "options": {"profile": rng.choice(["cash_safety", "verified_benefit", "fewer_cards"]), "decision_scenario": decision,
                        "time_limit_s": rng.choice([10, 1, 3600]), "workers": 8, "seed": 0, "stale_after_days": rng.choice([7, 0, 30, 366]),
                        "global_reserve_floor_minor": rng.choice([0, 0, amt(BIG)])}}

def allocations(doc, n):
    ids = [c["card_id"] for c in doc["cards"]]
    amount = doc["request"]["amount_minor"]
    out = []
    for _ in range(n):
        pool = ids + (["Z"] if rng.random() < 0.1 else [])
        k = rng.randint(1, min(3, len(pool)))
        chosen = rng.sample(pool, k)
        if rng.random() < 0.6 and amount >= k:
            cuts = sorted(rng.sample(range(1, amount), k - 1)) if k > 1 else []
            b = [0] + cuts + [amount]
            out.append([{"card_id": chosen[j], "amount_minor": b[j + 1] - b[j]} for j in range(k)])
        else:
            out.append([{"card_id": c, "amount_minor": amt(BIG)} for c in chosen])
    return out

made = tried = 0
while made < count:
    tried += 1
    doc = doc_once()
    try:
        inputs_from_protocol(doc)
    except ProtocolError:
        continue
    if runner.schema_errors(REG, "PlanInput.schema.json", doc):
        continue
    expected = [{"name": "cycles", "kind": "cycles", "assertions": [{"path": "", "length": len(doc["cards"])}]}]
    for j, a in enumerate(allocations(doc, 4)):
        expected.append({"name": f"verify_{j}", "kind": "verify", "allocation": a,
                         "decision_scenario": rng.choice([s["scenario_id"] for s in doc["scenarios"]]),
                         "assertions": [{"path": "", "length": 3}]})
    fixture = {"protocol_version": "1", "fixture_id": f"BLIND-{seed}-{made}", "description": "review I-0 blind-spot parity",
               "input": doc, "expected": expected}
    (out_dir / f"blind_{made:04d}.v1.json").write_text(json.dumps(fixture, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    made += 1
print(f"wrote {made} fixtures (tried {tried})")
