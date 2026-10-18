import json, sys, collections
py = {json.loads(l)["file"]: json.loads(l) for l in open(sys.argv[1])}
dart = {}
for l in open(sys.argv[2]):
    d = json.loads(l)
    dart[d["file"].split("/")[-1]] = d
c = collections.Counter(); bad = []
for f, p in sorted(py.items()):
    d = dart[f]
    o = d["outcome"]
    alloc = {a["card_id"]: a["amount_minor"] for a in d["allocation"]}
    st = p["status"]
    key = None
    if st == "NEEDS_DATA":
        key = "agree NEEDS_DATA" if o == "needsData" else "DISAGREE needs_data"
    elif st == "BASELINE_SHORTFALL":
        key = "agree BASELINE_SHORTFALL" if o == "baselineShortfall" else "DISAGREE shortfall"
    elif st in ("FEASIBLE_ROBUST", "CONDITIONALLY_FEASIBLE"):
        if o == "found":
            if alloc == p["allocation"] and d["failing_scenarios"] == p["failing"]:
                key = "agree found (same allocation)"
            elif p["k"] > 3 and len(p["allocation"]) > 3:
                key = "py uses >3 cards (k>3)"
            else:
                key = "DIFFERENT allocation" + (" (k>3)" if p["k"] > 3 else "")
        else:
            key = ("py needs >3 cards" if len(p["allocation"]) > 3 else "MISSED feasible plan") + (" (timedOut)" if d["timed_out"] else "")
    elif st == "INFEASIBLE":
        key = "agree INFEASIBLE/notFound" if o == "notFound" else "DISAGREE dart found but py infeasible"
    else:
        key = "py status " + st
    c[key] += 1
    if key.startswith(("DIFF", "MISS", "DISAGREE")):
        bad.append((f, key, p, {"outcome": o, "allocation": alloc, "failing": d["failing_scenarios"], "objectives": d.get("objectives")}))
for k, n in sorted(c.items()):
    print(f"{n:6d}  {k}")
for b in bad[:15]:
    print(json.dumps(b, ensure_ascii=False))
