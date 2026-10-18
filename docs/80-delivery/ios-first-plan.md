# 84 · iOS 优先执行计划（2026-10-18 重排）

版本 0.1 · 2026-10-18 · 状态：**执行中（I-0 代码与阶段末审查完成，待真机回传；I-1 执行中，当前 I1-a）**。用户于 2026-10-18 确认：公开仓库 `YePiXpert/cardflow`，Bundle ID `li.yep.cardflow`。本文取代 `m0-execution-plan.md` 的后续波次安排；M0 批次 A 已完成的部分冻结保留（§6）。

## 1. 为什么重排

- PRD 的默认使用模式是"纯本地、无账号、不需要服务器"，App 本身就是完整产品；此前两天的实现全部在可选的自托管后端上，用户没有任何可用的东西。
- 用户只需要 iOS 端；没有 Mac；有自己的签名证书，自行签名安装。
- 后端的加固深度（78 条 RLS 策略、5 个角色、清除令牌等）对应的是多设备同步阶段，不是当前阶段。

## 2. 构建与分发方式（ADR-015 修订）

| 环节 | 位置 | 说明 |
|---|---|---|
| 开发、分析、Dart 测试、全量编译检查 | 本服务器（Linux，Flutter SDK） | `flutter analyze`、`flutter test`、`flutter build web` 作为编译烟雾测试 |
| iOS 构建 | GitHub Actions `macos-26` runner（Xcode 26.x） | `flutter build ios --release --no-codesign` → 打包 `Payload/Runner.app` 为未签名 `.ipa` → 上传为 workflow artifact |
| 签名与安装 | 用户 | 用自有证书与非 Mac 工具签名后安装；项目不接触证书 |
| 真机反馈 | 用户 iPhone | 应用内诊断页（无个人数据的日志、设备信息、加密状态）可导出截图/文本发回 |

CI 设计：
- **Linux job**（每次 push）：`flutter analyze`、`flutter test`、`flutter build web`；服务端 pytest 只在相关路径变更时运行。
- **macOS job**（手动触发或 `ios-*` 标签）：出未签名 IPA；缓存 pub 与 Pods；单次约 10–20 分钟。
- **分钟预算**：macOS 分钟按 10 倍计；私有仓库免费池 2,000 分钟/月 ≈ 200 macOS 分钟 ≈ 每月约 10–15 次 iOS 构建；公开仓库不计费。所以 iOS 构建只在阶段交付或修复 iOS 原生配置时触发，日常验证走 Linux job。
- 仓库只含源码与规划文档；secret 文件已在 `.gitignore`；首次推送前做一次口令泄露扫描。

无 Mac 带来的限制与对策：
- 无模拟器、无 Xcode 日志 → 应用内诊断页 + 结构化本地日志导出（不含金额与正文）。
- iOS 原生配置错误（Info.plist、钩子编译、Pods）只能在 CI 上暴露 → 第一阶段先用最小原生面，第一个 IPA 只验证管线与加密库。
- v1 不使用任何特殊 entitlement（不做推送、不做分享扩展），任何证书重签都能安装与覆盖升级；Bundle ID 与签名身份自始至终不变，否则本地数据丢失。

## 3. 阶段

| 阶段 | 内容 | 交付的 IPA 能做什么 | 退出条件 |
|---|---|---|---|
| **I-0 管线、骨架与关键验证** | GitHub 仓库与 CI；Flutter 工程（Riverpod、go_router、主题、金额组件、五导航）；加密本地库（PoC-1，sqlite3mc 钩子，失败回退 sqflite_sqlcipher）；Dart 领域层移植（Money/EventTime、账期、现金时间线、验证器、有限搜索）；Dart fixture 运行器；iOS 工程配置（Bundle ID 经 xcconfig、PrivacyInfo、文档类型、Face ID 说明）；诊断页 | 空壳可导航；建库加密生效；诊断页显示加密库与算法 | CI 出 IPA；用户安装成功并回传诊断页；F-18 在 Dart 运行器 cycles/verify 两类 case 全过 |
| **I-1 卡片、账期、现金流** | 首次使用与演示模式；建卡/信用账户/币种子账户/额度快照；手工交易、账单版本、分期；还款登记与状态；现金账户、快照、收支计划、三口径、情景；资金日历与缺口 | 开始记真实数据 | 对应 F-01~F-08、F-12~F-17、F-19~F-28 的 Dart fixture 通过；用户真机走通 UF-1/3/5 |
| **I-2 智能用卡（本地）** | 规划输入、三类方案、解释、拒绝原因、"本地未找到（非证明）"标注；采纳→预留→关联真实交易→过期 | 规划一笔消费怎么刷 | F-09~F-11、F-67~F-69（有限搜索可达的部分）；UF-4 |
| **I-3 导入** | file_picker 与"用其他应用打开"接 PDF/CSV/.eml；PDF 文本层（pdfrx）；截图 OCR（ML Kit 中文）；校对、去重、入账、回滚 | 导账单 | F-47~F-53 设备端版本；UF-2 |
| **I-4 其余模块** | 活动/权益/积分/年费（规则解释器、手工录入活动）；本地提醒；统计；加密备份与恢复；应用锁、金额隐藏、遮罩 | 完整 v1（纯本地） | F-40~F-46、F-63、F-66；UF-6/7/9；TC-SEC-M01~M06 |
| **后置** | 自托管同步与服务端 CP-SAT（复用已冻结的后端）；分享扩展（需 App Group entitlement） | — | 用户决定要多设备时启动 |

