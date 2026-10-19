# 接续说明（handoff）

> 新会话或上下文压缩后从这里开始。读完本文与 `ios-first-plan.md` 即可继续，不需要翻历史对话。最后更新：2026-10-19（I-1 审查裁决、F-1 派发后）。

## 1. 当前状态

- 方向：**只做 iOS 端，纯本地模式**；后端已冻结（见 `m0-execution-plan.md` 状态行）。
- 仓库：`YePiXpert/cardflow`（公开，main）。本机 /projects/cardflow 已 `git init` 并与远端同步；`gh` 已登录。
- Flutter 3.47.7 stable 在 `/opt/flutter-sdk`（`export PATH=/opt/flutter-sdk/bin:$PATH`）；本机只能 analyze / test / build web。
- iOS 构建：GitHub Actions `macos-26` runner，`flutter build ios --release --no-codesign` → 未签名 IPA artifact；用户自己签名安装。Bundle ID `li.yep.cardflow`（不可改）。
- 服务器上的 `cardflow`、`cardflow-dev` Compose 项目已停止，卷保留（`cardflow_pgdata`、`cardflow_attachments`、`cardflow-dev_pgdata`）。
- 已完成：**I-0a**（Flutter 骨架、主题、金额组件、诊断页；iOS 配置；CI）。第一个未签名 IPA：https://github.com/YePiXpert/cardflow/actions/runs/39098193527/artifacts/12125766769（源码 eaed4a8，sha256 53e46d9e…，2026-11-01 过期）。证据 `evidence/i0/I0-a/`。
- 已完成：**I-0b**（drift + sqlite3mc 钩子加密库、Keychain 原始密钥、失败即止、诊断页加密状态与 10 万行基准）。第二个 IPA：https://github.com/YePiXpert/cardflow/actions/runs/39101728143/artifacts/12126439551（源码 4d720c9，sha256 4119031e…，2026-11-01 过期；4 个嵌套 framework 需一并重签）。证据 `evidence/i0/I0-b/`。
- 已完成：**I-0c**（纯 Dart 领域包 `apps/mobile/packages/cardflow_domain`：金额/日期/账期/现金时间线/验证器/有限搜索/协议 v1 适配与哈希；Dart fixture 运行器 `dart run cardflow_domain:run_fixtures [--dump DIR]`；Python 运行器 `--dump`；CI `protocol-parity` job 双端逐字节一致）。265 项领域测试、App 154 项；CI 运行 39114057360 全绿。不出 IPA。证据 `evidence/i0/I0-c/`。I-1 的领域包 API 说明见 `apps/mobile/README.md`"领域层"一节与 `packages/rules-protocol/README.md` 末节。
- I-0 阶段末审查已完成（报告 `evidence/i0/review-i0.md`，简报 `briefs/review-i0.md`）：blocker 0、major 0、minor 15、疑问 5。处置：R-15/R-03/R-08 等 8 条写入 `briefs/I1-a.md` §6，1 条写入 `briefs/I1-b.md` §5，其余记 backlog BL-13~BL-19；疑问裁决：有限搜索漏报（R-01）作 I-2 第一个任务 I2-0（BL-15）；PrivacyInfo 保留待 I1-c 扫描二进制（BL-16）；v1 暂不混淆（BL-17，security-privacy §3 已注明）。I-0 阶段退出只差用户真机回传。
- 已完成：**I1-a**（本地库 v2：9 张 STRICT 表、冻结迁移 SQL、11 索引 10 触发器；仓库层与领域映射；真实/演示工作空间与隔离；P-22/P-02/P-03 最小版/P-04/P-01 最小版；审查带入项 R-15/R-03/R-08 等全部落实）。291 项 App 测试；CI 运行 39140901236 绿；13 个提交（c82d9a0…012542a）。证据 `evidence/i1/I1-a/`。偏离与约定见 `apps/mobile/README.md` 的"I-1a 的偏离与约定"一节，主会话已接受并登记（data-model §10.14、BL-20/BL-21）。
- 已完成：**I1-b**（本地库 v3：现金账户、余额快照与包含事件、现金事件、周期事项与单期例外、情景与计算版本共 8 张 STRICT 表，冻结 2→3 迁移，13 索引、9 触发器；现金仓库层与领域映射，审查 §5 交叉规则复刻 `checkCashTimelineInputs`；演示空间现金数据（固定今天下基准口径 30 天内一个可见缺口）；P-08、P-07（只做表格视图）、P-09、P-01 现金压力卡；给 I-1c 的还款扣款接口 `planRepaymentDebit`/`confirmRepaymentDebit`/`cancelRepaymentDebit`）。385 项 App 测试；F-01~F-05、F-07 经仓库映射与领域包直算逐字段一致；CI 运行 39147014570 绿；10 个提交（201c8da…da46d65）。证据 `evidence/i1/I1-b/`。偏离见 `apps/mobile/README.md` 的"I-1b 的偏离与约定"一节，主会话 2026-10-19 全部接受并登记（data-model §10.14、BL-22~BL-24）。代理违反"一次一个代理"派了一个只读子审查代理，被用量上限打断、无产出；现金数据层的审查并入 I-1 阶段末审查。
- 已完成：**I1-c + I1-c2**（本地库 v4：交易、账单与追加只读版本、分期计划与各期、还款与分配、差异项共 8 张表，冻结 3→4 迁移；领域包分期模块 `installment.dart`，与 Python `money.py` 7 组样本对照；P-05 账单中心、P-06 还款登记与核对、P-03 补齐、P-01 近期到期与待办；演示数据补齐；BL-14 CI action 固定 SHA 与产出数断言；BL-16 Required Reason 扫描并删去 UserDefaults 声明；BL-18、BL-21；公测版改动：界面去掉内部阶段代号与规格编号、P-22 与「关于」的公测说明、App 图标、版本 0.0.1）。App 489 项、领域包 279 项测试。提交 4c77d44…83be815，证据 `evidence/i1/I1-c/` 与 `evidence/i1/release-0.0.1/`。I1-c 代理被用户停止过一次，由 I1-c2 新代理接续完成（被用量上限打断一次，续跑完成）。偏离全部接受并登记（data-model §10.14、BL-25~BL-31）。
- **公测版 0.0.1 已发布**（2026-10-19）：GitHub 预发布版 https://github.com/YePiXpert/cardflow/releases/tag/ios-v0.0.1 。标签 `ios-v0.0.1` 指向 83be815；构建 #55（运行 39268709025，dart/protocol-parity/ios-unsigned 全绿）；附件 `cardflow-0.0.1-unsigned.ipa`，10,466,921 字节，sha256 `2582c768e05406041913b3188fabd578161110aeb0e4f9ff654d09572fc720b9`（从发布页下载回来复核一致）。版本 0.0.1、构建号 55、Bundle ID、最低 iOS 15.0、图标与 4 个嵌套 framework 的 17 项检查全部通过。发版说明含公测须知、已知问题、安装与反馈。
- **真机回传（2026-10-19）**：用户装上 0.0.1（构建 55，iOS 27.0），诊断信息显示加密库已启用（SQLite3 Multiple Ciphers 2.6.1，chacha20）、密钥已生成、10 万行基准 open + count = 9 ms、启动到数据库打开 176 ms、Bundle ID 未被改写。ADR-001 PoC-1 真机通过（不回退 sqflite_sqlcipher），I-0 退出条件全部满足。原文 `evidence/i1/device-0.0.1/diagnostics-2026-10-19.txt`。
- 宣传视频：分支 `promo-video` 的 `docs/90-promo/`（未合入 main，是否合入由用户决定）。

