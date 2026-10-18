# 41 · API 契约（/v1）

版本 0.1 · 2026-10-16。OpenAPI 由 FastAPI 生成并作为契约事实；本文定义约定、端点清单、关键载荷与错误码。所有金额为最小单位整数 + 币种；所有时间为 ISO-8601 带时区。

## 1. 通用约定

| 项 | 约定 |
|---|---|
| 鉴权 | `Authorization: Bearer <access_token>`；设备注册后签发；刷新令牌轮换；撤销即失效 |
| 工作空间 | `X-Workspace-Id` 头；服务端校验成员资格后 `SET LOCAL app.workspace_id` |
| 幂等 | 所有写操作要求 `Idempotency-Key`（UUID）；同键同请求哈希→返回首次响应；同键不同哈希→409 `IDEMPOTENCY_MISMATCH` |
| 并发 | 更新携带 `row_version`；不匹配→409 `VERSION_CONFLICT`（金额/日期/状态字段）或自动合并（非敏感字段） |
| 分页 | 游标分页：`?limit=50&cursor=<opaque>`；响应 `next_cursor` |
| 过滤 | `?from=&to=&account_id=&status=`；时间按业务时区解释，返回 UTC |
| 错误 | `{ "error": { "code": "...", "message": "...", "details": {...}, "request_id": "..." } }` |
| 异步 | 长任务返回 202 + `{ "job_id" }`；`GET /v1/jobs/{id}` 轮询；状态 queued/running/succeeded/failed/dead |
| 版本 | 路径 `/v1`；破坏性变更→`/v2`；客户端最低版本在 `/v1/meta` |
| 速率 | 每设备 600 req/10 min；求解 30/10 min；解析上传 20/10 min |
| 演示 | demo 工作空间拒绝 `/sync/*` 与 `/export` 到真实空间 |

错误码：`VALIDATION_ERROR`、`UNAUTHORIZED`、`FORBIDDEN`、`NOT_FOUND`、`VERSION_CONFLICT`、`IDEMPOTENCY_MISMATCH`、`NEEDS_DATA`、`BASELINE_SHORTFALL`、`RULE_INVALID`、`DUPLICATE_DOCUMENT`、`FILE_REJECTED`、`PARSE_TIMEOUT`、`SOLVER_UNKNOWN`、`SOLVER_INFEASIBLE`、`MODEL_INVALID`、`RATE_LIMITED`、`DEMO_RESTRICTED`、`CONSENT_REQUIRED`。

## 2. 端点清单

