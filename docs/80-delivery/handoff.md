# 接续说明（handoff）

> 新会话或上下文压缩后从这里开始。读完本文与 `ios-first-plan.md` 即可继续，不需要翻历史对话。最后更新：2026-10-18。

## 1. 当前状态

- 方向：**只做 iOS 端，纯本地模式**；后端已冻结（见 `m0-execution-plan.md` 状态行）。
- 仓库：`YePiXpert/cardflow`（公开，main）。本机 /projects/cardflow 已 `git init` 并与远端同步；`gh` 已登录。
- Flutter 3.47.7 stable 在 `/opt/flutter-sdk`（`export PATH=/opt/flutter-sdk/bin:$PATH`）；本机只能 analyze / test / build web。
- iOS 构建：GitHub Actions `macos-26` runner，`flutter build ios --release --no-codesign` → 未签名 IPA artifact；用户自己签名安装。Bundle ID `li.yep.cardflow`（不可改）。
- 服务器上的 `cardflow`、`cardflow-dev` Compose 项目已停止，卷保留（`cardflow_pgdata`、`cardflow_attachments`、`cardflow-dev_pgdata`）。
- 进行中：**I-0a**（Flutter 骨架 + iOS 配置 + CI 出第一个未签名 IPA），简报见 `briefs/I0-a.md`，证据目录 `evidence/i0/I0-a/`。

## 2. 如何判断 I-0a 做到哪了

1. `git log --oneline -10` 与 `git status`：看 apps/mobile、.github/workflows/mobile.yml 是否已提交。
2. `ls evidence/i0/I0-a/`：按简报的验收清单核对哪些证据已存在。
3. `gh run list --workflow mobile.yml --limit 5`：看 dart / ios-unsigned job 是否跑过、是否绿。
4. 若代理被用量上限打断：同一会话用 SendMessage 续跑；新会话则按 `briefs/I0-a.md` 重新派发，并在简报开头注明"先核对磁盘现状，不要重复创建"。

## 3. 下一步（按顺序，一次一个代理）

1. 核对 I-0a 的 IPA：`unzip -l` 结构为 `Payload/Runner.app`，Info.plist 的 CFBundleIdentifier=li.yep.cardflow、MinimumOSVersion=15.0。把 artifact 链接给用户，等用户签名安装反馈（能装、能打开、诊断页能复制）。
2. **I-0b**：加密本地库 PoC-1（drift + sqlite3 构建钩子 sqlite3mc；运行时 `PRAGMA cipher_version` 非空；密钥存 Keychain WhenUnlockedThisDeviceOnly；失败回退 sqflite_sqlcipher）+ 诊断页登记加密状态。出第二个 IPA 让用户回传 cipher_version。
3. **I-0c**：Dart 领域层移植（Money/EventTime、账期、现金时间线、验证器、有限搜索 K≤3）+ Dart fixture 运行器：读 `packages/rules-protocol/schema/v1`、`fixtures/*.v1.json`，复现 README 的规范化哈希（F-18 的 `protocol_input_hash` = `ea990327f08b42d476fa157d9bb8ddff6a1d8eb4e41ff60b1e498c5861a91ee8`），cycles/verify 两类 case 全过；Python 引擎 1.1.0 是对照基准，语义以 `docs/30-rules-engine/engine-spec.md` §12/§12.1 为准。
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

- I-0a 的 IPA 签名安装结果（能否安装、打开、复制诊断信息）。
- 以后每个阶段的真机反馈：诊断页导出 + 问题描述；崩溃时附 iPhone"设置 › 隐私与安全性 › 分析与改进"里的崩溃日志。
