"""API-01/02/03 over HTTP (T-011): registration, access, refresh, reuse detection, revocation.

The application under test is the real one (``api_app``), logged in to PostgreSQL as the
temporary cardflow_api-like role -- never as the superuser -- so every request runs under
row-level security exactly as deployed. Pairing codes are created like ``cardflow pairing
create`` (superuser, ``pairing_codes`` fixture); the database state is inspected with the
superuser engine ``db_engine``.
"""

import base64
import hashlib
import io
import json
import logging
import subprocess
import sys
import uuid
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import TYPE_CHECKING, Any, Final

import jwt
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from httpx import Response
from pydantic import SecretStr
from sqlalchemy import func, insert, select, text, update
from sqlalchemy.engine import Engine

from cardflow.api.app import create_app
from cardflow.api.deps import (
    ENDPOINT_IDEMPOTENT_PATHS,
    IDEMPOTENCY_EXTENSION,
    dispose_database,
)
from cardflow.db.models import metadata
from cardflow.identity.pairing import NewPairingCode, normalize_pairing_code, pairing_code_hash
from cardflow.identity.throttle import FailureLimiter
from cardflow.identity.tokens import KeyRing, issue_access_token
from cardflow.log import JsonFormatter, RequestIdFilter
from cardflow.settings import Settings

if TYPE_CHECKING:
    from tests.conftest import RegisteredDevice

pytestmark = pytest.mark.db

T: Final = metadata.tables
PII_SCAN: Final = Path(__file__).resolve().parents[4] / "tools" / "pii_scan.py"
REGISTER: Final = "/v1/devices/register"
REFRESH: Final = "/v1/auth/refresh"
REVOKE: Final = "/v1/auth/revoke"
WORKSPACE: Final = "/v1/workspace"
REJECTED: Final = "The pairing code is invalid, expired or already used"
INVALID_ACCESS: Final = "Invalid or expired access token"

CodeFactory = Callable[..., NewPairingCode]
BodyFactory = Callable[..., dict[str, Any]]


def register(client: TestClient, body: dict[str, Any], key: uuid.UUID | None = None) -> Response:
    return client.post(REGISTER, json=body, headers={"Idempotency-Key": str(key or uuid.uuid4())})


def refresh(client: TestClient, token: str, key: uuid.UUID | None = None) -> Response:
    return client.post(
        REFRESH,
        json={"refresh_token": token},
        headers={"Idempotency-Key": str(key or uuid.uuid4())},
    )


def bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def workspace(client: TestClient, token: str, **headers: str) -> Response:
    return client.get(WORKSPACE, headers={**bearer(token), **headers})


def revoke(client: TestClient, token: str, scope: str | None = None) -> Response:
    return client.post(
        REVOKE,
        json=None if scope is None else {"scope": scope},
        headers={**bearer(token), "Idempotency-Key": str(uuid.uuid4())},
    )


def error_code(response: Response) -> str:
    return response.json()["error"]["code"]


def sessions_of(db_engine: Engine, device_id: str | uuid.UUID) -> list[tuple[Any, ...]]:
    sessions = T["auth_sessions"]
    with db_engine.connect() as connection:
        return [
            tuple(row)
            for row in connection.execute(
                select(sessions.c.id, sessions.c.revoked_reason, sessions.c.rotated_from_id)
                .where(sessions.c.device_id == uuid.UUID(str(device_id)))
                .order_by(sessions.c.created_at, sessions.c.id)
            )
        ]


def audit_actions(db_engine: Engine, workspace_id: str | uuid.UUID) -> list[str]:
    audit = T["audit_log"]
    with db_engine.connect() as connection:
        return list(
            connection.execute(
                select(audit.c.action)
                .where(audit.c.workspace_id == uuid.UUID(str(workspace_id)))
                .order_by(audit.c.at, audit.c.id)
            ).scalars()
        )


def claims(token: str) -> dict[str, Any]:
    return jwt.decode(token, options={"verify_signature": False})


# --- the main chain --------------------------------------------------------------------------


