"""Mutate valid PlanInput documents (from fixture dirs) to probe adapter rejections."""
import base64, copy, json, random, sys
from pathlib import Path
rng = random.Random(int(sys.argv[3]))
docs = []
for d in sys.argv[4:]:
    for p in sorted(Path(d).glob("*.v1.json"))[:150]:
        docs.append(json.loads(p.read_text())["input"])
docs.append(json.loads(Path("/projects/cardflow/packages/rules-protocol/fixtures/regression_2026-10-16_10000.v1.json").read_text())["input"])

def paths(node, prefix=()):
    yield prefix, node
    if isinstance(node, dict):
        for k, v in node.items():
            yield from paths(v, prefix + (k,))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from paths(v, prefix + (i,))

VALUES = [None, True, False, 0, -1, 1, 2**31, 2**31 - 1, 2**63, -(2**63) - 1, 10**13, 10**13 + 1, -(10**13) - 1,
          367, 366, 61, 60, 32, 31, 3, "", "x", "0", "1", "1.0", "0.5", "0.00001", "0.000001", "10", "10.5", "11",
          "01", "-1", "1e-3", "2026-02-29", "2028-02-29", "1969-12-31", "3000-01-01", "2026-13-01", "2026-1-1",
          "2026-10-16T09:00:00Z", "2026-10-16T09:00:00+24:00", "2026-10-16T09:00:00", "2026-10-16t09:00:00z",
          "plan_repay_X", "A", "a b", "Z" * 129, "Z" * 128, "CNY", "cny", "USD", "pos", "POS", "p1", "cash-0",
          "cash-x", "e0", "e99", "confirmed", "expected", "living", "timestamp", "fixed_day", "days_after_statement",
          "business", "next_business_day", "user_declared", "😀" * 1001, "😀" * 1000, [], {}, [1], {"a": 1}]
FLOATS = ["1.0", "0.5", "1e2", "10.0", "3600.0", "0.0"]

def mutate(doc):
    d = copy.deepcopy(doc)
    all_paths = [p for p, _ in paths(d) if p]
    kind = rng.random()
    p = rng.choice(all_paths)
    parent = d
    for k in p[:-1]:
        parent = parent[k]
    last = p[-1]
    floats = None
    if kind < 0.45:
        parent[last] = copy.deepcopy(rng.choice(VALUES))
    elif kind < 0.55 and isinstance(parent, dict):
        del parent[last]
    elif kind < 0.62 and isinstance(parent, dict):
        parent[rng.choice(["extra", "daily_cap_minor", "merchant", "day", "days", "kind", "at", "on", "label", "pool_id"])] = 1
    elif kind < 0.70:
        floats = (p, rng.choice(FLOATS))
        parent[last] = "__FLOAT__"
    elif kind < 0.85:
        # duplicate / cross-reference trouble: copy an id-like value from elsewhere
        ids = [(pp, v) for pp, v in paths(d) if isinstance(v, str) and pp and pp[-1] in ("card_id", "event_id", "scenario_id", "cash_account_id", "pool_id", "credit_account_id", "decision_scenario")]
        if ids:
            src = rng.choice(ids)[1]
            tgt = rng.choice(ids)[0]
            node = d
            for k in tgt[:-1]:
                node = node[k]
            node[tgt[-1]] = src
    else:
        # array surgery
        arrays = [pp for pp, v in paths(d) if isinstance(v, list) and pp]
        if arrays:
            ap = rng.choice(arrays)
            node = d
            for k in ap:
                node = node[k]
            if node and rng.random() < 0.5:
                node.append(copy.deepcopy(rng.choice(node)))
            elif node:
                node.pop(rng.randrange(len(node)))
    text = json.dumps(d, ensure_ascii=False)
    if floats:
        text = text.replace('"__FLOAT__"', floats[1], 1)
    return text.encode("utf-8")

n = int(sys.argv[2])
with open(sys.argv[1], "w") as f:
    for i in range(n):
        doc = rng.choice(docs)
        data = mutate(doc)
        if rng.random() < 0.3:
            data = mutate(json.loads(data)) if b"__FLOAT__" not in data else data
        f.write(base64.b64encode(data).decode() + "\n")
print("wrote", n)
