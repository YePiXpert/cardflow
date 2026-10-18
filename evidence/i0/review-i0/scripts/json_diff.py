import base64, sys
from cardflow.planner.engine.protocol import ProtocolError, parse_json, canonical_json
lines = open(sys.argv[1]).read().splitlines()
out = []
for line in lines:
    data = base64.b64decode(line)
    try:
        v = parse_json(data)
        c = canonical_json(v)
        out.append("OK " + base64.b64encode(c).decode())
    except ProtocolError as e:
        out.append("ERR " + e.message)
    except Exception as e:  # noqa
        out.append("CRASH " + type(e).__name__)
open(sys.argv[2], "w").write("\n".join(out) + "\n")