def test_register_access_refresh_reuse_then_all_sessions_are_revoked(
    api_client: TestClient,
    pairing_codes: CodeFactory,
    device_registration_body: BodyFactory,
    db_engine: Engine,
) -> None:
    """Pairing code -> register (201) -> GET /v1/workspace -> refresh -> the rotated token
    again = reuse: every session of the device is revoked and audited, all tokens 401."""
    code = pairing_codes()
    registered = register(api_client, device_registration_body(code.code))
    assert registered.status_code == 201, registered.text
    first = registered.json()
    assert set(first) == {
        "device_id",
        "workspace_id",
        "access_token",
        "access_expires_at",
        "refresh_token",
        "refresh_expires_at",
    }
    assert registered.headers["cache-control"] == "no-store"
    assert "idempotent-replayed" not in registered.headers

    seen = workspace(api_client, first["access_token"])
    assert seen.status_code == 200
    assert seen.json() == {"id": first["workspace_id"], "kind": "real"}

    rotated = refresh(api_client, first["refresh_token"])
    assert rotated.status_code == 200, rotated.text
    second = rotated.json()
    assert (second["device_id"], second["workspace_id"]) == (
        first["device_id"],
        first["workspace_id"],
    )
    assert second["refresh_token"] != first["refresh_token"]
    assert workspace(api_client, second["access_token"]).status_code == 200
    # Rotation ends the old session, and with it the old access token.
    assert workspace(api_client, first["access_token"]).status_code == 401

    reused = refresh(api_client, first["refresh_token"])
    assert (reused.status_code, error_code(reused)) == (401, "UNAUTHORIZED")
    assert workspace(api_client, second["access_token"]).status_code == 401
    assert refresh(api_client, second["refresh_token"]).status_code == 401

    reasons = [reason for _id, reason, _from in sessions_of(db_engine, first["device_id"])]
    assert reasons == ["rotated", "reuse_detected"]
    assert audit_actions(db_engine, first["workspace_id"]) == [
        "device.registered",
        "auth_session.reuse_detected",
    ]


def test_revoke_ends_the_session_at_once(
    api_client: TestClient,
    registered_device: "RegisteredDevice",
    pairing_codes: CodeFactory,
    device_registration_body: BodyFactory,
    db_engine: Engine,
) -> None:
    """A join code adds a second device (no user); POST /v1/auth/revoke ends its session:
    the access token and the refresh token are refused immediately (401)."""
    join = pairing_codes(registered_device.workspace_id)
    joined = register(api_client, device_registration_body(join.code, platform="ios"))
    assert joined.status_code == 201, joined.text
    tokens = joined.json()
    assert tokens["workspace_id"] == str(registered_device.workspace_id)
    assert workspace(api_client, tokens["access_token"]).status_code == 200

    revoked = revoke(api_client, tokens["access_token"])
    assert (revoked.status_code, revoked.json()) == (200, {"revoked_sessions": 1})
    assert workspace(api_client, tokens["access_token"]).status_code == 401
    assert refresh(api_client, tokens["refresh_token"]).status_code == 401
    assert revoke(api_client, tokens["access_token"]).status_code == 401  # already revoked
    # The first device is untouched.
    assert workspace(api_client, registered_device.access_token).status_code == 200

    devices = T["devices"]
    with db_engine.connect() as connection:
        user_ids = dict(
            connection.execute(
                select(devices.c.id, devices.c.user_id).where(
                    devices.c.workspace_id == registered_device.workspace_id
                )
            ).all()
        )
    assert user_ids[registered_device.device_id] is not None  # the bootstrap owner
    assert user_ids[uuid.UUID(tokens["device_id"])] is None  # ADR-011: device, no user
    assert audit_actions(db_engine, registered_device.workspace_id) == [
        "device.registered",
        "pairing_code.created",  # the join code belongs to the workspace
        "device.registered",
        "auth_session.revoked",
    ]


def test_revoke_with_device_scope_ends_every_session_of_the_device(
    api_client: TestClient, registered_device: "RegisteredDevice", db_engine: Engine
) -> None:
    devices = T["devices"]
    with db_engine.connect() as connection:
        before = connection.execute(
            select(devices.c.revoked_at).where(devices.c.id == registered_device.device_id)
        ).scalar_one()
    revoked = revoke(api_client, registered_device.access_token, "device")
    assert (revoked.status_code, revoked.json()) == (200, {"revoked_sessions": 1})
    assert workspace(api_client, registered_device.access_token).status_code == 401
    assert [reason for _, reason, _ in sessions_of(db_engine, registered_device.device_id)] == [
        "device_logout"
    ]
    assert before is None
    assert revoke(api_client, registered_device.access_token, "everything").status_code == 401


