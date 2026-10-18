"""``cardflow`` command line (console script entry point).

``cardflow api`` runs the HTTP API; ``cardflow migrate`` upgrades the database schema to
the Alembic head (``--lock``: under a PostgreSQL advisory lock, for concurrent starts;
``--check``: only report whether the database is at head, exit 0 if so, 1 otherwise).
``cardflow worker`` runs the background job worker (T-008): ``--concurrency N`` jobs at a
time, ``--once`` for a single claim round, graceful stop on SIGTERM/SIGINT (exit 0); exit 1
for invalid configuration or an unusable database. ``cardflow db-provision`` (T-006) creates
or updates the LOGIN roles cardflow_api / cardflow_worker_login / cardflow_admin_login after
``cardflow migrate``: it connects like ``migrate`` (DATABASE_URL + DATABASE_PASSWORD(_FILE),
a superuser) and reads the role passwords from DATABASE_API_PASSWORD_FILE,
DATABASE_WORKER_PASSWORD_FILE and DATABASE_ADMIN_PASSWORD_FILE (``--role`` limits the run);
idempotent, all-or-nothing, passwords never printed; exit 1 on any problem. ``backup`` is
owned by a later task; until it lands it fails loudly with exit code 2 instead of
pretending to succeed. ``cardflow pairing create (--new-workspace | --workspace ID)
[--ttl 10m]`` (T-011) prints a one-time device pairing code (API-01) and audits it; it
connects like ``migrate`` (the superuser credentials, see cardflow/identity/pairing.py for
why no application role may mint codes); exit 1 on any problem.
"""

import argparse
import sys
from collections.abc import Sequence
from typing import TYPE_CHECKING, Final

if TYPE_CHECKING:
    import uuid
    from datetime import timedelta

    from sqlalchemy.engine import URL

EXIT_OK: Final = 0
EXIT_CONFIG_ERROR: Final = 1
EXIT_NOT_IMPLEMENTED: Final = 2
EXIT_MIGRATE_FAILED: Final = 1
"""``cardflow migrate``: the upgrade failed, or (``--check``) the database is not at head."""
EXIT_WORKER_FAILED: Final = 1
"""``cardflow worker``: invalid configuration, database unusable at start, or a crash."""
EXIT_PROVISION_FAILED: Final = 1
"""``cardflow db-provision``: missing password, unsafe role setup or a database error."""
EXIT_PAIRING_FAILED: Final = 1
"""``cardflow pairing create``: invalid configuration, unknown workspace or a database error."""
PROVISION_ROLE_CHOICES: Final = ("api", "worker", "admin")
"""Keys of ``cardflow.db.roles.LOGIN_ROLES`` (not imported: keeps the CLI start fast)."""
WORKER_MAX_CONCURRENCY: Final = 10
"""Mirrors ``cardflow.jobs.worker.MAX_CONCURRENCY`` (not imported: keeps the CLI start fast)."""
DEFAULT_WORKER_SHUTDOWN_TIMEOUT_S: Final = 20.0
MAX_WORKER_SHUTDOWN_TIMEOUT_S: Final = 3600.0

# command -> (owning task, scope); see docs/80-delivery/m0-execution-plan.md §4.
NOT_IMPLEMENTED: Final[dict[str, tuple[str, str]]] = {
    "backup": ("T-013", "backup and restore drill"),
}


def _port(value: str) -> int:
    try:
        port = int(value)
    except ValueError:
        raise argparse.ArgumentTypeError(f"invalid port {value!r}") from None
    if not 1 <= port <= 65535:
        raise argparse.ArgumentTypeError("port must be between 1 and 65535")
    return port


def _concurrency(value: str) -> int:
    try:
        number = int(value)
    except ValueError:
        raise argparse.ArgumentTypeError(f"invalid concurrency {value!r}") from None
    if not 1 <= number <= WORKER_MAX_CONCURRENCY:
        raise argparse.ArgumentTypeError(
            f"concurrency must be between 1 and {WORKER_MAX_CONCURRENCY}"
        )
    return number


def _seconds(value: str) -> float:
    try:
        seconds = float(value)
    except ValueError:
        raise argparse.ArgumentTypeError(f"invalid number of seconds {value!r}") from None
    if not 0 <= seconds <= MAX_WORKER_SHUTDOWN_TIMEOUT_S:
        raise argparse.ArgumentTypeError(
            f"seconds must be between 0 and {MAX_WORKER_SHUTDOWN_TIMEOUT_S:g}"
        )
    return seconds


