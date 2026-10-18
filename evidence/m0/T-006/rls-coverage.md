# T-006 · RLS 覆盖清单（表 → RLS 状态 → 策略 → 授权）

由 `evidence/m0/T-006/commands.sh` 在临时库（迁移到 head 0003，生成后删除）上读取系统目录生成，2026-10-17T22:31:20Z。权限取 `has_column_privilege` / `has_table_privilege`（即实际生效的权限）。

图例：S/I/U = SELECT/INSERT/UPDATE；整表授权只写字母，列级授权写“字母(已授列数/总列数)”；D = DELETE；– = 无任何权限。所有角色在所有表上都没有 TRUNCATE（生成时已断言）。RLS 列：E = ENABLE，F = FORCE。策略的角色缩写：app=cardflow_app、worker=cardflow_worker、admin=cardflow_admin、purge=cardflow_purge、admin_views=cardflow_admin_views。

## 1. 逐表总览

| 表 | RLS | 策略（命令 → 角色） | app | worker | admin | purge | admin_views |
|---|---|---|---|---|---|---|---|
| `alembic_version` | 无 | （无策略） | S | S | S | – | S |
| `audit_log` | EF | `audit_append` INSERT → app, worker<br>`audit_review` SELECT → admin | I(10/11) | I(10/11) | S | – | – |
| `auth_sessions` | EF | `admin_views_read` SELECT → admin_views<br>`workspace_isolation` ALL → app, purge | S I U(3/10) | – | – | S D | S(5/10) |
| `banks` | EF | `template_maintenance` ALL → admin<br>`template_read` SELECT → app, worker<br>`workspace_isolation` ALL → app, purge, worker | S I U(6/11) | S I U(6/11) | S I U(5/11) | S D | – |
| `billing_rule_versions` | EF | `template_maintenance` ALL → admin<br>`template_read` SELECT → app, worker<br>`workspace_isolation` ALL → app, purge, worker | S I U(19/27) | S I U(19/27) | S I U(18/27) | S D | – |
| `card_products` | EF | `template_maintenance` ALL → admin<br>`template_read` SELECT → app, worker<br>`workspace_isolation` ALL → app, purge, worker | S I U(5/11) | S I U(5/11) | S I U(4/11) | S D | – |
| `cards` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(9/14) | S I U(9/14) | – | S D | – |
| `cash_accounts` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(7/12) | S I U(7/12) | – | S D | – |
| `cash_balance_snapshots` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(1/13) | S I U(1/13) | – | S D | – |
| `cash_events` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(13/19) | S I U(13/19) | – | S D | – |
| `cash_transfers` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(7/14) | S I U(7/14) | – | S D | – |
| `charges` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(10/17) | S I U(10/17) | – | S D | – |
| `consents` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(5/10) | S | – | S D | – |
| `credit_accounts` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(8/13) | S I U(8/13) | – | S D | – |
| `credit_pool_members` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(2/8) | S I U(2/8) | – | S D | – |
| `credit_pools` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(4/9) | S I U(4/9) | – | S D | – |
| `currencies` | 无 | （无策略） | S | S | S | – | – |
| `currency_accounts` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(3/9) | S I U(3/9) | – | S D | – |
| `dedupe_keys` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(2/5) | S I U(2/5) | – | S D | – |
| `deletion_tasks` | EF | `admin_views_read` SELECT → admin_views<br>`workspace_isolation` ALL → app, worker | S I U(1/6) | S U(2/6) | – | – | S |
| `devices` | EF | `admin_views_read` SELECT → admin_views<br>`workspace_isolation` ALL → app, purge, worker | S I U(3/9) | S | – | S D | S(7/9) |
| `extraction_candidates` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(4/14) | S I U(4/14) | – | S D | – |
| `forecast_runs` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(2/15) | S I U(2/15) | – | S D | – |
| `idempotency_keys` | EF | `workspace_isolation` ALL → app, purge | S I | – | – | S D | – |
| `import_batch_items` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(7/12) | S I U(7/12) | – | S D | – |
| `import_batches` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(8/12) | S I U(8/12) | – | S D | – |
| `installment_plans` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(10/15) | S I U(10/15) | – | S D | – |
| `installment_schedule` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(7/13) | S I U(7/13) | – | S D | – |
| `jobs` | EF | `admin_views_read` SELECT → admin_views<br>`jobs_admin_read` SELECT → admin<br>`jobs_app_enqueue` INSERT → app<br>`jobs_app_read` SELECT → app<br>`jobs_worker` ALL → worker | S I(8/18) | S I(8/18) U(10/18) | S(16/18) | – | S(6/18) |
| `limit_adjustments` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(12/18) | S I U(12/18) | – | S D | – |
| `limit_snapshots` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(1/21) | S I U(1/21) | – | S D | – |
| `parse_jobs` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(10/14) | S I U(10/14) | – | S D | – |
| `plan_allocations` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(1/22) | S I U(1/22) | – | S D | – |
| `plan_invalidations` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(2/12) | S I U(2/12) | – | S D | – |
| `plan_reservations` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(6/15) | S I U(6/15) | – | S D | – |
| `plan_run_checks` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(1/14) | S I U(1/14) | – | S D | – |
| `plan_runs` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(1/25) | S I U(1/25) | – | S D | – |
| `plans` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(13/19) | S I U(13/19) | – | S D | – |
| `preauth_holds` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(14/22) | S I U(14/22) | – | S D | – |
| `reconciliation_items` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(7/15) | S I U(7/15) | – | S D | – |
| `recurring_items` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(9/14) | S I U(9/14) | – | S D | – |
| `repayment_allocation_totals` | EF | `workspace_isolation` ALL → app, purge, worker | S | S | – | S D | – |
| `repayment_allocations` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(3/10) | S I U(3/10) | – | S D | – |
| `repayments` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(14/21) | S I U(14/21) | – | S D | – |
| `rule_bindings` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(4/11) | S I U(4/11) | – | S D | – |
| `scenarios` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(10/15) | S I U(10/15) | – | S D | – |
| `snapshot_included_events` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(2/9) | S I U(2/9) | – | S D | – |
| `source_documents` | EF | `admin_views_read` SELECT → admin_views<br>`workspace_isolation` ALL → app, purge, worker | S I U(5/14) | S I U(5/14) | – | S D | S(3/14) |
| `statement_attributions` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(3/11) | S I U(3/11) | – | S D | – |
| `statement_lines` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(1/17) | S I U(1/17) | – | S D | – |
| `statement_versions` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(1/24) | S I U(1/24) | – | S D | – |
| `statements` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(6/11) | S I U(6/11) | – | S D | – |
| `sync_changes` | EF | `admin_views_read` SELECT → admin_views<br>`workspace_isolation` ALL → app, purge, worker | S I(7/10) | S I(7/10) | – | S D | S(3/10) |
| `sync_conflicts` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(3/14) | S I U(3/14) | – | S D | – |
| `transaction_links` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(3/11) | S I U(3/11) | – | S D | – |
| `transactions` | EF | `workspace_isolation` ALL → app, purge, worker | S I U(20/28) | S I U(20/28) | – | S D | – |
| `users` | EF | `admin_views_read` SELECT → admin_views<br>`user_registration` INSERT → app<br>`user_self_update` UPDATE → app<br>`user_visibility` SELECT → app, worker | S I U(5/8) | S | – | – | S(4/8) |
| `worker_heartbeats` | 无 | （无策略） | S | S I U(2/7) D | S | – | S(1/7) |
| `workspace_members` | EF | `admin_views_read` SELECT → admin_views<br>`workspace_isolation` ALL → app, purge, worker | S I U(2/6) D | S | – | S D | S(2/6) |
| `workspaces` | EF | `admin_views_read` SELECT → admin_views<br>`workspace_isolation` ALL → app, purge, worker | S I U(2/6) | S U(2/6) | – | S D | S(5/6) |

