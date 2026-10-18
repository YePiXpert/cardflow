"""What a running job sees: :class:`JobContext` (identity, payload, deadline, transactions)."""

import threading
import time
import uuid
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass, field
from typing import Final

from sqlalchemy import text
from sqlalchemy.orm import Session, sessionmaker

from cardflow.db.tx import workspace_tx
from cardflow.jobs.codec import JsonValue
from cardflow.jobs.errors import JobTimeout, LeaseBusy, LeaseLost
from cardflow.jobs.queue import LeaseState, LockMode, lock_lease

_SET_STATEMENT_TIMEOUT: Final = text("SELECT set_config('statement_timeout', :value, true)")
MIN_STATEMENT_TIMEOUT_MS: Final = 1


@contextmanager
def plain_tx(session_factory: sessionmaker[Session]) -> Iterator[Session]:
    """One transaction without a workspace binding (system jobs); same semantics as
    :func:`cardflow.db.tx.workspace_tx`: commit on success, roll back on error."""
    with session_factory() as session, session.begin():
        yield session


@contextmanager
def fenced_tx(
    session_factory: sessionmaker[Session],
    *,
    job_id: uuid.UUID,
    worker_id: str,
    attempt: int,
    workspace_id: uuid.UUID | None,
    lock: LockMode,
    statement_timeout_ms: int,
) -> Iterator[Session]:
    """A transaction bound to the job's workspace that first re-checks the job's lease.

    ``workspace_id`` set: the transaction is opened with ``workspace_tx`` (row-level
    security, T-006). ``statement_timeout`` is set for the transaction. Raises
    :class:`LeaseLost` -- and rolls back -- when ``(worker_id, attempt)`` no longer holds
    the job, or :class:`LeaseBusy` (``update_skip`` only) when another transaction holds
    the row.
    """
    opener = (
        workspace_tx(session_factory, workspace_id)
        if workspace_id is not None
        else plain_tx(session_factory)
    )
    with opener as session:
        session.execute(
            _SET_STATEMENT_TIMEOUT,
            {"value": str(max(MIN_STATEMENT_TIMEOUT_MS, statement_timeout_ms))},
        )
        state = lock_lease(session, job_id=job_id, worker_id=worker_id, attempt=attempt, mode=lock)
        if state is LeaseState.BUSY:
            raise LeaseBusy
        if state is not LeaseState.HELD:
            raise LeaseLost
        yield session


@dataclass(frozen=True, slots=True, kw_only=True)
class JobContext:
    """Handed to inline handlers and to the ``prepare``/``persist`` hooks.

    Timeout semantics for inline handlers (a thread cannot be killed): when ``deadline``
    passes, the worker records the attempt as ``TIMEOUT`` and :attr:`cancelled` becomes
    true; from then on :meth:`transaction` raises :class:`LeaseLost` (or
    :class:`JobTimeout`), statements inside a transaction are cut off by
    ``statement_timeout`` at the deadline, and whatever the handler returns is discarded.
    Long loops should call :meth:`check` regularly; CPU-heavy work belongs in a subprocess
    handler.
    """

    job_id: uuid.UUID
    kind: str
    payload: JsonValue
    attempt: int
    """1 for the first run; ``jobs.attempts`` after this attempt's claim."""
    max_attempts: int
    workspace_id: uuid.UUID | None
    timeout_s: int
    worker_id: str
    session_factory: sessionmaker[Session] = field(repr=False)
    deadline: float = field(repr=False)
    """``time.monotonic()`` value at which the attempt times out."""
    cancel_event: threading.Event = field(repr=False)

    @property
    def cancelled(self) -> bool:
        """True once the attempt has timed out, lost its lease or is being shut down."""
        return self.cancel_event.is_set()

    def remaining_s(self) -> float:
        """Seconds until the deadline (negative once passed)."""
        return self.deadline - time.monotonic()

    def check(self) -> None:
        """Raise :class:`JobTimeout` past the deadline, :class:`LeaseLost` if cancelled."""
        if self.remaining_s() <= 0:
            raise JobTimeout
        if self.cancelled:
            raise LeaseLost

    @contextmanager
    def transaction(self) -> Iterator[Session]:
        """Workspace-bound, lease-fenced transaction for the handler's database work.

        Uses ``workspace_tx`` when the job has a ``workspace_id`` (required by row-level
        security), sets ``statement_timeout`` to the time left, and holds ``FOR KEY SHARE``
        on the job row: while it is open nobody can take the job from this attempt, and it
        raises :class:`LeaseLost` if that already happened. Commits on success.
        """
        self.check()
        remaining_ms = int(self.remaining_s() * 1000)
        with fenced_tx(
            self.session_factory,
            job_id=self.job_id,
            worker_id=self.worker_id,
            attempt=self.attempt,
            workspace_id=self.workspace_id,
            lock="share",
            statement_timeout_ms=remaining_ms,
        ) as session:
            yield session
