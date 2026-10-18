# ADR-012 Android 短信适配器：可选 flavor，政策约束

状态：已接受 · 2026-10-16

决策：短信解析仅作为 Android 独立构建 flavor（`sms`），默认 flavor 不含 READ_SMS/RECEIVE_SMS；上架 Play 需按 "SMS-based money management" 例外提交权限声明表并通过审核（S05）；不读取、不上传非金融短信；iOS 不提供任何短信能力（S04）。
后果：核心流程不依赖短信；适配器可随时移除。
补充（2026-10-16）：v1 不上架 Play（ADR-015），权限声明表仅在将来上架时需要；flavor 隔离与"不读取、不上传非金融短信"照常执行。
