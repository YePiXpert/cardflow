"""Runtime configuration loaded from environment variables (deployment-ops §2).

Field names map to upper-case variables (``database_url`` <- ``DATABASE_URL``). Secrets
can be given directly (``JWT_KEY``) or, preferably, as a file path in ``<NAME>_FILE``
(``JWT_KEY_FILE=/run/secrets/jwt_key``, the Compose-secrets convention); setting both
is an error. Secret values are :class:`pydantic.SecretStr`, so they never appear in
``repr()``/``str()``/logs, and validation errors never echo input values.
"""

import base64
import binascii
import os
from functools import lru_cache
from pathlib import Path
from typing import Annotated, Final, Literal

from pydantic import Field, SecretStr, field_validator
from pydantic.fields import FieldInfo
from pydantic_settings import (
    BaseSettings,
    NoDecode,
    PydanticBaseSettingsSource,
    SettingsConfigDict,
    SettingsError,
)

from cardflow.db.engine import normalize_database_url

SECRET_FIELDS: Final[tuple[str, ...]] = (
    "database_password",
    "database_api_password",
    "database_worker_password",
    "database_admin_password",
    "jwt_key",
    "jwt_previous_key",
    "kek",
    "backup_passphrase",
)
KEK_BYTES: Final = 32

LogLevel = Literal["debug", "info", "warning", "error", "critical"]
LogFormat = Literal["json", "text"]


def read_secret_file(path: Path) -> str:
    """Return the file content without trailing newlines.

    Same rule as the postgres image entrypoint (``$(< file)``), so one secret file can
    feed both the database container and the application.
    """
    return path.read_text(encoding="utf-8").rstrip("\n")


class SecretFileEnvSource(PydanticBaseSettingsSource):
    """Settings source resolving ``<NAME>_FILE`` variables for :data:`SECRET_FIELDS`."""

    def get_field_value(self, field: FieldInfo, field_name: str) -> tuple[object, str, bool]:
        """Unused: :meth:`__call__` resolves all secret files at once."""
        return None, field_name, False

    def __call__(self) -> dict[str, object]:
        """Read every configured secret file; error if a value is also set directly."""
        environ = {key.upper(): value for key, value in os.environ.items()}
        values: dict[str, object] = {}
        for field_name in SECRET_FIELDS:
            direct_var = field_name.upper()
            file_var = f"{direct_var}_FILE"
            file_path = environ.get(file_var, "")
            if not file_path:
                continue
            if environ.get(direct_var):
                raise SettingsError(f"{direct_var} and {file_var} are mutually exclusive")
            try:
                values[field_name] = read_secret_file(Path(file_path))
            except OSError as exc:
                # The path is not secret; the file content never appears in messages.
                reason = exc.strerror or type(exc).__name__
                raise SettingsError(f"cannot read {file_var} {file_path!r}: {reason}") from None
        return values


