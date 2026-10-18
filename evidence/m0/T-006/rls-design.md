# T-006 · 行级安全、数据库角色与授权设计（迁移 0003）

版本 0.1 · 2026-10-17 · 实现代理：T-006 · 依据：data-model §6/§10、security-privacy §1–§5、admin-console-spec（§0、§1、AP-05~AP-08）、api-contract §1/§4、ADR-003/006/011、`evidence/m0/review-wave2-schema.md` §5 与 R2-01/02/10/26/27、`evidence/m0/T-005/0002-r2-map.md`、`0002-privileges.txt`。

实现位置：

| 内容 | 文件 |
|---|---|
| 迁移（角色、加固、授权、RLS、策略、后台视图、jobs 拼写） | `services/api/alembic/versions/0003_rls.py`（声明式映射 `TABLE_ACCESS`、`POLICIES`、`FUNCTION_EXECUTE`、`IMMUTABLE_COLUMNS`、`ADMIN_VIEW_SOURCES`） |
| 登录角色与 `cardflow db-provision` | `services/api/cardflow/db/roles.py`、`cardflow/cli.py`、`cardflow/settings.py` |
| 会话绑定 `app.workspace_id` / `app.user_id` | `services/api/cardflow/db/tx.py` |
| 测试 | `tests/db/test_rls.py`（真实角色下的行为）、`tests/db/test_rls_grants.py`（系统目录 ⇄ 声明式映射）、`tests/db/test_db_provision.py`、`tests/db/test_migrations.py`（逐修订往返，含 ACL/策略/RLS/视图） |
| 逐表逐列的实际授权 | 同目录 `rls-coverage.md`（由系统目录生成） |

主会话据此更新 security-privacy.md。下文"绑定"指 `NULLIF(current_setting('app.workspace_id', true), '')::uuid`。

---

## 1. 部署前提

1. **迁移以 PostgreSQL 超级用户运行**（Compose 中 `migrate` 服务用数据库超级用户的口令文件）。原因：
   - 只有超级用户能创建 0003 的组角色，`REVOKE TEMPORARY ON DATABASE … FROM PUBLIC`、改 schema public 的 ACL、`ALTER FUNCTION … SECURITY DEFINER`；
   - 表、函数、schema `admin` 都归迁移用户所有。三个 SECURITY DEFINER 触发器函数以属主身份执行（§5），超级用户不受 RLS 过滤（FORCE 也不过滤超级用户）。
2. **api、worker、后台各用自己的 LOGIN 角色连接**，由 `cardflow db-provision` 在 `cardflow migrate` 之后建立或更新（§2.2）。任何长期运行的进程都不得以超级用户或表属主连接——它们绕过 RLS。
3. **角色是集群级对象**：
   - 0003 只在组角色不存在时创建；另一个库的迁移并发创建同名角色时，靠异常处理（`duplicate_object` / `unique_violation`）兜底。
   - 已存在的组角色若可登录，或带 SUPERUSER、BYPASSRLS、CREATEROLE、CREATEDB、REPLICATION 属性，迁移报错退出（fail closed）。
   - **降级不删除角色**：集群内其他库（其他部署、测试库）共用这些角色；只要任何库仍授予它们权限，`DROP ROLE` 就会失败；作为成员的登录角色会在会话中途失去权限。降级后，它们在本库不再持有任何权限。
4. **降级恢复 0001/0002 所假定的 PostgreSQL 默认权限**：PUBLIC 对数据库有 TEMPORARY，对 schema public 有 USAGE，对自有函数有 EXECUTE。若 DBA 在 0003 之前另行收紧过，降级后需要重新收紧。往返测试按"授权集合"比较 ACL（NULL 与内容相同的显式 ACL 视为相等，因为 REVOKE 之后 ACL 不会变回 NULL），因此降级在语义上精确还原 0002。
5. **备份（T-013）**：RLS 下，普通角色运行 `pg_dump`（`row_security=off`）会报错。应使用超级用户，或由 T-013 另建只读备份角色：该角色需要 BYPASSRLS、只授 SELECT，同样只能由超级用户创建。不要复用业务角色。
6. 新建的库在 `CREATE DATABASE` 时默认给 PUBLIC 保留 TEMPORARY。0003 只在当前库里收回，集群中的其他库不受影响。

## 2. 角色

### 2.1 组角色（NOLOGIN，均为 NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION）

| 角色 | 用途 | 成员 |
|---|---|---|
| `cardflow_app` | API。读写绑定空间的业务表；只能为本空间入队任务、只能读本空间的任务；追加审计；读 `alembic_version`、`worker_heartbeats`（/readyz） | `cardflow_api` |
| `cardflow_worker` | 后台任务进程。`jobs`、`worker_heartbeats` 可跨空间访问；业务表与 API 相同，受任务所绑定空间的 RLS 约束；身份类数据只读；无权访问 `auth_sessions`、`idempotency_keys` | `cardflow_worker_login` |
| `cardflow_admin` | 后台。只读 `admin.*` 元数据视图；维护官方模板（`workspace_id IS NULL` 的行）；只读审计；读任务元数据（不含 payload/result）。读不到任何用户的财务正文 | `cardflow_admin_login` |
| `cardflow_purge` | 物理删除（工作空间清除、tombstone 压缩），对绑定空间的可清除表有 SELECT + DELETE。7 张受保护事实表另外需要事务级清除令牌（0002） | `cardflow_worker_login`，授予时 `WITH INHERIT FALSE, SET TRUE`，必须显式 `SET LOCAL ROLE` 才生效 |
| `cardflow_admin_views` | 仅作为 `admin.*` 视图的属主：只对视图读取的元数据列有 SELECT，并在这些表上有 `USING (true)` 的 SELECT 策略 | 无（测试与 db-provision 都检查不得有成员） |

**集群中没有任何 `cardflow_*` 业务角色具有 BYPASSRLS**。开发集群里只有引导超级用户 `cardflow` 有此属性。

