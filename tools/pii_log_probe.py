"""Send PII-bearing requests to the CardFlow API and capture what the server logs (T-014).

The application is the real one: ``create_app()`` with the real ``configure_logging()``
handler (JSON, then text format), driven in-process through Starlette's TestClient. M0
has no endpoint that accepts a body yet, so a few test-only probe routes are added to the
app *instance* (as services/api/tests/test_api_envelope.py does) to reach the 422 paths
(body, query and path validation, malformed JSON), a 201 and a 500 whose exception message
carries card data. Every request carries synthetic amounts, card numbers, a phone number,
an e-mail address, an ID number or a bearer token in its query string, body, path or
headers.

    uv run --project services/api python tools/pii_log_probe.py tools/pii_samples/clean.log

writes the captured ``cardflow.*`` lines (JSON pass, then text pass) to the given file
(stdout without an argument) and fails if a response status differs from the expected
one. tools/tests/test_pii_scan.py runs the same probe in-process and scans the capture.
Lines of the test client's own ``httpx`` logger, which do contain the raw URLs, are
client-side output and never part of the server log.
"""

import argparse
import io
import json
import logging
import re
import sys
from collections.abc import Iterator, Mapping, Sequence
from contextlib import contextmanager
from dataclasses import dataclass, field
from pathlib import Path
from typing import Final, get_args
from uuid import UUID

from fastapi import FastAPI
from fastapi.testclient import TestClient
from pydantic import BaseModel, ConfigDict, Field

from cardflow.api.app import create_app
from cardflow.log import configure_logging
from cardflow.settings import LogFormat, Settings

# Synthetic values only: public test card numbers, the GB 11643 sample ID number, an
# example.com address, the 138-0013-8000 placeholder number and a JWT whose signature is
# the text "signature-not-real-0000".
CARD_VISA: Final = "4111111111111111"
CARD_VISA_SPACED: Final = "4111 1111 1111 1111"
CARD_MASTERCARD: Final = "5555555555554444"
CARD_MASTERCARD_SPACED: Final = "5555 5555 5555 4444"
AMOUNT_YUAN: Final = "¥8,000.00"
AMOUNT_FULLWIDTH: Final = "￥1,234.56"
AMOUNT_SUFFIX: Final = "8000元"
PHONE: Final = "13800138000"
EMAIL: Final = "zhang.san@example.com"
ID_NUMBER: Final = "11010519491231002X"
SAMPLE_JWT: Final = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJwcm9iZS1kZXZpY2UifQ."
    "c2lnbmF0dXJlLW5vdC1yZWFsLTAwMDA"
)
CARD_ID: Final = "0f0e0d0c-0b0a-4908-8706-050403020100"

LOG_FORMATS: Final[tuple[LogFormat, ...]] = get_args(LogFormat)
CLIENT_LOGGERS: Final = ("httpx", "httpcore")
_UVICORN_LOGGERS: Final = ("uvicorn", "uvicorn.error", "uvicorn.access")


@dataclass(frozen=True, slots=True)
class ProbeRequest:
    """One request of the probe and the status the application must answer with."""

    purpose: str
    method: str
    url: str
    expected_status: int
    params: Mapping[str, str] = field(default_factory=dict)
    json_body: object = None
    content: str | None = None
    headers: Mapping[str, str] = field(default_factory=dict)