# --- pairing code failures -----------------------------------------------------------------------


def _insert_expired_code(db_engine: Engine, code: str) -> None:
    """A bootstrap code with a known plaintext that expired an hour ago (superuser)."""
    codes = T["pairing_codes"]
    with db_engine.begin() as connection:
        connection.execute(
            insert(codes).values(
                purpose="bootstrap_workspace",
                code_hash=pairing_code_hash(normalize_pairing_code(code) or ""),
                created_via="cli",
                created_at=func.now() - timedelta(hours=2),
                expires_at=func.now() - timedelta(hours=1),
            )
        )


@pytest.mark.parametrize(
    "case", ["expired", "used", "unknown", "malformed", "deleted_workspace", "lowercase_ok"]
)
def test_pairing_code_must_be_known_unexpired_and_unused(
    api_client: TestClient,
    pairing_codes: CodeFactory,
    device_registration_body: BodyFactory,
    registered_device: "RegisteredDevice",
    db_engine: Engine,
    case: str,
) -> None:
    """Expired, used, unknown and malformed codes and join codes of a workspace being deleted
    all get the same 401; a code typed in lower case with spaces still works."""
    if case == "expired":
        code = "7K2M-9QXT-4B8R"
        _insert_expired_code(db_engine, code)
    elif case == "used":
        code = pairing_codes().code
        assert register(api_client, device_registration_body(code)).status_code == 201
    elif case == "unknown":
        code = "ZZZZ-ZZZZ-ZZZZ"
    elif case == "malformed":
        code = "not-a-code!"
    elif case == "deleted_workspace":
        code = pairing_codes(registered_device.workspace_id).code
        with db_engine.begin() as connection:
            connection.execute(
                update(T["workspaces"])
                .where(T["workspaces"].c.id == registered_device.workspace_id)
                .values(deleted_at=datetime.now(UTC))
            )
    else:
        code = pairing_codes().code.lower().replace("-", " ")

    response = register(api_client, device_registration_body(code))

    if case == "lowercase_ok":
        assert response.status_code == 201, response.text
        return
    assert response.status_code == 401
    assert response.json()["error"] == {
        "code": "UNAUTHORIZED",
        "message": REJECTED,
        "details": {},
        "request_id": response.headers["x-request-id"],
    }
    assert code not in response.text


def test_invalid_device_input_is_422_without_echo(
    api_client: TestClient, pairing_codes: CodeFactory, device_registration_body: BodyFactory
) -> None:
    """A bad public key, a card number in the device name, a missing Idempotency-Key: 422
    VALIDATION_ERROR naming the field, never repeating the input; the code stays unused."""
    code = pairing_codes().code
    bad_key = base64.b64encode(b"\x30" + b"\x01" * 60).decode()
    pan_name = "card 4111 1111 1111 1111"
    cases = [
        (device_registration_body(code, public_key=bad_key), "public_key", bad_key),
        (device_registration_body(code, name=pan_name), "name", pan_name),
        (device_registration_body(code, app_version="1.0"), "app_version", "1.0"),
    ]
    for body, field, value in cases:
        response = register(api_client, body)
        assert response.status_code == 422, field
        errors = response.json()["error"]["details"]["errors"]
        assert [error["loc"][-1] for error in errors] == [field]
        assert value not in response.text
    missing_key = api_client.post(REGISTER, json=device_registration_body(code))
    assert missing_key.status_code == 422
    assert register(api_client, device_registration_body(code)).status_code == 201


# --- access token checks ---------------------------------------------------------------------


def test_x_workspace_id_must_match_the_token(
    api_client: TestClient, registered_device: "RegisteredDevice"
) -> None:
    token = registered_device.access_token
    other = workspace(api_client, token, **{"X-Workspace-Id": str(uuid.uuid4())})
    garbage = workspace(api_client, token, **{"X-Workspace-Id": "not-a-uuid"})
    same = workspace(api_client, token, **{"X-Workspace-Id": str(registered_device.workspace_id)})

    assert (other.status_code, error_code(other)) == (403, "FORBIDDEN")
    assert (garbage.status_code, error_code(garbage)) == (403, "FORBIDDEN")
    assert same.status_code == 200


