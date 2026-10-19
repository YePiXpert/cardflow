"""生成随机分期样本并用 Python money.py 计算（只读调用冻结的引擎）。用法：python installment_cases.py OUT.json"""
import json, random, sys
from decimal import Decimal, ROUND_HALF_UP
from cardflow.planner.engine.money import split_installments, installment_cash_flows, irr_monthly, annualize

rnd = random.Random(20261019)
cases = []
def add(principal, periods, rate, rem):
    flows = installment_cash_flows(principal, periods, rate, rem)
    irr_flows = [(0, -principal)] + [(k, p + f) for k, p, f in flows]
    irr = irr_monthly(irr_flows)
    ann = annualize(irr)
    nom = annualize(Decimal(rate))["nominal_x12"]
    pct = lambda r: str((r * 100).quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP))
    cases.append({
        "principal": principal, "periods": periods, "rate": rate, "remainder": rem,
        "split": split_installments(principal, periods, rem),
        "fees": [f for _, _, f in flows],
        "irr": str(irr),
        "effective": str(ann["effective_compound"]),
        "nominal": str(nom),
        "effective_pct": pct(ann["effective_compound"]),
        "nominal_pct": pct(nom),
    })

edge_rates = ["0", "0.0000000001", "0.006", "0.0075", "0.015", "0.0999999999", "0.5"]
for periods in (1, 2, 3, 6, 12, 18, 24, 36):
    for rate in edge_rates:
        add(10**13 if periods % 2 else 1, periods, rate, "last" if periods % 3 else "first")
for _ in range(220):
    periods = rnd.choice([1, 2, 3, 5, 6, 7, 9, 12, 18, 24, 36])
    principal = rnd.choice([rnd.randint(1, 100), rnd.randint(100, 10**6), rnd.randint(10**6, 10**13)])
    digits = rnd.randint(1, 10)
    rate = str((Decimal(rnd.randint(0, 10**digits - 1)) / Decimal(10**digits) * Decimal("0.05")).quantize(Decimal(1).scaleb(-10)).normalize())
    if rate in ("0E-10", "0E+1"):
        rate = "0"
    add(principal, periods, rate, rnd.choice(["last", "first"]))
for principal, rate in ((123456789, "0.006"), (10**13, "0.0125")):
    add(principal, 60, rate, "last")
json.dump(cases, open(sys.argv[1], "w"), ensure_ascii=False)
print(f"python cases: {len(cases)}")