PROBE_REQUESTS: Final[tuple[ProbeRequest, ...]] = (
    ProbeRequest("liveness", "GET", "/healthz", 200),
    ProbeRequest(
        "PII in query string and headers of a matched route",
        "GET",
        "/healthz",
        200,
        params={"amount": AMOUNT_YUAN, "card": CARD_VISA_SPACED, "phone": PHONE},
        headers={"Authorization": f"Bearer {SAMPLE_JWT}", "X-Card-Number": CARD_VISA},
    ),
    ProbeRequest(
        "card number in an unmatched path, amount and e-mail in the query",
        "GET",
        f"/v1/cards/{CARD_VISA}/statements",
        404,
        params={"amount_minor": "800000", "email": EMAIL},
    ),
    ProbeRequest(
        "PII body on a GET-only route",
        "POST",
        "/healthz",
        405,
        json_body={"amount": AMOUNT_YUAN, "card_number": CARD_VISA_SPACED},
    ),
    ProbeRequest(
        "422: query validation (limit is an integer), PII in the query",
        "POST",
        "/v1/_probe/payments",
        422,
        params={"limit": AMOUNT_YUAN, "card": CARD_MASTERCARD, "phone": PHONE},
        json_body={"amount_minor": 800000, "card_last4": "4444"},
    ),
    ProbeRequest(
        "422: body validation, wrong types and unknown PII fields",
        "POST",
        "/v1/_probe/payments",
        422,
        json_body={
            "amount_minor": AMOUNT_FULLWIDTH,
            "card_last4": "尾号4444",
            "card_number": CARD_MASTERCARD_SPACED,
            "phone": PHONE,
            "email": EMAIL,
            "id_number": ID_NUMBER,
        },
    ),
    ProbeRequest(
        "422: malformed JSON body carrying an amount and a card number",
        "POST",
        "/v1/_probe/payments",
        422,
        content=f"amount={AMOUNT_SUFFIX}&card={CARD_VISA}",
        headers={"Content-Type": "application/json"},
    ),
    ProbeRequest(
        "201: valid body with an amount and a card tail",
        "POST",
        "/v1/_probe/payments",
        201,
        params={"limit": "50"},
        json_body={"amount_minor": 800000, "card_last4": "4444"},
    ),
    ProbeRequest(
        "422: path validation, card number where a UUID is expected",
        "GET",
        f"/v1/_probe/cards/{CARD_VISA}",
        422,
    ),
    ProbeRequest(
        "422: query validation, amount where an integer is expected",
        "GET",
        f"/v1/_probe/cards/{CARD_ID}",
        422,
        params={"balance": AMOUNT_FULLWIDTH},
    ),
    ProbeRequest("200: matched path parameter", "GET", f"/v1/_probe/cards/{CARD_ID}", 200),
    ProbeRequest(
        "500: exception message carries an amount, a card number and a phone number",
        "GET",
        "/v1/_probe/fail",
        500,
        params={"card": CARD_VISA},
    ),
)


class ProbePayment(BaseModel):
    """Body of the test-only payment probe: strict types, unknown fields rejected."""

    model_config = ConfigDict(strict=True, extra="forbid")

    amount_minor: int
    card_last4: str = Field(pattern=r"^\d{4}$")


def build_probe_app(settings: Settings) -> FastAPI:
    """``create_app(settings)`` plus test-only routes; none of them echoes its input."""
    app = create_app(settings)

    @app.post("/v1/_probe/payments", status_code=201)
    async def create_payment(payment: ProbePayment, limit: int = 50) -> dict[str, bool]:
        del payment, limit
        return {"accepted": True}

    @app.get("/v1/_probe/cards/{card_id}")
    async def get_card(card_id: UUID, balance: int | None = None) -> dict[str, bool]:
        del card_id, balance
        return {"found": True}

    @app.get("/v1/_probe/fail")
    async def fail(card: str | None = None) -> None:
        del card
        raise RuntimeError(f"charge {AMOUNT_YUAN} on {CARD_VISA_SPACED}, notify {PHONE}")

    return app


@dataclass(frozen=True, slots=True)
class LogLine:
    """One captured log line and the logger that wrote it ("" if unknown)."""

    logger: str
    text: str

    @property
    def from_cardflow(self) -> bool:
        """Written by a ``cardflow`` / ``cardflow.*`` logger."""
        return self.logger == "cardflow" or self.logger.startswith("cardflow.")

    @property
    def from_client(self) -> bool:
        """Written by the test client's HTTP stack, not by the server."""
        return any(
            self.logger == name or self.logger.startswith(f"{name}.") for name in CLIENT_LOGGERS
        )


