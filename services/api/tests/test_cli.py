"""``cardflow`` command line: argument handling (DB-backed ``migrate`` runs: tests/db)."""

import logging
import subprocess
import sys
from collections.abc import Iterator
from pathlib import Path

import pytest

from cardflow.cli import (
    EXIT_CONFIG_ERROR,
    EXIT_MIGRATE_FAILED,
    EXIT_NOT_IMPLEMENTED,
    EXIT_PROVISION_FAILED,
    EXIT_WORKER_FAILED,
    NOT_IMPLEMENTED,
    build_parser,
    main,
)


@pytest.mark.parametrize(
    ("argv", "task_id"),
    [
        (["backup"], "T-013"),
        (["backup", "--schedule", "0 3 * * *"], "T-013"),
    ],
)
def test_unimplemented_commands_exit_2_and_name_owner(
    argv: list[str], task_id: str, capsys: pytest.CaptureFixture[str]
) -> None:
    assert main(argv) == EXIT_NOT_IMPLEMENTED == 2

    captured = capsys.readouterr()
    assert captured.out == ""
    assert "not implemented yet" in captured.err
    assert task_id in captured.err


def test_console_script_backup_exits_2() -> None:
    script = Path(sys.executable).with_name("cardflow")

    result = subprocess.run([script, "backup"], capture_output=True, text=True, check=False)  # noqa: S603

    assert result.returncode == 2
    assert "T-013" in result.stderr


def test_db_provision_arguments() -> None:
    """T-006: ``--role`` is repeatable and limited to the three login roles."""
    assert build_parser().parse_args(["db-provision"]).roles is None
    args = build_parser().parse_args(["db-provision", "--role", "api", "--role", "admin"])
    assert args.roles == ["api", "admin"]
    with pytest.raises(SystemExit) as excinfo:
        main(["db-provision", "--role", "root"])
    assert excinfo.value.code == 2


def test_db_provision_without_passwords_exits_1_naming_the_variables(
    clean_settings_env: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    restore_root_logging: None,
) -> None:
    """No database is contacted when a login role has no password configured."""
    del clean_settings_env, restore_root_logging
    assert main(["db-provision", "--role", "worker"]) == EXIT_PROVISION_FAILED == 1

    captured = capsys.readouterr()
    assert "DATABASE_WORKER_PASSWORD_FILE" in captured.err
    assert "DATABASE_API_PASSWORD_FILE" not in captured.err


def test_worker_is_implemented() -> None:
    """T-008 replaced the stub; DB-backed runs are in tests/jobs/test_cli_worker.py."""
    assert "worker" not in NOT_IMPLEMENTED
    args = build_parser().parse_args(["worker"])
    assert (args.concurrency, args.once, args.shutdown_timeout) == (2, False, 20.0)
    args = build_parser().parse_args(
        ["worker", "--concurrency", "4", "--once", "--shutdown-timeout", "7.5"]
    )
    assert (args.concurrency, args.once, args.shutdown_timeout) == (4, True, 7.5)


@pytest.mark.parametrize(
    "argv",
    [
        ["worker", "--concurrency", "0"],
        ["worker", "--concurrency", "11"],
        ["worker", "--concurrency", "two"],
        ["worker", "--shutdown-timeout", "-1"],
        ["worker", "--shutdown-timeout", "nan"],
        ["worker", "--shutdown-timeout", "3601"],
        ["worker", "--bogus"],
        ["worker", "extra"],
    ],
)
def test_worker_rejects_bad_arguments(argv: list[str]) -> None:
    with pytest.raises(SystemExit) as excinfo:
        main(argv)

    assert excinfo.value.code == 2


def test_worker_with_invalid_configuration_exits_1_without_echoing_secret(
    clean_settings_env: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    clean_settings_env.setenv("DATABASE_URL", "postgresql://cardflow:pw-in-url-8d2@db/cardflow")

    assert main(["worker", "--once"]) == EXIT_CONFIG_ERROR == EXIT_WORKER_FAILED

    captured = capsys.readouterr()
    assert "cardflow worker: invalid configuration" in captured.err
    assert "pw-in-url-8d2" not in captured.out + captured.err


def test_api_rejects_unknown_arguments() -> None:
    with pytest.raises(SystemExit) as excinfo:
        main(["api", "--bogus"])

    assert excinfo.value.code == 2


def test_api_with_invalid_configuration_exits_1_without_echoing_secret(
    clean_settings_env: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    clean_settings_env.setenv("KEK", "short-kek-value-1")

    assert main(["api"]) == EXIT_CONFIG_ERROR

    captured = capsys.readouterr()
    assert "invalid configuration" in captured.err
    assert "short-kek-value-1" not in captured.err


def test_migrate_is_implemented() -> None:
    assert "migrate" not in NOT_IMPLEMENTED


@pytest.mark.parametrize(
    "argv",
    [["migrate", "--lock", "--check"], ["migrate", "--bogus"], ["migrate", "head"]],
)
def test_migrate_rejects_bad_arguments(argv: list[str]) -> None:
    with pytest.raises(SystemExit) as excinfo:
        main(argv)

    assert excinfo.value.code == 2


def test_migrate_with_invalid_configuration_exits_1_without_echoing_secret(
    clean_settings_env: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    clean_settings_env.setenv("DATABASE_URL", "postgresql://cardflow:pw-in-url-31f@db/cardflow")

    assert main(["migrate", "--check"]) == EXIT_CONFIG_ERROR

    captured = capsys.readouterr()
    assert "invalid configuration" in captured.err
    assert "pw-in-url-31f" not in captured.err


def test_migrate_check_with_unreachable_database_exits_1_without_echoing_secret(
    clean_settings_env: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    restore_root_logging: None,
) -> None:
    # Port 1 on the loopback interface: nothing listens there, the connect fails at once.
    clean_settings_env.setenv("DATABASE_URL", "postgresql+psycopg://cardflow@127.0.0.1:1/cardflow")
    clean_settings_env.setenv("DATABASE_PASSWORD", "db-pw-unreachable-77c")

    assert main(["migrate", "--check"]) == EXIT_MIGRATE_FAILED == 1

    captured = capsys.readouterr()
    assert "cardflow migrate: failed: OperationalError" in captured.err
    assert "db-pw-unreachable-77c" not in captured.out + captured.err


@pytest.fixture
def restore_root_logging() -> Iterator[None]:
    """``cardflow migrate`` installs its own root log handler; undo that after the test."""
    root = logging.getLogger()
    handlers, level = list(root.handlers), root.level
    yield
    root.handlers[:] = handlers
    root.setLevel(level)
