"""Entry point of a job subprocess (``multiprocessing`` ``spawn`` context).

The child receives one input message, imports the handler by ``module`` + ``qualname``,
calls it and sends one reply. Replies are plain bytes -- never pickles -- so a child that
processed hostile input (a crafted PDF) cannot make the worker unpickle arbitrary objects:

* ``b"O" + JSON`` -- the handler's output;
* ``b"E" + error text`` -- ``HANDLER_ERROR:<type>`` or ``RESULT_INVALID``;
* ``b"J" + JSON {"code", "permanent"}`` -- the handler raised :class:`JobError`.

The child ignores SIGINT (Ctrl+C in a terminal reaches the whole process group; the worker
decides what happens to its jobs) but keeps the default SIGTERM action, which the worker
uses -- followed by SIGKILL -- to enforce the timeout. A watchdog thread exits the child if
the worker process disappears, so an orphan never keeps computing. Logging uses the same
whitelisting JSON formatter as the worker; exception messages are never written.
"""

import json
import logging
import os
import signal
import threading
import time
from multiprocessing.connection import Connection
from typing import Final

from cardflow.jobs.codec import (
    MAX_TRANSPORT_BYTES,
    JsonRejected,
    decode_transport,
    encode_transport,
)
from cardflow.jobs.errors import JobError, JobErrorCode, handler_error
from cardflow.jobs.registry import resolve_target
from cardflow.log import configure_logging

REPLY_OK: Final = b"O"
REPLY_ERROR: Final = b"E"
REPLY_JOB_ERROR: Final = b"J"
EXIT_ORPHANED: Final = 70
PARENT_CHECK_INTERVAL_S: Final = 1.0

log = logging.getLogger("cardflow.jobs.child")


def _watch_parent(parent_pid: int) -> None:
    def watch() -> None:
        while True:
            if os.getppid() != parent_pid:
                os._exit(EXIT_ORPHANED)
            time.sleep(PARENT_CHECK_INTERVAL_S)

    threading.Thread(target=watch, name="cardflow-parent-watch", daemon=True).start()


def _run(input_conn: Connection, module: str, qualname: str) -> bytes:
    try:
        value = decode_transport(input_conn.recv_bytes(MAX_TRANSPORT_BYTES), exact=False)
        handler = resolve_target(module, qualname)
        if not callable(handler):
            raise TypeError("job handler target is not callable")
        output = handler(value)
    except JobError as exc:
        body = json.dumps({"code": exc.code, "permanent": exc.permanent})
        return REPLY_JOB_ERROR + body.encode("ascii")
    except Exception as exc:
        log.warning("job subprocess handler raised", exc_info=True)  # type + frames only
        return REPLY_ERROR + handler_error(exc).encode("ascii")
    try:
        return REPLY_OK + encode_transport(output)
    except JsonRejected:
        return REPLY_ERROR + JobErrorCode.RESULT_INVALID.encode("ascii")


def child_main(
    input_conn: Connection,
    output_conn: Connection,
    module: str,
    qualname: str,
    parent_pid: int,
    log_level: str,
    log_format: str,
) -> None:
    """Run one job handler in this (spawned) process and send its reply to the worker."""
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    _watch_parent(parent_pid)
    configure_logging(log_level, log_format)  # type: ignore[arg-type]
    try:
        reply = _run(input_conn, module, qualname)
    finally:
        input_conn.close()
    try:
        output_conn.send_bytes(reply)
    except OSError:  # the worker is gone or killed us meanwhile
        pass
    finally:
        output_conn.close()
