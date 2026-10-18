# ADR-011 身份与授权：设备令牌 + 可选账号，后台 RBAC

状态：已接受 · 2026-10-16

决策：移动端首次连接服务器时注册设备（公钥 + 配对码）；可选邮箱/口令账号（argon2id）；访问令牌 PyJWT（短期）+ 刷新令牌轮换 + 服务端会话撤销；工作空间成员角色 owner/admin/member；后台角色 owner/admin/operator/auditor；所有后台敏感操作审计。不用第三方登录（避免 App Review 4.8 的等效登录要求）。
后果：账号存在时必须提供应用内删除（App Review 5.1.1(v)）。
