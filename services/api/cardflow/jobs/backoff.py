"""Retry delays: exponential backoff with bounded jitter and a cap (architecture §4).

``delay(n) = min(cap, base * factor**(n-1) * (1 + jitter * r))`` with ``r`` uniform in
``[0, 1)`` and ``n`` the number of failed attempts so far. Because ``factor > 1 + jitter`` is
enforced, the jittered band of failure ``n`` lies entirely below the band of ``n + 1``:

    delay(n) < base * factor**(n-1) * (1 + jitter) < base * factor**n <= delay(n + 1)

so delays never decrease from one failure to the next, whatever the random draws, and
they never exceed ``cap``. The inequality must survive floating-point rounding, so
``factor`` has to exceed ``1 + jitter`` by a relative :data:`ORDER_MARGIN` (a policy with
``factor == 1 + jitter`` could, for a draw just below 1, round onto the next band); the
only exception is the constant policy ``factor == 1, jitter == 0``. The jitter spreads
retries of jobs that failed together (for example during a database restart) so they do
not hit the database at the same moment.
"""

import math
import secrets
from dataclasses import dataclass
from typing import Final

_RANDOM: Final = secrets.SystemRandom()
ORDER_MARGIN: Final = 1e-9
"""Relative gap required between ``1 + jitter`` and ``factor`` (far above float rounding)."""


@dataclass(frozen=True, slots=True)
class Backoff:
    """Backoff policy; the defaults give 10-15 s, 20-30 s, 40-60 s, 80-120 s, ... <= 1 h."""

    base_s: float = 10.0
    factor: float = 2.0
    cap_s: float = 3600.0
    jitter: float = 0.5

    def __post_init__(self) -> None:
        """Reject policies whose delays could decrease or are not finite and positive."""
        for name in ("base_s", "factor", "cap_s", "jitter"):
            if not math.isfinite(getattr(self, name)):
                raise ValueError(f"backoff {name} must be finite")
        if self.base_s <= 0:
            raise ValueError("backoff base_s must be positive")
        if not 0 <= self.jitter < 1:
            raise ValueError("backoff jitter must be in [0, 1)")
        constant = self.factor == 1 and self.jitter == 0
        if not constant and self.factor < (1 + self.jitter) * (1 + ORDER_MARGIN):
            raise ValueError(
                "backoff factor must exceed 1 + jitter (or be 1 with jitter 0), "
                "or delays could decrease"
            )
        if self.cap_s < self.base_s:
            raise ValueError("backoff cap_s must be >= base_s")

    def delay_s(self, failures: int, *, draw: float | None = None) -> float:
        """Seconds to wait after ``failures`` failed attempts (``failures >= 1``).

        ``draw`` replaces the random number in ``[0, 1)`` (tests).
        """
        if isinstance(failures, bool) or not isinstance(failures, int) or failures < 1:
            raise ValueError("failures must be an integer >= 1")
        r = _RANDOM.random() if draw is None else draw
        if not 0 <= r < 1:
            raise ValueError("draw must be in [0, 1)")
        exponent = failures - 1
        # Compare in log space first: factor**exponent may not fit in a float. Once this
        # test is true it stays true for every larger exponent (factor >= 1), so the result
        # is the cap from there on and never drops below an earlier delay.
        if exponent * math.log(self.factor) + math.log(self.base_s) >= math.log(self.cap_s):
            return self.cap_s
        raw = self.base_s * self.factor**exponent
        return min(self.cap_s, raw * (1 + self.jitter * r))
