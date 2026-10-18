# 卡序 CardFlow · 规划文档集（规划轮 2026-10-16）

本目录是「卡序 CardFlow」完整 App 的**唯一规划事实来源**。每份文档对应任务书第 12 节的一项交付物；需求、页面、数据表、API、测试、里程碑之间用统一 ID 互相引用，追踪矩阵见 `requirements-traceability.md`。

## 交付物索引

| # | 任务书交付物 | 文档 | 状态 |
|---|---|---|---|
| 1 | 项目理解、关键假设、资料核验、旧原型差距 | `00-overview/01-project-understanding.md` | 已完成 |
| 2 | PRD（模块、流程、状态机、指标口径、v1 范围与非目标） | `10-product/prd.md` | 已完成 |
| 3 | 架构文档与 ADR | `20-architecture/architecture.md`、`20-architecture/adr/` | 已完成 |
| 4 | 银行规则与智能引擎规格（含回归样本） | `30-rules-engine/bank-rules-spec.md`、`30-rules-engine/engine-spec.md`、`../poc/engine_reference/` | 已完成；PoC 已验证 |
| 5 | 数据库 ERD、字典、DDL/迁移、API 契约 | `40-data-api/data-model.md`、`40-data-api/api-contract.md` | 已完成 |
| 6 | UI 信息架构、页面/状态、设计规范、交互验收 | `50-ui/ui-spec.md` | 已完成 |
| 7 | 导入、活动、权益、积分、年费规则与维护后台 | `30-rules-engine/import-spec.md`、`30-rules-engine/promotions-benefits-spec.md`、`50-ui/admin-console-spec.md` | 已完成 |
| 8 | 安全隐私、威胁模型、删除/备份恢复、合规待核查 | `60-ops-security/security-privacy.md` | 已完成 |
| 9 | 测试计划、golden fixtures、性能基准设计、E2E 验收 | `70-testing/test-plan.md`、`../poc/engine_reference/fixtures/` | 已完成；首批 fixture 已验证 |
| 10 | 里程碑、工作包、依赖、子代理边界、交叉审查 | `80-delivery/milestones-workpackages.md`、`80-delivery/phase-1-tasks.md` | 已完成 |
| 11 | 部署/发布、配置、故障恢复、运维手册框架 | `60-ops-security/deployment-ops.md` | 已完成 |
| 12 | 需求追踪矩阵 | `requirements-traceability.md` | 已完成 |
| 13 | 来源清单 | `sources.md` | 已完成（含未取得项） |
| — | 外部依赖与阻塞清单 | `80-delivery/external-dependencies.md` | 已完成 |
| — | M0 执行计划（派发版，待用户确认启动） | `80-delivery/m0-execution-plan.md` | 已完成 |

## 状态图例（全项目统一）

- **已完成**：文档/代码存在且内部一致。
- **已验证**：有可复核证据（测试输出、运行记录、截图或部署健康检查）。
- **待外部凭证**：依赖 Mac 构建环境、用户自有签名身份（移动端由用户自签，ADR-015）、OAuth 审核、VPS 授权等本环境没有的条件。
- **未实现**：规划内但尚未开始。

## ID 约定

| 前缀 | 含义 | 示例 |
|---|---|---|
| `R-<模块>-nn` | 需求（PRD） | `R-CASH-04` |
| `P-nn` | 页面（UI 规格） | `P-07 资金日历` |
| `T-<表名>` | 数据表（数据模型） | `T-cash_events` |
| `API-nn` | 接口（API 契约） | `API-31` |
| `TC-nn` / `F-nn` | 测试用例 / golden fixture | `F-01` |
| `M0…M5` / `WP-nn` | 里程碑 / 工作包 | `WP-12` |
| `ADR-nnn` | 架构决策 | `ADR-003` |
| `E-nn` | 验收证据条目 | `E-04` |
| `S-nn` | 来源（sources.md） | `S07` |

模块缩写：CARD 卡片与信用账户、STMT 账单/交易/分期/还款/核对、CASH 现金流、PLAN 智能用卡、PROMO 活动、BEN 权益/积分/年费、NOTIF 提醒、STAT 统计、SYS 系统与后台、IMP 数据导入、RULE 银行规则、ENG 求解引擎、DATA 数据库、API 接口、ARCH 架构/离线/同步/隐私、UI 界面、SEC 安全、TEST 测试、DEL 交付。

## 阅读顺序

1. `00-overview/01-project-understanding.md`（10 分钟）
2. `10-product/prd.md` 的第 2、3、6 节（范围、概念模型、状态机）
3. `20-architecture/architecture.md` + ADR
4. 实施者按工作包进入对应规格：`30-*`、`40-*`、`50-*`、`60-*`
5. 验收者看 `70-testing/test-plan.md` 与 `requirements-traceability.md`

## 非事实声明

本规划不包含真实金融账户数据；所有数字样本为合成测试数据。文中对银行规则的陈述仅限 `sources.md` 已核验的范围，其他均标注为"待核验"。

## 变更记录

- 2026-10-16 · 移动端分发改为用户自签安装，v1 不上架、不走 TestFlight（新增 `20-architecture/adr/ADR-015-self-signed-distribution.md`）。同步修改：PRD §2.2/§9/§11/§12；架构约束；ADR-010/012 补充；导入规格 §6；安全 §3/§5/§10；部署 §3；测试计划 §6/§10（新增 TC-MOB-14）；里程碑 M5、WP-50/51、DoD、风险；外部依赖 B-01/02/03/08/10；M0 计划 D-7 与批次 B；任务 T-020/T-024；追踪矩阵 E-21/E-22、R-DEL-03/04；项目理解 A-17 与 §6。
- 2026-10-18 · 重排：iOS 优先、纯本地模式、GitHub Actions macOS runner 出未签名 IPA（新增 `80-delivery/ios-first-plan.md`；ADR-015 修订；external-dependencies B-01 改为已满足）。M0 批次 A 冻结（`m0-execution-plan.md` 状态更新）。