class Settings(BaseSettings):
    """CardFlow configuration (defaults follow deployment-ops §2)."""

    model_config = SettingsConfigDict(
        env_file=None,
        case_sensitive=False,
        env_ignore_empty=True,
        extra="forbid",
        frozen=True,
        hide_input_in_errors=True,
    )

    # Release / publishing. CARDFLOW_API_PORT is the host port Compose publishes on
    # 127.0.0.1; the API process itself binds to `cardflow api --host/--port`.
    cardflow_version: str = "dev"
    cardflow_api_port: int = Field(default=18080, ge=1, le=65535)
    # T-012: interactive API docs and the schema endpoint (/docs, /redoc, /openapi.json) are
    # off unless explicitly enabled (development); create_app().openapi() works regardless.
    api_docs_enabled: bool = False

    # Database: the URL carries no password; it comes from DATABASE_PASSWORD(_FILE).
    database_url: str = "postgresql+psycopg://cardflow@db/cardflow"
    database_password: SecretStr | None = None
    # Passwords that `cardflow db-provision` gives the LOGIN roles cardflow_api,
    # cardflow_worker_login and cardflow_admin_login (cardflow/db/roles.py; T-006). The
    # provisioning run itself connects with DATABASE_URL/DATABASE_PASSWORD (superuser); each
    # process later connects as its own role with the same password file as DATABASE_PASSWORD.
    database_api_password: SecretStr | None = None
    database_worker_password: SecretStr | None = None
    database_admin_password: SecretStr | None = None

    attachments_dir: Path = Path("/data/attachments")

    # CP-SAT solver and document parsing.
    solver_time_limit_s: int = Field(default=10, gt=0)
    solver_workers: int = Field(default=8, gt=0)
    parse_timeout_s: int = Field(default=120, gt=0)
    max_upload_mb: int = Field(default=25, gt=0)

    # Optional AI adapters (ADR-013): off unless explicitly enabled.
    ai_enabled: bool = False
    ai_provider: str | None = None
    ai_region: str | None = None

    # Promotion fetch allow-list; comma-separated in the environment. Empty = fetch nothing.
    promo_allowed_domains: Annotated[tuple[str, ...], NoDecode] = ()

    # RATE_LIMIT_*: api-contract §1 (per device 600 requests, solve 30, uploads 20 per 10 min).
    rate_limit_window_s: int = Field(default=600, gt=0)
    rate_limit_device_requests: int = Field(default=600, gt=0)
    rate_limit_solve_requests: int = Field(default=30, gt=0)
    rate_limit_upload_requests: int = Field(default=20, gt=0)

    log_level: LogLevel = "info"
    log_format: LogFormat = "json"

    backup_cron: str = "0 3 * * *"
    backup_retention_daily: int = Field(default=14, ge=1)
    backup_retention_weekly: int = Field(default=8, ge=0)

    tombstone_retention_days: int = Field(default=90, ge=1)
    audit_retention_days: int = Field(default=365, ge=1)

    min_client_version: str = Field(default="1.0.0", pattern=r"^\d+\.\d+\.\d+$")

    # Device tokens and pairing (T-011; cardflow/identity/). Access JWTs live
    # ACCESS_TOKEN_TTL_S (15 min), refresh tokens REFRESH_TOKEN_TTL_S (30 days, sliding); a
    # retried registration/refresh may replace its unreceived session within
    # TOKEN_REPLAY_WINDOW_S (0 = never). PAIRING_FAILURE_LIMIT failed pairing attempts per
    # client within PAIRING_FAILURE_WINDOW_S lock that client out for PAIRING_LOCKOUT_S.
    access_token_ttl_s: int = Field(default=900, ge=60, le=3600)
    refresh_token_ttl_s: int = Field(default=2_592_000, ge=3600, le=7_776_000)
    token_replay_window_s: int = Field(default=600, ge=0, le=3600)
    pairing_failure_limit: int = Field(default=10, ge=1, le=1000)
    pairing_failure_window_s: int = Field(default=600, gt=0, le=86_400)
    pairing_lockout_s: int = Field(default=900, gt=0, le=86_400)
    # Argon2id for optional account passwords (ADR-011); defaults: OWASP minimum
    # configuration m=19 MiB, t=2, p=1 (cardflow/identity/passwords.py).
    password_argon2_time_cost: int = Field(default=2, ge=1, le=20)
    password_argon2_memory_kib: int = Field(default=19_456, ge=7_168, le=1_048_576)
    password_argon2_parallelism: int = Field(default=1, ge=1, le=16)

    # Secrets: JWT signing key, KEK (base64 of 32 bytes), backup passphrase.
    # JWT_PREVIOUS_KEY(_FILE): the replaced signing key during a rotation -- it only verifies
    # tokens (security-privacy §5: keep it 7 days, then remove it). Both >= 32 bytes, checked
    # when the API first needs them (cardflow/identity/tokens.py).
    jwt_key: SecretStr | None = None
    jwt_previous_key: SecretStr | None = None
    kek: SecretStr | None = None
    backup_passphrase: SecretStr | None = None

    @classmethod
    def settings_customise_sources(
        cls,
        settings_cls: type[BaseSettings],
        init_settings: PydanticBaseSettingsSource,
        env_settings: PydanticBaseSettingsSource,
        dotenv_settings: PydanticBaseSettingsSource,
        file_secret_settings: PydanticBaseSettingsSource,
    ) -> tuple[PydanticBaseSettingsSource, ...]:
        """Init kwargs > environment > ``<NAME>_FILE``; no .env file is read implicitly."""
        return init_settings, env_settings, SecretFileEnvSource(settings_cls)

    @field_validator("log_level", "log_format", mode="before")
    @classmethod
    def _lowercase(cls, value: object) -> object:
        return value.lower() if isinstance(value, str) else value

    @field_validator("promo_allowed_domains", mode="before")
    @classmethod
    def _split_domains(cls, value: object) -> object:
        if isinstance(value, str):
            return tuple(part.strip().lower() for part in value.split(",") if part.strip())
        return value

    @field_validator("database_url")
    @classmethod
    def _check_database_url(cls, value: str) -> str:
        url = normalize_database_url(value)
        if url.password is not None:
            raise ValueError("DATABASE_URL must not contain a password; use DATABASE_PASSWORD_FILE")
        return url.render_as_string(hide_password=False)

    @field_validator("kek")
    @classmethod
    def _check_kek(cls, value: SecretStr | None) -> SecretStr | None:
        if value is None:
            return None
        try:
            raw = base64.b64decode(value.get_secret_value(), validate=True)
        except (binascii.Error, ValueError):
            raise ValueError("KEK must be base64") from None
        if len(raw) != KEK_BYTES:
            raise ValueError(f"KEK must decode to exactly {KEK_BYTES} bytes")
        return value


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Process-wide settings, read once from the environment."""
    return Settings()
