"""Strict JSON for job payloads, stored results and the subprocess channel (ADR-008).

Stored JSON -- ``jobs.payload`` and ``jobs.result`` -- may contain only null, booleans,
integers, strings, arrays and objects with string keys:

* no ``float`` and no :class:`~decimal.Decimal`: money is integer minor units, and a
  fractional JSON number cannot be told apart from a mistyped amount; other fractions
  (rates, durations) must be strings or integers in a smaller unit;
* no U+0000 in strings or keys (PostgreSQL ``jsonb`` rejects it);
* bounded nesting and size (:data:`MAX_PAYLOAD_BYTES`, :data:`MAX_RESULT_BYTES`).

The subprocess channel is transient: the parent sends the child's input as compact JSON
(finite numbers of any kind), and decodes the child's output with non-integer numbers as
exact :class:`~decimal.Decimal` values -- never as binary floats.

Error messages name the offending *path* (``$.items[2].amount``), never the value; keys
that are not plain identifiers are shown as ``<key>``.
"""

import json
import re
from decimal import Decimal
from typing import Final

type JsonValue = bool | int | str | list[JsonValue] | dict[str, JsonValue] | None

MAX_PAYLOAD_BYTES: Final = 64 * 1024
"""``jobs.payload`` limit: payloads carry identifiers and options, not documents."""
MAX_RESULT_BYTES: Final = 256 * 1024
"""``jobs.result`` limit: a status summary (ids, counts); bulk output belongs in its own tables."""
MAX_TRANSPORT_BYTES: Final = 64 * 1024 * 1024
"""Subprocess input/output message limit."""
MAX_DEPTH: Final = 32

_IDENTIFIER: Final = re.compile(r"[A-Za-z_][A-Za-z0-9_]{0,63}")


class JsonRejected(ValueError):  # noqa: N818 -- reads as "payload rejected"
    """A value cannot be used as job JSON; the message names the path, never the value."""


def _label(key: str) -> str:
    return key if _IDENTIFIER.fullmatch(key) else "<key>"


def _check(value: object, path: str, depth: int, what: str) -> None:
    if depth > MAX_DEPTH:
        raise JsonRejected(f"{what}: nested deeper than {MAX_DEPTH} levels at {path}")
    if value is None or isinstance(value, bool | int):
        return
    if isinstance(value, str):
        if "\x00" in value:
            raise JsonRejected(f"{what}: string with U+0000 at {path}")
        return
    if isinstance(value, float | Decimal):
        raise JsonRejected(
            f"{what}: non-integer number at {path}; amounts are integer minor units "
            "(ADR-008), other fractions must be strings"
        )
    if isinstance(value, dict):
        for key, item in value.items():
            if not isinstance(key, str):
                raise JsonRejected(f"{what}: non-string object key at {path}")
            if "\x00" in key:
                raise JsonRejected(f"{what}: object key with U+0000 at {path}")
            _check(item, f"{path}.{_label(key)}", depth + 1, what)
        return
    if isinstance(value, list | tuple):
        for index, item in enumerate(value):
            _check(item, f"{path}[{index}]", depth + 1, what)
        return
    raise JsonRejected(f"{what}: {type(value).__name__} at {path} is not a JSON value")


def check_stored_json(value: object, *, what: str) -> None:
    """Raise :class:`JsonRejected` unless ``value`` may be stored as job JSON."""
    _check(value, "$", 0, what)


def encode_stored(value: object, *, what: str, max_bytes: int) -> str:
    """Validate ``value`` (see module docstring) and return its compact JSON text."""
    check_stored_json(value, what=what)
    try:
        text = json.dumps(
            value, ensure_ascii=False, separators=(",", ":"), allow_nan=False, sort_keys=False
        )
        size = len(text.encode("utf-8"))
    except (TypeError, ValueError):  # e.g. lone surrogates, int beyond the str() digit limit
        raise JsonRejected(f"{what}: cannot be encoded as UTF-8 JSON") from None
    if size > max_bytes:
        raise JsonRejected(f"{what}: {size} bytes exceeds the limit of {max_bytes}")
    return text


def encode_transport(value: object) -> bytes:
    """Subprocess channel: compact UTF-8 JSON; NaN/Infinity and non-JSON types rejected."""
    try:
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode(
            "utf-8"
        )
    except (TypeError, ValueError):
        raise JsonRejected("value is not JSON-serializable (finite numbers only)") from None


def _reject_constant(name: str) -> object:
    raise JsonRejected(f"{name} is not a JSON number")


def decode_transport(data: bytes, *, exact: bool) -> object:
    """Decode a subprocess message; ``exact=True`` reads fractions as :class:`Decimal`."""
    try:
        return json.loads(
            data, parse_float=Decimal if exact else float, parse_constant=_reject_constant
        )
    except JsonRejected:
        raise
    except (ValueError, RecursionError):  # JSONDecodeError and UnicodeDecodeError included
        raise JsonRejected("message is not valid UTF-8 JSON") from None