## 2. 如何判断进行中任务做到哪了

1. `git log --oneline -10` 与 `git status`：看该任务路径是否已提交。
2. `ls evidence/i1/<任务>/`（I-0 的在 `evidence/i0/`）：按简报的验收清单核对哪些证据已存在。
3. `gh run list --workflow mobile.yml --limit 5`：看 dart / ios-unsigned job 是否跑过、是否绿。
4. 若代理被用量上限打断：同一会话用 SendMessage 续跑；新会话则按 `briefs/<任务>.md` 重新派发，并在简报开头注明"先核对磁盘现状，不要重复创建"。

## 3. 下一步（按顺序，一次一个代理）

1. **等用户真机走通 UF-1/UF-3/UF-5**（诊断信息已回传且全部达标，见 §1）：建卡与账期、登记还款到银行确认、资金日历与情景对比；记下卡住的地方，连同诊断信息回传。这是 I-1 退出条件里唯一还差的一项。
2. **I-1 阶段末审查已完成**（报告 `evidence/i1/review-i1.md`，blocker 2、major 3、minor 11、疑问 5；主会话亲自跑探针复核了 R-01、R-02 三种情形与 R-03）。裁决：账单接续与有效状态在读模型层推导（PRD §6.2 裁决段，F-33 按接续语义调整），已出账消费转分期允许并调整本期应还，设备备份保留、改说明文案，资金日历先加"未计入"提示（BL-33），入账日未知按保守口径并提示补入账日。处置：R-01/R-02/R-03/R-04/R-06/R-07/R-08/R-11/R-12/R-15/R-16/Q-3 → **F-1**（`briefs/F-1.md`，进行中）；R-09/R-10/Q-1/Q-2/BL-26 → U-1 §9；R-05 → L-1；R-14 → BL-32；R-13 主会话已改（证据文件头不再写宿主运行身份）。
3. **0.0.2 界面重做（U-1）**（F-1 之后派发；F-1 + U-1 一起发 0.0.2）：用户 2026-10-19 反馈 0.0.1"界面太丑，没有使用欲望"，并拿正在用的信用卡小程序对比"能看出多少钱和日期"。主会话在 iPhone 尺寸下渲染核对后出了设计稿 `docs/50-ui/mockups/0.0.2/`（卡账首页深/浅色、卡片详情、现金），写好简报 `briefs/U-1.md`：4 个标签（卡账/现金/规划/我的），首页每张卡一行显示待还、账单、N 天后出账、N 天后还款，"今天刷哪张"免息天数，快捷"记本期账单""还清本期"，现金余额曲线，新颜色与数字字号。审查交回并裁决后派发（审查的 blocker/major 先修或追加到简报末尾）；完成后主会话截图验收，按第 5 条发 0.0.2。
4. **0.0.3 消费贷（L-1）**：用户 2026-10-19 补充"另外还有消费贷要还，目前是按月付息到期还本"。登记为 PRD R-CASH-11，设计稿加了首页"贷款"分组与 `loan-dark.png`，简报 `briefs/L-1.md`（本地库 v5：loans、loan_payments；按月固定/按日 360/365 计息，有理数、四舍五入到分；还款计划可逐期更正、标记已还；未付期进资金日历与尾部责任；首页贷款分组与详情、表单）。U-1 验收后派发；完成后发 0.0.3。用户在此之前可以先用"现金 › 收支计划"的周期事项（类型其他债务，每月利息）加一次性支出（到期本金）记着，资金日历能算进去。
5. **I-2**：第一个任务 I2-0（BL-15 有限搜索漏报 + BL-23 交叉规则改为领域包公开函数），然后消费规划（`ios-first-plan.md` §3）。
6. 发下一个公测版的步骤：main 上 CI 绿 → `git tag -a ios-v<版本> <提交> -m ...` → 推送标签触发 ios-unsigned → `gh run download` 到新空目录，用 `evidence/i1/I1-c/ipa-inspect.txt` 文末的 inspect_ipa.py 检查 → `gh release create <标签> --verify-tag --prerelease --notes-file ... <ipa>` → 下载回来复核 sha256。版本号改 `apps/mobile/pubspec.yaml` 与 `lib/features/settings/public_beta.dart` 的 `PublicBeta.version`（测试会断言两者一致）。