def build_parser() -> argparse.ArgumentParser:
    """Argument parser for all sub-commands."""
    parser = argparse.ArgumentParser(prog="cardflow", description="CardFlow server commands.")
    commands = parser.add_subparsers(dest="command", required=True, metavar="COMMAND")

    api = commands.add_parser("api", help="run the HTTP API with uvicorn")
    api.add_argument("--host", default="127.0.0.1", help="bind address (default: 127.0.0.1)")
    api.add_argument("--port", type=_port, default=8000, help="bind port (default: 8000)")

    migrate = commands.add_parser(
        "migrate", help="upgrade the database schema to the latest revision (Alembic head)"
    )
    mode = migrate.add_mutually_exclusive_group()
    mode.add_argument(
        "--lock",
        action="store_true",
        help="hold a PostgreSQL advisory lock while upgrading (safe for concurrent starts)",
    )
    mode.add_argument(
        "--check",
        action="store_true",
        help="do not upgrade; exit 0 if the database is at head, 1 otherwise",
    )

    worker = commands.add_parser(
        "worker", help="run the background job worker (PostgreSQL jobs table, ADR-003)"
    )
    worker.add_argument(
        "--concurrency",
        type=_concurrency,
        default=2,
        help=f"jobs run at the same time, 1-{WORKER_MAX_CONCURRENCY} (default: 2)",
    )
    worker.add_argument(
        "--once",
        action="store_true",
        help="claim and run one round of due jobs (at most --concurrency), then exit",
    )
    worker.add_argument(
        "--shutdown-timeout",
        type=_seconds,
        default=DEFAULT_WORKER_SHUTDOWN_TIMEOUT_S,
        metavar="SECONDS",
        help="on SIGTERM/SIGINT, how long running jobs may finish before they are stopped "
        "and returned to the queue (default: 20)",
    )

    provision = commands.add_parser(
        "db-provision",
        help="create or update the LOGIN roles of the API, the worker and the admin console "
        "(run after migrate, as the database superuser)",
    )
    provision.add_argument(
        "--role",
        dest="roles",
        action="append",
        choices=PROVISION_ROLE_CHOICES,
        help="provision only this login role (repeatable; default: all three)",
    )

    pairing = commands.add_parser(
        "pairing", help="device pairing codes for POST /v1/devices/register (API-01)"
    )
    pairing_actions = pairing.add_subparsers(dest="pairing_action", required=True, metavar="ACTION")
    create = pairing_actions.add_parser(
        "create",
        help="print a one-time pairing code (run on the server, with the migration "
        "credentials DATABASE_URL + DATABASE_PASSWORD_FILE of the superuser)",
    )
    target = create.add_mutually_exclusive_group(required=True)
    target.add_argument(
        "--new-workspace",
        action="store_true",
        help="bootstrap code: the device registers into a new workspace as its owner",
    )
    target.add_argument(
        "--workspace",
        type=_workspace_id,
        metavar="ID",
        help="join code: the device registers into this existing workspace",
    )
    create.add_argument(
        "--ttl",
        type=_pairing_ttl,
        default=None,
        metavar="DURATION",
        help="validity, e.g. 90s, 10m, 2h, 1h30m; 1 minute to 24 hours (default: 10m)",
    )

    for name, (task_id, scope) in NOT_IMPLEMENTED.items():
        commands.add_parser(name, help=f"not implemented yet ({task_id}: {scope})")
    return parser


def _workspace_id(value: str) -> "uuid.UUID":
    import uuid

    try:
        return uuid.UUID(value)
    except ValueError:
        raise argparse.ArgumentTypeError("workspace id must be a UUID") from None


