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
| BL-11 | I-0c | 已知无影响的双端差异：Dart 严格 JSON 嵌套深度上限 512、Python 约 1000；错误消息措辞不同；fixture 名称校验 Python 的 `pattern` `$` 可匹配末尾换行前、Dart 整串匹配 | 记录即可；任何一端输出都不受影响 |
| BL-12 | I-0c | 领域包能编译到 Web，但 JS 整数语义与 VM 不同；Web 只是编译烟雾测试 | 不处理；若将来做 Web 端需先改 `int` 大数路径 |
