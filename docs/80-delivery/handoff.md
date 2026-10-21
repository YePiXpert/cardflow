# 接续说明（handoff）

> 新会话或上下文压缩后从这里开始。先读当前状态和本版验收记录即可继续，历史规划按需查阅。最后更新：2026-10-21（小清新界面源码收尾；已发布包仍为原界面的 0.0.3）。

## 1. 当前状态

- **最新视觉修订**：用户反馈上一版模板感过重。已删除叶子插画、渐变、星光与宣传式文案，首页去掉卡片外框，缩小金额/天数字号与分组圆角；改为中性色表面、细线分组，保留绿色操作。最新截图与日志 `evidence/fresh-ui/refined/`，尚无新 IPA。
- **最新界面任务**：用户要求参考小清新 iOS 记账软件的视觉，但用途仍为消费选卡。已实现暖白/薄荷主题、金额输入、推荐卡、简化卡片列表与可展开详情、无数据引导及深色适配；未改变推荐算法、数据库、领域包、协议或后端。本机完整 App 测试 502 通过（2 个截图生成器默认跳过），截图两主题另跑通过，静态分析与 Web 编译通过。当前证据入口 `evidence/fresh-ui/`。本次源码尚无新版 iOS 构建或 IPA，不能复用旧 CI #84 作为新界面已通过 iOS 构建的证据；真机视觉与交互待验收。

