"""Job handler registry: which code runs a job ``kind``, how, and with which limits.

Two execution modes (ADR-003, architecture §4):

* ``inline`` -- ``func(ctx: JobContext) -> result`` runs on a worker thread and may use the
  database through ``ctx.transaction()`` (workspace-bound and lease-fenced). Keep it short
  and I/O-bound; its timeout is enforced cooperatively (see :class:`cardflow.jobs.JobContext`).
* ``subprocess`` -- ``func(input) -> output`` runs in a fresh ``spawn`` child process: a
  pure function of JSON input, no database. The worker kills the child at the timeout
  (SIGTERM, then SIGKILL), so a runaway solver or parser cannot hang or bloat the worker.
  Optional hooks run in the worker process, around the child:

  - ``prepare(ctx, session) -> input`` loads what the child needs (default: the payload);
  - ``persist(ctx, session, output) -> result`` writes the child's output to business
    tables in the *same* transaction that marks the job ``succeeded`` (default: store the
    output itself as ``jobs.result``).

  ``persist`` is also available for inline handlers, for the same atomicity.

Production handlers register on :data:`REGISTRY` with :func:`register` in a module listed
in :data:`HANDLER_MODULES`; :func:`production_registry` imports those modules. Test and demo
kinds are registered on their own :class:`Registry` instances only.
"""

import importlib
import re
from collections.abc import Callable, Iterable, Iterator
from dataclasses import dataclass
from enum import StrEnum
from typing import TYPE_CHECKING, Any, Final

if TYPE_CHECKING:
    from sqlalchemy.orm import Session

    from cardflow.jobs.context import JobContext

KIND_PATTERN: Final = re.compile(r"[a-z][a-z0-9_]{0,31}(?:\.[a-z][a-z0-9_]{0,31}){0,3}")
"""``module.action`` style kinds, e.g. ``plan.solve``, ``imports.parse``."""
MAX_TIMEOUT_S: Final = 24 * 3600

HANDLER_MODULES: Final[tuple[str, ...]] = ()
"""Modules that register production handlers on import (T-009: planner solve, T-030: parse).

The worker's maintenance (lease reclaim, heartbeat cleanup) runs as periodic system tasks
(:mod:`cardflow.jobs.periodic`), not as queued jobs, so this is empty until those land.
"""

type InlineHandler = Callable[[JobContext], object]
type SubprocessHandler = Callable[[Any], object]
type PrepareHook = Callable[[JobContext, Session], object]
type PersistHook = Callable[[JobContext, Session, Any], object]


class Mode(StrEnum):
    """Where a handler runs."""

    INLINE = "inline"
    SUBPROCESS = "subprocess"


def check_kind(kind: object) -> str:
    """Return ``kind`` if it is a valid job kind, else raise :class:`ValueError`."""
    if not isinstance(kind, str) or KIND_PATTERN.fullmatch(kind) is None:
        raise ValueError("job kind must look like 'module.action' ([a-z][a-z0-9_]* segments)")
    return kind


def _positive_int(name: str, value: object, maximum: int | None = None) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        raise ValueError(f"{name} must be an integer >= 1")
    if maximum is not None and value > maximum:
        raise ValueError(f"{name} must be <= {maximum}")
    return value


def resolve_target(module: str, qualname: str) -> object:
    """Import ``module`` and return the attribute at ``qualname`` (``Class.method`` allowed)."""
    target: object = importlib.import_module(module)
    for part in qualname.split("."):
        target = getattr(target, part)
    return target


@dataclass(frozen=True, slots=True)
class HandlerSpec:
    """A registered handler and its limits."""

    kind: str
    mode: Mode
    func: Callable[..., object]
    timeout_s: int
    """Default timeout of one attempt; ``enqueue(timeout_s=...)`` overrides it per job."""
    max_attempts: int
    """Default ``jobs.max_attempts`` written by :func:`cardflow.jobs.enqueue`."""
    concurrency: int | None = None
    """At most this many jobs of the kind run at once in one worker (None: no extra limit)."""
    prepare: PrepareHook | None = None
    persist: PersistHook | None = None

    @property
    def target(self) -> tuple[str, str]:
        """``(module, qualname)`` the subprocess child imports to find :attr:`func`."""
        return self.func.__module__, self.func.__qualname__


