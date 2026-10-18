"""Pairing code format, normalisation, hashing and TTL parsing (no database)."""

import hashlib
import math
import re
from datetime import timedelta

import pytest

from cardflow.identity.pairing import (
    CODE_ENTROPY_BITS,
    CODE_LENGTH,
    CROCKFORD_ALPHABET,
    DEFAULT_TTL,
    MAX_TTL,
    MIN_TTL,
    format_pairing_code,
    generate_pairing_code,
    normalize_pairing_code,
    pairing_code_hash,
    parse_ttl,
)

DISPLAY = re.compile(r"[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}")


def test_codes_carry_at_least_50_bits_from_the_crockford_alphabet() -> None:
    codes = {generate_pairing_code() for _ in range(2000)}

    assert len(CROCKFORD_ALPHABET) == 32
    assert set(CROCKFORD_ALPHABET).isdisjoint("ILOU")
    assert CODE_ENTROPY_BITS == CODE_LENGTH * math.log2(len(CROCKFORD_ALPHABET)) >= 50
    assert len(codes) == 2000  # no repeats in a sample
    assert all(len(code) == CODE_LENGTH and set(code) <= set(CROCKFORD_ALPHABET) for code in codes)
    assert set("".join(codes)) == set(CROCKFORD_ALPHABET)  # every symbol is used
    assert all(DISPLAY.fullmatch(format_pairing_code(code)) for code in codes)


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("7K2M-9QXT-4B8R", "7K2M9QXT4B8R"),
        ("7k2m 9qxt 4b8r", "7K2M9QXT4B8R"),
        ("  7K2M9QXT4B8R\n", "7K2M9QXT4B8R"),
        ("OIL0-1111-2222", "011011112222"),  # Crockford: O -> 0, I/L -> 1
        ("7K2M-9QXT-4B8", None),  # too short
        ("7K2M-9QXT-4B8RR", None),  # too long
        ("7K2M-9QXT-4B8U", None),  # U is not in the alphabet
        ("7K2M_9QXT_4B8R", None),
        ("", None),
        ("7" * 65, None),
    ],
)
def test_normalisation(raw: str, expected: str | None) -> None:
    assert normalize_pairing_code(raw) == expected


def test_hash_is_sha256_with_a_domain_label() -> None:
    code = "7K2M9QXT4B8R"
    digest = pairing_code_hash(code)

    assert re.fullmatch(r"[0-9a-f]{64}", digest)
    assert digest == hashlib.sha256(b"cardflow-pairing-code:v1:" + code.encode()).hexdigest()
    assert digest != hashlib.sha256(code.encode()).hexdigest()
    assert code not in digest


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("10m", timedelta(minutes=10)),
        ("90s", timedelta(seconds=90)),
        ("2h", timedelta(hours=2)),
        ("1h30m", timedelta(hours=1, minutes=30)),
        ("24h", timedelta(hours=24)),
        ("1m", timedelta(minutes=1)),
    ],
)
def test_ttl_parsing(text: str, expected: timedelta) -> None:
    assert parse_ttl(text) == expected


@pytest.mark.parametrize("text", ["", "10", "59s", "24h1s", "25h", "10x", "-5m", "1d", "m"])
def test_ttl_out_of_range_or_malformed_is_rejected(text: str) -> None:
    with pytest.raises(ValueError, match="TTL"):
        parse_ttl(text)


def test_ttl_bounds() -> None:
    assert (
        timedelta(minutes=1),
        timedelta(minutes=10),
        timedelta(hours=24),
    ) == (MIN_TTL, DEFAULT_TTL, MAX_TTL)
