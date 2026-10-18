"""Device public keys and free-text checks of API-01 (no database)."""

import base64

import pytest
from cryptography.hazmat.primitives.asymmetric import ec, ed25519, rsa, x25519
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

from cardflow.identity.validation import check_free_text, decode_public_key, has_card_number


def spki(public_key: object, *, point: PublicFormat = PublicFormat.SubjectPublicKeyInfo) -> bytes:
    return public_key.public_bytes(Encoding.DER, point)  # type: ignore[attr-defined]


def b64(data: bytes) -> str:
    return base64.b64encode(data).decode()


@pytest.mark.parametrize(
    "make",
    [
        lambda: ec.generate_private_key(ec.SECP256R1()).public_key(),
        lambda: ec.generate_private_key(ec.SECP384R1()).public_key(),
        lambda: ed25519.Ed25519PrivateKey.generate().public_key(),
        lambda: rsa.generate_private_key(public_exponent=65537, key_size=2048).public_key(),
    ],
    ids=["p256", "p384", "ed25519", "rsa2048"],
)
def test_supported_signing_keys_are_accepted(make: object) -> None:
    der = spki(make())  # type: ignore[operator]
    assert decode_public_key(b64(der)) == der


@pytest.mark.parametrize(
    ("make", "message"),
    [
        (lambda: ec.generate_private_key(ec.SECP521R1()).public_key(), "P-256 and P-384"),
        (lambda: ec.generate_private_key(ec.SECP256K1()).public_key(), "P-256 and P-384"),
        (
            lambda: rsa.generate_private_key(
                public_exponent=65537,
                key_size=1024,  # noqa: S505 - the weak key under test
            ).public_key(),
            "2048 to 4096",
        ),
        (lambda: x25519.X25519PrivateKey.generate().public_key(), "only EC"),
    ],
    ids=["p521", "secp256k1", "rsa1024", "x25519"],
)
def test_other_keys_are_refused(make: object, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        decode_public_key(b64(spki(make())))  # type: ignore[operator]


# SubjectPublicKeyInfo header of an EC P-256 key with a 33-byte (compressed) point.
P256_COMPRESSED_SPKI_HEADER = bytes.fromhex("3039301306072a8648ce3d020106082a8648ce3d030107032200")


def test_malformed_input_is_refused_without_echo() -> None:
    key = ec.generate_private_key(ec.SECP256R1()).public_key()
    der = spki(key)
    cases = {
        "not base64": "not base64 at all!!",
        "url-safe alphabet": base64.urlsafe_b64encode(b"\xfb\xff" * 40).decode(),
        "too short": b64(b"\x30\x03\x01\x02\x03"),
        "trailing bytes": b64(der + b"\x00"),
        "random DER": b64(b"\x30\x40" + b"\x02" * 64),
        "too long": "A" * 6000,
    }
    for name, value in cases.items():
        with pytest.raises(ValueError, match="public_key") as caught:
            decode_public_key(value)
        assert value not in str(caught.value), name


def test_compressed_ec_points_are_not_canonical() -> None:
    """A compressed point parses, but re-encoding gives the uncompressed SPKI: refused, so
    one key always has one stored encoding."""
    key = ec.generate_private_key(ec.SECP256R1()).public_key()
    compressed = P256_COMPRESSED_SPKI_HEADER + key.public_bytes(
        Encoding.X962, PublicFormat.CompressedPoint
    )
    with pytest.raises(ValueError, match="canonical"):
        decode_public_key(b64(compressed))


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("4111111111111111", True),
        ("4111 1111 1111 1111", True),
        ("4111-1111-1111-1111", True),
        ("my 1234567890123 phone", True),  # 13 digits in a row (R-CARD-02)
        ("4111 1111 1111 1112", False),  # Luhn fails, groups
        ("Pixel 9 Pro", False),
        ("1.0.0+123456789012", False),
        ("1.0.0-4111111111111111", True),
    ],
)
def test_card_numbers_in_free_text(text: str, expected: bool) -> None:
    assert has_card_number(text) is expected


def test_free_text_rules() -> None:
    assert check_free_text("Zhang's iPhone", max_length=64) == "Zhang's iPhone"
    for bad, message in (
        ("", "1 to 64"),
        ("x" * 65, "1 to 64"),
        ("tab\there", "control"),
        ("card 4111 1111 1111 1111", "card number"),
    ):
        with pytest.raises(ValueError, match=message):
            check_free_text(bad, max_length=64)
