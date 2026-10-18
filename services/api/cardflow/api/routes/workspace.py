"""API-03 (minimal): ``GET /v1/workspace`` -- the caller's workspace, id and kind only.

The smallest protected endpoint (T-011): it proves the authentication dependency and the
workspace binding end to end and serves later tasks' tests. Consents (``PUT
/v1/workspace/consents``) come later.
"""

import uuid
from typing import Literal

from fastapi import APIRouter, Request
from pydantic import BaseModel
from sqlalchemy import select

from cardflow.api.deps import Authenticated, session_factory
from cardflow.api.errors import ApiError, ErrorCode
from cardflow.db import workspace_tx
from cardflow.workspaces.models import Workspace

router = APIRouter(prefix="/v1", tags=["workspace"])


class WorkspaceResponse(BaseModel):
    """The caller's workspace."""

    id: uuid.UUID
    kind: Literal["real", "demo"]


@router.get("/workspace", response_model=WorkspaceResponse, summary="Current workspace (API-03)")
def get_workspace(request: Request, auth: Authenticated) -> WorkspaceResponse:
    """Id and kind of the workspace the access token belongs to."""
    table = Workspace.__table__
    with workspace_tx(session_factory(request), auth.workspace_id) as session:
        row = session.execute(
            select(table.c.id, table.c.kind).where(table.c.id == auth.workspace_id)
        ).one_or_none()
    if row is None:
        raise ApiError(404, ErrorCode.NOT_FOUND, "Workspace not found")
    return WorkspaceResponse(id=row.id, kind=row.kind)
