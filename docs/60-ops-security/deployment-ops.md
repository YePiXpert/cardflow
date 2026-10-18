# 61 · 部署、发布、配置、故障恢复与运维手册框架

版本 0.1 · 2026-10-16。宿主实测：Docker 29.8.2 / Compose v5.6.0；宿主已有多个 Compose 项目与端口占用（清单保存在服务器本地，不入库）。**本项目完全隔离**：独立项目名 `cardflow`、独立网络、独立 Postgres 容器、仅 127.0.0.1 绑定、不修改任何现有项目或反向代理（反代/域名/TLS 由用户授权后配置）。

## 1. Compose 草案

```yaml
name: cardflow
services:
  db:
    image: postgres:18.6-trixie
    environment: { POSTGRES_DB: cardflow, POSTGRES_USER: cardflow, POSTGRES_PASSWORD_FILE: /run/secrets/db_password }
    secrets: [db_password]
    volumes: [pgdata:/var/lib/postgresql]
    healthcheck: { test: ["CMD-SHELL", "pg_isready -U cardflow -d cardflow"], interval: 10s, timeout: 5s, retries: 10 }
    deploy: { resources: { limits: { memory: 1g } } }
    restart: unless-stopped
  api:
    image: cardflow/api:${CARDFLOW_VERSION}
    command: ["cardflow", "api"]
    env_file: [.env]
    secrets: [db_password, kek, jwt_key]
    volumes: [attachments:/data/attachments]
    ports: ["127.0.0.1:${CARDFLOW_API_PORT:-18080}:8000"]
    depends_on: { db: { condition: service_healthy }, migrate: { condition: service_completed_successfully } }
    healthcheck: { test: ["CMD", "curl", "-fsS", "http://127.0.0.1:8000/readyz"], interval: 30s, timeout: 5s, retries: 3 }
    user: "10001:10001"
    read_only: true
    tmpfs: [/tmp]
    restart: unless-stopped
  migrate:
    image: cardflow/api:${CARDFLOW_VERSION}
    command: ["cardflow", "migrate", "--lock"]
    env_file: [.env]
    secrets: [db_password]
    depends_on: { db: { condition: service_healthy } }
  worker:
    image: cardflow/api:${CARDFLOW_VERSION}
    command: ["cardflow", "worker", "--concurrency", "2"]
    env_file: [.env]
    secrets: [db_password, kek]
    volumes: [attachments:/data/attachments]
    depends_on: { migrate: { condition: service_completed_successfully } }
    deploy: { resources: { limits: { memory: 2g, cpus: "4" } } }
    user: "10001:10001"
    restart: unless-stopped
  backup:
    image: cardflow/api:${CARDFLOW_VERSION}
    command: ["cardflow", "backup", "--schedule", "${BACKUP_CRON:-0 3 * * *}"]
    env_file: [.env]
    secrets: [db_password, kek, backup_passphrase]
    volumes: [attachments:/data/attachments:ro, backups:/data/backups]
    depends_on: [db]
    restart: unless-stopped
secrets:
  db_password: { file: ./secrets/db_password }
  kek: { file: ./secrets/kek }
  jwt_key: { file: ./secrets/jwt_key }
  backup_passphrase: { file: ./secrets/backup_passphrase }
volumes: { pgdata: {}, attachments: {}, backups: {} }
```

说明：后台 SPA 由 `api` 以 `/admin` 静态提供；默认端口 18080 未被占用（以部署时 `ss -tlnp` 复核为准）；不使用宿主已有的 PostgreSQL 实例。

## 2. 配置清单（.env）

| 变量 | 默认 | 说明 |
|---|---|---|
| CARDFLOW_VERSION | git sha/tag | 镜像标签 |
| CARDFLOW_API_PORT | 18080 | 仅 127.0.0.1 |
| DATABASE_URL | postgresql+psycopg://cardflow@db/cardflow | 口令来自 secret |
| ATTACHMENTS_DIR | /data/attachments | 信封加密 blob |
| SOLVER_TIME_LIMIT_S / SOLVER_WORKERS | 10 / 8 | CP-SAT |
| PARSE_TIMEOUT_S / MAX_UPLOAD_MB | 120 / 25 | 解析 |
| AI_ENABLED / AI_PROVIDER / AI_REGION | false / — / — | 可选 |
| PROMO_ALLOWED_DOMAINS | 空 | 抓取白名单 |
| RATE_LIMIT_WINDOW_S / RATE_LIMIT_DEVICE_REQUESTS / RATE_LIMIT_SOLVE_REQUESTS / RATE_LIMIT_UPLOAD_REQUESTS | 600 / 600 / 30 / 20 | 窗口内每设备请求数、求解数、上传数（API 契约 §1） |
| LOG_LEVEL / LOG_FORMAT | info / json | 无 PII |
| BACKUP_CRON / BACKUP_RETENTION_DAILY / WEEKLY | 0 3 * * * / 14 / 8 | |
| TOMBSTONE_RETENTION_DAYS / AUDIT_RETENTION_DAYS | 90 / 365 | |
| MIN_CLIENT_VERSION | 1.0.0 | /v1/meta |

