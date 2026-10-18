# T-005 / T-007 · TC 映射与表归属

生成于 2026-10-17（UTC），对应最终代码。结果取自本目录与 `evidence/m0/T-007/` 下的原始输出：
`evidence/m0/T-007/pytest.txt`（`pytest -v tests/db/test_constraints.py`，59 passed）、
`evidence/m0/T-005/pytest.txt`（全量 `pytest -q`，209 passed，其中 tests/db 77 项）、
`evidence/m0/T-005/pytest-migration-target.txt`（`CARDFLOW_TEST_MIGRATION_TARGET` = head / 0001 / base）。
所有 DB 测试使用开发库 superuser（127.0.0.1:18432），因此本表不涉及 RLS。

## 1. TC-DB（test-plan §4）→ 测试函数 → 结果

测试文件均在 `services/api/tests/db/`；函数名带 TC 编号。

| TC | 内容 | 测试函数（test_constraints.py） | 结果 |
|---|---|---|---|
| TC-DB-01 | statement_versions 金额 UPDATE 被触发器拒绝 | `test_tc_db_01_statement_version_amount_update_rejected`（参数化：9 个金额列 + due_date，共 10 例）、`test_tc_db_01_unchanged_amount_in_update_is_still_rejected`、`test_tc_db_01_non_amount_columns_stay_updatable`、`test_tc_db_01_correction_is_a_new_version` | PASSED ×13 |
| TC-DB-01（DELETE 部分） | 无 `app.purge` 禁止 DELETE/TRUNCATE；`set_config('app.purge','on',true)` 只在本事务内放行 DELETE，且不放行金额 UPDATE | `test_tc_db_01_delete_rejected_without_purge_flag`、`test_tc_db_01_truncate_rejected_without_purge_flag`、`test_tc_db_01_purge_flag_allows_delete_for_one_transaction_only` | PASSED ×3 |
| TC-DB-02 | cards.last4 非 4 位拒绝 | `test_tc_db_02_card_last4_must_be_four_digits`（参数化 7 例：'123'、'12a4'、'abcd'、''、'12 4' → 23514 `ck_cards_last4_digits`；'12345'、19 位卡号 → 22001 超长）、`test_tc_db_02_card_last4_accepts_four_digits` | PASSED ×8 |
| TC-DB-03 | billing_rule_versions 生效期重叠拒绝（按作用域） | `test_tc_db_03_same_scope_overlap_rejected`（同工作空间重叠 → 23P01）、`test_tc_db_03_two_published_templates_overlap_rejected`（模板作用域内重叠 → 23P01）、`test_tc_db_03_template_and_user_declared_do_not_conflict`、`test_tc_db_03_two_workspaces_do_not_conflict`、`test_tc_db_03_adjacent_periods_drafts_and_tombstones_do_not_conflict` | PASSED ×5 |
| TC-DB-04 | 复合外键跨工作空间拒绝 | `test_tc_db_04_currency_account_cannot_join_other_workspace_account`、`test_tc_db_04_transaction_cannot_use_other_workspace_card`、`test_tc_db_04_allocation_cannot_link_other_workspace_statement`、`test_tc_db_04_current_version_must_belong_to_the_statement`；模板表（普通 FK + 作用域触发器）：`test_tc_db_04_template_references_accept_templates_and_own_rows`、`test_tc_db_04_template_references_reject_other_workspaces`、`test_tc_db_04_rule_binding_and_subject_stay_in_scope`、`test_tc_db_04_template_rows_cannot_change_workspace`、`test_tc_db_04_templates_must_be_product_rules` | PASSED ×9 |
| TC-DB-05 | RLS 绕过 | 不在本任务（T-006，迁移 0002） | — |
| TC-DB-06 | admin 角色读正文列 | 不在本任务（T-006） | — |
| TC-DB-07 | 幂等键重复（本任务只验证数据库层唯一约束；API 重放语义属 T-010） | `test_tc_db_07_duplicate_idempotency_key_rejected`（同 (workspace_id,key) → 23505 `pk_idempotency_keys`，他空间同 key 可插入，首条响应保留）、`test_tc_db_07_request_hash_must_be_sha256_hex` | PASSED ×2 |
| TC-DB-08 | available_raw 允许负值 | `test_tc_db_08_negative_available_raw_is_kept`（-12 345 原值写入并读回） | PASSED |
| TC-DB-09 | repayment_allocations 和超额拒绝（延迟约束触发器） | `test_tc_db_09_over_allocation_rejected_at_commit`、`test_tc_db_09_full_allocation_across_two_statements_commits`（F-33）、`test_tc_db_09_temporary_overage_fixed_before_commit_succeeds`（证明是延迟约束）、`test_tc_db_09_set_constraints_immediate_reports_at_once`、`test_tc_db_09_lowering_repayment_below_allocations_rejected`、`test_tc_db_09_tombstoned_allocations_do_not_count`、`test_tc_db_09_statement_of_other_currency_account_rejected`、`test_tc_db_09_moving_an_allocated_statement_rejected`、`test_tc_db_09_concurrent_allocations_are_serialised`（两会话并发，第二个等待行锁后失败） | PASSED ×9 |
| TC-DB-10 | jobs SKIP LOCKED 并发领取 | 不在本任务（T-008）；本任务只建表与部分索引 | — |

