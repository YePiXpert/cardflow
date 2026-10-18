"""IdentityService against the database as the API role (no HTTP): registration paths,
concurrency on one pairing code or one refresh token, session bookkeeping.

The service gets a session factory on ``app_engine`` -- the temporary cardflow_api-like login
(member of cardflow_app, no superuser, no BYPASSRLS) -- exactly what the API uses.
"""

import base64
import threading
import uuid
from collections.abc import Callable
from datetime import timedelta
from typing import Final

import pytest
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
from sqlalchemy import select, text, update
from sqlalchemy.engine import Engine

from cardflow.db import create_session_factory
from cardflow.db.models import metadata
from cardflow.identity.pairing import NewPairingCode
from cardflow.identity.service import (
    AuthContext,
    DeviceRegistration,
    IdentityService,
    InvalidRefreshToken,
    RegistrationRejected,
    SessionInvalid,
    TokenGrant,
    TokenPolicy,
)
from cardflow.identity.tokens import KeyRing

pytestmark = pytest.mark.db

T: Final = metadata.tables
SECRET: Final = "service-test-secret-" + "0" * 32


@pytest.fixture
def service(app_engine: Engine) -> IdentityService:
    return IdentityService(
        create_session_factory(app_engine), KeyRing.from_secrets(SECRET, None), TokenPolicy()
    )


def registration(code: str, name: str = "Phone") -> DeviceRegistration:
    der = (
        Ed25519PrivateKey.generate()
        .public_key()
        .public_bytes(Encoding.DER, PublicFormat.SubjectPublicKeyInfo)
    )
    return DeviceRegistration(
        pairing_code=code, public_key=der, platform="android", app_version="1.0.0", name=name
    )


def test_service_runs_as_a_plain_role(app_engine: Engine) -> None:
    with app_engine.connect() as connection:
        superuser, bypass = connection.execute(
            text("SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user")
        ).one()
    assert (superuser, bypass) == (False, False)


def test_bootstrap_owner_and_join_device_contexts(
    service: IdentityService, pairing_codes: Callable[..., NewPairingCode], db_engine: Engine
) -> None:
    """A bootstrap device acts for the new anonymous owner; a join device has no user."""
    owner_grant = service.register(registration(pairing_codes().code), uuid.uuid4())
    owner = service.authenticate(owner_grant.access_token)
    join_grant = service.register(
        registration(pairing_codes(owner_grant.workspace_id).code), uuid.uuid4()
    )
    joined = service.authenticate(join_grant.access_token)

    with db_engine.connect() as connection:
        owner_user = connection.execute(
            select(T["workspaces"].c.owner_user_id).where(
                T["workspaces"].c.id == owner_grant.workspace_id
            )
        ).scalar_one()
    assert owner == AuthContext(
        owner_grant.device_id, owner_grant.workspace_id, owner_grant.session_id, owner_user
    )
    assert joined.workspace_id == owner_grant.workspace_id
    assert joined.user_id is None
    assert owner_grant.access_token not in repr(owner_grant)
    assert owner_grant.refresh_token not in repr(owner_grant)