- **当前任务 0.0.3**：用户纠正产品用途为「消费刷哪个卡合适」，并要求执行与删除无用功能；目前无真实数据。只做单笔单卡推荐，假设现金充足，保留卡片、额度、账期、我的；旧现金/账单/还款/情景/活动界面及专用 provider、读模型和 UI 测试已删除。数据库 v4、领域包、协议与后端保持不变。
- **实现完成、自动验证通过**：推荐按消费日重算容量与账期，以最早可能还款日保守排序；不创建现金、账单或额度预留。候选 `292135f61a17db19d46ce8034fab2527ee929825`，标签 `ios-v0.0.3`；主分支 CI #83（39607548193）和发布 CI #84（39608237211）通过。505 项 App 测试、279 项领域测试、协议一致性、格式/静态分析/Web 编译与 macOS iOS 构建成功；截图生成器两种主题另跑通过，14 条页面路径可访问性与放大字体检查通过。没有把旧提交的成功结果当作当前验证。
- **0.0.3 安装包已交付**：[GitHub 预发布版](https://github.com/YePiXpert/cardflow/releases/tag/ios-v0.0.3)，`cardflow-0.0.3-unsigned.ipa`，10,161,679 字节；版本 0.0.3、构建 84、Bundle ID `li.yep.cardflow`、最低 iOS 15.0。17 项包检查通过；主程序未签名，四个 framework 仅 ad-hoc；未接触用户签名证书。SHA-256 `d9c8c58fb68be972c6f4ca9ead89ba024aa5fd0ecebc633e42c9342099a25cbd`，发布附件回下载逐字节一致。本机包在 `build/releases/0.0.3/`（不入库），证据 `evidence/selection-0.0.3/`。发布后的交接提交仅更新文档和证据，标签仍指向候选。
- **真机待验收**：当前无本版手机结果。下面 0.0.2/U-1 及更早条目是历史交付事实，旧四标签不再代表当前源码界面。


- 方向：**只做 iOS 端，纯本地模式**；后端已冻结（见 `m0-execution-plan.md` 状态行）。
- **U-1 实现完成**：既有四标签、卡账金额与日期、快捷记账单与还款、现金曲线、隐藏金额与重置入口已核对；本轮没有修改 App 代码或新增功能，既有偏离见移动端 README。
- **自动验证通过**：发布候选 `962b197db25f637ce0aae89ba2b22df026037d7f`，标签 `ios-v0.0.2`。CI #82（39538400992）的 dart、protocol-parity、ios-unsigned 全绿；616 项 App 测试、279 项领域测试通过，2 个截图生成测试按配置跳过；本机另跑 124 项 U-1 专项测试通过。旧 CI #81 的输入等价复用依据与截图复用依据见 `evidence/u1/release-0.0.2/acceptance.md`，本版最终验证来自候选自身的 #82。
- **安装包已交付**（2026-10-21）：[0.0.2 GitHub 预发布版](https://github.com/YePiXpert/cardflow/releases/tag/ios-v0.0.2)，`cardflow-0.0.2-unsigned.ipa`，10,622,591 字节；版本 0.0.2、构建 82、Bundle ID `li.yep.cardflow`、最低 iOS 15.0，17 项包检查通过。主程序未签名，四个嵌套 framework 只有 ad-hoc 签名；未接触用户签名证书。SHA-256 `a2ec03725010fa07a0843bb8b694243b333caeb3526617d5aec13d1e2674805b`，发布后回下载复核一致。证据 `evidence/u1/release-0.0.2/`。
- **真机业务待验收**：0.0.2 覆盖安装、原数据保留、金额/日期、快捷账单与还款、现金与导航、深浅色及放大字体均待本版手机回传；0.0.1 已有加密诊断通过不等于这些流程已通过。本轮到安装包交付为止，不启动消费贷、I-2、导入或其他功能。
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
- 已完成：**F-1**（I-1 审查修复，2026-10-20 验收）：账单接续与有效状态（读模型只读，不再写库）、已出账消费转分期调整、还款只分配到本期且按入账日计算、冲正与修正后自动重新推导、交易删除/补入账日与分期作废入口、差异项由系统关闭、分期成本移到后台 isolate 并记忆化、切换空间回首页与表单空间校验、2x/3x 逐屏检查、CI 版本断言与扫描判失败与缓存 action 固定 SHA。App 534 项、领域包 279 项；提交 7071101…e223a7f；CI #56–#64 绿；证据 `evidence/f1/`。主会话本机复核全过；裁决：放宽"已还清不能修正"（进 U-1 §10）、接受偏大口径（BL-36）与 CI 残余；BL-34/BL-35 登记。
- 宣传视频：分支 `promo-video` 的 `docs/90-promo/`（未合入 main，是否合入由用户决定）。

## 2. 如何判断进行中任务做到哪了

1. `git log --oneline -10` 与 `git status`：看该任务路径是否已提交。
2. `ls evidence/i1/<任务>/`（I-0 的在 `evidence/i0/`）：按简报的验收清单核对哪些证据已存在。
3. `gh run list --workflow mobile.yml --limit 5`：看 dart / ios-unsigned job 是否跑过、是否绿。
4. 若代理被用量上限打断：同一会话用 SendMessage 续跑；新会话则按 `briefs/<任务>.md` 重新派发，并在简报开头注明"先核对磁盘现状，不要重复创建"。

## 3. 本轮收尾与后续边界

1. 0.0.3 当前候选已完成自动验证、iOS 构建、IPA 检查与发布回下载校验。本轮实现与交付结束，等待手机验收，不继续扩展。
2. 手机验收：添加卡片、更新额度和账期；输入金额与日期比较；不足额度与缺资料原因；隐藏金额、放大字体、空间切换；不要求维护现金或账单。
3. 不进入消费贷、导入、多卡拆分、现金约束求解或新产品规划。以前将 0.0.3 预留给消费贷的安排被本轮用途纠正取代，L-1/I-2 保持未启动。
4. 发版：候选 CI 绿 → `ios-v0.0.3` 标签 → macOS `ios-unsigned` → 下载新 artifact → 用既有 `inspect_ipa.py` 检查 → 创建预发布版 → 回下载验证 SHA-256。README 与本文件分别记录实现、自动验证、包交付和真机状态。

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

- 从 0.0.3 发布页下载未签名 IPA，沿用自己的签名身份和 Bundle ID 安装，验证消费选卡流程；真机诊断与具体失败步骤由用户回传。
