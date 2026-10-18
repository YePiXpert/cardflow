"""Worker side of a subprocess job: spawn, feed input, enforce the hard timeout, read reply.

Each attempt gets a fresh ``spawn`` child (no fork of the multi-threaded worker, no state
shared with it). The input goes through one pipe (written by a helper thread, so a child
that never reads cannot block the supervisor), the reply comes back through another. At the
deadline -- or when the attempt is cancelled (lease lost, forced shutdown) -- the child gets
SIGTERM and, if still alive after ``terminate_grace_s``, SIGKILL. The worker process itself
is never affected by what happens in the child.
"""

import json
import logging
import multiprocessing
import os
import threading
import time
from dataclasses import dataclass
from enum import Enum
from multiprocessing.connection import Connection, wait
from multiprocessing.process import BaseProcess
from typing import Final

from cardflow.jobs.child import REPLY_ERROR, REPLY_JOB_ERROR, REPLY_OK, child_main
from cardflow.jobs.codec import MAX_TRANSPORT_BYTES, JsonRejected, decode_transport
from cardflow.jobs.errors import JobErrorCode, check_error_code, parse_error_text

log = logging.getLogger("cardflow.jobs.subprocess")

_SPAWN: Final = multiprocessing.get_context("spawn")
WAIT_TICK_S: Final = 0.1


class ChildStatus(Enum):
    """How a child attempt ended."""

    OK = "ok"
    ERROR = "error"
    TIMEOUT = "timeout"
    CANCELLED = "cancelled"
    CRASHED = "crashed"


@dataclass(frozen=True, slots=True)
class ChildOutcome:
    """Result of :func:`run_child`."""

    status: ChildStatus
    output: object = None
    """Decoded output (``OK``); non-integer numbers are :class:`~decimal.Decimal`."""
    error: str | None = None
    """Safe error text (``ERROR``): ``HANDLER_ERROR:<type>``, ``RESULT_INVALID`` or a code."""
    permanent: bool = False
    """``ERROR`` raised as ``JobError(permanent=True)``."""
    pid: int | None = None
    exitcode: int | None = None
    stopped_with: str | None = None
    """``SIGTERM`` or ``SIGKILL`` when the worker had to stop the child."""


def _send(conn: Connection, data: bytes) -> None:
    try:
        conn.send_bytes(data)
    except OSError:  # the child died or was killed before reading everything
        pass
    finally:
        conn.close()


def _stop(process: BaseProcess, grace_s: float) -> str | None:
    """SIGTERM, wait ``grace_s``, then SIGKILL; returns the last signal sent (or None)."""
    if process.exitcode is not None:
        return None
    process.terminate()
    process.join(grace_s)
    if process.exitcode is not None:
        return "SIGTERM"
    process.kill()
    process.join()
    return "SIGKILL"


def _parse(message: bytes) -> ChildOutcome:
    tag, body = message[:1], message[1:]
    if tag == REPLY_OK:
        try:
            return ChildOutcome(ChildStatus.OK, output=decode_transport(body, exact=True))
        except JsonRejected:
            return ChildOutcome(ChildStatus.ERROR, error=JobErrorCode.RESULT_INVALID.value)
    if tag == REPLY_ERROR:
        text = parse_error_text(body.decode("ascii", errors="replace"))
        return ChildOutcome(ChildStatus.ERROR, error=text or JobErrorCode.HANDLER_ERROR.value)
    if tag == REPLY_JOB_ERROR:
        try:
            data = json.loads(body)
            code = check_error_code(data["code"])
            permanent = data["permanent"] is True
        except (ValueError, KeyError, TypeError):
            return ChildOutcome(ChildStatus.ERROR, error=JobErrorCode.HANDLER_ERROR.value)
        return ChildOutcome(ChildStatus.ERROR, error=code, permanent=permanent)
    return ChildOutcome(ChildStatus.ERROR, error=JobErrorCode.RESULT_INVALID.value)


def _supervise(
    process: BaseProcess,
    reader: Connection,
    *,
    deadline: float,
    cancel: threading.Event,
    grace_s: float,
) -> ChildOutcome:
    pid = process.pid
    while True:
        if cancel.is_set():
            stopped = _stop(process, grace_s)
            return ChildOutcome(
                ChildStatus.CANCELLED, pid=pid, exitcode=process.exitcode, stopped_with=stopped
            )
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            stopped = _stop(process, grace_s)
            return ChildOutcome(
                ChildStatus.TIMEOUT, pid=pid, exitcode=process.exitcode, stopped_with=stopped
            )
        ready = wait([reader, process.sentinel], timeout=min(remaining, WAIT_TICK_S))
        if reader in ready:
            try:
                message = reader.recv_bytes(MAX_TRANSPORT_BYTES + 1)  # + 1 tag byte
            except EOFError:  # the child closed its end without replying
                process.join(grace_s)
                stopped = _stop(process, grace_s)
                return ChildOutcome(
                    ChildStatus.CRASHED, pid=pid, exitcode=process.exitcode, stopped_with=stopped
                )
            except OSError:  # reply longer than the limit
                stopped = _stop(process, grace_s)
                return ChildOutcome(
                    ChildStatus.ERROR,
                    error=JobErrorCode.RESULT_INVALID.value,
                    pid=pid,
                    exitcode=process.exitcode,
                    stopped_with=stopped,
                )
            process.join(grace_s)
            stopped = _stop(process, grace_s)
            parsed = _parse(message)
            return ChildOutcome(
                parsed.status,
                output=parsed.output,
                error=parsed.error,
                permanent=parsed.permanent,
                pid=pid,
                exitcode=process.exitcode,
                stopped_with=stopped,
            )
        if process.sentinel in ready and not reader.poll(0):
            return ChildOutcome(ChildStatus.CRASHED, pid=pid, exitcode=process.exitcode)


def run_child(
    *,
    module: str,
    qualname: str,
    data: bytes,
    timeout_s: float,
    cancel: threading.Event,
    terminate_grace_s: float,
    log_level: str,
    log_format: str,
    name: str,
) -> ChildOutcome:
    """Run ``module:qualname`` on the JSON ``data`` in a new spawn child; never raises for
    anything the child does (crash, hang, garbage reply)."""
    input_reader, input_writer = _SPAWN.Pipe(duplex=False)
    output_reader, output_writer = _SPAWN.Pipe(duplex=False)
    process = _SPAWN.Process(
        target=child_main,
        args=(input_reader, output_writer, module, qualname, os.getpid(), log_level, log_format),
        name=name,
        daemon=True,
    )
    try:
        process.start()
    except BaseException:
        for conn in (input_reader, input_writer, output_reader, output_writer):
            conn.close()
        raise
    # The child holds its own copies now; closing ours lets EOF reach the other side.
    input_reader.close()
    output_writer.close()
    deadline = time.monotonic() + timeout_s
    writer = threading.Thread(
        target=_send, args=(input_writer, data), name=f"{name}-input", daemon=True
    )
    writer.start()
    try:
        return _supervise(
            process, output_reader, deadline=deadline, cancel=cancel, grace_s=terminate_grace_s
        )
    finally:
        output_reader.close()
        _stop(process, terminate_grace_s)
        writer.join(terminate_grace_s)
        process.close()