### 2.2 登录角色（`cardflow db-provision`）

| 登录角色 | 成员关系（PostgreSQL 16+ 授权选项） | 进程 | 口令来源 |
|---|---|---|---|
| `cardflow_api` | `cardflow_app`（INHERIT TRUE, SET FALSE） | `cardflow api` | `DATABASE_API_PASSWORD_FILE` |
| `cardflow_worker_login` | `cardflow_worker`（INHERIT TRUE, SET FALSE）＋ `cardflow_purge`（**INHERIT FALSE, SET TRUE**） | `cardflow worker` | `DATABASE_WORKER_PASSWORD_FILE` |
| `cardflow_admin_login` | `cardflow_admin`（INHERIT TRUE, SET FALSE） | 后台（T-031） | `DATABASE_ADMIN_PASSWORD_FILE` |

`db-provision` 的行为：

- **属性**：所有登录角色固定为 `LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT`。
- **幂等**：重复运行只更新口令。偏离规格的属性会被纠正，规格以外的成员关系被撤销（含其他授权人授予的，按 `GRANTED BY` 撤销），选项不对的成员关系重新授予。
- **口令**：在客户端算成 SCRAM-SHA-256 verifier 后再发送（libpq `PQencryptPasswordConn`，与 psql 的 `\password` 相同）。因此即使服务器开了 `log_statement`，日志里也只有 verifier，没有明文。命令输出只显示 `********`，也不写入日志。口令至少 16 个字符。
- **拒绝的情况**：同名角色已存在且是超级用户时拒绝修改，避免降级它自己正在使用的管理账号。
- **组角色检查**：开始前和结束后各检查一次（`group_role_problems`）——组角色缺失或属性不安全、`cardflow_admin_views` 有成员、有成员继承了 `cardflow_purge` 时，均报错。
- **事务**：所有操作在一个事务内完成，全有或全无；任何问题都以退出码 1 结束。

### 2.3 后台视图属主为什么不需要 BYPASSRLS

跨空间聚合必须越过"按空间"的过滤，有两种做法：给视图属主 BYPASSRLS，或给它专用的 `USING (true)` SELECT 策略。本迁移选后者：

- **作用范围**：BYPASSRLS 绕过全库所有表的 RLS；策略只作用于视图实际读取的 9 张 RLS 表（users、workspaces、workspace_members、devices、auth_sessions、deletion_tasks、source_documents、sync_changes、jobs）。另有两张无 RLS 的系统表 worker_heartbeats、alembic_version。
- **列级授权**：属主只对视图用到的元数据列有 SELECT（`ADMIN_VIEW_SOURCES`）。若有人把视图改成引用正文列，查询会在运行时报 `permission denied`，由数据库强制，而不是靠代码审查。
- **谁能以它的身份行事**：它不能登录，也没有成员，只有超级用户能以它的身份行事。它由 0003（超级用户）创建；视图也由超级用户创建后 `ALTER VIEW … OWNER TO`。
- **结果**：任何 `cardflow_*` 角色都不需要 BYPASSRLS，测试可以直接断言这一点。

## 3. 行级安全与策略

### 3.1 绑定

- `app.workspace_id`：由 `workspace_tx(factory, workspace_id)` 或 `set_workspace_id(conn, …)` 设置，即 `set_config(…, true)`，事务结束即失效。策略都写成 `NULLIF(current_setting('app.workspace_id', true), '')::uuid`。连接在之前的事务里设置过、本事务未设置时，该值是 `''` 而不是 NULL，因此必须用 NULLIF（测试中复用同一连接覆盖了这一情形）。未绑定时比较结果为 NULL，读不到也写不进任何租户行。
- `app.user_id`（新增）：由 `workspace_tx(…, user_id=…)` 或 `set_user_id(conn, …)` 设置，只用于 `users` 表（§3.4）。
- `SET LOCAL ROLE cardflow_purge`：只在清除事务里使用；用 `RESET ROLE` 回到 worker 身份（§8 T-013/清除任务）。

### 3.2 覆盖面

57 张表 **ENABLE + FORCE**：

- 带 `workspace_id` 的 55 张：50 张租户表、3 张模板表、`audit_log`、`jobs`；
- 加上 `workspaces`（比较 `id`）和 `users`。

不启用 RLS 的只有以下 3 张表（无 `workspace_id` 的全局表或系统表），各自的理由也列在 `tests/db/test_rls_grants.py::NO_RLS_TABLES` 中：

| 表 | 理由 | 访问 |
|---|---|---|
| `currencies` | 全局参考数据（ISO 4217 小数位） | 所有角色只读，无人可写 |
| `worker_heartbeats` | 系统表，每个 worker 进程一行 | worker 读写；app（/readyz）与 admin 只读 |
| `alembic_version` | Alembic 记账表 | app、worker、admin 只读（/readyz、`migrate --check`） |

`test_every_table_is_under_rls_or_listed_as_an_exception` 遍历系统目录中的所有表，以下情况都会使它失败：

- 带 `workspace_id` 的表缺少 ENABLE、缺少 FORCE，或没有适用于 `cardflow_app` 的策略；
- 不在例外清单里的表没有 RLS。

### 3.3 策略清单（共 78 条，全部 PERMISSIVE，`pg_policies` 与 `POLICIES` 逐条比对）

