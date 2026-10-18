# ADR-005 Web 后台：React 19 + Vite 8 + TypeScript 7，静态托管于 api 容器

状态：已接受 · 2026-10-16

决策：单页应用，构建产物由 FastAPI 以 `/admin` 静态路径提供（同源，简化 CSP 与鉴权）；类型从 OpenAPI 生成；Node 24 LTS 构建（Node 26 转 LTS 后在 M4 评估）。
备选：SvelteKit/Next（放弃：无需 SSR）；Flutter Web（放弃：后台表格/表单生态与可访问性）。
后果：后台与 API 同版本发布；不提供公网匿名访问。
