"""Input checks for device registration (API-01): public key, device name, platform, version.

* ``public_key``: base64 (RFC 4648 §4) of a DER SubjectPublicKeyInfo of a signing key the
  mobile key stores produce -- EC P-256/P-384 (iOS Secure Enclave, Android Keystore),
  Ed25519, or RSA 2048-4096 -- in canonical DER (re-encoding must give the same bytes), at
  most 4096 bytes (``ck_devices_public_key_length``). Error messages never repeat the key.
* Free text (device name, app version) must not contain a card number: no run of 13 or more
  digits (R-CARD-02), and nothing the database's ``looks_like_pan()`` would reject (13-19
  Luhn-valid digits, single spaces or hyphens allowed) -- checked here so that a client gets
  422 instead of the CHECK violation's 500.
"""

import base64
import binascii
import re
from typing import Final

from cryptography.exceptions import UnsupportedAlgorithm
from cryptography.hazmat.primitives.asymmetric import ec, ed25519, rsa
from cryptography.hazmat.primitives.serialization import (
    Encoding,
    PublicFormat,
    load_der_public_key,
)

MIN_PUBLIC_KEY_BYTES: Final = 32
MAX_PUBLIC_KEY_BYTES: Final = 4096
MAX_PUBLIC_KEY_BASE64: Final = 4 * ((MAX_PUBLIC_KEY_BYTES + 2) // 3)
EC_CURVES: Final = frozenset({"secp256r1", "secp384r1"})
RSA_BITS: Final = (2048, 4096)

PLATFORM_PATTERN: Final = r"^[a-z][a-z0-9_-]{1,31}$"
APP_VERSION_PATTERN: Final = r"^[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,6}(?:[-+][0-9A-Za-z.-]{1,40})?$"
MAX_DEVICE_NAME: Final = 64

_DIGIT_RUN: Final = re.compile(r"[0-9]{13,}")
_PAN_CANDIDATE: Final = re.compile(r"[0-9](?:[ -]?[0-9])*")
_CONTROL: Final = re.compile(r"[\x00-\x1f\x7f-\x9f]")


def _luhn_valid(digits: str) -> bool:
    total = 0
    for position, char in enumerate(reversed(digits)):
        value = int(char)
        if position % 2:
            value = value * 2 - 9 if value > 4 else value * 2
        total += value
    return total % 10 == 0


def has_card_number(text: str) -> bool:
    """True if ``text`` holds 13+ consecutive digits or what ``looks_like_pan()`` rejects."""
    if _DIGIT_RUN.search(text):
        return True
    for match in _PAN_CANDIDATE.finditer(text):
        digits = re.sub(r"[ -]", "", match.group())
        if 13 <= len(digits) <= 19 and _luhn_valid(digits):
            return True
    return False


def check_free_text(value: str, *, max_length: int) -> str:
    """``value`` if it is 1..max_length printable characters without a card number."""
    if not value or len(value) > max_length:
        raise ValueError(f"must be 1 to {max_length} characters")
    if _CONTROL.search(value):
        raise ValueError("must not contain control characters")
    if has_card_number(value):
        raise ValueError("must not contain a card number or 13 or more digits")
    return value


def decode_public_key(encoded: str) -> bytes:
    """Canonical DER SubjectPublicKeyInfo from its base64, or ``ValueError``."""
    if not isinstance(encoded, str) or len(encoded) > MAX_PUBLIC_KEY_BASE64:
        raise ValueError("public_key must be base64 of at most 4096 bytes")
    try:
        der = base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError):
        raise ValueError("public_key must be standard base64") from None
    if not MIN_PUBLIC_KEY_BYTES <= len(der) <= MAX_PUBLIC_KEY_BYTES:
        raise ValueError("public_key must be 32 to 4096 bytes of DER")
    try:
        key = load_der_public_key(der)
    except (ValueError, UnsupportedAlgorithm):
        raise ValueError("public_key is not a DER SubjectPublicKeyInfo") from None
    if isinstance(key, ec.EllipticCurvePublicKey):
        if key.curve.name not in EC_CURVES:
            raise ValueError("public_key: only EC P-256 and P-384 are accepted")
    elif isinstance(key, rsa.RSAPublicKey):
        if not RSA_BITS[0] <= key.key_size <= RSA_BITS[1]:
            raise ValueError("public_key: RSA keys must have 2048 to 4096 bits")
    elif not isinstance(key, ed25519.Ed25519PublicKey):
        raise ValueError("public_key: only EC P-256/P-384, Ed25519 and RSA keys are accepted")
    if key.public_bytes(Encoding.DER, PublicFormat.SubjectPublicKeyInfo) != der:
        raise ValueError("public_key must be canonical DER (uncompressed EC points)")
    return der