def test_revoked_device_is_refused_at_once(
    api_client: TestClient, registered_device: "RegisteredDevice", db_engine: Engine
) -> None:
    """AP-08 device revocation (here by the superuser): access and refresh fail at once."""
    assert workspace(api_client, registered_device.access_token).status_code == 200
    with db_engine.begin() as connection:
        connection.execute(
            update(T["devices"])
            .where(T["devices"].c.id == registered_device.device_id)
            .values(revoked_at=datetime.now(UTC))
        )
    assert workspace(api_client, registered_device.access_token).status_code == 401
    assert refresh(api_client, registered_device.refresh_token).status_code == 401


def test_disabled_owner_loses_access(
    api_client: TestClient, registered_device: "RegisteredDevice", db_engine: Engine
) -> None:
    devices, users = T["devices"], T["users"]
    with db_engine.begin() as connection:
        owner = connection.execute(
            select(devices.c.user_id).where(devices.c.id == registered_device.device_id)
        ).scalar_one()
        connection.execute(
            update(users).where(users.c.id == owner).values(disabled_at=datetime.now(UTC))
        )
    assert workspace(api_client, registered_device.access_token).status_code == 401


def _forged(registered: "RegisteredDevice", keys: KeyRing) -> dict[str, str]:
    base = claims(registered.access_token)
    now = int(datetime.now(UTC).timestamp())
    good = {**base, "iat": now, "exp": now + 600}
    secret, kid = keys.current.secret, keys.current.kid
    header = base64.urlsafe_b64encode(b'{"alg":"none","typ":"JWT"}').rstrip(b"=").decode()
    payload = base64.urlsafe_b64encode(json.dumps(good).encode()).rstrip(b"=").decode()
    expired, _ = issue_access_token(
        keys,
        device_id=uuid.UUID(base["sub"]),
        workspace_id=uuid.UUID(base["wsp"]),
        session_id=uuid.UUID(base["sid"]),
        ttl=timedelta(minutes=15),
        now=datetime.now(UTC) - timedelta(hours=1),
    )
    return {
        "expired": expired,
        "unknown_kid": jwt.encode(good, b"k" * 40, algorithm="HS256", headers={"kid": "nope"}),
        "bad_signature": jwt.encode(good, b"x" * 40, algorithm="HS256", headers={"kid": kid}),
        "wrong_type": jwt.encode(
            {**good, "typ": "refresh"}, secret, algorithm="HS256", headers={"kid": kid}
        ),
        "missing_sid": jwt.encode(
            {key: value for key, value in good.items() if key != "sid"},
            secret,
            algorithm="HS256",
            headers={"kid": kid},
        ),
        "other_algorithm": jwt.encode(good, secret, algorithm="HS512", headers={"kid": kid}),
        "alg_none": f"{header}.{payload}.",
        "future_iat": jwt.encode(
            {**good, "iat": now + 3600, "exp": now + 4000},
            secret,
            algorithm="HS256",
            headers={"kid": kid},
        ),
        "other_session": jwt.encode(
            {**good, "sid": str(uuid.uuid4())}, secret, algorithm="HS256", headers={"kid": kid}
        ),
        "garbage": "definitely.not.a-token",
    }


@pytest.mark.filterwarnings("ignore::jwt.warnings.InsecureKeyLengthWarning")  # HS512 forgery
def test_access_tokens_are_checked_strictly(
    api_client: TestClient,
    registered_device: "RegisteredDevice",
    api_settings: Settings,
) -> None:
    """Expired, unknown kid, bad signature, typ not access, a missing claim, another
    algorithm, alg none, a future iat, an unknown session and garbage: all the same 401 with
    a Bearer challenge; the genuine token works."""
    keys = KeyRing.from_settings(api_settings)
    responses = {
        name: workspace(api_client, token)
        for name, token in _forged(registered_device, keys).items()
    }
    responses["no_header"] = api_client.get(WORKSPACE)
    responses["basic_scheme"] = api_client.get(
        WORKSPACE, headers={"Authorization": "Basic dXNlcjpwYXNz"}
    )

    assert {name: response.status_code for name, response in responses.items()} == dict.fromkeys(
        responses, 401
    )
    messages = {name: response.json()["error"]["message"] for name, response in responses.items()}
    assert set(messages.values()) == {INVALID_ACCESS, "Authentication required"}
    assert messages["no_header"] == messages["basic_scheme"] == "Authentication required"
    challenges = {response.headers["www-authenticate"] for response in responses.values()}
    assert challenges == {
        'Bearer realm="cardflow"',
        'Bearer realm="cardflow", error="invalid_token"',
    }
    assert workspace(api_client, registered_device.access_token).status_code == 200