| 策略 | 表 | 命令 | 角色 | USING | WITH CHECK |
|---|---|---|---|---|---|
| `workspace_isolation` | 50 张租户表 + 3 张模板表 | ALL | 对该表有权限的 app / worker / purge | `workspace_id = 绑定` | 同左 |
| `workspace_isolation` | `workspaces` | ALL | app, worker, purge | `id = 绑定` | 同左 |
| `template_read` | banks, card_products, billing_rule_versions | SELECT | app, worker | `workspace_id IS NULL OR workspace_id = 绑定` | – |
| `template_maintenance` | 同上 | ALL | admin | `workspace_id IS NULL` | `workspace_id IS NULL` |
| `user_visibility` | users | SELECT | app, worker | `id = app.user_id` 或"是绑定空间的成员"（EXISTS workspace_members，后者本身也在 RLS 下） | – |
| `user_registration` | users | INSERT | app | – | `id = app.user_id` |
| `user_self_update` | users | UPDATE | app | `id = app.user_id` | 同左 |
| `audit_append` | audit_log | INSERT | app, worker | – | `workspace_id IS NULL OR workspace_id = 绑定` |
| `audit_review` | audit_log | SELECT | admin | `true` | – |
| `jobs_worker` | jobs | ALL | worker | `true` | `true` |
| `jobs_app_read` | jobs | SELECT | app | `workspace_id = 绑定` | – |
| `jobs_app_enqueue` | jobs | INSERT | app | – | `workspace_id = 绑定 AND status = 'queued'` |
| `jobs_admin_read` | jobs | SELECT | admin | `true` | – |
| `admin_views_read` | users, workspaces, workspace_members, devices, auth_sessions, deletion_tasks, source_documents, sync_changes, jobs | SELECT | admin_views | `true` | – |

条数：workspace_isolation 54 条，模板 6 条，users 3 条，audit 2 条，jobs 4 条，admin_views_read 9 条。各策略的规范化表达式见 `rls-coverage.md` §3。

### 3.4 各类表的设计要点

- **模板表**：
  - 对同一命令，多条 PERMISSIVE 策略按 OR 合并。因此业务角色能读到"官方模板 + 本空间私有行"，只能写本空间的行；向模板写入（`workspace_id IS NULL`）会被 WITH CHECK 拒绝，更新模板影响 0 行。admin 只能读写模板行，看不到任何空间的私有规则。
  - 作用域触发器（`check_template_scope`、`check_rule_subject_scope`）以调用者身份运行，查找条件同样是 `workspace_id IS NULL OR = NEW.workspace_id`，与策略看到的行一致：引用 B 的私有银行时，RLS 把该行隐藏，于是报 `23503 credit_accounts_bank_scope`（测试覆盖）。admin 写模板链（模板银行 → 模板产品 → 产品规则）也要经过这些触发器（测试覆盖）。
- **users（全局表，最小权限）**：
  - 可见范围：绑定的用户本人，以及绑定空间的成员。
  - 插入：只能插入 `id = app.user_id` 的行，注册时先绑定新用户 id。
  - 更新：只能改本人的 email、password_hash、display_name、updated_at、deleted_at。`disabled_at` 属后台操作，不授给 app。
  - worker 只读；admin 只能经视图看到 id、时间、禁用/删除时间，看不到 email、显示名、口令哈希。
  - 注册流程（§8 T-011）：在 RLS 下先绑定新 workspace_id 和 user_id，再插入 user → workspace → member → device → auth_session。ORM 风格的 `INSERT … RETURNING` 可行，因为新行在 SELECT 策略下可见（测试覆盖）。
- **jobs**：
  - worker 全部可见、可写（列级 UPDATE 限于状态迁移用到的 10 列）。
  - app 只能为本空间入队 `status = 'queued'` 的任务，只能 SELECT 本空间的任务（`get_job` 对 B 的任务返回 None）；系统任务（`workspace_id IS NULL`）不能由 app 入队。`status = 'queued'` 这一条件比简报更严，用来防止 API 伪造运行中或已完成的任务。
  - admin 只读 16 个元数据列，不含 payload 和 result。`last_error` 授给 admin，因为 T-008 保证它只存安全错误码（`CODE` 或 `CODE:ExceptionType`，见 `cardflow/jobs/errors.py`），AP-05 需要单列显示错误码；视图属主不读该列。
  - `jobs.workspace_id` 不授任何角色 UPDATE（测试覆盖）。
- **audit_log**：
  - app、worker 只能 INSERT 本空间或系统级（`workspace_id IS NULL`）的行，且列级 INSERT 不含 `at`，由数据库取时间。
  - admin 只读。
  - 任何角色都没有 UPDATE、DELETE、TRUNCATE（AP-06 只追加；三个角色逐一测试）。
  - app 没有 SELECT，因此写审计不能用 `RETURNING`：SQLAlchemy Core `insert()` 会为服务端生成的主键隐式加上 RETURNING，需要用 `.inline()` 或在客户端生成 id。
- **sync_changes**：
  - app、worker 只有 INSERT（列级，不含 `seq`、`txid`、`created_at`，由数据库分配拉取游标所需的序号与事务号）和 SELECT，都按空间隔离。
  - 无 UPDATE、DELETE；压缩由 purge 完成。
  - 序列 `sync_changes_seq_seq` 的 USAGE 授给 app 和 worker。
- **idempotency_keys**：按空间隔离。app 只有 INSERT 与 SELECT，worker 无权访问，admin 无权访问（`response_body` 是正文，R2-26）。
- **repayment_allocation_totals**：按空间隔离，业务角色只读；写入只发生在 SECURITY DEFINER 触发器中（§5）。
- **deletion_tasks**：
  - app 可 INSERT（API-94），可 UPDATE(status)（宽限期内撤销）；worker 可 UPDATE(status, executed_at)。
  - purge 不能删除它：删除记录要比被清除的空间活得久（data-model §9）。

## 4. 授权矩阵

### 4.1 表 × 角色 × 操作（汇总；逐表逐列见 `rls-coverage.md`）

S/I/U/D = SELECT/INSERT/UPDATE/DELETE；"U(…)"为列级；"–"为无权限。**任何角色在任何表上都没有 TRUNCATE、REFERENCES、TRIGGER、MAINTAIN。**