有限搜索（K≤3、候选切点）对个人持卡规模足够；服务端 CP-SAT 仅在多卡大规模时才有必要。

## 4. I-0 任务清单

| ID | 任务 | 验收 |
|---|---|---|
| I0-1 | 本地 `git init`、`.gitignore` 复核、口令泄露扫描、推送到 GitHub | 远端有首个提交；扫描 0 命中 |
| I0-2 | 服务器安装 Flutter SDK（版本写死，与 CI 一致）；`flutter doctor` 记录 | 证据 |
| I0-3 | `apps/mobile` 工程骨架：Riverpod、go_router、主题 token、金额组件、五导航空页面、诊断页 | `flutter analyze` 零警告；widget 测试 |
| I0-4 | CI：Linux job + macOS job（未签名 IPA artifact）；首个 IPA 由用户安装 | artifact 可下载；用户回传安装成功 |
| I0-5 | 加密 drift（PoC-1）：钩子方案；运行时加密自检（ADR-001）；密钥存 Keychain（WhenUnlockedThisDeviceOnly） | 诊断页显示非空版本；10 万行冷启动 <1 s（真机，用户回传） |
| I0-6 | Dart 领域层移植 + Dart fixture 运行器（读 `packages/rules-protocol` 的 schema 与 v1 fixture，复现规范化哈希） | F-18 cycles/verify 全过；`protocol_input_hash` 与 Python 一致 |
| I0-7 | 有限搜索（K≤3）与"非证明"标注 | 样本返回 A8000+C2000 可行；K=1 返回"本地未找到" |
| I0-8 | iOS 工程配置：最低 iOS 15、Bundle ID 与团队经 xcconfig 注入、PrivacyInfo.xcprivacy、文档类型、用途说明 | CI 构建通过；仓库无团队 ID |

顺序：I0-1 → I0-2 → I0-3 → I0-4（先出第一个空壳 IPA 验证管线）→ I0-5 → I0-6 → I0-7 → I0-8 随 I0-5 的 IPA 一起验证。

## 4b. I-1 任务清单（2026-10-18 拆分，一次一个代理）

| ID | 任务 | 简报 | 验收 |
|---|---|---|---|
| I1-a | 本地库 v2（工作空间、银行、授信池、信用账户、币种子账户、卡片、账期规则版本、额度快照）；真实/演示工作空间与隔离；P-22、P-02、P-03 最小版、P-04、P-01 最小版；BL-06、BL-07 | `briefs/I1-a.md` | F-19~F-27、F-14 数据侧的仓库测试；新建 vs 升级结构一致；隔离测试；analyze/test/web 绿；不出 IPA |
| I1-b | 本地库 v3（现金账户、快照与包含事件、现金事件、周期事项、调拨、情景与版本）；P-08、P-07、P-09、P-01 现金压力卡 | `briefs/I1-b.md` | F-01~F-05、F-07 经仓库映射与领域包直算一致；周期覆盖/跳过；不出 IPA |
| I1-c | 本地库 v4（交易、账单与追加只读版本、分期、还款与分配、差异项）；P-05、P-06、P-03 补齐、P-01 近期到期/待办；演示数据补齐；**阶段交付 IPA** | `briefs/I1-c.md` | F-06、F-21、F-24、F-28、F-30~F-38；金额列 UPDATE 触发器；IPA 出包；用户真机走通 UF-1/3/5 |

I-1 退出条件不变（§3）。I1-a 的前置：I-0 阶段末审查（`briefs/review-i0.md`）的 blocker/major 已修。

## 5. 执行方式

- 一次只运行一个实现代理；审查代理只在阶段结束时跑一次，只修 blocker/major，其余记入 `docs/80-delivery/backlog.md`。
- 简报不中途追加需求。
- 每个阶段结束：Linux 验证 → 触发一次 macOS 构建 → 用户安装与反馈 → 修复 → 进入下一阶段。
- 真机反馈格式：诊断页导出 + 问题描述；崩溃时附系统"分析数据"中的崩溃日志（设置 › 隐私与安全性 › 分析与改进）。

## 6. 已完成后端的处置

- M0 批次 A 已验证的 10 项（T-001~T-008、T-014、T-006）冻结，不再审查修复；T-011/T-012/T-030 在中断处冻结，代码保留。
- 服务器上的 `cardflow`、`cardflow-dev` 两个 Compose 项目停止（保留数据卷）。
- Python 引擎（1.1.0）与协议 v1、派生 fixture 是 Dart 移植的对照基准；后端其余部分留给"后置"阶段。

