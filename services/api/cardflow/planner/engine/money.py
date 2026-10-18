"""Integer minor-unit money helpers. No binary floats anywhere."""

from __future__ import annotations

from decimal import ROUND_CEILING, ROUND_DOWN, ROUND_HALF_EVEN, ROUND_HALF_UP, Decimal
from fractions import Fraction

# Minor-unit digits per ISO 4217 currency. Never assume "2 decimals" globally.
MINOR_DIGITS: dict[str, int] = {
    "CNY": 2,
    "USD": 2,
    "EUR": 2,
    "HKD": 2,
    "GBP": 2,
    "MOP": 2,
    "TWD": 2,
    "JPY": 0,
    "KRW": 0,
    "VND": 0,
    "KWD": 3,
    "BHD": 3,
    "JOD": 3,
}
ROUNDING = {
    "HALF_UP": ROUND_HALF_UP,  # 四舍五入
    "DOWN": ROUND_DOWN,  # 直接截断（如银联活动"取小数点后两位，不作四舍五入"）  # noqa: RUF003
    "HALF_EVEN": ROUND_HALF_EVEN,
    "UP": ROUND_CEILING,  # 向上（费用保守口径）  # noqa: RUF003
}


def minor_digits(currency: str) -> int:
    try:
        return MINOR_DIGITS[currency]
    except KeyError:
        raise ValueError(f"unknown minor-unit digits for currency {currency!r}") from None


def to_minor(amount: str | int | Decimal, currency: str) -> int:
    """'123.45' CNY -> 12345. Rejects sub-minor fractions instead of silently rounding."""
    d = Decimal(str(amount))
    digits = minor_digits(currency)
    q = Decimal(1).scaleb(-digits)
    if d != d.quantize(q):
        raise ValueError(f"{amount} has more precision than {currency} minor unit")
    return int(d.scaleb(digits))


def from_minor(minor: int, currency: str) -> Decimal:
    return Decimal(int(minor)).scaleb(-minor_digits(currency))


def fmt(minor: int, currency: str = "CNY") -> str:
    return f"{from_minor(minor, currency):,}"


def apply_rate(minor: int, rate: Decimal | str, rounding: str) -> int:
    """minor * rate with an explicit rounding mode. rate as Decimal/str, e.g. '0.03'."""
    r = Decimal(str(rate))
    return int((Decimal(int(minor)) * r).to_integral_value(rounding=ROUNDING[rounding]))


def decimal_text(value: Decimal) -> str:
    """Canonical text of a decimal (rates, factors): plain notation, no trailing fractional
    zeros, ``"0"`` for every zero. ``Decimal('0.0060000000')`` (a NUMERIC(20,10) read from the
    database), ``Decimal('6E-3')`` and ``Decimal('0.006')`` all give ``"0.006"`` -- one value,
    one text, one hash (review R3E-11)."""
    if not value.is_finite():
        raise ValueError("not a finite decimal")
    if value == 0:
        return "0"
    return format(value.normalize(), "f")


def rate_fraction(rate: Decimal | str) -> Fraction:
    """Exact rational for use as integer coefficients in CP-SAT (num/den)."""
    return Fraction(Decimal(str(rate)))


def split_installments(principal_minor: int, periods: int, remainder_to: str = "last") -> list[int]:
    """Per-period principal. CCB merchant-installment clause (2024-09 版): per-period =
    round-half-up(total/periods), difference adjusted in the LAST period. Other banks may
    put the remainder first; the policy is a rule parameter, never a hidden default."""
    if periods <= 0:
        raise ValueError("periods must be >= 1")
    base = int(
        (Decimal(principal_minor) / Decimal(periods)).to_integral_value(rounding=ROUND_HALF_UP)
    )
    parts = [base] * periods
    diff = principal_minor - base * periods
    parts[-1 if remainder_to == "last" else 0] += diff
    assert sum(parts) == principal_minor  # noqa: S101
    return parts


def installment_cash_flows(
    principal_minor: int,
    periods: int,
    per_period_rate: Decimal | str,
    remainder_to: str = "last",
    rate_rounding: str = "HALF_UP",
) -> list[tuple[int, int, int]]:
    """Returns [(period_no, principal_part, interest_part)] with interest = total * per-period rate
    (CCB style: 每期分期利息 = 分期本金总额 * 每期分期利率), rounded explicitly."""
    parts = split_installments(principal_minor, periods, remainder_to)
    interest = apply_rate(principal_minor, per_period_rate, rate_rounding)
    return [(k + 1, p, interest) for k, p in enumerate(parts)]


def irr_monthly(flows: list[tuple[int, int]], tol: Decimal = Decimal("1e-12")) -> Decimal:
    """Monthly IRR by bisection on Decimal. flows = [(month_index, amount_minor)], month 0 =
    disbursement (+), months 1..n = payments (-). Used to compare 'nominal x12' vs true
    annualized cost."""

    def npv(r: Decimal) -> Decimal:
        return sum(Decimal(a) / (Decimal(1) + r) ** t for t, a in flows)

    lo, hi = Decimal("0"), Decimal("1")
    if npv(lo) < 0:
        raise ValueError("no positive IRR: payments do not exceed principal")
    for _ in range(200):
        mid = (lo + hi) / 2
        if npv(mid) > 0:
            lo = mid
        else:
            hi = mid
        if hi - lo < tol:
            break
    return (lo + hi) / 2


def annualize(monthly_rate: Decimal) -> dict[str, Decimal]:
    simple = monthly_rate * 12
    compound = (Decimal(1) + monthly_rate) ** 12 - Decimal(1)
    return {"nominal_x12": simple, "effective_compound": compound}
