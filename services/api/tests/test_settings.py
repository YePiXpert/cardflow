"""Settings: deployment-ops §2 defaults, secret handling, validation without echoing input."""

from pathlib import Path

import pytest
from pydantic import ValidationError
from pydantic_settings import SettingsError

from cardflow.db import database_url_from_settings
from cardflow.settings import Settings

VALID_KEK = "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY="  # base64 of 32 bytes


@pytest.mark.usefixtures("clean_settings_env")
def test_defaults_follow_deployment_ops() -> None:
    settings = Settings()

    assert settings.cardflow_api_port == 18080
    assert settings.database_url == "postgresql+psycopg://cardflow@db/cardflow"
    assert settings.database_password is None
    assert settings.attachments_dir == Path("/data/attachments")
    assert (settings.solver_time_limit_s, settings.solver_workers) == (10, 8)
    assert (settings.parse_timeout_s, settings.max_upload_mb) == (120, 25)
    assert (settings.ai_enabled, settings.ai_provider, settings.ai_region) == (False, None, None)
    assert settings.promo_allowed_domains == ()
    assert settings.rate_limit_window_s == 600
    assert settings.rate_limit_device_requests == 600
    assert settings.rate_limit_solve_requests == 30
    assert settings.rate_limit_upload_requests == 20
    assert (settings.log_level, settings.log_format) == ("info", "json")
    assert settings.backup_cron == "0 3 * * *"
    assert (settings.backup_retention_daily, settings.backup_retention_weekly) == (14, 8)
    assert (settings.tombstone_retention_days, settings.audit_retention_days) == (90, 365)
    assert settings.min_client_version == "1.0.0"
    assert (settings.jwt_key, settings.kek, settings.backup_passphrase) == (None, None, None)
    assert (
        settings.database_api_password,
        settings.database_worker_password,
        settings.database_admin_password,
    ) == (None, None, None)


def test_environment_overrides_and_parsing(clean_settings_env: pytest.MonkeyPatch) -> None:
    clean_settings_env.setenv("LOG_LEVEL", "DEBUG")
    clean_settings_env.setenv("LOG_FORMAT", "Text")
    clean_settings_env.setenv("PROMO_ALLOWED_DOMAINS", "a.example.com, B.example.com,,")
    clean_settings_env.setenv("SOLVER_WORKERS", "4")
    clean_settings_env.setenv("BACKUP_PASSPHRASE", "pass-phrase-9")

    settings = Settings()

    assert settings.log_level == "debug"
    assert settings.log_format == "text"
    assert settings.promo_allowed_domains == ("a.example.com", "b.example.com")
    assert settings.solver_workers == 4
    assert settings.backup_passphrase is not None
    assert settings.backup_passphrase.get_secret_value() == "pass-phrase-9"
    assert "pass-phrase-9" not in repr(settings)


def test_direct_value_and_file_are_mutually_exclusive(
    tmp_path: Path, clean_settings_env: pytest.MonkeyPatch
) -> None:
    secret_file = tmp_path / "jwt_key"
    secret_file.write_text("from-file", encoding="utf-8")
    clean_settings_env.setenv("JWT_KEY", "from-env")
    clean_settings_env.setenv("JWT_KEY_FILE", str(secret_file))

    with pytest.raises(SettingsError, match="JWT_KEY and JWT_KEY_FILE are mutually exclusive"):
        Settings()


def test_login_role_passwords_come_from_secret_files(
    tmp_path: Path, clean_settings_env: pytest.MonkeyPatch
) -> None:
    """T-006: cardflow db-provision reads the LOGIN-role passwords like every other secret."""
    for name in ("api", "worker", "admin"):
        secret = tmp_path / f"db_{name}_password"
        secret.write_text(f"{name}-secret-0123456789\n", encoding="utf-8")
        clean_settings_env.setenv(f"DATABASE_{name.upper()}_PASSWORD_FILE", str(secret))

    settings = Settings()

    assert settings.database_api_password is not None
    assert settings.database_api_password.get_secret_value() == "api-secret-0123456789"
    assert settings.database_worker_password is not None
    assert settings.database_worker_password.get_secret_value() == "worker-secret-0123456789"
    assert settings.database_admin_password is not None
    assert settings.database_admin_password.get_secret_value() == "admin-secret-0123456789"
    assert "secret-0123456789" not in repr(settings)


def test_unreadable_secret_file_names_variable_and_path(
    tmp_path: Path, clean_settings_env: pytest.MonkeyPatch
) -> None:
    missing = tmp_path / "absent"
    clean_settings_env.setenv("DATABASE_PASSWORD_FILE", str(missing))

    with pytest.raises(SettingsError, match="DATABASE_PASSWORD_FILE") as excinfo:
        Settings()

    assert str(missing) in str(excinfo.value)


@pytest.mark.parametrize(
    "kek",
    ["not base64 !!", "MDEyMzQ1Njc4OWFiY2RlZg=="],  # garbage / only 16 bytes
)
def test_invalid_kek_is_rejected_without_echo(
    kek: str, clean_settings_env: pytest.MonkeyPatch
) -> None:
    clean_settings_env.setenv("KEK", kek)

    with pytest.raises(ValidationError) as excinfo:
        Settings()

    assert "KEK must" in str(excinfo.value)
    assert kek not in str(excinfo.value)


def test_valid_kek_is_accepted(clean_settings_env: pytest.MonkeyPatch) -> None:
    clean_settings_env.setenv("KEK", VALID_KEK)

    settings = Settings()

    assert settings.kek is not None
    assert settings.kek.get_secret_value() == VALID_KEK


def test_password_inside_database_url_is_rejected_without_echo(
    clean_settings_env: pytest.MonkeyPatch,
) -> None:
    clean_settings_env.setenv("DATABASE_URL", "postgresql://cardflow:hunter2-x@db/cardflow")

    with pytest.raises(ValidationError) as excinfo:
        Settings()

    assert "must not contain a password" in str(excinfo.value)
    assert "hunter2-x" not in str(excinfo.value)


@pytest.mark.usefixtures("clean_settings_env")
@pytest.mark.parametrize(
    "url", ["sqlite:///cardflow.db", "postgresql+psycopg2://cardflow@db/cardflow", "::nonsense"]
)
def test_non_psycopg_database_urls_are_rejected(url: str) -> None:
    with pytest.raises(ValidationError):
        Settings(database_url=url)


@pytest.mark.usefixtures("clean_settings_env")
def test_engine_url_gets_driver_and_secret_password() -> None:
    settings = Settings(
        database_url="postgresql://cardflow@127.0.0.1:18432/cardflow",
        database_password="pw-from-secret-3",
    )

    url = database_url_from_settings(settings)

    assert settings.database_url == "postgresql+psycopg://cardflow@127.0.0.1:18432/cardflow"
    assert url.drivername == "postgresql+psycopg"
    assert url.password == "pw-from-secret-3"
    assert "pw-from-secret-3" not in repr(url)
    assert "pw-from-secret-3" not in str(url)


@pytest.mark.usefixtures("clean_settings_env")
def test_settings_are_immutable() -> None:
    settings = Settings()

    with pytest.raises(ValidationError):
        settings.log_level = "debug"  # type: ignore[misc]
