"""Golden-fixture loader (JSON with money as decimal strings)."""
from __future__ import annotations

import json
from datetime import date
from decimal import Decimal

from .allocation import CardOption, ModelInputs, PlanRequest
from .billing import BillingRule, DueRule
from .cash import CashAccount, CashEvent, EventClass, Scenario, Snapshot
from .money import to_minor


def _d(s: str) -> date:
    return date.fromisoformat(s)


def load_fixture(path: str):
    raw = json.load(open(path, encoding="utf-8"))
    cur = raw["request"]["currency"]
    m = lambda s: to_minor(s, cur)
    rq = raw["request"]
    request = PlanRequest(m(rq["amount"]), cur, _d(rq["txn_date"]), rq.get("allow_split", False), rq.get("max_cards", 1),
                          m(rq.get("min_split", "0.01")), rq.get("payment_lead_days", 0), rq.get("channel", "pos"))
    cards = []
    for c in raw["cards"]:
        due = c["due"]
        rule = BillingRule(c.get("rule_id", f"rule-{c['id']}"), c["statement_day"],
                           DueRule(due["kind"], due.get("day"), due.get("month_offset", 0), due.get("days")),
                           c.get("statement_day_inclusive", True), c.get("holiday_rollover", "none"),
                           source=c.get("rule_source", "fixture"), status=c.get("rule_status", "user_declared"))
        cards.append(CardOption(c["id"], c["account_id"], c.get("name", c["id"]), m(c["available"]), rule, c["repay_from"],
                                m(c.get("uncounted_holds", "0")), m(c.get("plan_reservations", "0")), c.get("pool_id"),
                                m(c["per_txn_cap"]) if c.get("per_txn_cap") else None,
                                m(c["min_split"]) if c.get("min_split") else None,
                                c.get("channel_ok", True), c.get("currency_ok", True), c.get("status_ok", True),
                                Decimal(c.get("fee_rate", "0")), m(c.get("fee_fixed", "0")),
                                Decimal(c.get("verified_benefit_rate", "0")),
                                m(c["verified_benefit_cap"]) if c.get("verified_benefit_cap") else None,
                                Decimal(c.get("potential_benefit_rate", "0")),
                                c.get("posting_delay_min", 0), c.get("posting_delay_max", 0)))
    pools = {k: m(v) for k, v in raw.get("pools", {}).items()}
    accounts = [CashAccount(a["id"], a.get("name", a["id"]), a.get("currency", cur), m(a.get("reserve_floor", "0")),
                            a.get("usable_for_repayment", True)) for a in raw["cash_accounts"]]
    snapshots = {s["account"]: Snapshot(s["account"], m(s["balance"]), _d(s["as_of"]),
                                        includes_event_ids=frozenset(s.get("includes_event_ids", [])))
                 for s in raw["snapshots"]}
    events = [CashEvent(e["id"], e.get("account", accounts[0].id), _d(e["on"]), m(e["amount"]), EventClass(e["cls"]),
                        e.get("category", ""), e.get("label", "")) for e in raw["events"]]
    scenarios = {}
    for sid, s in raw["scenarios"].items():
        ov = {k: ({"on": _d(v["on"])} if "on" in v else {}) | ({"amount": m(v["amount"])} if "amount" in v else {})
              for k, v in s.get("event_overrides", {}).items()}
        scenarios[sid] = Scenario(sid, s.get("include_expected", True), s.get("income_delay_days", 0),
                                  Decimal(s.get("income_scale", "1")), Decimal(s.get("expense_scale", "1")), ov,
                                  s.get("same_day_order", "conservative"), s.get("description", ""))
    inputs = ModelInputs(request, cards, pools, accounts, snapshots, events, _d(raw["horizon_end"]),
                         m(raw.get("global_reserve_floor", "0")))
    return inputs, scenarios, raw