简报 §4d 的其余约束（同文件）：

| 约束 | 测试函数 | 结果 |
|---|---|---|
| statements CHECK (due_date > statement_date) | `test_statement_due_date_must_follow_statement_date` | PASSED |
| statements UNIQUE (currency_account_id, statement_date) | `test_one_statement_per_currency_account_and_date` | PASSED |
| repayments：bank_confirmed 必须有 bank_confirmed_at | `test_bank_confirmed_repayment_needs_bank_confirmed_at` | PASSED |
| source_documents UNIQUE (workspace_id, sha256) | `test_source_document_fingerprint_unique_per_workspace` | PASSED |
| dedupe_keys PK (workspace_id, key_hash) | `test_dedupe_key_primary_key` | PASSED |
| currencies 种子 = 引擎 MINOR_DIGITS | `test_currencies_seed_matches_engine_minor_units` | PASSED |
| 主键默认 uuidv7() | `test_primary_keys_default_to_uuidv7` | PASSED |
| 每个信用账户至多一个有效主币种子账户（自行补充） | `test_one_live_primary_currency_account` | PASSED |
| jobs running 必须持有租约；worker_heartbeats.running_jobs ≥ 0 | `test_running_job_needs_a_lease_and_heartbeat_counts_are_non_negative` | PASSED |

## 2. 迁移、模型一致性与类型扫描

| 验收项 | 测试函数 | 结果 |
|---|---|---|
| 空库 upgrade head → downgrade base → upgrade head（每步校验表/函数/触发器/延迟属性/扩展/序列/版本/种子；再降一次证明可重复） | `test_migrations.py::test_upgrade_downgrade_upgrade_round_trip` | PASSED |
| head 上重复 upgrade 为空操作 | `test_migrations.py::test_upgrade_at_head_is_a_no_op` | PASSED |
| 可复用的版本比较函数（/readyz 用） | `test_migrations.py::test_migration_status_reports_base_and_head` | PASSED |
| `cardflow migrate --check` 非 head 退出 1、head 退出 0；`cardflow migrate` 升级 | `test_migrations.py::test_migrate_check_exit_codes`、`test_migrate_check_after_downgrade_exits_1` | PASSED |
| `cardflow migrate --lock`：升级后释放锁；锁被占用时等待、释放后执行 | `test_migrations.py::test_migrate_lock_upgrades_and_releases_the_lock`、`test_migrate_lock_waits_while_another_migrator_holds_it` | PASSED |
| 会话库遵循 `CARDFLOW_TEST_MIGRATION_TARGET` | `test_migrations.py::test_session_database_is_at_the_requested_target` | PASSED |
| 模型 = 迁移（compare_metadata 无差异） | `test_model_drift.py::test_autogenerate_reports_no_difference` | PASSED |
| autogenerate 盲区（CHECK、EXCLUDE、部分索引谓词、索引方法/opclass/DESC、FK 名、主键）用 create_all 库逐对象比对 pg_get_constraintdef / pg_get_indexdef / 列类型与默认值 | `test_model_drift.py::test_catalog_definitions_match_models`、`test_catalog_covers_the_blind_spots` | PASSED |
| 模型无法表达的对象（触发器/函数、扩展、种子、alembic_version）列为豁免并在库中核验 | `test_model_drift.py::test_objects_outside_the_models_exist` | PASSED |
| 约束/索引名 ≤ 63 字符且全局唯一 | `test_model_drift.py::test_every_name_fits_the_postgres_identifier_limit` | PASSED |
| 无 float/double/real/money 列（information_schema 扫描，含数组类型） | `test_no_float_columns.py::test_no_float_double_real_or_money_column` | PASSED |
| `*_minor` 全为 bigint；numeric 全有显式精度（利率/系数 NUMERIC(20,10)）；时间戳全为 timestamptz；自有函数不用浮点 | `test_no_float_columns.py` 其余 4 项 | PASSED |

自检：layer 2 的有效性做过变异验证——把模型里 `ck_cards_last4_digits` 改成 `{3,4}` 后
`test_catalog_definitions_match_models` 失败（compare_metadata 看不到这类差异），恢复后通过。