@contextmanager
def running(settings: Settings) -> Iterator[TestClient]:
    """A TestClient on a fresh application with ``settings``; its engine disposed after."""
    application: FastAPI = create_app(settings)
    try:
        with TestClient(application) as client:
            yield client
    finally:
        dispose_database(application)


def test_key_rotation_keeps_old_tokens_valid_until_the_old_key_is_removed(
    api_settings: Settings,
    pairing_codes: CodeFactory,
    device_registration_body: BodyFactory,
    jwt_secrets: tuple[str, str],
) -> None:
    """security-privacy §5: JWT_KEY K1 -> rotation (JWT_KEY K2, JWT_PREVIOUS_KEY K1): tokens
    signed with K1 still pass and new ones are signed with K2; once K1 is removed, tokens
    signed with it fail although their session is live."""
    first_key, second_key = jwt_secrets
    before = api_settings.model_copy(update={"jwt_key": SecretStr(first_key)})
    during = api_settings.model_copy(
        update={"jwt_key": SecretStr(second_key), "jwt_previous_key": SecretStr(first_key)}
    )
    after = api_settings.model_copy(update={"jwt_key": SecretStr(second_key)})
    kid_1, kid_2 = (
        KeyRing.from_settings(before).current.kid,
        KeyRing.from_settings(after).current.kid,
    )

    with running(before) as client:
        rotated = register(client, device_registration_body(pairing_codes().code)).json()
        untouched = register(client, device_registration_body(pairing_codes().code)).json()
    with running(during) as client:
        old_token_during_rotation = workspace(client, rotated["access_token"]).status_code
        refreshed = refresh(client, rotated["refresh_token"]).json()
        new_token_during_rotation = workspace(client, refreshed["access_token"]).status_code
    with running(after) as client:
        new_token_after = workspace(client, refreshed["access_token"]).status_code
        old_token_after = workspace(client, untouched["access_token"]).status_code

    assert kid_1 != kid_2
    assert jwt.get_unverified_header(rotated["access_token"])["kid"] == kid_1
    assert jwt.get_unverified_header(refreshed["access_token"])["kid"] == kid_2
    assert (old_token_during_rotation, new_token_during_rotation) == (200, 200)
    assert (new_token_after, old_token_after) == (200, 401)


# --- registration under RLS ------------------------------------------------------------------


def test_registration_runs_as_the_api_role_under_rls(
    api_app: FastAPI,
    api_client: TestClient,
    pairing_codes: CodeFactory,
    device_registration_body: BodyFactory,
    db_engine: Engine,
) -> None:
    """The API's own database role (no superuser, no BYPASSRLS) registers a device into a
    new workspace: anonymous owner, kind real, owner membership, device bound to the owner,
    one session, the code marked used -- and only hashes stored."""
    code = pairing_codes()
    body = device_registration_body(code.code, name="Pixel 9", app_version="1.2.3+45")
    tokens = register(api_client, body).json()

    with api_app.state.session_factory() as session:
        role = session.execute(
            text(
                "SELECT current_user, r.rolsuper, r.rolbypassrls FROM pg_roles AS r "
                "WHERE r.rolname = current_user"
            )
        ).one()
    workspace_id, device_id = uuid.UUID(tokens["workspace_id"]), uuid.UUID(tokens["device_id"])
    with db_engine.connect() as connection:
        ws = connection.execute(
            select(T["workspaces"]).where(T["workspaces"].c.id == workspace_id)
        ).one()
        members = connection.execute(
            select(T["workspace_members"].c.user_id, T["workspace_members"].c.role).where(
                T["workspace_members"].c.workspace_id == workspace_id
            )
        ).all()
        device = connection.execute(
            select(T["devices"]).where(T["devices"].c.id == device_id)
        ).one()
        owner = connection.execute(
            select(T["users"]).where(T["users"].c.id == ws.owner_user_id)
        ).one()
        session_rows = connection.execute(
            select(T["auth_sessions"]).where(T["auth_sessions"].c.device_id == device_id)
        ).all()
        pairing = connection.execute(
            select(T["pairing_codes"]).where(T["pairing_codes"].c.id == code.pairing_code_id)
        ).one()

    assert role[0].startswith("cardflow_test_app_")
    assert (role[1], role[2]) == (False, False)
    assert ws.kind == "real"
    assert members == [(ws.owner_user_id, "owner")]
    assert (owner.email, owner.password_hash) == (None, None)
    assert device.user_id == ws.owner_user_id
    assert (device.name, device.platform, device.app_version) == ("Pixel 9", "android", "1.2.3+45")
    assert device.public_key == base64.b64decode(body["public_key"])
    assert len(session_rows) == 1
    assert (
        session_rows[0].refresh_token_hash
        == hashlib.sha256(tokens["refresh_token"].encode()).hexdigest()
    )
    assert session_rows[0].revoked_at is None
    assert (pairing.used_workspace_id, pairing.used_by_device_id) == (workspace_id, device_id)
    assert pairing.used_at is not None
    normalized = normalize_pairing_code(code.code) or ""
    assert pairing.code_hash == pairing_code_hash(normalized)
    stored = json.dumps([list(map(str, pairing)), list(map(str, session_rows[0]))])
    for secret in (normalized, code.code, tokens["refresh_token"], tokens["access_token"]):
        assert secret not in stored


