"""Two inputs on which the frozen Python adapter raises an uncaught exception instead of ProtocolError."""
from cardflow.planner.engine.protocol import ProtocolError, canonical_json, parse_json

CASES = [
    ("lone-surrogate key", b'{"\\ud800": 1}'),
    ("nested 1000", b"[" * 1000 + b"]" * 1000),
]
for label, text in CASES:
    value = parse_json(text)  # both parse
    try:
        canonical_json(value)
        print(label, "-> accepted")
    except ProtocolError as e:
        print(label, "-> ProtocolError:", e.message)
    except Exception as e:  # noqa: BLE001
        print(label, "-> uncaught", type(e).__name__)