无 RLS 的表只有 `currencies`、`worker_heartbeats`、`alembic_version`（无 workspace_id 的全局/系统表，理由见 rls-design.md §3.6；`tests/db/test_rls_grants.py` 的 NO_RLS_TABLES 逐一列出，新表漏加 RLS 会让测试失败）。

## 2. 列级授权明细

### cardflow_app

- `audit_log` INSERT: id, workspace_id, actor_kind, actor_id, action, target_table, target_id, before_hash, after_hash, ip
- `auth_sessions` UPDATE: last_used_at, revoked_at, revoked_reason
- `banks` UPDATE: name, country, business_tz_default, source, deleted_at, origin_device_id
- `billing_rule_versions` UPDATE: statement_day, statement_day_inclusive, due_kind, due_day, due_month_offset, due_days, due_day_kind, holiday_rollover, cutoff_time, cutoff_tz, source, published_on, effective_from, effective_to, verified_on, review_status, exceptions, deleted_at, origin_device_id
- `card_products` UPDATE: name, network, source, deleted_at, origin_device_id
- `cards` UPDATE: last4, network, holder_kind, status, expires_ym, replaced_by_card_id, alias, deleted_at, origin_device_id
- `cash_accounts` UPDATE: name, kind, usable_for_repayment, available_from, reserve_floor_minor, deleted_at, origin_device_id
- `cash_balance_snapshots` UPDATE: deleted_at
- `cash_events` UPDATE: event_on, event_at, amount_minor, cls, category, label, posting_status, recurring_item_id, linked_repayment_id, linked_plan_run_id, deleted_at, origin_device_id, event_tz
- `cash_transfers` UPDATE: amount_minor, sent_on, arrives_on, out_event_id, in_event_id, deleted_at, origin_device_id
- `charges` UPDATE: statement_id, transaction_id, kind, amount_minor, charged_on, details, source_kind, confirmation_level, deleted_at, origin_device_id
- `consents` UPDATE: granted_at, withdrawn_at, details, deleted_at, origin_device_id
- `credit_accounts` UPDATE: product_id, holder_alias, business_tz, status, opened_on, closed_on, deleted_at, origin_device_id
- `credit_pool_members` UPDATE: deleted_at, origin_device_id
- `credit_pools` UPDATE: name, parent_pool_id, deleted_at, origin_device_id
- `currency_accounts` UPDATE: is_primary, deleted_at, origin_device_id
- `dedupe_keys` UPDATE: entity_kind, entity_id
- `deletion_tasks` UPDATE: status
- `devices` UPDATE: name, last_seen_at, revoked_at
- `extraction_candidates` UPDATE: validations, confirmed_value, confirmed_by, confirmed_at
- `forecast_runs` UPDATE: deleted_at, origin_device_id
- `import_batch_items` UPDATE: entity_kind, candidate_refs, decision, duplicate_of_id, resulting_entity_kind, resulting_entity_id, updated_at
- `import_batches` UPDATE: status, target_currency_account_id, source_document_id, failure_reason, updated_at, confirmed_at, posted_at, rolled_back_at
- `installment_plans` UPDATE: principal_minor, periods, per_period_rate, fee_mode, remainder_policy, rounding, status, early_settled_at, deleted_at, origin_device_id
- `installment_schedule` UPDATE: principal_minor, interest_minor, statement_date, due_date, status, deleted_at, origin_device_id
- `jobs` INSERT: kind, payload, status, run_after, max_attempts, timeout_s, workspace_id, dedupe_key
- `limit_adjustments` UPDATE: kind, previous_limit_minor, new_limit_minor, effective_on, expires_on, purpose, source_kind, source_document_id, observed_at, confirmation_level, deleted_at, origin_device_id
- `limit_snapshots` UPDATE: deleted_at
- `parse_jobs` UPDATE: import_batch_id, job_id, parser, parser_version, status, attempts, failure_reason, started_at, finished_at, updated_at
- `plan_allocations` UPDATE: deleted_at
- `plan_invalidations` UPDATE: deleted_at, origin_device_id
- `plan_reservations` UPDATE: cash_account_id, amount_minor, status, linked_transaction_id, deleted_at, origin_device_id
- `plan_run_checks` UPDATE: deleted_at
- `plan_runs` UPDATE: deleted_at
- `plans` UPDATE: amount_minor, txn_date, allow_split, max_cards, min_split_minor, payment_lead_days, channel, merchant, category, allow_installment, status, deleted_at, origin_device_id
- `preauth_holds` UPDATE: card_id, amount_minor, held_at, held_tz, time_precision, expected_release_on, merchant, status, transaction_id, source_kind, source_document_id, confirmation_level, deleted_at, origin_device_id
- `reconciliation_items` UPDATE: status, suggested_action, resolution, resolved_by, resolved_at, deleted_at, origin_device_id
- `recurring_items` UPDATE: label, category, amount_minor, cls, recurrence, starts_on, ends_on, deleted_at, origin_device_id
- `repayment_allocations` UPDATE: amount_minor, deleted_at, origin_device_id
- `repayments` UPDATE: cash_account_id, amount_minor, status, method, payment_initiated_at, cash_debited_at, credit_posted_at, bank_confirmed_at, evidence_document_id, origin_device_id, deleted_at, event_tz, cash_debited_precision, credit_posted_precision
- `rule_bindings` UPDATE: effective_from, effective_to, deleted_at, origin_device_id
- `scenarios` UPDATE: name, include_expected, income_delay_days, income_scale, expense_scale, event_overrides, same_day_order, description, deleted_at, origin_device_id
- `snapshot_included_events` UPDATE: deleted_at, origin_device_id
- `source_documents` UPDATE: storage_key, dek_wrapped, retention_until, deleted_at, origin_device_id
- `statement_attributions` UPDATE: confirmation_level, deleted_at, origin_device_id
- `statement_lines` UPDATE: deleted_at
- `statement_versions` UPDATE: deleted_at
- `statements` UPDATE: statement_date, due_date, status, current_version_id, deleted_at, origin_device_id
- `sync_changes` INSERT: workspace_id, table_name, row_id, op, row_version, payload, origin_device_id
- `sync_conflicts` UPDATE: status, resolved_by, resolved_at
- `transaction_links` UPDATE: confirmation_level, deleted_at, origin_device_id
- `transactions` UPDATE: card_id, txn_type, amount_minor, txn_at, txn_tz, time_precision, posted_on, merchant, mcc, category, status, bank_reference, parent_transaction_id, fingerprint, source_kind, source_document_id, confirmation_level, deleted_at, origin_device_id, observed_at
- `users` UPDATE: email, password_hash, display_name, updated_at, deleted_at
- `workspace_members` UPDATE: role, updated_at
- `workspaces` UPDATE: dek_wrapped, deleted_at

