# ADR-002 后端：FastAPI 模块化单体 + SQLAlchemy 2 + Alembic + PostgreSQL 18

状态：已接受 · 2026-10-16

背景：需要 API、后台、解析/求解 worker、自托管、少量服务。
决策：Python 3.13；FastAPI 0.143 + pydantic v2；SQLAlchemy 2.1 + Alembic；psycopg 3；PostgreSQL 18.6（独立容器）；模块化单体（§4）+ 单一 worker 进程；OpenAPI 作为契约来源。
备选：Django（放弃：ORM 风格与 pydantic 契约重复）；Go（放弃：OR-Tools Python 生态与团队栈）；微服务（放弃：规模不需要）。
后果：所有模块共用一个部署单元，边界靠包结构与测试守护；求解在 worker 子进程隔离。