| 表或对象 | app | worker | admin | purge | admin_views |
|---|---|---|---|---|---|
| 35 张普通业务表（租户表中除下列特例与 7 张受保护表之外的） | S I U(列) | S I U(列) | – | S D | – |
| 7 张受保护事实表（statement_versions、statement_lines、plan_runs、plan_allocations、plan_run_checks、limit_snapshots、cash_balance_snapshots） | S I U(deleted_at) | S I U(deleted_at) | – | S D（另需清除令牌） | – |
| 模板表 banks、card_products、billing_rule_versions | S I U(列)，只限本空间行 | 同 app | S I U(列)，只限模板行 | S D（本空间私有行） | – |
| workspaces | S I U(dek_wrapped, deleted_at) | S U(dek_wrapped, deleted_at) | – | S D | S（5 列） |
| users | S I U(email, password_hash, display_name, updated_at, deleted_at) | S | – | – | S（4 列） |
| workspace_members | S I U(role, updated_at) D | S | – | S D | S（2 列） |
| devices | S I U(name, last_seen_at, revoked_at) | S | – | S D | S（7 列） |
| auth_sessions | S I U(last_used_at, revoked_at, revoked_reason) | – | – | S D | S（5 列） |
| consents | S I U(granted_at, withdrawn_at, details, deleted_at, origin_device_id) | S | – | S D | – |
| idempotency_keys | S I | – | – | S D | – |
| repayment_allocation_totals | S | S | – | S D | – |
| sync_changes | S I（7 列） | S I（7 列） | – | S D | S（seq, workspace_id, created_at） |
| deletion_tasks | S I U(status) | S U(status, executed_at) | – | – | S（6 列） |
| audit_log | I（10 列，不含 at） | I（10 列） | S | – | – |
| jobs | S I（8 列） | S I（8 列）U（10 列） | S（16 列，不含 payload/result） | – | S（6 列） |
| worker_heartbeats | S | S I U(last_seen_at, running_jobs) D | S | – | S(last_seen_at) |
| currencies | S | S | S | – | – |
| alembic_version | S | S | S | – | S(version_num) |
| 序列 sync_changes_seq_seq | USAGE | USAGE | – | – | – |
| schema public | USAGE | USAGE | USAGE | USAGE | –（视图运行时不需要） |
| schema admin 与 6 个视图 | – | – | USAGE + SELECT | – | 属主 |
| 数据库 | PUBLIC 只有 CONNECT；所有角色均无 TEMPORARY、CREATE | | | | |

worker 对身份类表只读，对 auth_sessions、idempotency_keys 没有任何权限。理由：worker 若能插入会话、设备或成员关系，就能给自己签发任意空间的 API 访问权（`test_worker_cannot_mint_api_access`）。

### 4.2 列级 UPDATE 的规则（等同 T-005 所说的"不可变列逐项清单"）

业务角色（app、worker）的 UPDATE 授权由 `BUSINESS_UPDATE` 正向列出（默认拒绝：新增的列在声明前不可更新），并满足以下规则。`test_updatable_columns_respect_the_immutability_rules` 以 0002 的常量和 `IMMUTABLE_COLUMNS` 为准逐列验证；`test_privileges_match_the_declared_access` 逐表、逐列、逐角色比对"实际授权 = 声明的集合"。

1. 永不可更新：`id`、`workspace_id`（含 `jobs.workspace_id`）。
2. 0002 新增的 11 个派生列：transactions.credit_account_id、preauth_holds.credit_account_id、statement_versions.currency_account_id、statement_lines.currency_account_id、statement_attributions.currency_account_id、snapshot_included_events.cash_account_id、repayment_allocations.currency_account_id、plan_runs.currency、plan_allocations.currency、plan_allocations.credit_account_id、plan_reservations.currency。
3. 可同步表的 `row_version`、`updated_at`（由触发器维护）；所有表的 `created_at`、`recorded_at`（创建出处）；所有 `currency` 列。
4. 受保护事实表：除 `deleted_at` 外全部列；快照的金额、时间与账户列（0002 `SNAPSHOT_IMMUTABLE_COLUMNS`）。
5. 不可变的引用与身份列（`IMMUTABLE_COLUMNS`）：

| 表 | 不可更新的列 |
|---|---|
| workspaces | owner_user_id, kind |
| workspace_members | user_id |
| devices | user_id, platform, public_key |
| auth_sessions | device_id, refresh_token_hash, rotated_from_id, expires_at |
| consents | purpose |
| card_products / credit_pools / credit_accounts | bank_id |
| credit_pool_members | pool_id, credit_account_id |
| currency_accounts | credit_account_id, currency |
| cards | credit_account_id |
| billing_rule_versions | subject_kind, subject_id, version |
| rule_bindings | credit_account_id, currency_account_id, billing_rule_version_id |
| limit_adjustments | currency_account_id |
| transactions / preauth_holds / charges / repayments | currency_account_id, currency |
| transaction_links | from_transaction_id, to_transaction_id, kind |
| statements | currency_account_id |
| statement_attributions | transaction_id, statement_id |
| installment_plans | transaction_id |
| installment_schedule | plan_id, period_no |
| cash_accounts | currency |
| recurring_items / cash_events | cash_account_id |
| repayment_allocations | repayment_id, statement_id |
| repayment_allocation_totals | repayment_id, allocated_minor（无人可写，见 §5） |
| source_documents | sha256, mime, size_bytes, uploaded_by_device_id |
| import_batches | kind |
| parse_jobs | source_document_id |
| extraction_candidates | parse_job_id, field_path, raw_value, normalized_value, raw_location, parser_version, confidence（解析器输出；可改的只有 validations 与 confirmed_*） |
| import_batch_items | import_batch_id, item_no |
| scenarios | code |
| forecast_runs | scenario_id, input_hash, result |
| plans | currency |
| plan_invalidations | plan_id, run_id, cause, caused_by_table, caused_by_id |
| plan_reservations | plan_id, run_id, currency_account_id |
| snapshot_included_events | snapshot_id, cash_event_id |
| cash_transfers | from_cash_account_id, to_cash_account_id, currency |
| reconciliation_items | kind, refs, source_kind |
| sync_conflicts | table_name, row_id, server_payload, client_payload |
| deletion_tasks | requested_at, grace_until |
| jobs | id, kind, payload, workspace_id, created_at |

