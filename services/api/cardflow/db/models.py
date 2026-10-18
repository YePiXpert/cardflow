"""Registry of every ORM model: importing this module fills :data:`metadata`.

Alembic's ``env.py`` and the model-drift test use :data:`metadata`; application code
normally imports the model classes from their own modules (``cardflow.cards.models`` ...).
"""

from typing import Final

from sqlalchemy import MetaData

from cardflow.audit.models import AuditLog
from cardflow.cards.models import (
    Bank,
    BillingRuleVersion,
    Card,
    CardProduct,
    CreditAccount,
    CreditPool,
    CreditPoolMember,
    Currency,
    CurrencyAccount,
    LimitAdjustment,
    LimitSnapshot,
    PreauthHold,
    RuleBinding,
)
from cardflow.cash.models import (
    CashAccount,
    CashBalanceSnapshot,
    CashEvent,
    CashTransfer,
    ForecastRun,
    RecurringItem,
    Scenario,
    SnapshotIncludedEvent,
)
from cardflow.db.base import Base
from cardflow.identity.models import AuthSession, Device, PairingCode, User
from cardflow.imports.models import (
    DedupeKey,
    ExtractionCandidate,
    ImportBatch,
    ImportBatchItem,
    ParseJob,
    SourceDocument,
)
from cardflow.jobs.models import Job, WorkerHeartbeat
from cardflow.planner.models import (
    Plan,
    PlanAllocation,
    PlanInvalidation,
    PlanReservation,
    PlanRun,
    PlanRunCheck,
)
from cardflow.statements.models import (
    Charge,
    InstallmentPlan,
    InstallmentSchedule,
    ReconciliationItem,
    Repayment,
    RepaymentAllocation,
    RepaymentAllocationTotal,
    Statement,
    StatementAttribution,
    StatementLine,
    StatementVersion,
    Transaction,
    TransactionLink,
)
from cardflow.sync.models import SyncChange, SyncConflict
from cardflow.workspaces.models import (
    Consent,
    DeletionTask,
    IdempotencyKey,
    Workspace,
    WorkspaceMember,
)

metadata: Final[MetaData] = Base.metadata

__all__ = [
    "AuditLog",
    "AuthSession",
    "Bank",
    "Base",
    "BillingRuleVersion",
    "Card",
    "CardProduct",
    "CashAccount",
    "CashBalanceSnapshot",
    "CashEvent",
    "CashTransfer",
    "Charge",
    "Consent",
    "CreditAccount",
    "CreditPool",
    "CreditPoolMember",
    "Currency",
    "CurrencyAccount",
    "DedupeKey",
    "DeletionTask",
    "Device",
    "ExtractionCandidate",
    "ForecastRun",
    "IdempotencyKey",
    "ImportBatch",
    "ImportBatchItem",
    "InstallmentPlan",
    "InstallmentSchedule",
    "Job",
    "LimitAdjustment",
    "LimitSnapshot",
    "PairingCode",
    "ParseJob",
    "Plan",
    "PlanAllocation",
    "PlanInvalidation",
    "PlanReservation",
    "PlanRun",
    "PlanRunCheck",
    "PreauthHold",
    "ReconciliationItem",
    "RecurringItem",
    "Repayment",
    "RepaymentAllocation",
    "RepaymentAllocationTotal",
    "RuleBinding",
    "Scenario",
    "SnapshotIncludedEvent",
    "SourceDocument",
    "Statement",
    "StatementAttribution",
    "StatementLine",
    "StatementVersion",
    "SyncChange",
    "SyncConflict",
    "Transaction",
    "TransactionLink",
    "User",
    "WorkerHeartbeat",
    "Workspace",
    "WorkspaceMember",
    "metadata",
]
