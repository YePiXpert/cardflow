# 接续说明（handoff）

> 新会话或上下文压缩后从这里开始。读完本文与 `ios-first-plan.md` 即可继续，不需要翻历史对话。最后更新：2026-10-19（I1-b 验收、I1-c 派发后）。

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

## 2. 如何判断进行中任务做到哪了

1. `git log --oneline -10` 与 `git status`：看该任务路径是否已提交。
2. `ls evidence/i1/<任务>/`（I-0 的在 `evidence/i0/`）：按简报的验收清单核对哪些证据已存在。
3. `gh run list --workflow mobile.yml --limit 5`：看 dart / ios-unsigned job 是否跑过、是否绿。
4. 若代理被用量上限打断：同一会话用 SendMessage 续跑；新会话则按 `briefs/<任务>.md` 重新派发，并在简报开头注明"先核对磁盘现状，不要重复创建"。

## 3. 下一步（按顺序，一次一个代理）

1. **I1-c 做到一半被用户停止**（2026-10-19 派发，代理于当天被用户在界面上停止，不是用量上限；已做并推送 6 个提交 4c77d44 v4 表、5af9a89 领域包分期模块、b161f62 账单与还款数据层、2cee4b4 P-05/P-06/P-03/P-01、ceebeb1 演示数据、6486fbf BL-21/BL-18，前 5 个 CI 绿；工作树只剩未提交的 `evidence/i1/I1-c/installment-parity.txt`。**未做**：P-05/P-06 组件测试是否齐全待核、简报 §6 第 7 条 CI 固定 SHA 与产出数断言、第 8 条 Required Reason 扫描、apps/mobile README 与根 README、触发 ios-unsigned 出 IPA、证据全套、汇报。重新派发时须是新代理，简报开头加"先核对磁盘与 git 现状，不要重复创建"并附上面的提交清单。原任务说明——简报 `briefs/I1-c.md`，其 §6 是派发前补的带入项与裁决；证据 `evidence/i1/I1-c/`）：本地库 v4（交易、账单与追加只读版本、分期、还款与分配、差异项）；领域包新增分期拆分与 IRR 模块（主会话裁决，简报 §6 第 1 条，与 Python `money.py` 对照）；P-05、P-06、P-03 补齐、P-01 近期到期/待办；演示数据补齐；CI 固定 action SHA 与 Required Reason API 扫描（BL-14/BL-16）；BL-18、BL-21。结束时触发 ios-unsigned 出第三个未签名 IPA（最多 2 次）。验收后：写 `briefs/review-i1.md` 跑 I-1 阶段末审查（范围 I1-a/b/c 全部，重点现金数据层与还款状态机）→ 用户真机走通 UF-1/3/5 → I-2（第一个任务 I2-0 = BL-15 + BL-23）。
2. 等用户对 IPA 4d720c9 回传：加密库状态应为"已启用（SQLite3 Multiple Ciphers 2.6.1，算法 chacha20）"，密钥"已生成"，基准 `open_ms + count_ms < 1000`。若真机加密库不可用，按 ADR-001 回退 sqflite_sqlcipher（只换 drift 的执行器，领域包与数据层接口不变）。
3. **I-1**（卡片、账期、现金流；`ios-first-plan.md` §3、§4b）拆成的三个单代理任务中 I1-a、I1-b 已验收，只剩 I1-c。真机回传未到时也可继续，但 DB 层必须留在 `openAppDatabase` 抽象之后以便回退。只有 I1-c 触发 iOS 构建。

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

- 两个 IPA 中任选较新的（4d720c9）签名安装；装好后 我的 › 诊断信息 › 先点「运行数据库基准（10 万行）」再「复制诊断信息」发回。签名时 Frameworks 目录下 4 个嵌套 framework（App、Flutter、objective_c、sqlite3mc）一并重签。
- 以后每个阶段的真机反馈：诊断页导出 + 问题描述；崩溃时附 iPhone"设置 › 隐私与安全性 › 分析与改进"里的崩溃日志。
