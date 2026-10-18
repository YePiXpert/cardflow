"""Scale every money amount of fixtures by F (so that the bounded search is no longer exhaustive)."""
import json, sys, random
from pathlib import Path
src, dst, F, seed = Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
rng = random.Random(seed)
dst.mkdir(parents=True, exist_ok=True)
def scale(v, jitter=True):
    return v * F + (rng.randint(-F // 3, F // 3) if jitter and v != 0 else 0)
for p in sorted(src.glob("*.v1.json")):
    fx = json.loads(p.read_text())
    d = fx["input"]
    d["request"]["amount_minor"] = max(1, d["request"]["amount_minor"] * F)
    d["request"]["min_split_minor"] = max(1, d["request"]["min_split_minor"] * F)
    for c in d["cards"]:
        for k in ("raw_available_minor", "holds_uncounted_minor", "reservations_minor", "per_txn_cap_minor",
                  "min_split_minor", "fee_fixed_minor", "verified_benefit_cap_minor"):
            if k in c:
                c[k] = c[k] * F
        if c.get("min_split_minor") == 0:
            c["min_split_minor"] = 1
    # cards of one credit account keep one available value (already equal before scaling)
    for pl in d["pools"]:
        pl["available_minor"] = pl["available_minor"] * F
    for a in d["cash_accounts"]:
        a["reserve_floor_minor"] *= F
    for s in d["snapshots"]:
        s["balance_minor"] = scale(s["balance_minor"])
    for e in d["events"]:
        e["amount_minor"] = scale(e["amount_minor"])
    for sc in d["scenarios"]:
        for o in sc["event_overrides"]:
            if "amount_minor" in o:
                o["amount_minor"] = scale(o["amount_minor"])
    d["options"]["global_reserve_floor_minor"] *= F
    # verify cases: scale allocations too (keeps the fixture valid)
    for case in fx["expected"]:
        if case["kind"] == "verify":
            for a in case["allocation"]:
                a["amount_minor"] *= F
    (dst / p.name).write_text(json.dumps(fx, ensure_ascii=False) + "\n")