# --- idempotent registration (API-01) and refresh (API-02) -------------------------------------


def test_registration_replay_returns_the_same_device_with_new_tokens(
    api_client: TestClient,
    pairing_codes: CodeFactory,
    device_registration_body: BodyFactory,
    db_engine: Engine,
) -> None:
    """Same code + Idempotency-Key + request: the same device and workspace, NEW tokens, the
    earlier session revoked as replaced; same key with another body: 409; another key: 401;
    once the client used its tokens the replay is over (401)."""
    body = device_registration_body(pairing_codes().code)
    key = uuid.uuid4()
    first = register(api_client, body, key)
    replay = register(api_client, body, key)
    conflict = register(api_client, {**body, "name": "Another name"}, key)
    other_key = register(api_client, body)

    assert (first.status_code, replay.status_code) == (201, 201)
    assert replay.headers["idempotent-replayed"] == "true"
    one, two = first.json(), replay.json()
    assert (two["device_id"], two["workspace_id"]) == (one["device_id"], one["workspace_id"])
    assert (two["access_token"], two["refresh_token"]) != (
        one["access_token"],
        one["refresh_token"],
    )
    assert (conflict.status_code, error_code(conflict)) == (409, "IDEMPOTENCY_MISMATCH")
    assert (other_key.status_code, other_key.json()["error"]["message"]) == (401, REJECTED)
    assert workspace(api_client, one["access_token"]).status_code == 401
    assert refresh(api_client, one["refresh_token"]).status_code == 401
    assert workspace(api_client, two["access_token"]).status_code == 200

    after_use = register(api_client, body, key)
    assert after_use.status_code == 401
    assert [reason for _, reason, _ in sessions_of(db_engine, one["device_id"])] == [
        "replaced",
        None,
    ]
    assert audit_actions(db_engine, one["workspace_id"]) == [
        "device.registered",
        "device.registration_replayed",
    ]


def test_registration_replay_window_can_be_closed(
    api_settings: Settings, pairing_codes: CodeFactory, device_registration_body: BodyFactory
) -> None:
    """TOKEN_REPLAY_WINDOW_S=0: a used code never registers again, not even as a replay."""
    body = device_registration_body(pairing_codes().code)
    key = uuid.uuid4()
    with running(api_settings.model_copy(update={"token_replay_window_s": 0})) as client:
        assert register(client, body, key).status_code == 201
        assert register(client, body, key).status_code == 401


def test_refresh_retry_with_the_same_key_is_not_reuse(
    api_client: TestClient, registered_device: "RegisteredDevice", db_engine: Engine
) -> None:
    """A refresh whose response was lost is retried with the same Idempotency-Key: a fresh
    pair, the unreceived one dead; no reuse detection. Presenting the lost token later (it
    can only come from someone else) is a reuse and revokes everything."""
    key = uuid.uuid4()
    lost = refresh(api_client, registered_device.refresh_token, key)
    retried = refresh(api_client, registered_device.refresh_token, key)

    assert (lost.status_code, retried.status_code) == (200, 200)
    assert retried.headers["idempotent-replayed"] == "true"
    assert workspace(api_client, retried.json()["access_token"]).status_code == 200
    assert workspace(api_client, lost.json()["access_token"]).status_code == 401
    assert [reason for _, reason, _ in sessions_of(db_engine, registered_device.device_id)] == [
        "rotated",
        "replaced",
        None,
    ]

    stolen = refresh(api_client, lost.json()["refresh_token"])
    assert stolen.status_code == 401
    assert workspace(api_client, retried.json()["access_token"]).status_code == 401
    assert audit_actions(db_engine, registered_device.workspace_id)[-1] == (
        "auth_session.reuse_detected"
    )


