"""Access JWTs and refresh tokens (no database)."""

import base64
import hashlib
import json
import uuid
from datetime import UTC, datetime, timedelta

import jwt
import pytest
from pydantic import SecretStr

from cardflow.identity.tokens import (
    MIN_KEY_BYTES,
    AuthConfigurationError,
    InvalidAccessToken,
    KeyRing,
    SigningKey,
    issue_access_token,
    key_id,
    new_refresh_token,
    refresh_token_hash,
    signing_key,
    verify_access_token,
)
from cardflow.settings import Settings

CURRENT = "c" * 40
PREVIOUS = "p" * 40
DEVICE, WORKSPACE, SESSION = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()


def issue(keys: KeyRing, **overrides: object) -> str:
    arguments: dict[str, object] = {
        "device_id": DEVICE,
        "workspace_id": WORKSPACE,
        "session_id": SESSION,
        "ttl": timedelta(minutes=15),
    }
    arguments.update(overrides)
    token, _ = issue_access_token(keys, **arguments)  # type: ignore[arg-type]
    return token


def reason(keys: KeyRing, token: str) -> str:
    with pytest.raises(InvalidAccessToken) as caught:
        verify_access_token(keys, token)
    return caught.value.reason


def test_issue_and_verify_round_trip() -> None:
    keys = KeyRing.from_secrets(CURRENT, None)
    now = datetime.now(UTC)
    token, expires = issue_access_token(
        keys,
        device_id=DEVICE,
        workspace_id=WORKSPACE,
        session_id=SESSION,
        ttl=timedelta(minutes=15),
    )

    claims = verify_access_token(keys, token)
    header = jwt.get_unverified_header(token)
    payload = jwt.decode(token, options={"verify_signature": False})

    assert (claims.device_id, claims.workspace_id, claims.session_id) == (
        DEVICE,
        WORKSPACE,
        SESSION,
    )
    assert claims.expires_at == expires
    assert timedelta(minutes=14) < expires - now <= timedelta(minutes=15)
    assert header == {"alg": "HS256", "kid": keys.current.kid, "typ": "JWT"}
    assert set(payload) == {"sub", "wsp", "sid", "iat", "exp", "typ"}
    assert payload["typ"] == "access"
    assert payload["exp"] - payload["iat"] == 900


def test_kid_is_derived_from_the_key_and_reveals_nothing() -> None:
    first, second = signing_key(CURRENT), signing_key(PREVIOUS)

    assert first.kid == key_id(CURRENT.encode()) == signing_key(CURRENT).kid
    assert first.kid != second.kid
    assert len(first.kid) == 16
    assert CURRENT not in first.kid
    assert first.kid != hashlib.sha256(CURRENT.encode()).hexdigest()[:16]
    assert CURRENT not in repr(first)
    assert CURRENT not in repr(KeyRing(first))


def test_previous_key_verifies_but_never_signs() -> None:
    old = KeyRing.from_secrets(PREVIOUS, None)
    rotating = KeyRing.from_secrets(CURRENT, PREVIOUS)
    rotated = KeyRing.from_secrets(CURRENT, None)
    old_token = issue(old)

    assert verify_access_token(rotating, old_token).device_id == DEVICE
    assert jwt.get_unverified_header(issue(rotating))["kid"] == rotating.current.kid
    assert rotating.kids == (signing_key(CURRENT).kid, signing_key(PREVIOUS).kid)
    assert reason(rotated, old_token) == "unknown_kid"


@pytest.mark.filterwarnings("ignore::jwt.warnings.InsecureKeyLengthWarning")  # HS512 forgery
def test_rejections() -> None:
    keys = KeyRing.from_secrets(CURRENT, None)
    kid = keys.current.kid
    now = int(datetime.now(UTC).timestamp())
    good = {
        "sub": str(DEVICE),
        "wsp": str(WORKSPACE),
        "sid": str(SESSION),
        "iat": now,
        "exp": now + 60,
        "typ": "access",
    }

    def signed(payload: dict[str, object], secret: bytes = CURRENT.encode(), **header: str) -> str:
        return jwt.encode(payload, secret, algorithm="HS256", headers={"kid": kid, **header})

    unsigned = (
        base64.urlsafe_b64encode(json.dumps({"alg": "none", "kid": kid}).encode()).rstrip(b"=")
        + b"."
        + base64.urlsafe_b64encode(json.dumps(good).encode()).rstrip(b"=")
        + b"."
    ).decode()
    cases = {
        "expired": issue(keys, now=datetime.now(UTC) - timedelta(hours=1)),
        "bad_signature": signed(good, b"x" * 40),
        "unknown_kid": signed(good, kid="someone-else"),
        "wrong_type": signed({**good, "typ": "refresh"}),
        "invalid": signed({key: value for key, value in good.items() if key != "sid"}),
        "bad_sub": signed({**good, "sub": "device-1"}),
        "bad_times": signed({**good, "iat": True}),
    }
    found = {name: reason(keys, token) for name, token in cases.items()}

    assert found == {name: name for name in cases}
    assert reason(keys, unsigned) == "invalid"  # alg none
    assert reason(keys, jwt.encode(good, CURRENT.encode(), "HS512", {"kid": kid})) == "invalid"
    assert reason(keys, signed({**good, "iat": now + 3600, "exp": now + 4000})) == "invalid"
    assert reason(keys, "garbage") == "malformed"
    assert reason(keys, "") == "malformed"
    assert reason(keys, "a" * 5000) == "malformed"


def test_key_configuration_errors_name_the_setting_not_the_secret() -> None:
    with pytest.raises(AuthConfigurationError, match="JWT_KEY is not configured"):
        KeyRing.from_secrets(None, None)
    with pytest.raises(AuthConfigurationError, match=f"JWT_KEY must be at least {MIN_KEY_BYTES}"):
        KeyRing.from_secrets("short-secret", None)
    with pytest.raises(AuthConfigurationError, match="JWT_PREVIOUS_KEY must be") as caught:
        KeyRing.from_secrets(CURRENT, "short-previous")
    assert "short-previous" not in str(caught.value)


def test_key_ring_from_settings(clean_settings_env: pytest.MonkeyPatch) -> None:
    del clean_settings_env
    keys = KeyRing.from_settings(
        Settings(jwt_key=SecretStr(CURRENT), jwt_previous_key=SecretStr(PREVIOUS))
    )
    assert keys.kids == (signing_key(CURRENT).kid, signing_key(PREVIOUS).kid)
    assert isinstance(keys.current, SigningKey)


def test_refresh_tokens_are_256_bit_base64url() -> None:
    tokens = {new_refresh_token() for _ in range(500)}

    assert len(tokens) == 500
    for token in tokens:
        assert len(token) == 43
        assert len(base64.urlsafe_b64decode(token + "=")) == 32
        assert refresh_token_hash(token) == hashlib.sha256(token.encode()).hexdigest()
    for bad in ("", "a" * 42, "a" * 44, "a" * 42 + "!", None, 42):
        assert refresh_token_hash(bad) is None
