# ADR-001 移动端技术栈：Flutter + Riverpod + go_router + drift（加密 SQLite）

状态：已接受 · 2026-10-16

背景：需要 iOS 主体验 + Android 完整功能，本地加密持久化，纯 Dart 领域层可与服务端共享 golden fixtures。
决策：Flutter 3.47.7（最低 iOS 15 / Android API 24）；状态管理 flutter_riverpod 3.4.x + 代码生成；路由 go_router 18.x；本地库 drift 2.35.x + sqlite3 3.7.x，加密通过 sqlite3 构建钩子 `hooks.user_defines.sqlite3.source: sqlite3mc`（drift 官方路线，S20），运行时启动检查 `PRAGMA cipher_version` 非空否则拒绝打开；密钥存 flutter_secure_storage，生物识别门控用 local_auth。
备选：sqflite_sqlcipher 3.4.1（PoC-1 失败时的回退，需 ProGuard 规则）；React Native（放弃：团队栈与 Dart 领域层共享）；原生双端（成本）。
后果：构建钩子较新，M0 必须真机验证（PoC-1）；旧 `*_flutter_libs` 包已 EOL 不得引入；iOS 构建只能在 macOS（S19）。
