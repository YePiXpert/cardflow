import base64, sys
from cardflow.planner.engine.protocol import ProtocolError, parse_json, inputs_from_protocol, protocol_input_hash
out = []
for line in open(sys.argv[1]).read().splitlines():
    try:
        doc = parse_json(base64.b64decode(line))
    except ProtocolError as e:
        out.append("PARSE " + e.message); continue
    try:
        inputs_from_protocol(doc)
        out.append("OK " + protocol_input_hash(doc))
    except ProtocolError as e:
        out.append(f"ERR {e.path} | {e.message}")
    except Exception as e:  # noqa
        out.append("CRASH " + type(e).__name__)
open(sys.argv[2], "w").write("\n".join(out) + "\n")