| ID | 方法 | 路径 | 权限 | 幂等 | 异步 | 说明 |
|---|---|---|---|---|---|---|
| API-01 | POST | /v1/devices/register | 公开（配对码） | 是 | 否 | 设备注册，返回令牌 |
| API-02 | POST | /v1/auth/refresh · /v1/auth/revoke | 设备 | 是 | 否 | 令牌轮换/撤销 |
| API-03 | GET/PUT | /v1/workspace · /v1/workspace/consents | 成员 | PUT 是 | 否 | 工作空间与隐私授权 |
| API-10 | GET/POST | /v1/credit-accounts | 成员 | 是 | 否 | 建信用账户（含默认币种子账户） |
| API-11 | GET/PATCH | /v1/credit-accounts/{id} | 成员 | 是 | 否 | 状态、业务时区、池归属 |
| API-12 | POST | /v1/credit-accounts/{id}/cards · PATCH /v1/cards/{id} | 成员 | 是 | 否 | 建卡/换卡/销卡 |
| API-13 | POST | /v1/currency-accounts/{id}/limit-snapshots | 成员 | 是 | 否 | 额度快照（可负） |
| API-14 | GET/POST | /v1/credit-accounts/{id}/billing-rules | 成员 | 是 | 否 | 用户声明规则版本；`?effective_on=` |
| API-15 | GET | /v1/rule-templates?bank=&product= | 成员 | — | 否 | 官方模板（后台维护） |
| API-20 | POST | /v1/documents | 成员 | 是 | 否 | 上传附件（multipart，≤25 MB，类型嗅探）；重复指纹→200 已存在 |
| API-21 | POST | /v1/imports | 成员 | 是 | 是 | 创建导入批次并入队解析 |
| API-22 | GET | /v1/imports/{id} | 成员 | — | 否 | 批次状态、候选字段、置信度、原始位置 |
| API-23 | POST | /v1/imports/{id}/review | 成员 | 是 | 否 | 提交逐字段确认与映射 |
| API-24 | POST | /v1/imports/{id}/confirm | 成员 | 是 | 否 | 去重后入账；返回生成实体与差异项 |
| API-25 | POST | /v1/imports/{id}/rollback | 成员 | 是 | 否 | 撤销入账（tombstone + 审计） |
| API-30 | GET/POST | /v1/transactions | 成员 | 是 | 否 | 列表/手工录入 |
| API-31 | GET | /v1/statements?currency_account_id= · /v1/statements/{id} | 成员 | — | 否 | 账单与版本 |
| API-32 | POST | /v1/statements/{id}/versions | 成员 | 是 | 否 | 新版本（人工修正留痕） |
| API-33 | POST | /v1/repayments · PATCH /v1/repayments/{id}/status | 成员 | 是 | 否 | 登记还款；状态推进需证据字段 |
| API-34 | POST | /v1/repayments/{id}/allocations | 成员 | 是 | 否 | 跨账单分配 |
| API-35 | GET/POST | /v1/reconciliation-items · /{id}/resolve | 成员 | 是 | 否 | 差异清单与处理 |
| API-36 | POST | /v1/transactions/{id}/installment-plan | 成员 | 是 | 否 | 分期计划与期次 |
| API-40 | GET/POST | /v1/cash-accounts · /{id}/snapshots · /{id}/events | 成员 | 是 | 否 | 现金账户、快照（含 included_event_ids）、事件 |
| API-41 | GET/POST | /v1/scenarios | 成员 | 是 | 否 | 情景定义 |
| API-42 | POST | /v1/forecasts | 成员 | 是 | 否（≤1 s） | 现金预测；返回逐账户时间线、缺口点、假设 |
| API-50 | POST | /v1/plans | 成员 | 是 | 否 | 创建计划（输入校验） |
| API-51 | POST | /v1/plans/{id}/solve | 成员 | 是 | 是 | 入队求解；`profile`、`decision_scenario_id`、`time_limit_s` |
| API-52 | GET | /v1/plans/{id}/runs · /v1/plan-runs/{run_id} | 成员 | — | 否 | 运行记录、分配、验证、拒绝原因、敏感性 |
| API-53 | POST | /v1/plan-runs/{run_id}/adopt | 成员 | 是 | 否 | 采纳→创建预留 |
| API-54 | POST | /v1/plans/{id}/link-transaction | 成员 | 是 | 否 | 关联真实交易→转换预留 |
| API-55 | POST | /v1/plans/{id}/invalidate · /cancel | 成员 | 是 | 否 | 失效/取消（释放预留） |
| API-60 | GET | /v1/promotions?bank=&status= · /{id} | 成员 | — | 否 | 活动与当前规则版本 |
| API-61 | POST | /v1/promotions/import | 成员 | 是 | 是 | 用户分享链接/粘贴条款/截图→创建待复核活动 |
| API-62 | POST | /v1/promotions/{id}/enroll · PATCH /v1/enrollments/{id} | 成员 | 是 | 否 | 报名状态（user_confirmed）与证据 |
| API-63 | GET | /v1/enrollments/{id}/progress | 成员 | — | 否 | 进度、估计奖励、未知项 |
| API-64 | POST | /v1/enrollments/{id}/rewards/claim · /confirm-posted | 成员 | 是 | 否 | 领取确认 / 到账核对（关联交易） |
| API-70 | GET/POST | /v1/benefits · /v1/benefit-grants/{id}/usages | 成员 | 是 | 否 | 权益与使用/取消/恢复 |
| API-71 | GET/POST | /v1/points/batches · /events | 成员 | 是 | 否 | 积分批次与事件 |
| API-72 | GET/POST | /v1/annual-fees/cycles | 成员 | 是 | 否 | 年费周期与达标进度 |
| API-80 | GET/PUT | /v1/notification-rules · GET /v1/notifications | 成员 | 是 | 否 | 提醒规则与消息中心 |
| API-90 | POST | /v1/sync/push | 设备 | 是（每项） | 否 | 批量推送 outbox；返回 acked/conflicts |
| API-91 | GET | /v1/sync/pull?cursor= | 设备 | — | 否 | 自游标后的变更（含 tombstone） |
| API-92 | GET/POST | /v1/sync/conflicts · /{id}/resolve | 成员 | 是 | 否 | 冲突列表与解决 |
| API-93 | POST | /v1/export | 成员 | 是 | 是 | 导出（CSV/JSON，加密 zip） |
| API-94 | POST | /v1/workspace/delete | owner | 是 | 是 | 删除任务（宽限期） |
| API-95 | GET | /v1/jobs/{id} · /v1/meta · /healthz · /readyz | 各 | — | 否 | 任务状态、元信息、健康 |
| API-A1 | * | /admin/api/rules/* · /promotions/* · /templates/* · /jobs/* · /audit · /backups · /users | 后台角色 | 是 | 部分 | 后台（RBAC；operator 无账单正文） |

## 3. 关键载荷

### API-51 求解请求 / API-52 响应（节选）
```json
POST /v1/plans/{id}/solve
{ "profile": "cash_safety", "decision_scenario_id": "…", "time_limit_s": 10, "reserve_override_minor": null }
→ 202 { "job_id": "…", "run_id": "…" }

GET /v1/plan-runs/{run_id}
{
  "run_id": "…", "solver_status": "OPTIMAL", "business_status": "CONDITIONALLY_FEASIBLE",
  "allocation": [ { "card_id": "A", "amount_minor": 800000, "statement_date": "2026-11-10", "due_date": "2026-11-28",
                    "repay_on": "2026-11-28", "repay_from_cash_account_id": "…", "buffer_days": 43,
                    "fee_minor": 0, "verified_benefit_minor": 0, "potential_benefit_minor": 0,
                    "cycle_assumptions": ["posting delay 0d -> posting 2026-10-16"], "alternative_cycles": [] } ],
  "verification": { "weighted_buffer_days": "42.4",
                    "checks": { "baseline": { "ok": true, "min_balance_by_account": { "cash-main": 300000 }, "breaches": [] },
                                "confirmed": { "ok": false, "breaches": [ { "on": "2026-11-08", "balance": -200000, "gap_to_zero": 200000, "gap_to_reserve": 400000 } ] },
                                "stress_income_delay": { "ok": false, "breaches": [ { "on": "2026-11-28", "balance": -200000, "gap_to_zero": 200000, "gap_to_reserve": 400000 } ] } } },
  "failing_scenarios": ["confirmed", "stress_income_delay"],
  "rejections": [ { "card_id": "B", "reason": "CASH_BREACH_ALONE", "first_breach": { "on": "2026-11-08", "balance": -350000 } } ],
  "sensitivity": { "stress_income_delay": { "min_extra_confirmed_cash": { "total": 400000 }, "max_affordable_amount": { "amount": 600000 }, "first_feasible_date_shift": { "shift_days": 5, "txn_date": "2026-10-21" } } },
  "assumptions": [], "input_hash": "…", "model_version": "1.1.0", "solver_version": "9.15.6755", "protocol_version": "1", "diagnostics": null,
  "time_limit_s": 10, "wall_time_s": 0.012, "created_at": "…"
}
```

### API-90 同步推送
```json
POST /v1/sync/push  { "device_id": "…", "ops": [ { "idempotency_key": "…", "local_seq": 120, "table": "repayments", "op": "update", "row_id": "…", "base_version": 3, "payload": { … } } ] }
→ 200 { "acked": [ { "local_seq": 120, "row_version": 4 } ], "conflicts": [ { "local_seq": 121, "conflict_id": "…", "fields": ["amount_minor"] } ], "server_cursor": 98213 }
```

### API-24 导入确认
```json
POST /v1/imports/{id}/confirm  { "decisions": [ { "item_id": "…", "decision": "new" }, { "item_id": "…", "decision": "duplicate", "duplicate_of": "…" } ] }
→ 200 { "statement_version_id": "…", "transactions_created": 12, "transactions_deduplicated": 3, "reconciliation_items": [ { "kind": "amount_mismatch", "id": "…" } ] }
```

### API-33 还款状态推进
```json
PATCH /v1/repayments/{id}/status  { "status": "bank_confirmed", "bank_confirmed_at": "2026-11-29T02:00:00Z", "evidence_document_id": "…", "row_version": 2 }
→ 400 VALIDATION_ERROR 若无证据字段；→ 409 VERSION_CONFLICT 若版本不符
```

## 4. 后台接口要点（API-A1）

- RBAC：owner/admin 全部；operator 仅规则、活动、模板、任务重试、系统状态；auditor 只读审计。
- 所有后台写操作记录审计（actor、动作、目标、前后哈希、IP）。
- 用户数据接口只返回元数据（计数、状态、时间），不返回账单正文、交易明细、附件内容。
- 备份接口触发备份任务并返回清单与校验摘要；恢复演练接口在隔离库执行并产出报告。

## 5. 兼容性矩阵

| 客户端版本 | API | 说明 |
|---|---|---|
| 1.x | /v1 | `/v1/meta.min_client_version` 低于当前时客户端提示升级；服务端对旧字段保持 6 个月兼容 |
