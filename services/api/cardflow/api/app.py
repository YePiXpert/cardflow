"""FastAPI application factory."""

from importlib.metadata import PackageNotFoundError, version
from typing import Final

from fastapi import FastAPI
from fastapi.telemetry import TelemetryConfig

from cardflow.api.errors import install_error_handlers
from cardflow.api.middleware.request_context import RequestContextMiddleware
from cardflow.api.routes import auth, devices, health, workspace
from cardflow.settings import Settings, get_settings

# FastAPI's native OpenTelemetry hooks would record exception messages and request
# validation inputs (which can contain financial data). Keep them off until telemetry
# is an explicit, reviewed decision.
_TELEMETRY_OFF: Final[TelemetryConfig] = {
    "tracing": False,
    "metrics": False,
    "logs": False,
    "operation_spans": False,
    "auto_configure": False,
}


def _package_version() -> str:
    try:
        return version("cardflow")
    except PackageNotFoundError:
        return "0+unknown"


def create_app(settings: Settings | None = None) -> FastAPI:
    """Build the API application.

    ``settings`` defaults to :func:`cardflow.settings.get_settings` and is exposed as
    ``app.state.settings``.
    """
    resolved = settings if settings is not None else get_settings()
    # T-012: /docs, /redoc and /openapi.json exist only with API_DOCS_ENABLED=true; the
    # schema itself stays available in code through app.openapi() (admin type generation).
    docs = resolved.api_docs_enabled
    app = FastAPI(
        title="CardFlow API",
        version=_package_version(),
        telemetry=_TELEMETRY_OFF,
        openapi_url="/openapi.json" if docs else None,
        docs_url="/docs" if docs else None,
        redoc_url="/redoc" if docs else None,
    )
    app.state.settings = resolved
    install_error_handlers(app)
    app.include_router(health.router)
    # T-011: device registration and tokens (API-01/02), minimal API-03.
    app.include_router(devices.router)
    app.include_router(auth.router)
    app.include_router(workspace.router)
    # Must stay the LAST add_middleware() call (= outermost user middleware); add any
    # other middleware above this line.
    app.add_middleware(RequestContextMiddleware)
    return app
