# 接续说明（handoff）

> 新会话或上下文压缩后从这里开始。读完本文与 `ios-first-plan.md` 即可继续，不需要翻历史对话。最后更新：2026-10-18（I-0b 验收后）。

## 1. 当前状态

- 方向：**只做 iOS 端，纯本地模式**；后端已冻结（见 `m0-execution-plan.md` 状态行）。
- 仓库：`YePiXpert/cardflow`（公开，main）。本机 /projects/cardflow 已 `git init` 并与远端同步；`gh` 已登录。
- Flutter 3.47.7 stable 在 `/opt/flutter-sdk`（`export PATH=/opt/flutter-sdk/bin:$PATH`）；本机只能 analyze / test / build web。
- iOS 构建：GitHub Actions `macos-26` runner，`flutter build ios --release --no-codesign` → 未签名 IPA artifact；用户自己签名安装。Bundle ID `li.yep.cardflow`（不可改）。
- 服务器上的 `cardflow`、`cardflow-dev` Compose 项目已停止，卷保留（`cardflow_pgdata`、`cardflow_attachments`、`cardflow-dev_pgdata`）。
- 已完成：**I-0a**（Flutter 骨架、主题、金额组件、诊断页；iOS 配置；CI）。第一个未签名 IPA：https://github.com/YePiXpert/cardflow/actions/runs/39098193527/artifacts/12125766769（源码 eaed4a8，sha256 53e46d9e…，2026-11-01 过期）。证据 `evidence/i0/I0-a/`。
- 已完成：**I-0b**（drift + sqlite3mc 钩子加密库、Keychain 原始密钥、失败即止、诊断页加密状态与 10 万行基准）。第二个 IPA：https://github.com/YePiXpert/cardflow/actions/runs/39101728143/artifacts/12126439551（源码 4d720c9，sha256 4119031e…，2026-11-01 过期；4 个嵌套 framework 需一并重签）。证据 `evidence/i0/I0-b/`。
- 进行中：**I-0c** Dart 领域层移植 + Dart fixture 运行器 + 有限搜索，简报见 `briefs/I0-c.md`，证据目录 `evidence/i0/I0-c/`。本任务不出 IPA。

## 2. 如何判断进行中任务做到哪了

1. `git log --oneline -10` 与 `git status`：看该任务路径是否已提交。
2. `ls evidence/i0/<任务>/`：按简报的验收清单核对哪些证据已存在。
3. `gh run list --workflow mobile.yml --limit 5`：看 dart / ios-unsigned job 是否跑过、是否绿。
4. 若代理被用量上限打断：同一会话用 SendMessage 续跑；新会话则按 `briefs/<任务>.md` 重新派发，并在简报开头注明"先核对磁盘现状，不要重复创建"。

## 3. 下一步（按顺序，一次一个代理）

1. 等用户对第一个 IPA 的签名安装反馈（能装、能打开、诊断页能复制）；不阻塞 I-0b。
2. 等用户对第二个 IPA 回传：加密库状态应为"已启用（SQLite3 Multiple Ciphers 2.6.1，算法 chacha20）"，密钥"已生成"，基准 `open_ms + count_ms < 1000`。
3. **I-0c**（进行中）：Dart 领域层移植（Money/EventTime、账期、现金时间线、验证器、有限搜索 K≤3）+ Dart fixture 运行器：读 `packages/rules-protocol/schema/v1`、`fixtures/*.v1.json`，复现 README 的规范化哈希（F-18 的 `protocol_input_hash` = `ea990327f08b42d476fa157d9bb8ddff6a1d8eb4e41ff60b1e498c5861a91ee8`），cycles/verify 两类 case 全过；Python 引擎 1.1.0 是对照基准，语义以 `docs/30-rules-engine/engine-spec.md` §12/§12.1 为准。
4. 之后进入 I-1（卡片、账期、现金流），见 `ios-first-plan.md` §3。

## 4. 执行规则（已与用户约定）

- 一次只跑一个实现代理；审查只在阶段末跑一次，只修 blocker/major，其余记 `backlog.md`。
- 简报不中途追加需求。
- **提交、PR、代码、文档中不出现 Claude / AI 署名**（用户要求）；提交身份 `YePiXpert <YePiXpert@users.noreply.github.com>`。
- 公开仓库：不得出现宿主服务清单、端口清单、口令、令牌、用户邮箱；推送前扫描。
- iOS 构建只在阶段交付或修 iOS 原生配置时触发。
- 宿主是用户的生产 VPS：不碰其他容器、/opt 下其他目录、系统配置；不连接 127.0.0.1:5432。
- 用量上限将至时：更新本文 §1–§3 与记忆文件，提交推送，再停。

## 5. 待用户的事

- 两个 IPA 中任选较新的（4d720c9）签名安装；装好后 我的 › 诊断信息 › 先点「运行数据库基准（10 万行）」再「复制诊断信息」发回。签名时 Frameworks 目录下 4 个嵌套 framework（App、Flutter、objective_c、sqlite3mc）一并重签。
- 以后每个阶段的真机反馈：诊断页导出 + 问题描述；崩溃时附 iPhone"设置 › 隐私与安全性 › 分析与改进"里的崩溃日志。
