import json, sys, collections, re
from pathlib import Path
root = Path(sys.argv[1])
c = collections.Counter()
for p in root.rglob("*.json"):
    d = json.loads(p.read_text())
    if p.name.endswith(".cycles.json"):
        for cid, v in d.items():
            if "error" in v:
                c["cycles error: " + re.sub(r"r[A-G]|\d{4}-\d{2}-\d{2}|\[.*\]", "X", v["error"])] += 1
            else:
                c["cycles ok"] += 1
                if v["alternative_cycles"]:
                    c["cycles with alternatives"] += 1
                if v["due_date"][5:] in ("02-29",) or v["statement_date"][5:] == "02-29":
                    c["cycle touches Feb 29"] += 1
    else:
        for i in d["data_issues"]:
            c["issue " + i["code"]] += 1
        v = d["verification"]
        if v is None:
            c["verify: data issues"] += 1
            continue
        c["verify ok" if v["ok"] else "verify not ok"] += 1
        for viol in v["violations"]:
            c["violation " + re.sub(r"'?[A-GZ]'?: | [A-GZ]: |[0-9]+|'[A-Z]'", "", viol.split(":")[0] if viol.startswith(("UNKNOWN", "PLANNED", "amount", "uses", "credit", "pool")) else re.sub(r"^[A-G]: ", "", viol))[:60]] += 1
        for sid, chk in v["checks"].items():
            for a in chk["assumptions"]:
                key = re.sub(r"\d{4}-\d{2}-\d{2}|cash-\d|e\d+|plan_repay_[A-Z]", "X", a)
                c["assumption " + key[:70]] += 1
            if chk["global_breaches"]:
                c["global breaches"] += 1
            if chk["breaches"]:
                c["breaches"] += 1
        if v["weighted_buffer_days"].startswith("-"):
            c["negative weighted buffer"] += 1
for k, n in sorted(c.items()):
    print(f"{n:6d}  {k}")