def test_refresh_retry_after_the_new_token_was_used_is_reuse(
    api_client: TestClient, registered_device: "RegisteredDevice"
) -> None:
    key = uuid.uuid4()
    new = refresh(api_client, registered_device.refresh_token, key).json()
    assert workspace(api_client, new["access_token"]).status_code == 200  # the client had it

    again = refresh(api_client, registered_device.refresh_token, key)
    assert again.status_code == 401
    assert workspace(api_client, new["access_token"]).status_code == 401


def test_refresh_rejects_malformed_tokens_alike(api_client: TestClient) -> None:
    responses = [
        refresh(api_client, token)
        for token in ("x", "A" * 43, "not a token at all", "eyJhbGciOiJIUzI1NiJ9.e30.x")
    ]
    assert {response.status_code for response in responses} == {401}
    assert {response.json()["error"]["message"] for response in responses} == {
        "Invalid or expired refresh token"
    }


def test_token_endpoints_handle_idempotency_themselves(api_app: FastAPI) -> None:
    """For T-010: the three POST routes are marked (OpenAPI extension and
    ``ENDPOINT_IDEMPOTENT_PATHS``); the generic idempotency middleware must skip them."""
    marked = {
        path
        for path, operations in api_app.openapi()["paths"].items()
        for operation in operations.values()
        if operation.get(IDEMPOTENCY_EXTENSION) == "endpoint"
    }
    assert marked == {REGISTER, REFRESH, REVOKE} == ENDPOINT_IDEMPOTENT_PATHS


# --- brute-force guard -----------------------------------------------------------------------


class FakeClock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


def test_repeated_pairing_failures_lock_the_client_out(
    api_app: FastAPI,
    api_client: TestClient,
    pairing_codes: CodeFactory,
    device_registration_body: BodyFactory,
) -> None:
    """3 failures (limit 3) lock the client: even a valid code gets 429 RATE_LIMITED with
    Retry-After until the lockout ends; then the code works."""
    clock = FakeClock()
    api_app.state.pairing_guard = FailureLimiter(limit=3, window_s=600, lockout_s=900, clock=clock)
    good = pairing_codes().code
    failures = [
        register(api_client, device_registration_body(code)).status_code
        for code in ("AAAA-AAAA-AAAA", "BBBB-BBBB-BBBB", "CCCC-CCCC-CCCC")
    ]
    locked = register(api_client, device_registration_body(good))
    clock.now += 899
    still_locked = register(api_client, device_registration_body(good))
    clock.now += 2
    unlocked = register(api_client, device_registration_body(good))

    assert failures == [401, 401, 401]
    assert (locked.status_code, error_code(locked)) == (429, "RATE_LIMITED")
    assert locked.headers["retry-after"] == "900"
    assert still_locked.status_code == 429
    assert unlocked.status_code == 201


# --- audit and logs ----------------------------------------------------------------------------


def test_audit_rows_hold_ids_and_hashes_only(
    api_client: TestClient,
    pairing_codes: CodeFactory,
    device_registration_body: BodyFactory,
    db_engine: Engine,
) -> None:
    code = pairing_codes()
    body = device_registration_body(code.code)
    tokens = register(api_client, body).json()
    refreshed = refresh(api_client, tokens["refresh_token"]).json()
    assert refresh(api_client, tokens["refresh_token"]).status_code == 401  # reuse
    audit = T["audit_log"]
    with db_engine.connect() as connection:
        rows = connection.execute(
            select(audit).where(
                (audit.c.workspace_id == uuid.UUID(tokens["workspace_id"]))
                | (audit.c.target_id == code.pairing_code_id)
            )
        ).all()

    by_action = {row.action: row for row in rows}
    assert set(by_action) == {
        "pairing_code.created",
        "device.registered",
        "auth_session.reuse_detected",
    }
    registered = by_action["device.registered"]
    assert (registered.actor_kind, registered.actor_id) == (
        "device",
        uuid.UUID(tokens["device_id"]),
    )
    assert registered.after_hash == hashlib.sha256(base64.b64decode(body["public_key"])).hexdigest()
    assert str(registered.ip) == "testclient" or registered.ip is None  # TestClient: no IP
    assert by_action["pairing_code.created"].actor_kind == "cli"
    dump = json.dumps([[str(value) for value in row] for row in rows])
    secrets_seen = [
        code.code,
        normalize_pairing_code(code.code),
        body["public_key"],
        tokens["access_token"],
        tokens["refresh_token"],
        refreshed["refresh_token"],
    ]
    assert [secret for secret in secrets_seen if secret and secret in dump] == []