## 7. 风险

| 风险 | 对策 |
|---|---|
| sqlite3mc 构建钩子在 CI 的 macOS 上编译失败 | 回退 sqflite_sqlcipher（ADR-001 备选） |
| iOS 原生配置错误只能在 CI 暴露，每次迭代消耗 macOS 分钟 | 最小原生面；先出空壳 IPA；错误日志作为 artifact 保存 |
| 用户签名工具对 IPA 结构有要求 | 标准 `Payload/Runner.app` 结构；嵌套 Framework 由签名工具处理；首个 IPA 即验证 |
| 无法在本地复现真机问题 | 诊断页与日志导出；必要时加临时调试开关（Release 关闭） |
| ML Kit 中文模型体积（约 38 MB/脚本） | I-3 再引入，并记录包体增量 |

## 8. 待用户决定

| 编号 | 事项 | 默认 |
|---|---|---|
| P-1 | GitHub 仓库 | **已定**：`YePiXpert/cardflow`（2026-10-18 创建） |
| P-2 | 仓库可见性 | **已定**：公开（用户决定；macOS 构建分钟不计费）。因此仓库内不得出现宿主服务清单、端口清单、口令、令牌；首次推送前已做清理与扫描 |
| P-3 | Bundle ID（之后不可改） | **已定**：`li.yep.cardflow` |
| P-4 | 停止服务器上的后端部署与开发库（保留卷） | **已完成**（2026-10-18；卷 cardflow_pgdata、cardflow_attachments、cardflow-dev_pgdata 保留） |
| P-5 | 服务器安装 Flutter SDK | **已完成**（2026-10-18，Flutter 3.47.7 stable，/opt/flutter-sdk；只用于 analyze/test/web 编译检查） |

## 9. 执行记录

| 日期 | 事项 |
|---|---|
| 2026-10-18 | 仓库 `YePiXpert/cardflow` 创建并推送首个提交（377 文件；宿主服务清单已脱敏；无 Claude 署名）；后端两个 Compose 项目停止；Flutter 3.47.7 安装；I-0a（骨架 + iOS 配置 + CI 未签名 IPA）派发 |
| 2026-10-18 | I-0a 完成并验收：analyze 零输出、104 项测试、CI dart job 两次绿、ios-unsigned 首次即成功（Xcode 26.6，3m51s）；IPA `cardflow-unsigned-eaed4a8`（Bundle ID、MinimumOSVersion 15.0 核对无误）。I-0b 派发 |
| 2026-10-18 | I-0b 完成并验收：sqlite3mc 钩子方案成功、未回退；153 项测试；CI dart/ios 各一次绿（iOS 2m23s）；IPA `cardflow-unsigned-4d720c9`（含 sqlite3mc.framework 2.6.1）。发现 `PRAGMA cipher_version` 为 SQLCipher 专有，文档改为"加密自检"。I-0c 派发 |
| 2026-10-18 | I-0c 完成并验收（I0-6、I0-7）：纯 Dart 领域包 `apps/mobile/packages/cardflow_domain`（money/time/billing/cash/verifier/search/protocol，7619 行，禁止 double 扫描 0 违规），265 项测试；F-18 哈希 `ea990327…1ee8` 双端一致；Dart 与 Python 运行器 `--dump` 对 F-18 的 3 个 cycles/verify 输出逐字节一致，另 300 份（CI）+ 24,000 份（本机）随机 fixture 一致；有限搜索 K≤3 返回 A 800000 + C 200000（proven=false，约 18 ms），K=1 返回"本地未找到（非证明无解）"，与 CP-SAT 在 3000 份随机文档上 0 不一致；App 154 项测试、web 构建通过；CI 运行 39113804928、39114057360 dart 与 protocol-parity 全绿。提交 16cb2da…5fd23ca，证据 `evidence/i0/I0-c/`。代理曾被用量上限打断一次，SendMessage 续跑完成。裁决：登记 `test` 1.33.0（dev）；顺延无日历按引擎报 `BILLING_RULE_INVALID`，bank-rules-spec §3.7 已统一；ADR-008 改为自写 `Rational`；其余记 BL-09~BL-12。I-0 代码部分完成，待用户真机回传 IPA 4d720c9 的诊断信息；阶段末审查随后进行 |
| 2026-10-18 | I-0 阶段末审查完成（`evidence/i0/review-i0.md`）：blocker 0、major 0、minor 15、疑问 5；双端差分 18,000 盲区输出 + 20,000 变异文档 + 5,489 JSON 用例 + 5,000 搜索对照只见一处 Dart 更严格的分歧。处置：8 条进 I1-a 简报 §6（含 R-15 密钥缓存与重置）、1 条进 I1-b 简报、其余 BL-13~BL-19；裁决 Q-1 有限搜索漏报作 I2-0、Q-2 PrivacyInfo 待扫描、Q-3 v1 暂不混淆、Q-4 随 BL-09。I-1 拆为 I1-a/b/c（§4b），I1-a 派发 |