可更新的可选关联（建立后再挂接的外键）仍然开放，例如 transactions.card_id/parent_transaction_id、statements.current_version_id、cards.replaced_by_card_id、credit_pools.parent_pool_id、credit_accounts.product_id、repayments.cash_account_id/evidence_document_id、charges.statement_id/transaction_id、plan_reservations.linked_transaction_id、cash_events.linked_*。复合外键保证它们仍在同一空间、同一账户。

### 4.3 INSERT 的列限制

- `jobs`（app、worker）只能写 kind, payload, status, run_after, max_attempts, timeout_s, workspace_id, dedupe_key。attempts、租约列、result、时间列只能取默认值。
- `sync_changes`（app、worker）不能写 seq、txid、created_at。
- `audit_log`（app、worker）不能写 `at`。

其余表的 INSERT 为整表授权：插入新行不会破坏他人的行；跨空间由 WITH CHECK 与复合外键挡住，派生列由触发器覆盖。

### 4.4 DELETE 与物理删除

- 业务角色的 DELETE 只有两处：app 删 `workspace_members`（移除成员），worker 删 `worker_heartbeats`（清理心跳）。
- 其余删除一律是 tombstone，即 `UPDATE deleted_at`。
- 物理删除（工作空间清除、tombstone 压缩）只能经 `cardflow_purge`：worker 登录角色执行 `SET LOCAL ROLE cardflow_purge`，绑定空间后只能删该空间的行；7 张受保护表还需 `set_config('app.purge', pg_current_xact_id()::text, true)`。不 SET ROLE 时报 permission denied，不带令牌时被 `<table>_no_delete` 触发器拒绝。TRUNCATE 不授给任何人，因为 TRUNCATE 不受 RLS 约束。

### 4.5 函数

- 对全部 19 个自有函数执行 `REVOKE EXECUTE … FROM PUBLIC`，然后授予：
  - `looks_like_pan(text)`、`luhn_valid(text)` → app、worker、admin（CHECK 约束以写入者身份调用；admin 写模板时也会触发）；
  - `inserted_by_current_transaction(xid)` → app、worker（statement_lines 触发器）。
- 触发器函数本身不需要 EXECUTE：调用者不需要该权限（T-005 实测 B），也不能直接调用触发器函数。
- `add_to_repayment_allocation_total` 与 `check_repayment_allocations` 不授给任何业务角色，原因见 §5（这是对简报"授予 5 个辅助函数"的有意偏离）。
- `test_own_functions_are_executable_only_where_needed` 断言：PUBLIC 不能执行任何自有函数；授权与 `FUNCTION_EXECUTE` 完全一致；SECURITY DEFINER 函数恰为声明的三个，由超级用户拥有，search_path 固定。以后新增函数如果忘记收回 PUBLIC 的 EXECUTE，这个测试会失败。

### 4.6 数据库与 schema 加固（R2-01 纵深防御）

- 用动态 SQL 执行 `REVOKE TEMPORARY ON DATABASE <current_database()> FROM PUBLIC`，且不把 TEMP 授给任何角色。即使 0002 固定 search_path 的修复失效，也没有会话能用临时表遮蔽表名。测试覆盖 app、worker、admin 以及 SET ROLE 之后的 purge，错误码均为 42501。
- `REVOKE USAGE ON SCHEMA public FROM PUBLIC`，只授给 app、worker、admin、purge；没有人对任何 schema 有 CREATE。
- 结果：业务角色无法建表、建函数、建临时对象，也就无法把 SECURITY DEFINER 触发器函数挂到自己的表上。

## 5. 还款分配合计：选择 SECURITY DEFINER 而非授权（二选一）

T-005 的实测（0002-privileges.txt）表明，在调用者权限模型下，写分配的角色需要对 `repayment_allocation_totals` 有 SELECT、INSERT、UPDATE，并对 repayments 有列级 UPDATE。**这意味着 API 自己就能把合计改成 0，再写入超额分配**——"分配和 ≤ 还款额"在 SQL 注入面前失效，而该不变量正是数据库应当兜底的。因此选择 SECURITY DEFINER：

- 只有三个**触发器函数**改为 SECURITY DEFINER：`maintain_repayment_allocation_totals`（逐行维护合计）、`repayment_allocations_check`、`repayments_allocation_check`（提交时检查）。它们原本就固定了 `search_path = pg_catalog, public, pg_temp`，表名全部限定为 `public.`。被调用的 `add_to_repayment_allocation_total`、`check_repayment_allocations` 仍是 INVOKER，在属主上下文中执行。
- **API 只读合计表**，不能 UPDATE 或 INSERT 合计，也不能调用两个辅助函数（均为 42501）。触发器函数不能直接调用，业务角色也无法建表来挂接它们（无 TEMP、无 CREATE）。触发器拿到的输入是 NEW/OLD 行，这些行已经过 WITH CHECK 与复合外键的校验。
- **属主与 FORCE RLS**：属主是迁移超级用户，RLS 对它不生效，计算基于全部行，结果正确。若属主是普通角色（例如托管数据库没有超级用户），FORCE RLS 会作用于属主，而属主没有策略，写合计会报 42501，分配随之失败，即 fail closed，而不是不经检查就放行（`test_allocation_check_fails_closed_when_its_owner_is_subject_to_rls`）。
- **并发语义不变**：READ COMMITTED 下第二个会话等待后得到 23514；REPEATABLE READ 下第二个会话得到 40001（`test_allocations_as_app_race_in_both_isolation_levels`，两种隔离级别均以 app 身份运行）。
- purge 删除分配时由同一触发器同步合计，purge 不需要合计表的写权限。

