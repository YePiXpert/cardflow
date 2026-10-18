"""Unit tests without a database: payload/result JSON rules, backoff, error texts, registry,
signal handling."""

import faulthandler
import math
import os
import signal
import time
import uuid
from datetime import UTC, datetime
from decimal import Decimal

import jobs_testkit
import pytest
from hypothesis import given, settings
from hypothesis import strategies as st
from jobs_helpers import make_config
from sqlalchemy.orm import sessionmaker

from cardflow.jobs import JobError, Mode, Registry, production_registry
from cardflow.jobs.backoff import ORDER_MARGIN, Backoff
from cardflow.jobs.codec import (
    MAX_DEPTH,
    MAX_PAYLOAD_BYTES,
    JsonRejected,
    check_stored_json,
    decode_transport,
    encode_stored,
    encode_transport,
)
from cardflow.jobs.errors import (
    JobErrorCode,
    error_text,
    handler_error,
    parse_error_text,
)
from cardflow.jobs.registry import HANDLER_MODULES, REGISTRY, check_kind
from cardflow.jobs.worker import Worker

# --------------------------------------------------------------------------- stored JSON


def test_payload_accepts_integers_strings_booleans_null_lists_objects() -> None:
    value = {
        "plan_id": str(uuid.uuid4()),
        "amount_minor": 123456,
        "flags": [True, False, None],
        "nested": {"tuple": (1, 2), "text": "卡序"},
        "big": 2**70,
    }

    text = encode_stored(value, what="payload", max_bytes=MAX_PAYLOAD_BYTES)

    assert '"amount_minor":123456' in text
    assert '"tuple":[1,2]' in text


@pytest.mark.parametrize(
    ("value", "path"),
    [
        (12.5, "$"),
        ({"amount": 1.0}, "$.amount"),
        ({"items": [{"amount_minor": 1}, {"amount_minor": 99.99}]}, "$.items[1].amount_minor"),
        ([1, 2, float("nan")], "$[2]"),
        ({"x": float("inf")}, "$.x"),
        ({"rate": Decimal("0.0005")}, "$.rate"),
        ({"金额": 3.5}, "$.<key>"),
    ],
)
def test_payload_rejects_non_integer_numbers_and_names_the_path_only(
    value: object, path: str
) -> None:
    with pytest.raises(JsonRejected) as excinfo:
        check_stored_json(value, what="payload")

    message = str(excinfo.value)
    assert f"at {path};" in message
    assert "integer minor units" in message
    for digits in ("12.5", "99.99", "0.0005", "3.5"):
        assert digits not in message


@pytest.mark.parametrize(
    "value",
    [
        {1: "int key"},
        {"a": {1, 2}},
        {"a": b"bytes"},
        {"a": datetime.now(UTC)},
        {"a": uuid.uuid4()},
        {"a": object()},
        {"a": "nul\x00char"},
        {"nul\x00key": 1},
    ],
)
def test_payload_rejects_values_json_or_jsonb_cannot_hold(value: object) -> None:
    with pytest.raises(JsonRejected):
        encode_stored(value, what="payload", max_bytes=MAX_PAYLOAD_BYTES)


def test_payload_size_and_depth_are_bounded() -> None:
    with pytest.raises(JsonRejected, match="exceeds the limit"):
        encode_stored({"s": "x" * MAX_PAYLOAD_BYTES}, what="payload", max_bytes=MAX_PAYLOAD_BYTES)
    deep: object = 1
    for _ in range(MAX_DEPTH + 1):
        deep = [deep]
    with pytest.raises(JsonRejected, match="nested deeper"):
        check_stored_json(deep, what="payload")


def test_lone_surrogate_is_rejected_not_crashing() -> None:
    with pytest.raises(JsonRejected, match="UTF-8"):
        encode_stored({"s": "\ud800"}, what="result", max_bytes=1024)


def test_transport_keeps_fractions_exact_and_rejects_nan() -> None:
    data = encode_transport({"ratio": 0.1, "n": 3, "time_limit_s": 10.0})

    decoded = decode_transport(data, exact=True)
    assert decoded == {"ratio": Decimal("0.1"), "n": 3, "time_limit_s": Decimal("10.0")}
    assert decode_transport(data, exact=False) == {"ratio": 0.1, "n": 3, "time_limit_s": 10.0}
    with pytest.raises(JsonRejected):
        encode_transport({"x": math.nan})
    with pytest.raises(JsonRejected):
        encode_transport({"x": Decimal("1.5")})
    with pytest.raises(JsonRejected):
        decode_transport(b'{"x": NaN}', exact=True)
    with pytest.raises(JsonRejected):
        decode_transport(b"\xff", exact=True)


# --------------------------------------------------------------------------- backoff


def test_default_backoff_bands() -> None:
    backoff = Backoff()

    lows = [backoff.delay_s(n, draw=0.0) for n in range(1, 6)]
    highs = [backoff.delay_s(n, draw=0.999999) for n in range(1, 6)]

    assert lows == [10.0, 20.0, 40.0, 80.0, 160.0]
    assert all(high < 1.5 * low + 1e-6 for low, high in zip(lows, highs, strict=True))
    assert backoff.delay_s(10_000) == backoff.cap_s == 3600.0