## 3. 表清单与 workspace 归属（58 张 + alembic_version）

由模型元数据生成（与迁移的一致性由 `test_model_drift.py` 保证）。"同步列" = row_version、updated_at、deleted_at、origin_device_id 齐全。
"组"为 data-model §1 实体组；`10*` = 主会话追加的系统表 worker_heartbeats。

| # | 表 | 组 | 归属 | workspace 关联 | UNIQUE (workspace_id, id) | 同步列 | 主键 |
|---|---|---|---|---|---|---|---|
| 1 | `auth_sessions` | 1 | 用户数据（workspace_id NOT NULL） | 复合FK×2 | 是 | — | id |
| 2 | `consents` | 1 | 用户数据（workspace_id NOT NULL） | FK→workspaces | 是 | 是 | id |
| 3 | `devices` | 1 | 用户数据（workspace_id NOT NULL） | FK→workspaces | 是 | — | id |
| 4 | `idempotency_keys` | 1 | 用户数据（workspace_id NOT NULL） | FK→workspaces | — | — | workspace_id, key |
| 5 | `users` | 1 | 全局身份（无 workspace_id） | — | — | — | id |
| 6 | `workspace_members` | 1 | 用户数据（workspace_id NOT NULL） | FK→workspaces | 是 | — | id |
| 7 | `workspaces` | 1 | 租户根（id 即工作空间键） | — | — | — | id |
| 8 | `banks` | 2 | 模板/用户数据（workspace_id 可空，NULL=官方模板） | FK→workspaces | 是 | 是 | id |
| 9 | `billing_rule_versions` | 2 | 模板/用户数据（workspace_id 可空，NULL=官方模板） | FK→workspaces | 是 | 是 | id |
| 10 | `card_products` | 2 | 模板/用户数据（workspace_id 可空，NULL=官方模板） | FK→workspaces | 是 | 是 | id |
| 11 | `cards` | 2 | 用户数据（workspace_id NOT NULL） | 复合FK×2 | 是 | 是 | id |
| 12 | `credit_accounts` | 2 | 用户数据（workspace_id NOT NULL） | FK→workspaces | 是 | 是 | id |
| 13 | `credit_pool_members` | 2 | 用户数据（workspace_id NOT NULL） | 复合FK×2 | 是 | 是 | id |
| 14 | `credit_pools` | 2 | 用户数据（workspace_id NOT NULL） | FK→workspaces + 复合FK×1 | 是 | 是 | id |
| 15 | `currencies` | 2 | 全局参考数据（无 workspace_id） | — | — | — | code |
| 16 | `currency_accounts` | 2 | 用户数据（workspace_id NOT NULL） | 复合FK×1 | 是 | 是 | id |
| 17 | `rule_bindings` | 2 | 用户数据（workspace_id NOT NULL） | 复合FK×2 | 是 | 是 | id |
| 18 | `limit_adjustments` | 3 | 用户数据（workspace_id NOT NULL） | 复合FK×1 | 是 | 是 | id |
| 19 | `limit_snapshots` | 3 | 用户数据（workspace_id NOT NULL） | 复合FK×1 | 是 | 是 | id |
| 20 | `plan_reservations` | 3 | 用户数据（workspace_id NOT NULL） | 复合FK×5 | 是 | 是 | id |
| 21 | `preauth_holds` | 3 | 用户数据（workspace_id NOT NULL） | 复合FK×3 | 是 | 是 | id |
| 22 | `charges` | 4 | 用户数据（workspace_id NOT NULL） | 复合FK×3 | 是 | 是 | id |
| 23 | `installment_plans` | 4 | 用户数据（workspace_id NOT NULL） | 复合FK×1 | 是 | 是 | id |
| 24 | `installment_schedule` | 4 | 用户数据（workspace_id NOT NULL） | 复合FK×1 | 是 | 是 | id |
| 25 | `statement_attributions` | 4 | 用户数据（workspace_id NOT NULL） | 复合FK×2 | 是 | 是 | id |
| 26 | `statement_lines` | 4 | 用户数据（workspace_id NOT NULL） | 复合FK×2 | 是 | 是 | id |
| 27 | `statement_versions` | 4 | 用户数据（workspace_id NOT NULL） | 复合FK×1 | 是 | 是 | id |
| 28 | `statements` | 4 | 用户数据（workspace_id NOT NULL） | 复合FK×2 | 是 | 是 | id |
| 29 | `transaction_links` | 4 | 用户数据（workspace_id NOT NULL） | 复合FK×2 | 是 | 是 | id |
| 30 | `transactions` | 4 | 用户数据（workspace_id NOT NULL） | 复合FK×3 | 是 | 是 | id |
| 31 | `cash_accounts` | 5 | 用户数据（workspace_id NOT NULL） | FK→workspaces | 是 | 是 | id |
| 32 | `cash_balance_snapshots` | 5 | 用户数据（workspace_id NOT NULL） | 复合FK×1 | 是 | 是 | id |
| 33 | `cash_events` | 5 | 用户数据（workspace_id NOT NULL） | 复合FK×4 | 是 | 是 | id |
| 34 | `cash_transfers` | 5 | 用户数据（workspace_id NOT NULL） | 复合FK×4 | 是 | 是 | id |
| 35 | `reconciliation_items` | 5 | 用户数据（workspace_id NOT NULL） | FK→workspaces | 是 | 是 | id |
| 36 | `recurring_items` | 5 | 用户数据（workspace_id NOT NULL） | 复合FK×1 | 是 | 是 | id |
| 37 | `repayment_allocations` | 5 | 用户数据（workspace_id NOT NULL） | 复合FK×2 | 是 | 是 | repayment_id, statement_id |
| 38 | `repayments` | 5 | 用户数据（workspace_id NOT NULL） | 复合FK×2 | 是 | 是 | id |
| 39 | `snapshot_included_events` | 5 | 用户数据（workspace_id NOT NULL） | 复合FK×2 | 是 | 是 | snapshot_id, cash_event_id |
| 40 | `dedupe_keys` | 6 | 用户数据（workspace_id NOT NULL） | FK→workspaces | — | — | workspace_id, key_hash |
| 41 | `extraction_candidates` | 6 | 用户数据（workspace_id NOT NULL） | 复合FK×1 | 是 | — | id |
| 42 | `import_batch_items` | 6 | 用户数据（workspace_id NOT NULL） | 复合FK×1 | 是 | — | id |
| 43 | `import_batches` | 6 | 用户数据（workspace_id NOT NULL） | FK→workspaces + 复合FK×1 | 是 | — | id |
| 44 | `parse_jobs` | 6 | 用户数据（workspace_id NOT NULL） | 复合FK×2 | 是 | — | id |
| 45 | `source_documents` | 6 | 用户数据（workspace_id NOT NULL） | FK→workspaces | 是 | 是 | id |
| 46 | `forecast_runs` | 7 | 用户数据（workspace_id NOT NULL） | 复合FK×1 | 是 | 是 | id |
| 47 | `plan_allocations` | 7 | 用户数据（workspace_id NOT NULL） | 复合FK×4 | 是 | 是 | run_id, currency_account_id |
| 48 | `plan_invalidations` | 7 | 用户数据（workspace_id NOT NULL） | 复合FK×2 | 是 | 是 | id |
| 49 | `plan_run_checks` | 7 | 用户数据（workspace_id NOT NULL） | 复合FK×2 | 是 | 是 | id |
| 50 | `plan_runs` | 7 | 用户数据（workspace_id NOT NULL） | 复合FK×2 | 是 | 是 | id |
| 51 | `plans` | 7 | 用户数据（workspace_id NOT NULL） | FK→workspaces | 是 | 是 | id |
| 52 | `scenarios` | 7 | 用户数据（workspace_id NOT NULL） | FK→workspaces | 是 | 是 | id |
| 53 | `audit_log` | 10 | 系统（workspace_id 可空，软引用） | 无FK（软引用，需在工作空间删除后保留） | — | — | id |
| 54 | `deletion_tasks` | 10 | 用户数据（workspace_id NOT NULL） | 无FK（软引用，需在工作空间删除后保留） | 是 | — | id |
| 55 | `jobs` | 10 | 系统（workspace_id 可空，软引用） | 无FK（软引用，需在工作空间删除后保留） | — | — | id |
| 56 | `sync_changes` | 10 | 用户数据（workspace_id NOT NULL） | FK→workspaces | — | — | seq |
| 57 | `sync_conflicts` | 10 | 用户数据（workspace_id NOT NULL） | FK→workspaces | 是 | — | id |
| 58 | `worker_heartbeats` | 10* | 系统（无 workspace_id） | — | — | — | worker_id |

归属汇总：用户数据（workspace_id NOT NULL）49 张；模板/用户数据（可空，NULL=官方模板）3 张（banks、card_products、billing_rule_versions）；
全局参考 1 张（currencies）；全局身份 1 张（users）；租户根 1 张（workspaces）；系统 3 张（jobs、audit_log：workspace_id 可空软引用；worker_heartbeats：无 workspace_id）。
给 T-006：RLS 适用于全部"用户数据"表与 3 张模板表（模板行只读策略）；workspaces 以 id 比较；users、currencies、worker_heartbeats、jobs、audit_log 需单独决定。