## 4. 执行规则（已与用户约定）

- 一次只跑一个实现代理，实现代理不得再派子代理（I1-b 曾违反）；审查只在阶段末由主会话派一次，只修 blocker/major，其余记 `backlog.md`。
- 简报不中途追加需求。
- **提交、PR、代码、文档中不出现 Claude / AI 署名**（用户要求）；提交身份 `YePiXpert <YePiXpert@users.noreply.github.com>`。
- 公开仓库：不得出现宿主服务清单、端口清单、口令、令牌、用户邮箱；推送前扫描。
- iOS 构建只在阶段交付或修 iOS 原生配置时触发。
- 宿主是用户的生产 VPS：不碰其他容器、/opt 下其他目录、系统配置；不连接 127.0.0.1:5432。
- 证据必须是工具原文（tee），不得省略成 `<关键行>`/`...`；证据中过滤宿主发行版/内核/代理状态行（`grep -Ev`）并在文件头注明（审查 R-10/R-11）。
- 用量上限将至时：更新本文 §1–§3 与记忆文件，提交推送，再停。

## 5. 待用户的事

- 公测版 0.0.1 已装好并回传诊断信息（全部达标）。还差：按发版说明走通 UF-1/UF-3/UF-5，把卡住的地方与诊断信息一起发回。
- 以后每个阶段的真机反馈：诊断页导出 + 问题描述；崩溃时附 iPhone"设置 › 隐私与安全性 › 分析与改进"里的崩溃日志。
