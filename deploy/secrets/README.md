# deploy/secrets/ — CardFlow 部署 secret（T-012）

本目录存放 `deploy/compose.yaml` 用到的全部口令与密钥。除本文件外，其他文件都不进 Git（`.gitignore`）、不进镜像（`services/api/.dockerignore`）、不进日志和证据；不要粘贴到聊天、工单或截图里。

## 生成

在仓库根目录以 root（或 sudo）执行：

```bash
tools/gen-secrets.sh
```

- 只创建缺失的文件。已有文件不覆盖：只检查它非空、格式正确，并修正权限。重复运行是安全的。
- 目录权限 0700，属主为运维用户。文件权限 0600，属主 `10001:10001`。
  - 容器以 uid/gid 10001 运行。Compose 把每个文件只读地 bind-mount 到 `/run/secrets/<名称>`，权限和属主保持宿主上的原样，所以文件必须属于 10001。
  - 不以 root 运行时，脚本会提示需要执行的 `chown` 命令。
- 脚本不输出任何值。文件内容不带结尾换行；即使带了，应用和 postgres 镜像也都会去掉结尾换行。

## 文件清单

| 文件 | 用途 | 格式 | 读取方（容器内路径 `/run/secrets/<文件>`） |
|---|---|---|---|
| `db_password` | PostgreSQL 超级用户 `cardflow` 的口令 | 64 位十六进制 | `db`（`POSTGRES_PASSWORD_FILE`，**只在首次初始化空数据卷时**读取）；`migrate`、`provision`、`backup`（`DATABASE_PASSWORD_FILE`） |
| `db_api_password` | 登录角色 `cardflow_api`（API 进程） | 64 位十六进制（≥16 字符） | `provision`（`DATABASE_API_PASSWORD_FILE`）、`api`（`DATABASE_PASSWORD_FILE`） |
| `db_worker_password` | 登录角色 `cardflow_worker_login`（worker） | 同上 | `provision`、`worker` |
| `db_admin_password` | 登录角色 `cardflow_admin_login`（后台，T-031） | 同上 | `provision`；后台服务接入后由它读取 |
| `jwt_key` | 访问令牌（JWT）签名密钥 | 64 个随机字节，base64url 编码，无填充（86 字符），可直接用作 HMAC 密钥 | `api`（`JWT_KEY_FILE`） |
| `kek` | 服务端主密钥 KEK，用来包裹各工作空间的 DEK（附件信封加密，security-privacy §5） | 32 个随机字节，标准 base64（44 字符）；应用启动时校验 | `api`、`worker`、`backup`（`KEK_FILE`） |
| `backup_passphrase` | 备份加密口令（T-013） | 64 位十六进制 | `backup`（`BACKUP_PASSPHRASE_FILE`） |

**必须另行离线保存**（密码管理器或离线介质）：`backup_passphrase` 和 `kek`。服务器整体丢失时，没有它们，备份无法解密，附件无法读取。其余口令都可以重新生成。

## 轮换

以下命令都在仓库根目录执行，并且都带 `-p cardflow -f deploy/compose.yaml`。替换文件时先删除旧文件，再运行 `tools/gen-secrets.sh` 生成新值（属主和权限由脚本设置）；也可以手工写入新值后再运行一次脚本来修正权限。

> 注意：Compose 的 secret 是对**文件**（inode）的 bind mount。替换文件后，正在运行的容器仍然读到旧文件，必须重启或重建相应容器。

### 登录角色口令（`db_api_password`、`db_worker_password`、`db_admin_password`）

1. 替换文件，例如：`rm deploy/secrets/db_api_password && tools/gen-secrets.sh`。
2. 把新口令写入数据库：`docker compose -p cardflow -f deploy/compose.yaml run --rm provision`。
   - `cardflow db-provision` 是幂等的，只更新口令和不合规格的属性。
   - 口令在客户端算成 SCRAM verifier 后再发送，日志里没有明文。
3. 重启使用该口令的进程：`docker compose -p cardflow -f deploy/compose.yaml restart api`（worker 口令则重启 `worker`）。
4. 检查：`curl -sS 127.0.0.1:18080/readyz` 返回 200。

在第 2 步到第 3 步之间，旧进程新建数据库连接会失败，`/readyz` 会短暂变红。若要零中断，需要为同一用途准备两个登录角色交替使用，当前未实现。

### 超级用户口令（`db_password`）

`POSTGRES_PASSWORD_FILE` 只在初始化空数据卷时生效，**单改文件不会改数据库里的口令**。正确顺序：

1. 交互式修改，口令不会出现在命令行或日志里：
   - 执行 `docker compose -p cardflow -f deploy/compose.yaml exec db psql -U cardflow -d cardflow`；
   - 在 psql 中执行 `\password cardflow`，输入新值（取自新生成的文件内容）。
2. 用新值替换 `deploy/secrets/db_password`，再运行 `tools/gen-secrets.sh` 修正权限。之后 `migrate`、`provision`、`backup` 下次运行时读取新值，常驻进程不使用这个口令。

### JWT 签名密钥（`jwt_key`）

**一次性切换**（当前 compose.yaml 支持的方式）：替换文件后重启 `api`。已签发的访问令牌全部失效，客户端需要用刷新令牌换新的访问令牌。

**新旧密钥并存**（security-privacy §5 的"并存 7 天"）：T-011 正在引入 `JWT_PREVIOUS_KEY(_FILE)`，旧密钥只用于验签，进行中。落地后按以下步骤操作：
1. 把 `jwt_key` 改名为 `jwt_previous_key`，运行 `tools/gen-secrets.sh` 生成新的 `jwt_key`。
2. 在 compose.yaml 中为 `api` 增加 secret `jwt_previous_key`，并设置 `JWT_PREVIOUS_KEY_FILE=/run/secrets/jwt_previous_key`。
3. 执行 `up -d api`。
4. 7 天后删除该 secret 与文件，再执行一次 `up -d api`。

`gen-secrets.sh` 不生成也不检查 `jwt_previous_key`。

### KEK（`kek`）

**不要直接替换。** 换掉 KEK 之前，必须先用旧 KEK 解开所有 DEK，再用新 KEK 重新包裹（security-privacy §5），否则所有服务端附件都无法读取。这个重包工具属于 crypto 模块，尚未实现。在它实现之前，只在确认泄露时处理 KEK，并按 deployment-ops §6 "KEK 丢失"一行记录事故。

### 备份口令（`backup_passphrase`）

替换后，新备份使用新口令；已有备份仍然需要旧口令才能解密。因此旧口令要离线保留，直到用它加密的最后一份备份过了保留期（每日 14 份、每周 8 份）。具体格式与轮换流程见 T-013。

## 不在这里的配置

非敏感配置（镜像版本、端口、日志级别等）在 `deploy/.env` 中，由 `deploy/.env.example` 复制而来。各服务的 `DATABASE_URL` 与 `*_FILE` 路径写在 `deploy/compose.yaml` 里。环境变量中只出现 secret 文件的路径，不出现口令本身。