### cardflow_worker

- `audit_log` INSERT: id, workspace_id, actor_kind, actor_id, action, target_table, target_id, before_hash, after_hash, ip
- `banks` UPDATE: name, country, business_tz_default, source, deleted_at, origin_device_id
- `billing_rule_versions` UPDATE: statement_day, statement_day_inclusive, due_kind, due_day, due_month_offset, due_days, due_day_kind, holiday_rollover, cutoff_time, cutoff_tz, source, published_on, effective_from, effective_to, verified_on, review_status, exceptions, deleted_at, origin_device_id
- `card_products` UPDATE: name, network, source, deleted_at, origin_device_id
- `cards` UPDATE: last4, network, holder_kind, status, expires_ym, replaced_by_card_id, alias, deleted_at, origin_device_id
- `cash_accounts` UPDATE: name, kind, usable_for_repayment, available_from, reserve_floor_minor, deleted_at, origin_device_id
- `cash_balance_snapshots` UPDATE: deleted_at
- `cash_events` UPDATE: event_on, event_at, amount_minor, cls, category, label, posting_status, recurring_item_id, linked_repayment_id, linked_plan_run_id, deleted_at, origin_device_id, event_tz
- `cash_transfers` UPDATE: amount_minor, sent_on, arrives_on, out_event_id, in_event_id, deleted_at, origin_device_id
- `charges` UPDATE: statement_id, transaction_id, kind, amount_minor, charged_on, details, source_kind, confirmation_level, deleted_at, origin_device_id
- `credit_accounts` UPDATE: product_id, holder_alias, business_tz, status, opened_on, closed_on, deleted_at, origin_device_id
- `credit_pool_members` UPDATE: deleted_at, origin_device_id
- `credit_pools` UPDATE: name, parent_pool_id, deleted_at, origin_device_id
- `currency_accounts` UPDATE: is_primary, deleted_at, origin_device_id
- `dedupe_keys` UPDATE: entity_kind, entity_id
- `deletion_tasks` UPDATE: status, executed_at
- `extraction_candidates` UPDATE: validations, confirmed_value, confirmed_by, confirmed_at
- `forecast_runs` UPDATE: deleted_at, origin_device_id
- `import_batch_items` UPDATE: entity_kind, candidate_refs, decision, duplicate_of_id, resulting_entity_kind, resulting_entity_id, updated_at
- `import_batches` UPDATE: status, target_currency_account_id, source_document_id, failure_reason, updated_at, confirmed_at, posted_at, rolled_back_at
- `installment_plans` UPDATE: principal_minor, periods, per_period_rate, fee_mode, remainder_policy, rounding, status, early_settled_at, deleted_at, origin_device_id
- `installment_schedule` UPDATE: principal_minor, interest_minor, statement_date, due_date, status, deleted_at, origin_device_id
- `jobs` INSERT: kind, payload, status, run_after, max_attempts, timeout_s, workspace_id, dedupe_key
- `jobs` UPDATE: status, run_after, attempts, locked_by, locked_until, heartbeat_at, last_error, result, updated_at, finished_at
- `limit_adjustments` UPDATE: kind, previous_limit_minor, new_limit_minor, effective_on, expires_on, purpose, source_kind, source_document_id, observed_at, confirmation_level, deleted_at, origin_device_id
- `limit_snapshots` UPDATE: deleted_at
- `parse_jobs` UPDATE: import_batch_id, job_id, parser, parser_version, status, attempts, failure_reason, started_at, finished_at, updated_at
- `plan_allocations` UPDATE: deleted_at
- `plan_invalidations` UPDATE: deleted_at, origin_device_id
- `plan_reservations` UPDATE: cash_account_id, amount_minor, status, linked_transaction_id, deleted_at, origin_device_id
- `plan_run_checks` UPDATE: deleted_at
- `plan_runs` UPDATE: deleted_at
- `plans` UPDATE: amount_minor, txn_date, allow_split, max_cards, min_split_minor, payment_lead_days, channel, merchant, category, allow_installment, status, deleted_at, origin_device_id
- `preauth_holds` UPDATE: card_id, amount_minor, held_at, held_tz, time_precision, expected_release_on, merchant, status, transaction_id, source_kind, source_document_id, confirmation_level, deleted_at, origin_device_id
- `reconciliation_items` UPDATE: status, suggested_action, resolution, resolved_by, resolved_at, deleted_at, origin_device_id
- `recurring_items` UPDATE: label, category, amount_minor, cls, recurrence, starts_on, ends_on, deleted_at, origin_device_id
- `repayment_allocations` UPDATE: amount_minor, deleted_at, origin_device_id
- `repayments` UPDATE: cash_account_id, amount_minor, status, method, payment_initiated_at, cash_debited_at, credit_posted_at, bank_confirmed_at, evidence_document_id, origin_device_id, deleted_at, event_tz, cash_debited_precision, credit_posted_precision
- `rule_bindings` UPDATE: effective_from, effective_to, deleted_at, origin_device_id
- `scenarios` UPDATE: name, include_expected, income_delay_days, income_scale, expense_scale, event_overrides, same_day_order, description, deleted_at, origin_device_id
- `snapshot_included_events` UPDATE: deleted_at, origin_device_id
- `source_documents` UPDATE: storage_key, dek_wrapped, retention_until, deleted_at, origin_device_id
- `statement_attributions` UPDATE: confirmation_level, deleted_at, origin_device_id
- `statement_lines` UPDATE: deleted_at
- `statement_versions` UPDATE: deleted_at
- `statements` UPDATE: statement_date, due_date, status, current_version_id, deleted_at, origin_device_id
- `sync_changes` INSERT: workspace_id, table_name, row_id, op, row_version, payload, origin_device_id
- `sync_conflicts` UPDATE: status, resolved_by, resolved_at
- `transaction_links` UPDATE: confirmation_level, deleted_at, origin_device_id
- `transactions` UPDATE: card_id, txn_type, amount_minor, txn_at, txn_tz, time_precision, posted_on, merchant, mcc, category, status, bank_reference, parent_transaction_id, fingerprint, source_kind, source_document_id, confirmation_level, deleted_at, origin_device_id, observed_at
- `worker_heartbeats` UPDATE: last_seen_at, running_jobs
- `workspaces` UPDATE: dek_wrapped, deleted_at

