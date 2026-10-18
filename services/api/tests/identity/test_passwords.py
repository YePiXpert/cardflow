"""Argon2id password hashing helpers (ADR-011 optional accounts)."""

import uuid

import pytest
from argon2 import PasswordHasher, Type, extract_parameters
from pydantic import SecretStr
from sqlalchemy import insert, text
from sqlalchemy.engine import Engine
from sqlalchemy.exc import IntegrityError

from cardflow.db.models import metadata
from cardflow.identity.passwords import (
    ARGON2ID_PREFIX,
    DEFAULT_PARAMETERS,
    Argon2Parameters,
    hash_password,
    needs_rehash,
    verify_password,
)
from cardflow.settings import Settings

FAST = Argon2Parameters(time_cost=1, memory_kib=8192, parallelism=1)


def test_defaults_follow_the_owasp_minimum_configuration() -> None:
    """OWASP Password Storage Cheat Sheet: Argon2id, m=19 MiB, t=2, p=1."""
    hashed = hash_password("correct horse battery staple")
    parameters = extract_parameters(hashed)

    assert hashed.startswith(ARGON2ID_PREFIX)
    assert (parameters.type, parameters.memory_cost, parameters.time_cost) == (Type.ID, 19456, 2)
    assert (parameters.parallelism, parameters.hash_len, parameters.salt_len) == (1, 32, 16)
    assert Argon2Parameters() == DEFAULT_PARAMETERS


def test_verify_accepts_the_password_and_nothing_else() -> None:
    hashed = hash_password("s3cret-pass", FAST)

    assert verify_password(hashed, "s3cret-pass", FAST)
    assert not verify_password(hashed, "s3cret-pasS", FAST)
    assert not verify_password(hashed, "", FAST)
    assert not verify_password("not-a-hash", "s3cret-pass", FAST)
    argon2i = PasswordHasher(type=Type.I).hash("s3cret-pass")
    assert not verify_password(argon2i, "s3cret-pass", FAST)  # only Argon2id
    assert hash_password("s3cret-pass", FAST) != hashed  # random salt


def test_parameters_are_configurable_and_old_hashes_still_verify(
    clean_settings_env: pytest.MonkeyPatch,
) -> None:
    clean_settings_env.setenv("PASSWORD_ARGON2_TIME_COST", "3")
    clean_settings_env.setenv("PASSWORD_ARGON2_MEMORY_KIB", "12288")
    stronger = Argon2Parameters.from_settings(Settings())
    old = hash_password("pw-1234567", FAST)

    assert (stronger.time_cost, stronger.memory_kib, stronger.parallelism) == (3, 12288, 1)
    assert verify_password(old, "pw-1234567", stronger)
    assert needs_rehash(old, stronger)
    assert not needs_rehash(hash_password("pw-1234567", stronger), stronger)
    assert needs_rehash("garbage", stronger)


def test_unacceptable_passwords_are_rejected() -> None:
    with pytest.raises(ValueError, match="non-empty"):
        hash_password("")
    with pytest.raises(ValueError, match="at most"):
        hash_password("x" * 5000)


def test_settings_reject_parameters_below_the_floor(clean_settings_env: pytest.MonkeyPatch) -> None:
    clean_settings_env.setenv("PASSWORD_ARGON2_MEMORY_KIB", "1024")
    with pytest.raises(ValueError, match="password_argon2_memory_kib"):
        Settings()


def test_hashes_satisfy_the_users_check_constraint(db_engine: Engine) -> None:
    """0001's ck_users_password_argon2id accepts these hashes and rejects anything else."""
    users = metadata.tables["users"]
    with db_engine.connect() as connection, connection.begin() as transaction:
        connection.execute(
            insert(users).values(
                id=uuid.uuid4(),
                email=f"{uuid.uuid4().hex}@example.invalid",
                password_hash=hash_password("pw-1234567", FAST),
            )
        )
        with (
            pytest.raises(IntegrityError, match="ck_users_password_argon2id"),
            connection.begin_nested(),
        ):
            connection.execute(
                insert(users).values(
                    id=uuid.uuid4(),
                    email=f"{uuid.uuid4().hex}@example.invalid",
                    password_hash=PasswordHasher(type=Type.I).hash("pw"),
                )
            )
        assert connection.execute(text("SELECT 1")).scalar_one() == 1
        transaction.rollback()


def test_secret_settings_do_not_show_in_repr(clean_settings_env: pytest.MonkeyPatch) -> None:
    del clean_settings_env
    settings = Settings(jwt_previous_key=SecretStr("previous-secret-0123456789abcdefgh"))
    assert "previous-secret" not in repr(settings)
