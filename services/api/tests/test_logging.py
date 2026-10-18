"""Structured logging: field whitelist, exception reduction, handler setup."""

import io
import json
import logging
import sys
import warnings
from collections.abc import Iterator

import pytest
from pydantic import BaseModel

from cardflow.log import (
    QUIET_LOGGERS,
    JsonFormatter,
    TextFormatter,
    configure_logging,
    describe_exception,
    request_id_var,
)


def make_record(**extra: object) -> logging.LogRecord:
    record = logging.LogRecord("cardflow.test", logging.INFO, __file__, 1, "event", None, None)
    record.__dict__.update(extra)
    return record


def test_json_formatter_drops_fields_outside_whitelist() -> None:
    record = make_record(request_id="r-1", status=200, amount_minor=1234567, merchant="Shop-Q")

    fields = json.loads(JsonFormatter().format(record))

    assert fields["request_id"] == "r-1"
    assert fields["status"] == 200
    assert fields["message"] == "event"
    assert "amount_minor" not in fields
    assert "1234567" not in json.dumps(fields)
    assert "Shop-Q" not in json.dumps(fields)


def test_exception_message_is_never_logged() -> None:
    try:
        raise ValueError("card 6222021234567890 amount 88800")
    except ValueError:
        record = make_record()
        record.exc_info = sys.exc_info()

    line = JsonFormatter().format(record)

    fields = json.loads(line)
    assert fields["exc_type"] == "ValueError"
    assert fields["exc_frames"]
    assert all(":" in frame for frame in fields["exc_frames"])
    assert "6222021234567890" not in line
    assert "88800" not in line


def test_exception_chain_lists_types_only() -> None:
    try:
        try:
            raise OSError("disk detail 1")
        except OSError as inner:
            raise KeyError("key detail 2") from inner
    except KeyError:
        exc_type, exc, tb = sys.exc_info()
    assert exc_type is not None
    assert exc is not None

    fields = describe_exception((exc_type, exc, tb))

    assert fields["exc_type"] == "KeyError"
    assert fields["exc_chain"] == ["OSError"]
    assert "detail" not in json.dumps(fields)


def test_text_formatter_keeps_one_line_per_record() -> None:
    record = make_record(request_id="r-2")
    record.msg = "first\nforged second line"

    line = TextFormatter().format(record)

    assert "\n" not in line
    assert 'request_id="r-2"' in line


@pytest.fixture
def restore_logging() -> Iterator[None]:
    """Undo configure_logging() so pytest's own capture keeps working."""
    root = logging.getLogger()
    saved_root = (list(root.handlers), root.level)
    names = ("uvicorn", "uvicorn.error", "uvicorn.access")
    saved = {
        name: (
            list(logging.getLogger(name).handlers),
            logging.getLogger(name).propagate,
            logging.getLogger(name).disabled,
        )
        for name in names
    }
    saved_levels = {name: logging.getLogger(name).level for name in QUIET_LOGGERS}
    saved_showwarning = warnings.showwarning
    yield
    root.handlers[:] = saved_root[0]
    root.setLevel(saved_root[1])
    for name, (handlers, propagate, disabled) in saved.items():
        logger = logging.getLogger(name)
        logger.handlers[:] = handlers
        logger.propagate = propagate
        logger.disabled = disabled
    for name, level in saved_levels.items():
        logging.getLogger(name).setLevel(level)
    warnings.showwarning = saved_showwarning


@pytest.mark.usefixtures("restore_logging")
def test_configure_logging_emits_json_with_request_id_and_mutes_uvicorn_access() -> None:
    stream = io.StringIO()
    configure_logging("info", "json", stream=stream)

    token = request_id_var.set("req-abc")
    try:
        logging.getLogger("cardflow.test").info("hello", extra={"status": 201})
        logging.getLogger("uvicorn.access").info('GET /x?token=raw-q HTTP/1.1" 200')
        logging.getLogger("uvicorn.error").info("server started")
    finally:
        request_id_var.reset(token)

    lines = [json.loads(line) for line in stream.getvalue().splitlines()]
    assert [line["message"] for line in lines] == ["hello", "server started"]
    assert lines[0]["request_id"] == "req-abc"
    assert lines[0]["status"] == 201
    assert lines[0]["level"] == "info"
    assert "raw-q" not in stream.getvalue()


class _Amount(BaseModel):
    amount_minor: int


@pytest.mark.usefixtures("restore_logging")
def test_warning_text_is_never_logged() -> None:
    """Pydantic serialization warnings quote input_value; only class + location may be logged."""
    stream = io.StringIO()
    configure_logging("info", "json", stream=stream)

    with warnings.catch_warnings():
        warnings.simplefilter("always")
        warnings.warn("value 4111111111111111 amount 88800", UserWarning, stacklevel=1)
        _Amount.model_construct(amount_minor="4111111111111111").model_dump()  # type: ignore[arg-type]

    output = stream.getvalue()
    lines = [json.loads(line) for line in output.splitlines()]
    assert len(lines) == 2
    assert all(line["logger"] == "py.warnings" for line in lines)
    assert lines[0]["message"].startswith("UserWarning at tests/test_logging.py:")
    assert lines[1]["message"].startswith("UserWarning at pydantic/")
    assert "4111111111111111" not in output
    assert "88800" not in output


@pytest.mark.usefixtures("restore_logging")
def test_url_logging_third_parties_are_capped_at_warning() -> None:
    stream = io.StringIO()
    configure_logging("debug", "json", stream=stream)

    logging.getLogger("httpx").info("HTTP Request: GET https://x.test/?card=4111111111111111")

    assert "4111111111111111" not in stream.getvalue()
    for name in QUIET_LOGGERS:
        assert not logging.getLogger(name).isEnabledFor(logging.INFO)