def _race[R](count: int, work: Callable[[int], R]) -> list[R | Exception]:
    barrier = threading.Barrier(count)
    results: list[R | Exception] = [RuntimeError("not run")] * count

    def run(index: int) -> None:
        barrier.wait()
        try:
            results[index] = work(index)
        except Exception as exc:  # noqa: BLE001 - collected for the assertion
            results[index] = exc

    threads = [threading.Thread(target=run, args=(index,)) for index in range(count)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(60)
    return results


@pytest.mark.parametrize("purpose", ["bootstrap", "join"])
def test_concurrent_registrations_with_one_code_create_one_device(
    service: IdentityService,
    pairing_codes: Callable[..., NewPairingCode],
    db_engine: Engine,
    purpose: str,
) -> None:
    """Six clients race with the same code (different Idempotency-Keys): exactly one device
    is registered, the others are rejected; no stray workspace or user is left behind."""
    workspace = None
    if purpose == "join":
        workspace = service.register(registration(pairing_codes().code), uuid.uuid4()).workspace_id
    code = pairing_codes(workspace)
    with db_engine.connect() as connection:
        before = connection.execute(text("SELECT count(*) FROM workspaces")).scalar_one()

    results = _race(
        6, lambda index: service.register(registration(code.code, f"P{index}"), uuid.uuid4())
    )

    grants = [result for result in results if isinstance(result, TokenGrant)]
    errors = [result for result in results if not isinstance(result, TokenGrant)]
    assert len(grants) == 1
    assert all(isinstance(error, RegistrationRejected) for error in errors), errors
    with db_engine.connect() as connection:
        devices = connection.execute(
            select(T["pairing_codes"].c.used_by_device_id).where(
                T["pairing_codes"].c.id == code.pairing_code_id
            )
        ).scalar_one()
        after = connection.execute(text("SELECT count(*) FROM workspaces")).scalar_one()
    assert devices == grants[0].device_id
    assert after - before == (1 if purpose == "bootstrap" else 0)


def test_concurrent_refreshes_leave_at_most_one_live_session(
    service: IdentityService, pairing_codes: Callable[..., NewPairingCode], db_engine: Engine
) -> None:
    """Two refreshes of one token with different keys: one rotation wins; the other is a
    reuse, so every session of the device ends up revoked (clients must refresh one at a
    time and retry with the same Idempotency-Key)."""
    grant = service.register(registration(pairing_codes().code), uuid.uuid4())

    results = _race(2, lambda _index: service.refresh(grant.refresh_token, uuid.uuid4()))

    assert sorted(type(result).__name__ for result in results) == [
        "InvalidRefreshToken",
        "TokenGrant",
    ]
    sessions = T["auth_sessions"]
    with db_engine.connect() as connection:
        live = connection.execute(
            select(sessions.c.id).where(
                sessions.c.device_id == grant.device_id, sessions.c.revoked_at.is_(None)
            )
        ).all()
    assert live == []


def test_authentication_checks_the_session_every_time(
    service: IdentityService, pairing_codes: Callable[..., NewPairingCode], db_engine: Engine
) -> None:
    grant = service.register(registration(pairing_codes().code), uuid.uuid4())
    sessions, devices = T["auth_sessions"], T["devices"]

    service.authenticate(grant.access_token)
    with db_engine.connect() as connection:
        first_use = connection.execute(
            select(sessions.c.last_used_at).where(sessions.c.id == grant.session_id)
        ).scalar_one()
        seen = connection.execute(
            select(devices.c.last_seen_at).where(devices.c.id == grant.device_id)
        ).scalar_one()
    service.authenticate(grant.access_token)  # within a minute: no further write
    with db_engine.begin() as connection:
        again = connection.execute(
            select(sessions.c.last_used_at).where(sessions.c.id == grant.session_id)
        ).scalar_one()
        connection.execute(
            update(sessions)
            .where(sessions.c.id == grant.session_id)
            .values(expires_at=sessions.c.created_at + timedelta(microseconds=1))
        )

    assert first_use is not None
    assert seen is not None
    assert again == first_use
    with pytest.raises(SessionInvalid):
        service.authenticate(grant.access_token)  # the session expired
    with pytest.raises(InvalidRefreshToken):
        service.refresh(grant.refresh_token, uuid.uuid4())


def test_refresh_updates_the_reported_app_version(
    service: IdentityService, pairing_codes: Callable[..., NewPairingCode], db_engine: Engine
) -> None:
    grant = service.register(registration(pairing_codes().code), uuid.uuid4())
    service.refresh(grant.refresh_token, uuid.uuid4(), app_version="1.1.0")
    with db_engine.connect() as connection:
        version = connection.execute(
            select(T["devices"].c.app_version).where(T["devices"].c.id == grant.device_id)
        ).scalar_one()
    assert version == "1.1.0"


def test_public_key_is_stored_as_canonical_der(
    service: IdentityService, pairing_codes: Callable[..., NewPairingCode], db_engine: Engine
) -> None:
    request = registration(pairing_codes().code)
    grant = service.register(request, uuid.uuid4())
    with db_engine.connect() as connection:
        stored = connection.execute(
            select(T["devices"].c.public_key).where(T["devices"].c.id == grant.device_id)
        ).scalar_one()
    assert bytes(stored) == request.public_key
    assert base64.b64encode(request.public_key).decode() not in repr(grant)
