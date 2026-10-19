# 待办（非阻塞项，按阶段末审查与实现代理的汇报归集）

| 编号 | 来源 | 事项 | 处置建议 |
|---|---|---|---|
| BL-01 | I-0a | go_router 18 改用从 SDK 拆出的 `material_ui`/`cupertino_ui`；本工程用 SDK 自带 material，每条路由显式 MaterialPage，包内带两套 Material 代码 | I-1 界面成形后评估迁移；迁移前不加表外依赖 |
| BL-02 | I-0a | `ubuntu-latest` 自 2026-10-19 起切到 Ubuntu 26 | dart job 出问题则固定 `ubuntu-24.04` |
| BL-03 | I-0a | Web 编译有一条来自 cupertino_ui 的字体告警（已删 cupertino_icons） | 随 BL-01 处理 |
| BL-04 | I-0a | 金额隐藏开关只在内存；平板侧边栏；减少动效；无工作空间时跳 P-22 | I-1 实现 |
| BL-05 | M0 后端 | `evidence/m0/review-wave2-schema.md` 暂缓项（data-model §10.11）、T-011/T-012/T-030 中断处 | 后端解冻（同步阶段）时处理 |
| BL-06 | I-0b | `lib/data/db/database_providers.dart` 引用 `features/diagnostics/diagnostic_log.dart`（数据层向上依赖） | 诊断日志挪到 `lib/app`，I-1 顺手处理 |
| BL-07 | I-0b | 从备份恢复到新手机时钥匙串无密钥 → `key_missing`，目前无"重置或从备份恢复"入口 | I-1 加重置入口；I-4 的备份恢复流程覆盖 |
| BL-08 | I-0b | 基准的 open_ms 测的是文件缓存热的新连接，不是磁盘冷读 | 记录口径，不再追求真冷读 |
| BL-09 | I-0c | Python 适配层对超出浮点范围的整数 `time_limit_s` 抛未处理的 `OverflowError`，而不是 `ProtocolError`；Dart 端报 `ProtocolError` | 后端已冻结；解冻时修 `protocol.py` 并加拒绝用例；parity 不受影响（该输入在 fixture 中不出现） |
| BL-10 | I-0c | 本地有限搜索只保证可行、不保证最优：切点为上下限、单卡现金余量、补足额、等分、共享额度层剩余（范围 ≤64 时逐一枚举）。带手续费样本 R3E-07 本地得 500000/500000（余量 97000），CP-SAT 最优 497166/502834（余量 97017） | I-2 加"余量平衡"切点（整数三分搜索）；UI 始终显示"非最优证明" |
| BL-11 | I-0c | 已知无影响的双端差异：Dart 严格 JSON 嵌套深度上限 512；Python `parse_json` 实测接受到约 9,998 层、`canonical_json` 约 995 层以上抛错（BL-13）；错误消息措辞不同；fixture 名称校验 Python 的 `pattern` `$` 可匹配末尾换行前、Dart 整串匹配 | 记录即可；任何一端输出都不受影响 |
| BL-12 | I-0c | 领域包能编译到 Web，但 JS 整数语义与 VM 不同；Web 只是编译烟雾测试 | 不处理；若将来做 Web 端需先改 `int` 大数路径 |
| BL-13 | R-I0 Q-4 | 冻结的 Python 端两处未处理异常：`canonical_json` 对孤立代理项作键抛 `UnicodeEncodeError`；约 995 层以上嵌套抛 `RecursionError`（`parse_json` 却接受到约 9,998 层）。两端都拒绝，parity 不受影响 | 与 BL-09 一并在后端解冻时修为 `ProtocolError` |
| BL-14 | R-I0 R-05/R-06 | CI：golden 与 schema 校验步骤只断言"有产出"未断言数量；第三方 action 只固定到大版本标签未固定到提交 SHA（影响用户自签安装的 IPA 的供应链） | I1-c 阶段交付改 CI 时一起做：断言输出文件数 = 期望数；action 固定 SHA 并注明版本 |
| BL-15 | R-I0 R-01/R-02/R-07/R-12/R-14 | 领域包 **I-2 前必修**：R-01 有限搜索切点不含全局底线导致有可行方案却报"本地未找到"（反例 `evidence/i0/review-i0/scripts/global_floor_band.json`，CP-SAT 给 A 600000 + B 400000）；R-02 时间预算是软上限（2000 ms 预算实测 2065 ms），需为最终验证预留；R-07 `bounded_search` CLI 错误输入退出码 255 与文档 0/2 不符；R-12 `Money` 加减无 64 位溢出检查；R-14 `test_limits.py` 边界用例与 R3E-13 运行器用例未移植。另 BL-10 的"余量平衡"切点 | 作为 I-2 的第一个任务 I2-0 派发（含反例做成测试、全局底线切点、预算预留、Python 对照） |
| BL-16 | R-I0 Q-2 | `PrivacyInfo.xcprivacy` 声明 DiskSpace（E174.1）与 UserDefaults（CA92.1），App 自身代码未用到；是否由引擎/插件/sqlite3mc 调用在 Linux 上无法核实 | 保留声明（多报不影响安装）；I1-c 的 iOS 构建在 macOS runner 上扫描二进制符号后再定 |
| BL-17 | R-I0 Q-3 | security-privacy §3 CODE 要求 Release 混淆；v1 自签纯本地阶段**暂不启用** `--obfuscate`：诊断页是唯一反馈渠道，混淆后代码位置不可读且需保管符号文件 | 已在 security-privacy §3 注明；I-4（备份/应用锁）阶段评估随符号文件管理一起启用 |
| BL-18 | R-I0 R-13 | `test/ios/ios_config_test.dart` 遍历目录，有本地签名配置（`CardFlow.local.xcconfig`）的 Mac 上会误报 | 测试排除 `*.local.xcconfig`；I1-c 顺手 |
| BL-19 | R-I0 R-04 | 领域包 `json.dart` 注释写 Python 深度"约 1000"不准（实测约 9,998 层接受、约 995 层 canonical 抛错） | 随 BL-15 改注释 |
| BL-20 | I1-a | "重置本地数据"只要求输入"删除"，ui-spec §4.5 要求的设备认证未做（local_auth 属 I-4） | I-4 应用锁落地时给重置加设备认证 |
| BL-21 | I1-a | P-04 在无规则时预填"10 日 / 当月 28 日"并提示核对；预填值可能被未核对就保存，导致账期错误 | I1-c 顺手改为不预填、必须用户填写（示例文案只作 placeholder） |
| BL-22 | I1-b | 现金账户没有业务时区列，现金日期与"今天"一律按 Asia/Shanghai 解释；手机时区不影响结果，但人在其他时区时现金的"今天"可能与当地差一天 | 同步阶段或 I-4 评估给 `cash_accounts` 加 `business_tz`（限 8 个固定偏移时区，加列只 expand） |
| BL-23 | I1-b | 资金日历的交叉规则在 App 层复刻了一份（`checkCashTimelineInputs`），与领域包 `inputsFromProtocol` 两处维护 | I2-0（BL-15）时在领域包提供公开校验函数（输入领域对象，返回规则标识），App 层改为调用它 |
| BL-24 | I1-b | P-07 只有表格视图（简报允许），ui-spec 的图表↔表格切换未做；"储备虚线"在表格里是图例 + "低于储备"标记 | I-4 打磨阶段补图表（不引入表外依赖，用 CustomPaint） |
| BL-25 | I1-c2 | PrivacyInfo 的 SystemBootTime（35F9.1）是多报：sqlite3mc 导入 `sysctlbyname`，但只读 `hw.ncpu`，没有 `kern.boottime` | 侧载安装不受影响，0.0.1 保留；若将来上架 App Store，按扫描结果删除并重建 |
| BL-26 | I1-c2 | 「重置本地数据」只在数据库打不开时出现在启动页，正常使用时没有清空真实数据的入口（只能删 App） | I-4 与设备认证（BL-20）一起放进"我的" |
| BL-27 | I1-c2 | 登记还款必须先有那一期正式账单（分配合计须等于还款额）；先还款、后录账单的用户无路可走 | 下一个公测版评估：允许暂不分配，录入账单后再分配 |
| BL-28 | I1-c2 | 没有额度规则（LimitRule），还款入账后额度一律不释放，要用户手动记额度快照 | I-2 加额度释放时滞规则，未知仍不释放 |
| BL-29 | I1-c2 | 冲正（银行确认 → 已冲正）后，已结清的账单状态不回退，只重算剩余应还，状态与金额可能看起来矛盾 | **已裁决**（I-1 审查 R-03/Q-5，2026-10-19）：有效状态由金额与日期推导（PRD §6.2 裁决段），由 F-1 实现 |
| BL-30 | I1-c2 | 诊断日志只在内存，重启后清空；公测用户遇到崩溃后无法回传日志 | I-4 评估持久化（只存无内容的事件码，限条数） |
| BL-31 | I1-c2 | 演示空间固定"今天"为 2026-10-16，日期会越来越旧 | 演示数据改为相对今天生成（后续版本） |
| BL-32 | R-I1 R-14 | 账单读模型在大数据量下偏慢：14,610 笔交易时 `LedgerReader.load` 762–1,714 ms（JIT）；热点在交易排序时反复解析时刻、每笔交易重映射规则、每笔还款一次查询 | I-3（导入）前处理，并把审查 perf-probe 的数据量做成常驻性能测试 |
| BL-33 | R-I1 Q-1 | 信用卡本期应还在登记还款之前不进资金日历；U-1 先加"未计入"提示与「还清本期」入口 | I-2 开始前决定是否按到期日、从默认还款账户把应还作为计划流出（规划、资金日历与首页对同一笔钱要给出同一结论） |