@settings(max_examples=500)
@given(
    failures=st.integers(min_value=1, max_value=200),
    draw_now=st.floats(min_value=0, max_value=1, exclude_max=True),
    draw_next=st.floats(min_value=0, max_value=1, exclude_max=True),
    base=st.floats(min_value=0.01, max_value=100),
    jitter=st.floats(min_value=0, max_value=0.9),
    extra_factor=st.floats(min_value=0, max_value=3),
    constant=st.booleans(),
)
def test_backoff_never_decreases_and_never_exceeds_the_cap(
    failures: int,
    draw_now: float,
    draw_next: float,
    base: float,
    jitter: float,
    extra_factor: float,
    constant: bool,
) -> None:
    if constant:
        backoff = Backoff(base_s=base, factor=1, cap_s=base * 50, jitter=0)
    else:  # the smallest valid factor, plus anything
        factor = (1 + jitter) * (1 + 2 * ORDER_MARGIN) + extra_factor
        backoff = Backoff(base_s=base, factor=factor, cap_s=base * 50, jitter=jitter)

    now = backoff.delay_s(failures, draw=draw_now)
    following = backoff.delay_s(failures + 1, draw=draw_next)

    assert base <= now <= following <= backoff.cap_s


def test_backoff_slow_growth_does_not_plateau_below_the_cap() -> None:
    """Regression (found by hypothesis): an exponent clamp at 64 made delay(66) < delay(65)
    for slowly growing policies (1.07**64 is still far below this cap)."""
    backoff = Backoff(base_s=1.0, factor=1.07, cap_s=1000.0, jitter=0.0625)

    delays = [backoff.delay_s(n, draw=0.999 if n % 2 else 0.0) for n in range(1, 400)]

    assert delays == sorted(delays)
    assert delays[-1] == 1000.0
    assert backoff.delay_s(10**9) == 1000.0


def test_backoff_boundary_policies_are_rejected() -> None:
    """Regression (found by hypothesis): with factor == 1 + jitter (jitter = 2.2e-16), a draw
    of 0.75 rounded onto the next band and delay(33) exceeded delay(34) by one ulp."""
    tiny = 2.220446049250313e-16
    with pytest.raises(ValueError, match="must exceed"):
        Backoff(base_s=12.375, factor=1 + tiny, cap_s=618.75, jitter=tiny)
    with pytest.raises(ValueError, match="must exceed"):
        Backoff(base_s=1, factor=1.5, cap_s=100, jitter=0.5)
    constant = Backoff(base_s=3, factor=1, cap_s=100, jitter=0)
    assert [constant.delay_s(n) for n in (1, 2, 50)] == [3, 3, 3]


def test_backoff_random_draws_stay_in_band() -> None:
    backoff = Backoff(base_s=1.0, factor=2.0, cap_s=100.0, jitter=0.5)

    delays = [backoff.delay_s(3) for _ in range(200)]

    assert all(4.0 <= delay < 6.0 for delay in delays)
    assert len(set(delays)) > 1  # jittered


@pytest.mark.parametrize(
    "kwargs",
    [
        {"base_s": 0},
        {"jitter": 1.0},
        {"jitter": -0.1},
        {"factor": 1.2, "jitter": 0.5},  # bands could overlap -> delays could decrease
        {"factor": 1 + 1e-12, "jitter": 0},  # growth below float-rounding safety
        {"cap_s": 1.0, "base_s": 2.0},
        {"base_s": math.inf},
    ],
)
def test_backoff_rejects_policies_that_could_decrease_or_overflow(kwargs: dict[str, float]) -> None:
    with pytest.raises(ValueError, match="backoff"):
        Backoff(**kwargs)


def test_backoff_huge_factor_saturates_at_cap() -> None:
    assert Backoff(base_s=1, factor=1e300, cap_s=60, jitter=0).delay_s(5) == 60


# --------------------------------------------------------------------------- error texts


def test_error_text_keeps_codes_and_type_names_only() -> None:
    assert error_text("TIMEOUT") == "TIMEOUT"
    assert handler_error(ValueError(jobs_testkit.PII_MESSAGE)) == "HANDLER_ERROR:ValueError"
    assert (
        error_text("HANDLER_ERROR", "pkg.Err12345Foo bar@x.com")
        == "HANDLER_ERROR:pkg.Err#Foo_bar_x.com"
    )


@pytest.mark.parametrize("code", ["timeout", "T", "E12345", "HAS SPACE", "", "X" * 65])
def test_job_error_rejects_codes_outside_the_pattern(code: str) -> None:
    with pytest.raises(ValueError, match="error code"):
        JobError(code)


