"""Brute-force guard for pairing codes (API-01): failure counting and temporary lockout.

Pairing codes carry 60 bits and live minutes, so guessing one is already infeasible; this
guard is defence in depth and keeps scanners from hammering the public endpoint. When a
client key (the client address uvicorn reports) has failed :attr:`limit` times within
:attr:`window_s` seconds it is locked out for :attr:`lockout_s` seconds, during which every
attempt is refused before the database is asked (HTTP 429, ``Retry-After``). A successful
registration clears the key.

The state lives in the API process (no shared store exists before T-010's rate limiter):
several API processes each count separately, and a restart forgets. Behind a proxy whose
address uvicorn does not translate (``--forwarded-allow-ips``), every client shares one key,
so the lockout then applies to everybody -- acceptable for a self-hosted server where
registration is rare, and the safer failure mode. Memory is bounded by :attr:`max_keys`.
"""

import threading
import time
from collections.abc import Callable
from dataclasses import dataclass
from typing import TYPE_CHECKING, Final

if TYPE_CHECKING:
    from cardflow.settings import Settings

DEFAULT_MAX_KEYS: Final = 10_000


@dataclass(slots=True)
class _Counter:
    window_started: float
    failures: int = 0
    locked_until: float = 0.0


class FailureLimiter:
    """Thread-safe failure counter with a fixed window and a lockout per key."""

    def __init__(
        self,
        *,
        limit: int,
        window_s: float,
        lockout_s: float,
        clock: Callable[[], float] = time.monotonic,
        max_keys: int = DEFAULT_MAX_KEYS,
    ) -> None:
        """``limit`` failures within ``window_s`` seconds lock a key for ``lockout_s``."""
        if limit < 1 or window_s <= 0 or lockout_s <= 0 or max_keys < 1:
            raise ValueError("limit, window, lockout and max_keys must be positive")
        self.limit = limit
        self.window_s = window_s
        self.lockout_s = lockout_s
        self.max_keys = max_keys
        self._clock = clock
        self._lock = threading.Lock()
        self._counters: dict[str, _Counter] = {}

    @classmethod
    def from_settings(cls, settings: "Settings") -> "FailureLimiter":
        """Limits from ``PAIRING_FAILURE_LIMIT`` / ``_WINDOW_S`` and ``PAIRING_LOCKOUT_S``."""
        return cls(
            limit=settings.pairing_failure_limit,
            window_s=settings.pairing_failure_window_s,
            lockout_s=settings.pairing_lockout_s,
        )

    def retry_after(self, key: str) -> float | None:
        """Seconds until ``key`` may try again, or ``None`` if it is not locked out."""
        now = self._clock()
        with self._lock:
            counter = self._counters.get(key)
            if counter is None or counter.locked_until <= now:
                return None
            return counter.locked_until - now

    def record_failure(self, key: str) -> bool:
        """Count a failed attempt of ``key``; True if ``key`` is now locked out."""
        now = self._clock()
        with self._lock:
            counter = self._counters.get(key)
            if counter is None:
                if len(self._counters) >= self.max_keys:
                    self._evict(now)
                counter = self._counters[key] = _Counter(window_started=now)
            elif now - counter.window_started >= self.window_s:
                counter.window_started, counter.failures = now, 0
            counter.failures += 1
            if counter.failures < self.limit:
                return False
            counter.locked_until = now + self.lockout_s
            counter.window_started, counter.failures = now, 0
            return True

    def reset(self, key: str) -> None:
        """Forget ``key`` (after a successful attempt)."""
        with self._lock:
            self._counters.pop(key, None)

    def _evict(self, now: float) -> None:
        """Drop idle keys; if none is idle, drop the oldest windows (bounded memory)."""
        idle = [
            key
            for key, counter in self._counters.items()
            if counter.locked_until <= now and now - counter.window_started >= self.window_s
        ]
        for key in idle:
            del self._counters[key]
        if len(self._counters) >= self.max_keys:
            oldest = sorted(self._counters, key=lambda key: self._counters[key].window_started)
            for key in oldest[: len(self._counters) - self.max_keys + 1]:
                del self._counters[key]