## 6. 后台元数据视图（schema `admin`）

所有视图都设 `security_barrier`，属主为 `cardflow_admin_views`，`cardflow_admin` 只有 SELECT。视图只输出计数、状态、时间和 id，不输出金额或正文。

| 视图 | 服务的页面 | 列 |
|---|---|---|
| `admin.workspace_overview` | AP-08 用户/空间列表 | workspace_id, kind, owner_user_id, created_at, deleted_at, member_count, device_count, active_device_count, last_active_at, last_sync_at, document_count, document_bytes, deletion_status, deletion_requested_at, deletion_grace_until, deletion_executed_at |
| `admin.user_overview` | AP-08 | user_id, created_at, disabled_at, deleted_at, workspace_count, device_count, active_device_count, last_seen_at（无 email、显示名、口令哈希） |
| `admin.device_overview` | AP-08 设备 | device_id, workspace_id, user_id, platform, created_at, last_seen_at, revoked_at, active_session_count, last_session_used_at（无设备名、公钥、令牌哈希） |
| `admin.deletion_requests` | AP-08 删除请求（空间被清除后仍保留） | deletion_task_id, workspace_id, status, requested_at, grace_until, executed_at |
| `admin.job_summary` | AP-05/AP-07 任务积压 | kind, status, job_count, due_count, oldest_created_at, earliest_run_after, last_finished_at, max_attempts_used |
| `admin.system_status` | AP-07 系统、迁移与备份状态 | schema_revision, live_workers（≤2 分钟）, last_worker_seen_at, queued/due/running/failed/dead_jobs, oldest_due_run_after, last_backup_succeeded_at, last_backup_status, last_backup_created_at, last_backup_finished_at |

- **"样本 <5 显示'<5'"放在 API 层，不放在视图层。** 理由：
  1. 这是展示规则，阈值将来可能可配；
  2. AP-08 的逐空间、逐设备列表本来就要显示单个实体的元数据（例如某空间的设备数），admin 角色可以由此自行算出任何分布，所以在聚合视图里压制小样本只是表面保护；
  3. 后台 API 是视图唯一的使用方，并且已经负责 RBAC。

  约定：视图返回精确值；后台 API（T-031）对"聚合统计"区块中的每一个分组计数，凡小于 5 一律显示为"<5"（含 0），对单个实体的元数据照常显示。
- **备份元信息**：当前库中没有备份记录。`system_status` 假定备份以任务类型 `kind = 'backup'` 运行（ADR-003 的任务类型），只取状态和时间。清单、大小、校验摘要、密钥 ID 位于 `jobs.result`，admin 不可读。若 T-013 改用 Compose 中独立的 `backup` 服务或单独的表，应在其迁移中重建该视图（以及 `backup_runs` 之类的元数据表与授权），沿用本节的属主/列授权模式。
- **后台的写操作尚未授权**：admin 目前只能写模板。AP-01/05/06/08 中，以下操作需要 T-031 的迁移另行授权并加测试：
  - 写审计：建议只开放 `INSERT … WITH CHECK (actor_kind = 'admin')`；
  - 重试/取消任务：只授 jobs 状态相关列的 UPDATE；
  - 撤销设备与会话：只授 `devices.revoked_at`、`auth_sessions.revoked_*` 的 UPDATE，并配套跨空间 UPDATE 策略；
  - 禁用用户：只授 `users.disabled_at`。

  这些写入都会碰到受 RLS 保护的数据，建议采用与 §8 T-011 相同的 SECURITY DEFINER 小函数模式，而不是放宽表级权限。

## 7. 威胁模型

- **`app.workspace_id`、`app.user_id` 是任何会话都能自行设置的 GUC。** RLS 防的是应用逻辑错误：忘了加过滤、拼错 id、在错误的空间上下文里执行。它**防不了 SQL 注入**：攻击者只要能执行任意 SQL，就能绑定任意空间，读写该空间的业务数据。
- **注入场景下仍然成立的防线**（数据库的最后一道）：
  1. **复合外键**：A 的行不能关联到 B 的行，RLS 下由 owner 执行的外键检查依旧生效（TC-DB-04 在 RLS 下复测）。
  2. **迁移 0002 的触发器**：事实不可改、明细与版本同事务、币种/账户一致、作用域检查，search_path 固定（R2-01）。
  3. **无 TEMP、无 CREATE**：不能建临时表遮蔽表名，不能建函数、表或触发器。
  4. **列级授权**：不能把行移到别的空间，不能改不可变列，不能伪造派生列、行版本或时间，不能改写审计时间、同步游标、任务租约。
  5. **不授 DELETE、TRUNCATE**：业务数据与事实不能被物理删除，审计只追加。
  6. **还款分配合计只能由 SECURITY DEFINER 触发器写入**，"分配和 ≤ 还款额"在注入下仍然成立。
  7. **函数 EXECUTE 收回**：内部辅助函数不能被直接调用。
- **各角色被攻破时的影响范围**：

| 被攻破的角色 | 可以做什么 | 不能做什么 |
|---|---|---|
| app（API 注入） | 读写任意空间的业务数据，以 tombstone 形式"删除" | 物理删除；改不可变列或事实；读审计、读或改他人任务；碰模板；建对象 |
| worker | 同 app，另可读所有任务载荷，可 `SET ROLE cardflow_purge` 后物理删除任意空间的数据（受保护事实另需自设令牌，属于显式多步操作） | 签发会话、设备或成员关系（无权限） |
| admin | 改模板，读元数据与审计 | 读任何正文、金额、口令哈希、令牌哈希、幂等响应 |
| purge | 只能删除 | 读写之外的任何事 |

