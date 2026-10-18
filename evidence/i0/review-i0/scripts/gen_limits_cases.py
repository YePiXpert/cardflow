"""Documents of tests/protocol/test_limits.py (BOUNDARY, PROBE adapter cases, array sizes at and over
the limit) for the Python-vs-Dart adapter comparison."""
import base64, copy, importlib.util, json, sys
from pathlib import Path

ROOT = Path("/projects/cardflow")
spec = importlib.util.spec_from_file_location("tl", ROOT / "services/api/tests/protocol/test_limits.py")
tl = importlib.util.module_from_spec(spec); spec.loader.exec_module(tl)
f18 = json.loads((ROOT / "packages/rules-protocol/fixtures/regression_2026-10-16_10000.v1.json").read_text())["input"]
docs = []
for name, path, value, _ in tl.BOUNDARY:
    docs.append((name, tl._set(f18, path, value)))
for name, path, value, _ in tl.PROBE:
    docs.append((name, tl._set(f18, path, value)))
for member, limit in (("cards", 200), ("cash_accounts", 100), ("events", 10000)):
    docs.append((f"{member}-at-{limit}", tl._grow(f18, member, limit)))
    docs.append((f"{member}-at-{limit + 1}", tl._grow(f18, member, limit + 1)))
with open(sys.argv[1], "w") as f, open(sys.argv[2], "w") as names:
    for name, d in docs:
        f.write(base64.b64encode(json.dumps(d).encode()).decode() + "\n")
        names.write(name + "\n")
print(len(docs), "documents")