def test_parse_error_text_accepts_only_canonical_texts() -> None:
    assert parse_error_text("HANDLER_ERROR:ValueError") == "HANDLER_ERROR:ValueError"
    assert parse_error_text("RESULT_INVALID") == "RESULT_INVALID"
    assert parse_error_text("HANDLER_ERROR:card 4111111111111111") is None
    assert parse_error_text("lowercase") is None


def test_queue_error_codes() -> None:
    assert {code.value for code in JobErrorCode} == {
        "TIMEOUT",
        "HANDLER_ERROR",
        "CRASHED",
        "INPUT_INVALID",
        "RESULT_INVALID",
        "LEASE_EXPIRED",
        "INTERRUPTED",
    }


# --------------------------------------------------------------------------- registry


@pytest.mark.parametrize("kind", ["plan.solve", "imports.parse", "noop", "a.b_c.d9"])
def test_valid_kinds(kind: str) -> None:
    assert check_kind(kind) == kind


@pytest.mark.parametrize("kind", ["", "Plan.solve", "plan..solve", "plan.", "1plan", "a b", 3])
def test_invalid_kinds(kind: object) -> None:
    with pytest.raises(ValueError, match="job kind"):
        check_kind(kind)


def test_registry_rejects_duplicates_bad_limits_and_unimportable_subprocess_handlers() -> None:
    registry = Registry()
    registry.register("t.one", mode="inline", timeout_s=5, max_attempts=1)(jobs_testkit.noop)

    with pytest.raises(ValueError, match="already registered"):
        registry.register("t.one", mode="inline", timeout_s=5, max_attempts=1)(jobs_testkit.noop)
    with pytest.raises(ValueError, match="timeout_s"):
        registry.register("t.two", mode="inline", timeout_s=0, max_attempts=1)
    with pytest.raises(ValueError, match="max_attempts"):
        registry.register("t.two", mode="inline", timeout_s=5, max_attempts=0)
    with pytest.raises(ValueError, match="concurrency"):
        registry.register("t.two", mode="inline", timeout_s=5, max_attempts=1, concurrency=0)
    with pytest.raises(ValueError, match="'bogus' is not a valid Mode"):
        registry.register("t.two", mode="bogus", timeout_s=5, max_attempts=1)
    with pytest.raises(ValueError, match="prepare"):
        registry.register(
            "t.two",
            mode=Mode.INLINE,
            timeout_s=5,
            max_attempts=1,
            prepare=jobs_testkit.prepare_values,
        )
    with pytest.raises(ValueError, match="module-level"):
        registry.register("t.two", mode="subprocess", timeout_s=5, max_attempts=1)(
            lambda data: data
        )

    def nested(data: object) -> object:
        return data

    with pytest.raises(ValueError, match="module-level"):
        registry.register("t.two", mode="subprocess", timeout_s=5, max_attempts=1)(nested)
    assert registry.kinds() == ("t.one",)


def test_registered_handler_is_returned_unchanged() -> None:
    registry = Registry()

    returned = registry.register("t.sum", mode="subprocess", timeout_s=5, max_attempts=2)(
        jobs_testkit.child_sum
    )

    assert returned is jobs_testkit.child_sum
    assert registry["t.sum"].target == ("jobs_testkit", "child_sum")


def test_production_registry_holds_no_test_or_demo_kinds() -> None:
    """Test kinds are only registered on test registries (T-008 brief)."""
    production = production_registry()

    assert production is REGISTRY
    assert HANDLER_MODULES == ()
    assert production.kinds() == ()
    assert not any(kind.startswith(("test.", "demo.")) for kind in production.kinds())
    assert len(jobs_testkit.build_registry()) > 20
    assert production.kinds() == ()


# --------------------------------------------------------------------------- signals


def test_signal_handler_takes_no_lock() -> None:
    """Regression: the handler used to call ``Event.set()``. Event wraps a non-reentrant
    Lock, so a SIGTERM arriving while the main thread was inside ``Event.clear()/wait()``
    deadlocked the worker. Now the handler only records the signal; the main thread acts
    on it. If the handler took one of these locks again, this test would deadlock --
    faulthandler then kills the run after 20 s instead of letting it hang."""
    worker = Worker(sessionmaker(), jobs_testkit.build_registry(), make_config())
    events = (worker._wake, worker._stop, worker._force)
    restore = worker.install_signal_handlers()
    faulthandler.dump_traceback_later(20, exit=True)
    try:
        for event in events:
            event._cond.acquire()
        try:
            os.kill(os.getpid(), signal.SIGTERM)
            time.sleep(0.05)  # the handler runs on this thread while the locks are held
        finally:
            for event in events:
                event._cond.release()
        assert not worker._stop.is_set()
        assert list(worker._pending_signals) == [signal.SIGTERM]

        worker._poll_signals()

        assert worker._stop.is_set()
        assert not worker._force.is_set()
        os.kill(os.getpid(), signal.SIGINT)
        time.sleep(0.05)
        worker._poll_signals()
        assert worker._force.is_set()  # a second signal escalates
    finally:
        faulthandler.cancel_dump_traceback_later()
        restore()