### cardflow_admin

- `banks` UPDATE: name, country, business_tz_default, source, deleted_at
- `billing_rule_versions` UPDATE: statement_day, statement_day_inclusive, due_kind, due_day, due_month_offset, due_days, due_day_kind, holiday_rollover, cutoff_time, cutoff_tz, source, published_on, effective_from, effective_to, verified_on, review_status, exceptions, deleted_at
- `card_products` UPDATE: name, network, source, deleted_at
- `jobs` SELECT: id, kind, status, run_after, attempts, max_attempts, locked_by, locked_until, heartbeat_at, timeout_s, last_error, workspace_id, created_at, updated_at, finished_at, dedupe_key

### cardflow_purge

- （只有整表授权或无授权）

### cardflow_admin_views

- `auth_sessions` SELECT: workspace_id, device_id, expires_at, last_used_at, revoked_at
- `devices` SELECT: id, workspace_id, user_id, platform, created_at, last_seen_at, revoked_at
- `jobs` SELECT: kind, status, run_after, attempts, created_at, finished_at
- `source_documents` SELECT: workspace_id, size_bytes, deleted_at
- `sync_changes` SELECT: seq, workspace_id, created_at
- `users` SELECT: id, created_at, disabled_at, deleted_at
- `worker_heartbeats` SELECT: last_seen_at
- `workspace_members` SELECT: workspace_id, user_id
- `workspaces` SELECT: id, owner_user_id, kind, created_at, deleted_at