@pytest.fixture
def captured_logs() -> Iterator[io.StringIO]:
    """Every ``cardflow.*`` record as JSON lines through the production formatter."""
    stream = io.StringIO()
    handler = logging.StreamHandler(stream)
    handler.setFormatter(JsonFormatter())
    handler.addFilter(RequestIdFilter())
    logger = logging.getLogger("cardflow")
    previous = logger.level
    logger.addHandler(handler)
    logger.setLevel(logging.DEBUG)
    try:
        yield stream
    finally:
        logger.removeHandler(handler)
        logger.setLevel(previous)


def test_logs_never_contain_tokens_codes_or_keys(
    api_app: FastAPI,
    api_client: TestClient,
    pairing_codes: CodeFactory,
    device_registration_body: BodyFactory,
    captured_logs: io.StringIO,
    tmp_path: Path,
) -> None:
    """Every path of the flow -- success, 401, 403, 409, 422, 429, reuse detection,
    revocation -- logged through the production JSON formatter: tools/pii_scan.py finds
    nothing, and no token, code or key appears verbatim."""
    api_app.state.pairing_guard = FailureLimiter(limit=2, window_s=600, lockout_s=60)
    code = pairing_codes()
    body = device_registration_body(code.code)
    key = uuid.uuid4()
    tokens = register(api_client, body, key).json()
    replayed = register(api_client, body, key).json()
    register(api_client, {**body, "name": "x"}, key)  # 409
    register(api_client, device_registration_body(code.code, public_key="QUJD" * 20))  # 422
    workspace(api_client, replayed["access_token"])
    workspace(api_client, replayed["access_token"], **{"X-Workspace-Id": str(uuid.uuid4())})
    workspace(api_client, tokens["access_token"])  # 401 (replaced)
    rotated = refresh(api_client, replayed["refresh_token"]).json()
    refresh(api_client, replayed["refresh_token"])  # reuse -> 401
    join = pairing_codes(uuid.UUID(tokens["workspace_id"]))
    second = register(api_client, device_registration_body(join.code)).json()
    revoke(api_client, second["access_token"], "device")
    for wrong in ("AAAA-AAAA-AAAA", "BBBB-BBBB-BBBB", "CCCC-CCCC-CCCC"):  # 401, 401, 429
        register(api_client, device_registration_body(wrong))

    log_text = captured_logs.getvalue()
    log_file = tmp_path / "t011-api.log"
    log_file.write_text(log_text, encoding="utf-8")
    scan = subprocess.run(  # noqa: S603 - fixed interpreter and script
        [sys.executable, "-I", str(PII_SCAN), str(log_file)],
        capture_output=True,
        text=True,
        check=False,
        timeout=60,
    )

    lines = [json.loads(line) for line in log_text.splitlines()]
    events = {line["message"] for line in lines}
    assert {
        "device_registered",
        "device_registration_replayed",
        "refresh_token_reuse_detected",
    } <= events
    assert {"pairing_rejected", "pairing_lockout_started", "sessions_revoked"} <= events
    assert {line.get("status") for line in lines} >= {201, 200, 401, 403, 409, 422}
    assert (scan.returncode, scan.stdout) == (0, ""), scan.stderr
    secrets_seen = [
        code.code,
        normalize_pairing_code(code.code),
        join.code,
        body["public_key"],
        *(tokens[name] for name in ("access_token", "refresh_token")),
        *(replayed[name] for name in ("access_token", "refresh_token")),
        *(rotated[name] for name in ("access_token", "refresh_token")),
        *(second[name] for name in ("access_token", "refresh_token")),
        str(key),
    ]
    assert [secret for secret in secrets_seen if secret and secret in log_text] == []
