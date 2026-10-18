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