## 3. 策略表达式

| 策略 | 命令 | 角色 | USING | WITH CHECK | 表 |
|---|---|---|---|---|---|
| `admin_views_read` | SELECT | admin_views | `true` | `–` | 9 张表：`auth_sessions`, `deletion_tasks`, `devices`, `jobs`, `source_documents`, `sync_changes`, `users`, `workspace_members`, `workspaces` |
| `audit_append` | INSERT | app, worker | `–` | `((workspace_id IS NULL) OR (workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid))` | `audit_log` |
| `audit_review` | SELECT | admin | `true` | `–` | `audit_log` |
| `jobs_admin_read` | SELECT | admin | `true` | `–` | `jobs` |
| `jobs_app_enqueue` | INSERT | app | `–` | `((workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid) AND (status = 'queued'::text))` | `jobs` |
| `jobs_app_read` | SELECT | app | `(workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid)` | `–` | `jobs` |
| `jobs_worker` | ALL | worker | `true` | `true` | `jobs` |
| `template_maintenance` | ALL | admin | `(workspace_id IS NULL)` | `(workspace_id IS NULL)` | `banks`, `billing_rule_versions`, `card_products` |
| `template_read` | SELECT | app, worker | `((workspace_id IS NULL) OR (workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid))` | `–` | `banks`, `billing_rule_versions`, `card_products` |
| `user_registration` | INSERT | app | `–` | `(id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::uuid)` | `users` |
| `user_self_update` | UPDATE | app | `(id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::uuid)` | `(id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::uuid)` | `users` |
| `user_visibility` | SELECT | app, worker | `((id = (NULLIF(current_setting('app.user_id'::text, true), ''::text))::uuid) OR (EXISTS ( SELECT 1 FROM workspace_members m WHERE ((m.user_id = users.id) AND (m.workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid)))))` | `–` | `users` |
| `workspace_isolation` | ALL | app, worker | `(workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid)` | `(workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid)` | `deletion_tasks` |
| `workspace_isolation` | ALL | app, purge, worker | `(id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid)` | `(id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid)` | `workspaces` |
| `workspace_isolation` | ALL | app, purge | `(workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid)` | `(workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid)` | `auth_sessions`, `idempotency_keys` |
| `workspace_isolation` | ALL | app, purge, worker | `(workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid)` | `(workspace_id = (NULLIF(current_setting('app.workspace_id'::text, true), ''::text))::uuid)` | 50 张表：`banks`, `billing_rule_versions`, `card_products`, `cards`, `cash_accounts`, `cash_balance_snapshots`, `cash_events`, `cash_transfers`, `charges`, `consents`, `credit_accounts`, `credit_pool_members`, `credit_pools`, `currency_accounts`, `dedupe_keys`, `devices`, `extraction_candidates`, `forecast_runs`, `import_batch_items`, `import_batches`, `installment_plans`, `installment_schedule`, `limit_adjustments`, `limit_snapshots`, `parse_jobs`, `plan_allocations`, `plan_invalidations`, `plan_reservations`, `plan_run_checks`, `plan_runs`, `plans`, `preauth_holds`, `reconciliation_items`, `recurring_items`, `repayment_allocation_totals`, `repayment_allocations`, `repayments`, `rule_bindings`, `scenarios`, `snapshot_included_events`, `source_documents`, `statement_attributions`, `statement_lines`, `statement_versions`, `statements`, `sync_changes`, `sync_conflicts`, `transaction_links`, `transactions`, `workspace_members` |