- **残余风险与缓解**：
  - API 必须由服务端校验成员资格后再绑定空间（SEC-S-04），不能直接采用 `X-Workspace-Id` 请求头；所有 SQL 一律参数化。
  - worker 的物理删除能力是清除任务的需要，只授给 worker 登录角色，且需要显式 `SET ROLE`。
  - `users` 的 `app.user_id` 绑定与空间绑定一样可自设，口令哈希对 API 可读（改口令时需要），登录查找应走 §8 的 SECURITY DEFINER 函数。
  - 拒绝服务（长事务、咨询锁）不在本任务范围内。

## 8. 给后续任务的用法说明

**连接方式（所有进程）**：`DATABASE_URL=postgresql+psycopg://<登录角色>@db/cardflow`，`DATABASE_PASSWORD_FILE=/run/secrets/<该角色的口令文件>`。只有 `migrate` 与 `db-provision` 用超级用户。每个请求或任务都用 `workspace_tx(session_factory, workspace_id[, user_id=…])` 开事务；不带空间的代码（系统任务、/readyz）只能访问上表中不受 RLS 约束、或策略为 `true` 的对象。

- **T-009（求解）**：
  - API（`cardflow_app`）在 `workspace_tx` 中写 plans，并用 `cardflow.jobs.enqueue(…, workspace_id=绑定空间)` 入队，状态只能是 queued；用 `get_job(…, workspace_id=…)` 读任务。
  - worker 的 `JobContext.transaction()` 已按任务的 workspace_id 绑定；在其中写 plan_runs、plan_allocations、plan_run_checks 与 sync_changes。这些事实写入后只能 tombstone。
- **T-010（幂等）**：
  - `idempotency_keys` 只能 INSERT 与 SELECT，与业务写入同事务；没有 UPDATE，响应应在业务完成后一次写入。
  - 公开端点（API-01，注册前没有空间）的幂等记录需要新表：在新迁移中按"全局表 + 最小权限 + RLS 或仅授 INSERT/SELECT"的方式加入，并在 `NO_RLS_TABLES` 或策略中登记。
  - 清理过期键属于物理删除，走 purge，或由 T-010 另行授予 worker 带 RLS 的 DELETE。
- **T-011（设备与令牌）**：
  - 注册流程：先生成 workspace_id 与 user_id，然后
    ```python
    with workspace_tx(factory, workspace_id, user_id=user_id) as s:
        # 依次插入 users、workspaces、workspace_members、devices、auth_sessions
        ...
    ```
    测试 `test_registration_flow_under_rls` 已按此顺序验证。
  - "工作空间未知时的查找"（刷新令牌、配对码、按 email 登录、列出我的空间）在迁移 0004 中实现，推荐模式如下：
    ```sql
    CREATE ROLE cardflow_auth_lookup NOLOGIN;                       -- 与 cardflow_admin_views 同一模式，无成员
    GRANT USAGE ON SCHEMA public TO cardflow_auth_lookup;
    GRANT SELECT (id, workspace_id, device_id, expires_at, revoked_at, refresh_token_hash, rotated_from_id)
        ON public.auth_sessions TO cardflow_auth_lookup;
    CREATE POLICY auth_lookup_read ON public.auth_sessions FOR SELECT TO cardflow_auth_lookup USING (true);
    CREATE FUNCTION public.session_by_refresh_hash(p_hash char(64))
        RETURNS TABLE (session_id uuid, workspace_id uuid, device_id uuid,
                       expires_at timestamptz, revoked_at timestamptz, rotated boolean)
        LANGUAGE sql STABLE SECURITY DEFINER
        SET search_path = pg_catalog, public, pg_temp
    AS $$
        SELECT s.id, s.workspace_id, s.device_id, s.expires_at, s.revoked_at,
               EXISTS (SELECT 1 FROM public.auth_sessions AS r WHERE r.rotated_from_id = s.id)
          FROM public.auth_sessions AS s
         WHERE s.refresh_token_hash = p_hash          -- 只按不可猜的秘密的哈希精确匹配
    $$;
    ALTER FUNCTION public.session_by_refresh_hash(char) OWNER TO cardflow_auth_lookup;
    REVOKE ALL ON FUNCTION public.session_by_refresh_hash(char) FROM PUBLIC;
    GRANT EXECUTE ON FUNCTION public.session_by_refresh_hash(char) TO cardflow_app;
    ```
    要点：
    1. 只按不可猜的秘密的哈希（刷新令牌、配对码）精确查找；按 email 查找时只返回 (user_id, password_hash)，并在 API 层限速。
    2. 只返回绑定空间所需的最少列，不返回令牌哈希或正文。
    3. 属主用专用的 NOLOGIN 角色，只有列级 SELECT 与 `USING (true)` 策略，不用超级用户；用测试证明它不能读其他列、没有成员。
    4. search_path 固定且 `pg_temp` 放在最后，全部限定 `public.`，不用动态 SQL。
    5. 收回 PUBLIC 的 EXECUTE，只授给 cardflow_app。
    6. 查到 workspace_id 之后，后续写入（轮换时插入新会话并撤销旧会话）全部在 `workspace_tx` 中、在 RLS 下完成。
    7. 金样清单中，该函数会带 ` security_definer` 标记，需重新登记。
- **T-012（Compose）**：
  - 启动顺序：`db` → `migrate`（超级用户，`cardflow migrate --lock`）→ 新服务 `provision`（超级用户，`cardflow db-provision`，secrets：db_password、db_api_password、db_worker_password、db_admin_password）→ `api`（`cardflow_api` + db_api_password）与 `worker`（`cardflow_worker_login` + db_worker_password）。
  - `/readyz` 需要：能连接，能执行 `migration_status()`（SELECT alembic_version，app 已授权），能读 worker_heartbeats（app 已授权），附件卷可写。它不需要绑定空间，也不需要任何租户表权限。`test_worker_heartbeats_and_readyz_queries` 已用 app 身份验证前两项查询。
  - 口令文件权限设为 0600，至少 16 个字符。
