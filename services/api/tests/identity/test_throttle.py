"""The pairing brute-force guard (no database)."""

import pytest

from cardflow.identity.throttle import FailureLimiter
from cardflow.settings import Settings


class Clock:
    def __init__(self) -> None:
        self.now = 100.0

    def __call__(self) -> float:
        return self.now


def test_lockout_after_the_limit_and_release_after_the_lockout() -> None:
    clock = Clock()
    guard = FailureLimiter(limit=3, window_s=60, lockout_s=300, clock=clock)

    assert [guard.record_failure("a") for _ in range(3)] == [False, False, True]
    assert guard.retry_after("a") == 300
    assert guard.retry_after("b") is None  # per key
    clock.now += 299.5
    assert guard.retry_after("a") == pytest.approx(0.5)
    clock.now += 1
    assert guard.retry_after("a") is None
    assert guard.record_failure("a") is False  # a fresh window after the lockout


def test_failures_outside_the_window_do_not_add_up() -> None:
    clock = Clock()
    guard = FailureLimiter(limit=3, window_s=60, lockout_s=300, clock=clock)
    guard.record_failure("a")
    guard.record_failure("a")
    clock.now += 61
    assert guard.record_failure("a") is False
    assert guard.retry_after("a") is None


def test_reset_clears_a_key() -> None:
    guard = FailureLimiter(limit=2, window_s=60, lockout_s=300, clock=Clock())
    guard.record_failure("a")
    guard.reset("a")
    assert guard.record_failure("a") is False


def test_memory_stays_bounded() -> None:
    clock = Clock()
    guard = FailureLimiter(limit=5, window_s=60, lockout_s=300, clock=clock, max_keys=100)
    for index in range(1000):
        guard.record_failure(f"client-{index}")
    assert len(guard._counters) <= 100


def test_invalid_limits_are_refused() -> None:
    with pytest.raises(ValueError, match="positive"):
        FailureLimiter(limit=0, window_s=60, lockout_s=60)


def test_defaults_from_settings(clean_settings_env: pytest.MonkeyPatch) -> None:
    del clean_settings_env
    guard = FailureLimiter.from_settings(Settings())
    assert (guard.limit, guard.window_s, guard.lockout_s) == (10, 600, 900)
