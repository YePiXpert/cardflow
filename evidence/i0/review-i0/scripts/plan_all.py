import json, sys
from pathlib import Path
from cardflow.planner.engine.protocol import plan_from_protocol, parse_json
out = open(sys.argv[2], "w")
for p in sorted(Path(sys.argv[1]).glob("*.v1.json")):
    doc = parse_json(p.read_bytes())["input"]
    o = plan_from_protocol(doc, with_sensitivity=False)
    req = doc["request"]
    k = req["max_cards"] if req["allow_split"] else 1
    out.write(json.dumps({"file": p.name, "status": o["business_status"], "solver": o["solver_status"],
                          "allocation": {a["card_id"]: a["amount_minor"] for a in o["allocation"]},
                          "failing": o["failing_scenarios"], "k": k, "proven": o["proven_optimal"],
                          "notes": [n for n in o["notes"] if "TIE_BREAK" in n]}) + "\n")