Secrets：`db_password`、`kek`（32 字节 base64）、`jwt_key`、`backup_passphrase`，文件权限 0600，不进 Git。

## 3. 发布流程

后端：CI 构建镜像（tag = git sha）→ 运行测试/迁移测试/安全扫描 → 推送私有 registry 或 `docker save` 传输 → VPS `docker compose pull && up -d`（migrate 带锁先行）→ `/readyz` 绿 → 冒烟（建卡→导入→求解 fixture）→ 记录版本与健康输出为证据 E-20。回滚：`CARDFLOW_VERSION` 回退 + 若迁移处于 contract 阶段则先执行对应 downgrade。

移动端分发：用户自签安装，v1 不上架、不走 TestFlight（ADR-015）。签名密钥与证书只在用户手里，不进仓库、不进 CI、不交给代理。

Android：`flutter build apk --release --flavor default`（可加 `--split-per-abi`），不出 AAB。用户本机签名：Gradle 读取不进仓库的 `key.properties`，或对未签名 APK 执行 `zipalign` + `apksigner sign`，再用 `apksigner verify --print-certs` 核对证书指纹。代理只用测试密钥验证安装与覆盖升级（TC-MOB-14），产物哈希与安装记录为证据 E-21；`sms` flavor 单独构建。**签名密钥必须长期固定并自行备份**：换密钥后无法覆盖升级，只能卸载重装，本地数据随之清除，换之前须先备份或同步。

iOS：需 macOS + Xcode 26（S10）；Bundle ID 与开发团队经 xcconfig 注入，仓库不含团队 ID。两条路径：① 用户在 Xcode 选择自己的 Apple ID 团队，直接安装到真机；② `flutter build ios --release --no-codesign` → 将 `Runner.app` 放入 `Payload/` 打包为未签名 IPA → 用户用自选工具签名安装。免费 Apple ID 的描述文件约 7 天过期，需用同一 Apple ID 重签（待核验）；换 Apple ID/团队等同换设备，须先备份或同步。证据 E-22 = Mac 构建日志 + 产物哈希 + 用户自签真机安装截图。**Linux VPS 后端部署完成不等于 iOS 打包完成**。

版本：语义化 `MAJOR.MINOR.PATCH` + 构建号；移动端与 API 兼容矩阵在 API 契约 §5。

## 4. 健康检查与监控

- `/healthz`：进程存活；`/readyz`：DB 连接 + Alembic 版本一致 + worker 心跳（≤2 分钟）+ 附件卷可写。
- 指标（日志/简易端点 `/admin/api/status`）：队列深度、死信数、最近备份时间与大小、磁盘余量、求解 p95、解析失败率。
- 告警：由用户现有监控（如面板或 uptime 工具）轮询 `/readyz`；本项目不假设邮件/推送渠道。

## 5. 备份与恢复

- 每日：`pg_dump -Fc` + 附件增量 tar + `manifest.json`（sha256、版本、计数）→ AES-256-GCM（口令派生）→ `backups/` 卷；可选 rclone 到异地（用户配置）。
- 恢复演练（季度）：新建 `cardflow-drill` Compose 项目 → 恢复最近备份 → 运行一致性检查（行数、金额守恒、账单版本链）→ 报告归档为证据 E-23。
- 目标：RPO 24 h、RTO 1 h（未测量，标记为目标）。

## 6. 故障恢复手册（Runbook 框架）

| 场景 | 症状 | 处置 |
|---|---|---|
| DB 不可用 | /readyz 红，api 500 | 查看 db 日志；磁盘；重启 db；必要时从备份恢复 |
| 磁盘满 | 写失败 | 清理旧备份/tombstone 压缩；扩容 |
| 迁移失败 | migrate 容器非 0 退出 | 查看锁与错误；downgrade；修复后重跑；不手改金额 |
| worker 卡死/死信堆积 | 队列深度增长 | 重启 worker；后台 AP-05 重试死信；查看超时任务 |
| KEK 丢失 | 附件解密失败 | 业务数据仍可用；附件需用户重新导入；记录事故 |
| 设备丢失 | — | 后台撤销设备 → 会话失效；用户换设备从备份/同步恢复 |
| 同步重复/冲突激增 | 冲突列表增长 | 检查幂等键与时钟；冲突页人工解决；不批量覆盖 |
| 误删数据 | 用户报告 | tombstone 期内恢复；否则从备份恢复到演练库再导出 |
| 密钥轮换 | 计划内 | JWT 双密钥 7 天；KEK 重包 DEK；记录 |

## 7. 日志与审计

结构化 JSON、字段白名单、`request_id` 贯穿 api/worker；保留 30 天；审计表 365 天；禁止金额/商户/附件内容/令牌。

## 8. 运维手册目录（框架）

1 环境与隔离 · 2 安装与首次部署 · 3 配置与秘密 · 4 发布与回滚 · 5 备份与恢复演练 · 6 监控与告警 · 7 Runbooks · 8 安全事件响应 · 9 容量与性能 · 10 变更记录。