## 4. 函数 EXECUTE 与 SECURITY DEFINER

| 函数 | SECURITY DEFINER | PUBLIC 可执行 | 可执行的组角色 |
|---|---|---|---|
| `public.add_to_repayment_allocation_total(uuid, uuid, bigint)` | 否 | 否 | – |
| `public.bump_row_version()` | 否 | 否 | – |
| `public.check_card_replacement_cycle()` | 否 | 否 | – |
| `public.check_credit_pool_cycle()` | 否 | 否 | – |
| `public.check_repayment_allocations(uuid)` | 否 | 否 | – |
| `public.check_rule_subject_scope()` | 否 | 否 | – |
| `public.check_statement_line_transaction()` | 否 | 否 | – |
| `public.check_template_scope()` | 否 | 否 | – |
| `public.derive_from_parent()` | 否 | 否 | – |
| `public.forbid_column_update()` | 否 | 否 | – |
| `public.forbid_fact_delete()` | 否 | 否 | – |
| `public.forbid_fact_rewrite()` | 否 | 否 | – |
| `public.forbid_workspace_change()` | 否 | 否 | – |
| `public.inserted_by_current_transaction(xid)` | 否 | 否 | app, worker |
| `public.looks_like_pan(text)` | 否 | 否 | admin, app, worker |
| `public.luhn_valid(text)` | 否 | 否 | admin, app, worker |
| `public.maintain_repayment_allocation_totals()` | 是 | 否 | – |
| `public.repayment_allocations_check()` | 是 | 否 | – |
| `public.repayments_allocation_check()` | 是 | 否 | – |

