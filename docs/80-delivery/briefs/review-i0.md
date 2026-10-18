# 简报 R-I0 · I-0 阶段末审查（只读）

派发：2026-10-18。对应 `ios-first-plan.md` §5"审查代理只在阶段结束时跑一次，只修 blocker/major，其余记入 backlog"。本任务**不改代码**，产出一份审查报告；修复由主会话另行安排。

## 环境与规则
- 仓库 /projects/cardflow = `YePiXpert/cardflow`（公开，main）。Flutter 3.47.7 在 /opt/flutter-sdk（`export PATH=/opt/flutter-sdk/bin:$PATH`，含 `dart`）；Python 引擎用 `uv run --project /projects/cardflow/services/api ...`。
- 宿主是生产 VPS：不运行 docker；不改 /opt 下除 flutter-sdk 外的目录；不装系统包；不连接 127.0.0.1:5432。
- 只读审查：可以运行 analyze / test / 运行器 / 临时脚本（放 /tmp）来验证怀疑点，但**不修改**仓库内任何已有文件，不提交、不推送。唯一允许新建的文件：`evidence/i0/review-i0.md`（报告）与 `evidence/i0/review-i0/`（复现输出，tee）。
- 报告、文件、命令里不得出现 Claude/AI 署名。
- 报告里不回显密钥、口令或用户邮箱；引用金额只用 fixture 里的合成数据。

## 范围
`apps/mobile/`（含 `packages/cardflow_domain/`）、`.github/workflows/mobile.yml`、`packages/rules-protocol/runner_py/run_fixtures.py` 的 `--dump` 改动、`evidence/i0/` 的证据是否能支撑结论。不审查 `services/api/` 其余部分（已冻结）。

## 对照依据（必读）
docs/30-rules-engine/engine-spec.md §8、§12、§12.1；docs/30-rules-engine/bank-rules-spec.md §3/§5；docs/20-architecture/adr/ADR-001、ADR-004、ADR-008、ADR-015；docs/60-ops-security/security-privacy.md §3、§5；packages/rules-protocol/README.md（字段约定、断言语义、v1 修订记录、Dart 端同步清单、末节"Dart 端实现与 parity"）；services/api/cardflow/planner/engine/（Python 引擎 1.1.0，语义基准）与 services/api/tests/engine、tests/protocol（尤其 test_rejections.py、test_review_wave3_*.py、test_differential.py）；docs/80-delivery/briefs/I0-a.md、I0-b.md、I0-c.md（各任务的要求）；apps/mobile/README.md。

## 重点（按风险排序）
1. **金额与日期语义是否偏离 Python 引擎**：Dart `money`/`time`/`billing`/`cash`/`verifier` 与 Python 对应模块逐函数对照；关注取整方向（费用向上、收益向下）、月末截断与闰年、入账窗口多账期取最早到期、快照包含判定先于情景变换、同日顺序规则、三层容量截零、还款早于快照日/晚于 horizon 的处理、平局字典序。parity 只覆盖随机生成器能生成的输入，请专门找生成器覆盖不到的分支（读 `tool/gen_parity_fixtures.dart` 与 Python `tests/engine/test_differential.py` 的 gen_doc 判断覆盖盲区）。
2. **协议适配层拒绝清单是否齐**：把 `tests/protocol/test_rejections.py`、`test_review_wave3_protocol.py` 的每条用例与 Dart `test/` 对照，列出 Dart 未覆盖的用例；检查 `parseJson`（重复键、NaN、BOM、深度、整值浮点）、`canonicalJson`（UTF-16 键序、ECMAScript 数字、控制字符转义）与 `protocolInputHash` 是否有 Python 不会拒绝/接受而 Dart 相反的输入。
3. **有限搜索**：`proven` 恒为 false 是否在所有输出路径成立；时间预算在候选枚举与验证两个阶段是否都生效；K≤3 的候选切点是否可能漏掉"显然可行"的方案（给出反例或说明没有）；平局规则与 Python 一致；NEEDS_DATA/BASELINE_SHORTFALL 的早停是否正确。
4. **加密库失败即止是否有绕过**：`lib/data/db/` 中任何能在自检失败、密钥缺失、密钥错误时仍返回可用数据库或明文库的路径；`PRAGMA` 结果被忽略的地方；Web 条件导入是否可能在 iOS 上被选中；错误码是否稳定。
5. **密钥与日志泄露**：密钥十六进制、原始字节、Keychain 值是否可能进入异常消息、诊断报告、环形日志、测试输出；诊断页复制的报告是否含金额以外的个人数据；`containsKeyMaterial` 一类测试的覆盖是否真实。
6. **CI 是否可能静默通过**：`mobile.yml` 中 `continue-on-error`、`|| true`、缺少 `set -euo pipefail`、diff 为空时目录是否可能本来就是空的（0 个文件也 diff 为空）、jsonschema 校验的文件数是否被断言、`paths` 过滤是否可能漏掉需要触发的改动、`--enforce-lockfile`/`--locked` 是否生效、`dart test` 是否真的在领域包目录运行。
7. **iOS 配置不变量**：无团队 ID、无 entitlement、Bundle ID `li.yep.cardflow`、最低 iOS 15、PrivacyInfo 的 API 声明与实际用到的 API（UserDefaults、文件时间戳等）是否一致、`test/ios/ios_config_test.dart` 是否覆盖这些。
8. **公开仓库卫生**：apps/mobile、evidence/i0、.github 内是否出现宿主服务/端口清单、口令、令牌、邮箱、真实卡号样式的数字。
9. **证据是否能支撑结论**：evidence/i0/I0-a、I0-b、I0-c 的文件是否与简报验收清单一致、是否为工具原文（非手写）、命令是否可复现。

## 分级
- **blocker**：金额/日期算错、数据丢失、密钥泄露、能退回明文库、CI 可能在失败时显示绿、公开仓库泄露。
- **major**：现实输入下行为错误、缺少 Python 已有的拒绝、测试缺口掩盖了缺陷、文档与实现矛盾且会误导 I-1。
- **minor**：风格、命名、注释、可读性、非阻塞改进。
每条发现：编号、级别、文件:行、现象、复现方式（命令或测试片段）、建议修法。拿不准的标"疑问"而不是定级。

## 报告格式（`evidence/i0/review-i0.md`）
1. 范围与方法（看了什么、跑了什么，命令原文）；2. 发现清单（按级别排序）；3. 已核对无问题的项（逐条，便于以后不重复审）；4. 对 I-1 的建议（不超过 10 条）；5. 复现输出索引（`evidence/i0/review-i0/*.txt`）。

## 回复格式
报告路径；blocker/major/minor 各几条，blocker 与 major 的一句话摘要；疑问清单。