@dataclass(frozen=True, slots=True)
class ProbeRun:
    """Everything one probe run logged, and the status of each response."""

    lines: tuple[LogLine, ...]
    statuses: tuple[int, ...]

    def cardflow_lines(self) -> list[str]:
        """Lines written by ``cardflow.*`` loggers."""
        return [line.text for line in self.lines if line.from_cardflow]

    def server_lines(self) -> list[str]:
        """Every line except the test client's own (``httpx``/``httpcore``) lines."""
        return [line.text for line in self.lines if not line.from_client]


_TEXT_HEAD: Final = re.compile(r"\S+ [A-Z]+ +(?P<logger>[^\s:]+):")


def _logger_of(text: str) -> str:
    try:
        record = json.loads(text)
    except ValueError:
        match = _TEXT_HEAD.match(text)
        return match.group("logger") if match else ""
    return str(record.get("logger", "")) if isinstance(record, dict) else ""


@contextmanager
def captured_logging(fmt: LogFormat) -> Iterator[io.StringIO]:
    """Install the real ``configure_logging()`` handler on a buffer; restore afterwards."""
    root = logging.getLogger()
    saved_root = (list(root.handlers), root.level)
    saved = {
        name: (list(logger.handlers), logger.propagate, logger.disabled)
        for name in _UVICORN_LOGGERS
        for logger in (logging.getLogger(name),)
    }
    stream = io.StringIO()
    configure_logging("info", fmt, stream=stream)
    try:
        yield stream
    finally:
        root.handlers[:] = saved_root[0]
        root.setLevel(saved_root[1])
        for name, (handlers, propagate, disabled) in saved.items():
            logger = logging.getLogger(name)
            logger.handlers[:] = handlers
            logger.propagate = propagate
            logger.disabled = disabled
        logging.captureWarnings(False)


def _send(client: TestClient, request: ProbeRequest) -> int:
    response = client.request(
        request.method,
        request.url,
        params=dict(request.params) or None,
        json=request.json_body,
        content=request.content,
        headers=dict(request.headers) or None,
    )
    return response.status_code


def run_probe(
    fmt: LogFormat, app: FastAPI, requests: Sequence[ProbeRequest] = PROBE_REQUESTS
) -> ProbeRun:
    """Send ``requests`` to ``app`` with logging configured as in production (``fmt``)."""
    with captured_logging(fmt) as stream, TestClient(app) as client:
        statuses = tuple(_send(client, request) for request in requests)
    lines = tuple(LogLine(_logger_of(text), text) for text in stream.getvalue().splitlines())
    return ProbeRun(lines, statuses)


def main(argv: Sequence[str] | None = None) -> int:
    """Run the probe in both log formats and write the ``cardflow.*`` lines."""
    parser = argparse.ArgumentParser(
        prog="pii_log_probe",
        description="Drive the CardFlow API with synthetic PII and print what it logs.",
    )
    parser.add_argument(
        "output", nargs="?", type=Path, help="file for the cardflow.* lines (default: stdout)"
    )
    args = parser.parse_args(argv)

    expected = tuple(request.expected_status for request in PROBE_REQUESTS)
    lines: list[str] = []
    for fmt in LOG_FORMATS:
        run = run_probe(fmt, build_probe_app(Settings()))
        if run.statuses != expected:
            sys.stderr.write(
                f"pii_log_probe: {fmt}: statuses {run.statuses} != expected {expected}\n"
            )
            return 1
        lines.extend(run.cardflow_lines())
    text = "".join(f"{line}\n" for line in lines)
    if args.output is None:
        sys.stdout.write(text)
    else:
        args.output.write_text(text, encoding="utf-8")
    sys.stderr.write(
        f"pii_log_probe: {len(PROBE_REQUESTS)} requests x {len(LOG_FORMATS)} formats "
        f"({', '.join(LOG_FORMATS)}), statuses as expected {expected}; "
        f"{len(lines)} cardflow.* lines\n"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