class Registry:
    """Mapping ``kind`` -> :class:`HandlerSpec`."""

    def __init__(self, specs: Iterable[HandlerSpec] = ()) -> None:
        """Start with ``specs`` (e.g. ``Registry(production_registry().specs())``)."""
        self._specs: dict[str, HandlerSpec] = {}
        for spec in specs:
            self.add(spec)

    def add(self, spec: HandlerSpec) -> None:
        """Add a validated spec; a kind can be registered only once."""
        check_kind(spec.kind)
        if spec.kind in self._specs:
            raise ValueError(f"job kind {spec.kind!r} is already registered")
        self._specs[spec.kind] = spec

    def register[F: Callable[..., object]](
        self,
        kind: str,
        *,
        mode: Mode | str,
        timeout_s: int,
        max_attempts: int,
        concurrency: int | None = None,
        prepare: PrepareHook | None = None,
        persist: PersistHook | None = None,
    ) -> Callable[[F], F]:
        """Decorator registering ``func`` as the handler of ``kind``; returns ``func`` as is.

        ``timeout_s`` (1 s .. 24 h) is the default per-attempt limit, ``max_attempts`` the
        default number of attempts (first run included) before the job goes ``dead``,
        ``concurrency`` the per-worker limit for this kind. ``prepare`` is only meaningful
        for subprocess handlers. A subprocess handler must be a module-level function (the
        child imports it by module and qualified name).
        """
        mode = Mode(mode)
        check_kind(kind)
        _positive_int("timeout_s", timeout_s, MAX_TIMEOUT_S)
        _positive_int("max_attempts", max_attempts)
        if concurrency is not None:
            _positive_int("concurrency", concurrency)
        if prepare is not None and mode is not Mode.SUBPROCESS:
            raise ValueError("prepare= is only supported for subprocess handlers")

        def decorator(func: F) -> F:
            if not callable(func):
                raise TypeError("a job handler must be callable")
            spec = HandlerSpec(
                kind=kind,
                mode=mode,
                func=func,
                timeout_s=timeout_s,
                max_attempts=max_attempts,
                concurrency=concurrency,
                prepare=prepare,
                persist=persist,
            )
            if mode is Mode.SUBPROCESS:
                _check_importable(spec)
            self.add(spec)
            return func

        return decorator

    def get(self, kind: str) -> HandlerSpec | None:
        """The spec of ``kind``, or ``None``."""
        return self._specs.get(kind)

    def __getitem__(self, kind: str) -> HandlerSpec:
        """The spec of ``kind``; :class:`KeyError` if unknown."""
        return self._specs[kind]

    def __contains__(self, kind: object) -> bool:
        """True if ``kind`` is registered."""
        return kind in self._specs

    def __iter__(self) -> Iterator[str]:
        """Registered kinds, in registration order."""
        return iter(self._specs)

    def __len__(self) -> int:
        """Number of registered kinds."""
        return len(self._specs)

    def kinds(self) -> tuple[str, ...]:
        """Registered kinds, sorted."""
        return tuple(sorted(self._specs))

    def specs(self) -> tuple[HandlerSpec, ...]:
        """All specs, in registration order."""
        return tuple(self._specs.values())


def _check_importable(spec: HandlerSpec) -> None:
    module, qualname = spec.target
    if "<" in qualname:
        raise ValueError(
            f"subprocess handler for {spec.kind!r} must be a module-level function, "
            "not a lambda or nested function"
        )
    try:
        found = resolve_target(module, qualname)
    except (ImportError, AttributeError):
        found = None
    if found is not spec.func:
        raise ValueError(
            f"subprocess handler for {spec.kind!r} is not importable as {module}:{qualname}"
        )


REGISTRY: Final = Registry()
"""The production registry: system and business handlers only, never test kinds."""

register: Final = REGISTRY.register
"""``@register("plan.solve", mode="subprocess", ...)`` for production handler modules."""


def production_registry() -> Registry:
    """Import every module in :data:`HANDLER_MODULES` and return :data:`REGISTRY`."""
    for name in HANDLER_MODULES:
        importlib.import_module(name)
    return REGISTRY