- **T-013（备份与恢复）**：
  - 用超级用户执行 `pg_dump`，或另建只读 BYPASSRLS 备份角色（§1.5）。
  - 恢复到隔离库时以超级用户导入；角色是集群级对象，恢复演练的新集群需要先执行 `cardflow migrate`，或在导入前创建组角色。
  - 备份元信息见 §6。
  - 清除任务的写法：
    ```sql
    -- 在 worker 中，任务事务里
    SET LOCAL ROLE cardflow_purge;
    SELECT set_config('app.purge', pg_current_xact_id()::text, true);
    -- 先删子表，再删父表：分配 → 还款 → ……
    RESET ROLE;   -- 然后以 worker 身份写审计、更新任务与 deletion_tasks
    ```
- **T-031（后台）**：
  - 以 `cardflow_admin_login` 连接，只读 `admin.*` 视图、`jobs` 元数据、`audit_log`、`worker_heartbeats`、`alembic_version`、`currencies`；只能写模板表的模板行。
  - "<5" 在 API 层实现（§6）。
  - 写审计、任务重试/取消、设备撤销、禁用用户需要另一个迁移授权（§6 末尾）。
  - "operator 调正文接口 → 403 + 审计"由 API 层实现；数据库层已保证即使 API 出错也读不到正文（TC-DB-06）。
- **新迁移的约定**（测试会提醒）：
  - **新表**：带 workspace_id 的表要 `ENABLE + FORCE ROW LEVEL SECURITY` 并建策略，否则 `test_every_table_is_under_rls_or_listed_as_an_exception` 失败；全局表则登记到 `NO_RLS_TABLES` 并说明理由。授权要在新修订的 `TABLE_ACCESS` 中声明（测试按修订顺序合并各修订的声明），否则 `test_privileges_match_the_declared_access` 失败。
  - **新函数**：`REVOKE EXECUTE … FROM PUBLIC` 后按需授予；SECURITY DEFINER 函数要固定 search_path、由超级用户或专用角色拥有，并在金样中登记。
  - 改触发器或函数后执行 `CARDFLOW_UPDATE_GOLDEN=1 uv run pytest tests/db/test_db_objects.py`。
  - 带 FORCE RLS 的表上做数据修复时，要么以超级用户迁移，要么按空间逐个绑定 GUC（review §5.10）。
- **测试 fixture**（`services/api/tests/conftest.py` 模块文档）：
  - `app_engine`、`worker_engine`、`purge_capable_engine`、`admin_engine`：会话级，各自以随机名、随机口令的临时 LOGIN 角色连接会话测试库。这些角色由生产用的 `provision_login_role` 创建，形状与部署一致；会话结束时 `DROP OWNED` 再 `DROP ROLE`。连接池为 NullPool，SET ROLE 或 GUC 不会在测试之间残留。
  - 用 `db_engine`（超级用户）准备并提交数据，再用角色 engine 执行被测代码；`database_logins["app"].url(test_database_url)` 可以给被测应用当作 DATABASE_URL。
  - schema 未到 head 时，这些 fixture 跳过并说明原因。

## 9. 与简报的偏离、待定事项

1. **视图属主不用 BYPASSRLS**：改用专用 SELECT 策略加列级授权，权限更小（§2.3），因此"说明为什么需要 BYPASSRLS"改为说明为什么不需要。
2. **还款分配合计用 SECURITY DEFINER**：`add_to_repayment_allocation_total`、`check_repayment_allocations` 不授给业务角色（§5）。简报"收回 EXECUTE 后授予 5 个辅助函数"的前提是调用者权限模型，此处只授予需要的 3 个，测试证明 app、worker 的写入路径与 purge 的删除路径均可用。
3. **比简报更严的几处**：
   - app 只能入队 `queued` 任务；
   - jobs、sync_changes、audit_log 的 INSERT 有列限制；
   - worker 对身份表只读，无权访问 auth_sessions、idempotency_keys；
   - purge 的 DELETE 覆盖所有可清除的租户表，不止 7 张受保护表，否则工作空间清除时其余表无人可删，而业务角色不应有 DELETE。
4. **`app.user_id`**：为 users 的最小权限新增第二个会话设置；`cardflow/db/tx.py` 增加了 `user_id=` 参数与 `set_user_id()`。
5. **jobs 的 'cancelled'**：按 data-model §10.12 放在 0003 中更正，未修改 0002。升级时把已有的 'canceled' 行改为 'cancelled'，降级时改回；改动的是状态值，不是金额。模型 `cardflow/jobs/models.py` 的 `JOB_STATUSES` 与文档字符串同步修改：这是简报 (b) 明确要求的"同步模型"，属于 jobs 包中唯一的改动。
6. **R2-23**：0001 的 downgrade 不再删除扩展；目录往返测试把扩展视为环境前提。0002 文档字符串末尾"R2-23 未处理"的说明已过时，但按禁令未修改 0002，建议主会话在下一次允许修改 0002 时更正。
7. **备份元信息**假定任务类型为 `backup`（§6），由 T-013 确认或替换。
8. **快照的 tombstone 可以反复修改（待裁决）**：
   - 0002 只冻结 limit_snapshots、cash_balance_snapshots 的金额、时间与账户列（data-model §10.3）。"tombstone 只能一次、此后整行冻结"只适用于 5 张不可变事实表。
   - 因此 API 对两张快照表的 deleted_at 可以反复修改，包括撤销 tombstone；其他列在授权层面一律不可改。测试 `test_protected_facts_take_only_the_tombstone` 按此断言。
   - 若希望快照也只能 tombstone 一次，需要在后续迁移中给这两张表加 `forbid_fact_rewrite` 类触发器，属于语义变更，请主会话裁决。
9. **ACL 比较方式**：往返比较的是"授权集合"，NULL 的 ACL 与等价的显式 ACL 视为相等，因为 REVOKE 之后表的 relacl 不会变回 NULL；列级 ACL 会变回 NULL，可以严格相等比较。