def _pairing_ttl(value: str) -> "timedelta":
    from cardflow.identity.pairing import parse_ttl

    try:
        return parse_ttl(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(str(exc)) from None


def _run_api(host: str, port: int) -> int:
    # Imported lazily so the other commands stay fast and dependency-light.
    import uvicorn
    from pydantic import ValidationError
    from pydantic_settings import SettingsError

    from cardflow.api.app import create_app
    from cardflow.log import configure_logging
    from cardflow.settings import Settings

    try:
        settings = Settings()
    except (ValidationError, SettingsError) as exc:
        # Settings hide input values in validation errors, so no secret is echoed here.
        sys.stderr.write(f"cardflow api: invalid configuration\n{exc}\n")
        return EXIT_CONFIG_ERROR
    configure_logging(settings.log_level, settings.log_format)
    uvicorn.run(
        create_app(settings),
        host=host,
        port=port,
        log_config=None,  # keep the JSON handler installed by configure_logging()
        access_log=False,  # access lines come from RequestContextMiddleware
        server_header=False,
    )
    return EXIT_OK


def _describe_failure(exc: BaseException) -> str:
    """One log-safe line: exception type, SQLSTATE and PostgreSQL's primary message.

    Never the full ``str(exc)``: SQLAlchemy appends statements and parameters, and the
    detail part of a PostgreSQL error can quote row values.
    """
    orig = getattr(exc, "orig", None)
    diag = getattr(orig, "diag", None)
    sqlstate = getattr(orig, "sqlstate", None)
    primary = getattr(diag, "message_primary", None)
    if sqlstate or primary:
        return f"{type(exc).__name__} [{sqlstate or '-'}] {primary or ''}".rstrip()
    from alembic.util import CommandError

    if isinstance(exc, CommandError):
        return f"{type(exc).__name__}: {exc}"
    return type(exc).__name__


def _check_revision(url: "URL") -> int:
    from sqlalchemy.pool import NullPool

    from cardflow.db.engine import create_engine
    from cardflow.db.migrations import MIGRATE_APPLICATION_NAME, migration_status

    engine = create_engine(url, application_name=MIGRATE_APPLICATION_NAME, poolclass=NullPool)
    try:
        with engine.connect() as connection:
            status = migration_status(connection)
    finally:
        engine.dispose()
    current = ",".join(status.current) or "(none)"
    heads = ",".join(status.heads)
    verdict = "up to date" if status.up_to_date else "NOT at head"
    sys.stdout.write(f"database revision {current}; code head {heads}: {verdict}\n")
    return EXIT_OK if status.up_to_date else EXIT_MIGRATE_FAILED


def _run_migrate(*, lock: bool, check: bool) -> int:
    from alembic.util import CommandError
    from pydantic import ValidationError
    from pydantic_settings import SettingsError
    from sqlalchemy.exc import SQLAlchemyError

    from cardflow.db.engine import database_url_from_settings
    from cardflow.db.migrations import upgrade
    from cardflow.log import configure_logging
    from cardflow.settings import Settings

    try:
        settings = Settings()
    except (ValidationError, SettingsError) as exc:
        sys.stderr.write(f"cardflow migrate: invalid configuration\n{exc}\n")
        return EXIT_CONFIG_ERROR
    configure_logging(settings.log_level, settings.log_format)
    url = database_url_from_settings(settings)
    try:
        if check:
            return _check_revision(url)
        upgrade(url, "head", lock=lock)
        return _check_revision(url)
    except (SQLAlchemyError, CommandError) as exc:
        sys.stderr.write(f"cardflow migrate: failed: {_describe_failure(exc)}\n")
        return EXIT_MIGRATE_FAILED


def _run_worker(*, concurrency: int, once: bool, shutdown_timeout_s: float) -> int:
    from pydantic import ValidationError
    from pydantic_settings import SettingsError

    from cardflow.jobs.worker import serve
    from cardflow.log import configure_logging
    from cardflow.settings import Settings

    try:
        settings = Settings()
    except (ValidationError, SettingsError) as exc:
        sys.stderr.write(f"cardflow worker: invalid configuration\n{exc}\n")
        return EXIT_CONFIG_ERROR
    configure_logging(settings.log_level, settings.log_format)
    return serve(
        settings, concurrency=concurrency, once=once, shutdown_timeout_s=shutdown_timeout_s
    )


def _setting_variable(field: str) -> str:
    return f"{field.upper()}_FILE"


def _run_db_provision(role_keys: Sequence[str]) -> int:
    from pydantic import ValidationError
    from pydantic_settings import SettingsError
    from sqlalchemy.exc import SQLAlchemyError
    from sqlalchemy.pool import NullPool

    from cardflow.db.engine import create_engine, database_url_from_settings
    from cardflow.db.roles import (
        LOGIN_ROLES,
        ProvisionError,
        group_role_problems,
        provision_login_role,
    )
    from cardflow.log import configure_logging
    from cardflow.settings import Settings

    try:
        settings = Settings()
    except (ValidationError, SettingsError) as exc:
        sys.stderr.write(f"cardflow db-provision: invalid configuration\n{exc}\n")
        return EXIT_CONFIG_ERROR
    configure_logging(settings.log_level, settings.log_format)
    logins = [LOGIN_ROLES[key] for key in dict.fromkeys(role_keys)]
    missing = [
        _setting_variable(login.password_setting)
        for login in logins
        if getattr(settings, login.password_setting) is None
    ]
    if missing:
        sys.stderr.write(
            f"cardflow db-provision: no password configured: set {', '.join(missing)}\n"
        )
        return EXIT_PROVISION_FAILED
    engine = create_engine(
        database_url_from_settings(settings),
        application_name="cardflow-provision",
        poolclass=NullPool,
    )
    results = []
    try:
        with engine.begin() as connection:
            problems = group_role_problems(connection)
            if problems:
                raise ProvisionError("; ".join(problems))
            results += [
                provision_login_role(
                    connection,
                    login,
                    getattr(settings, login.password_setting).get_secret_value(),
                )
                for login in logins
            ]
            problems = group_role_problems(connection)
            if problems:
                raise ProvisionError("; ".join(problems))
    except ProvisionError as exc:
        sys.stderr.write(f"cardflow db-provision: {exc}\n")
        return EXIT_PROVISION_FAILED
    except SQLAlchemyError as exc:
        sys.stderr.write(f"cardflow db-provision: failed: {_describe_failure(exc)}\n")
        return EXIT_PROVISION_FAILED
    finally:
        engine.dispose()
    for result in results:
        sys.stdout.write(result.describe() + "\n")
    return EXIT_OK


def _run_pairing_create(workspace_id: "uuid.UUID | None", ttl: "timedelta | None") -> int:
    from pydantic import ValidationError
    from pydantic_settings import SettingsError
    from sqlalchemy.exc import SQLAlchemyError
    from sqlalchemy.pool import NullPool

    from cardflow.db.engine import create_engine, database_url_from_settings
    from cardflow.identity.pairing import (
        BOOTSTRAP_WORKSPACE,
        DEFAULT_TTL,
        UnknownWorkspaceError,
        create_pairing_code,
    )
    from cardflow.log import configure_logging
    from cardflow.settings import Settings

    try:
        settings = Settings()
    except (ValidationError, SettingsError) as exc:
        sys.stderr.write(f"cardflow pairing create: invalid configuration\n{exc}\n")
        return EXIT_PAIRING_FAILED
    configure_logging(settings.log_level, settings.log_format)
    engine = create_engine(
        database_url_from_settings(settings),
        application_name="cardflow-pairing",
        poolclass=NullPool,
    )
    try:
        with engine.begin() as connection:
            created = create_pairing_code(
                connection, workspace_id=workspace_id, ttl=ttl or DEFAULT_TTL
            )
    except UnknownWorkspaceError:
        sys.stderr.write("cardflow pairing create: no live workspace with this id\n")
        return EXIT_PAIRING_FAILED
    except SQLAlchemyError as exc:
        sys.stderr.write(
            f"cardflow pairing create: failed: {_describe_failure(exc)} (connect with the "
            "migration credentials: DATABASE_URL and DATABASE_PASSWORD_FILE of the superuser)\n"
        )
        return EXIT_PAIRING_FAILED
    finally:
        engine.dispose()
    if created.purpose == BOOTSTRAP_WORKSPACE:
        purpose = f"{created.purpose} (the device registers into a new workspace as its owner)"
    else:
        purpose = f"{created.purpose} (the device registers into the workspace below)"
    sys.stdout.write(
        f"pairing code:    {created.code}\n"
        f"purpose:         {purpose}\n"
        f"workspace:       {created.workspace_id or 'new'}\n"
        f"expires at:      {created.expires_at.isoformat()}\n"
        f"pairing code id: {created.pairing_code_id}\n"
        "The code is shown only this once, stored only as a hash and works once.\n"
    )
    return EXIT_OK


def main(argv: Sequence[str] | None = None) -> int:
    """Run the ``cardflow`` command line; returns the process exit code."""
    parser = build_parser()
    # Stub commands accept and ignore the options the Compose draft passes them (e.g.
    # `backup --schedule ...`), so the operator sees the "not implemented" message.
    args, unknown = parser.parse_known_args(argv)
    if args.command not in NOT_IMPLEMENTED and unknown:
        parser.error(f"unrecognized arguments: {' '.join(unknown)}")
    if args.command == "api":
        return _run_api(args.host, args.port)
    if args.command == "migrate":
        return _run_migrate(lock=args.lock, check=args.check)
    if args.command == "db-provision":
        return _run_db_provision(args.roles or PROVISION_ROLE_CHOICES)
    if args.command == "pairing":
        return _run_pairing_create(args.workspace, args.ttl)
    if args.command == "worker":
        return _run_worker(
            concurrency=args.concurrency,
            once=args.once,
            shutdown_timeout_s=args.shutdown_timeout,
        )
    task_id, scope = NOT_IMPLEMENTED[args.command]
    sys.stderr.write(
        f"cardflow {args.command}: not implemented yet - owned by {task_id} ({scope}).\n"
    )
    return EXIT_NOT_IMPLEMENTED