## 5. 序列、数据库与 schema 权限

- `sync_changes_seq_seq` USAGE：app=是, worker=是, admin=否, purge=否, admin_views=否
- 数据库 TEMPORARY / CREATE：PUBLIC: TEMP=否, CREATE=否; app: TEMP=否, CREATE=否; worker: TEMP=否, CREATE=否; admin: TEMP=否, CREATE=否; purge: TEMP=否, CREATE=否; admin_views: TEMP=否, CREATE=否
- schema public USAGE / CREATE，schema admin USAGE：PUBLIC: -- / admin -; app: U- / admin -; worker: U- / admin -; admin: U- / admin U; purge: U- / admin -; admin_views: -- / admin -

## 6. 后台元数据视图（schema admin）

| 视图 | 属主 | 选项 | 列 |
|---|---|---|---|
| `admin.deletion_requests` | cardflow_admin_views | security_barrier=true | deletion_task_id, workspace_id, status, requested_at, grace_until, executed_at |
| `admin.device_overview` | cardflow_admin_views | security_barrier=true | device_id, workspace_id, user_id, platform, created_at, last_seen_at, revoked_at, active_session_count, last_session_used_at |
| `admin.job_summary` | cardflow_admin_views | security_barrier=true | kind, status, job_count, due_count, oldest_created_at, earliest_run_after, last_finished_at, max_attempts_used |
| `admin.system_status` | cardflow_admin_views | security_barrier=true | schema_revision, live_workers, last_worker_seen_at, queued_jobs, due_jobs, oldest_due_run_after, running_jobs, failed_jobs, dead_jobs, last_backup_succeeded_at, last_backup_status, last_backup_created_at, last_backup_finished_at |
| `admin.user_overview` | cardflow_admin_views | security_barrier=true | user_id, created_at, disabled_at, deleted_at, workspace_count, device_count, active_device_count, last_seen_at |
| `admin.workspace_overview` | cardflow_admin_views | security_barrier=true | workspace_id, kind, owner_user_id, created_at, deleted_at, member_count, device_count, active_device_count, last_active_at, last_sync_at, document_count, document_bytes, deletion_status, deletion_requested_at, deletion_grace_until, deletion_executed_at |

