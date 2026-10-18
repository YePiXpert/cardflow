# tools/ — 开发与检查脚本

所有命令都在**仓库根目录**执行。

| 路径 | 用途 | 任务 |
|---|---|---|
| `dev-db.sh` | 开发库管理（用法见根 `README.md`） | T-002 |
| `pii_scan.py` | 日志 PII 扫描器：金额、卡号、卡尾号、令牌/凭据、身份证号、手机号、邮箱、密钥样串 | T-014 |
| `pii_log_probe.py` | 用带合成 PII 的请求驱动真实应用，收集服务端日志（生成 `clean.log`，端到端测试也用它） | T-014 |
| `pii_samples/clean.log` | 真实运行生成的日志样本，扫描必须 0 命中 | T-014 |
| `pii_samples/dirty.log` | 人工注入样本，每条规则至少一个正例 | T-014 |
| `tests/test_pii_scan.py` | 上述两个脚本的测试 | T-014 |
| `pytest.ini`、`ruff.toml` | 本目录的 pytest 配置；ruff 继承 `services/api/pyproject.toml` 的规则 | T-014 |

## pii_scan.py（日志 PII 扫描，SEC-S-08 / TC-SEC-S07）

```bash
uv run --project services/api python tools/pii_scan.py <文件或目录>...
# 只依赖标准库（Python ≥ 3.12，项目统一 3.13），不需要 venv：
python3 tools/pii_scan.py tools/pii_samples/clean.log
# 从标准输入读（参数 -）：
docker compose -p <项目名> logs --no-color api worker | python3 tools/pii_scan.py -
# 打印规则清单：
python3 tools/pii_scan.py --list-rules
```

**输出**：每个命中一行，写到 stdout：`文件:行:字段:规则名`，例如
`tools/pii_samples/dirty.log:7:message:card_number`。**不回显命中的原文**，所以输出可以直接留在 CI 日志里。
最后一行汇总（文件数、行数、命中数、命中的规则）和错误写到 stderr。

- 字段：JSON 路径（`error.details.errors[0].msg`）、文本行中 `key=value` 的键名，自由文本为 `-`。键名不是纯 ASCII 标识符，或键名本身含命中时，显示为 `<key>`（键名也可能是敏感数据，不打印）。
- 同一行同一字段同一规则只报一次。

**退出码**

| 退出码 | 含义 | CI 处理 |
|---|---|---|
| 0 | 扫描完整，无命中 | 通过 |
| 1 | 有命中 | 失败 |
| 2 | 参数或读取错误：路径不存在、文件不可读、某行不是 UTF-8、目录里没有文件、目录中有非普通文件 | 失败（不得当作通过） |

2 优先于 1：扫描不完整时不会报告成普通结果，但已经发现的命中照常输出；某一行不是 UTF-8 时报告行号，文件其余各行继续扫描。

**扫描方式**

1. **JSON 行**（可以带 `docker compose logs` 的前缀，如 `api-1  | {...}`）：解析后逐个值扫描，字段名和外层字段名作为规则上下文；键名本身也扫描。
2. **非 JSON 行与 JSON 字符串值**：按文本扫描。其中的 `key=value` / `key: value`（`LOG_FORMAT=text` 的格式、查询串、header 行、消息里的 `amount_minor=800000`）同样获得字段名上下文；这些值还会 URL 解码后再扫一遍（`%C2%A5` → `¥`，`+` → 空格）。
3. **白名单字段**只在值符合预期形状时跳过（见下表），否则按普通字段扫描。
4. 目录递归扫描其中所有普通文件（含隐藏文件，按路径排序）。

### 规则清单（12 条，集中定义在 `TEXT_RULES` / `FIELD_RULES`）

"文本"规则在任何文本里找模式；"字段"规则看字段名（含外层字段名，先经 `normalize_key()`：小写、`_` 连接、拆开 camelCase）。

| 规则名 | 类型 | 检测内容 | 降误报措施 |
|---|---|---|---|
| `amount` | 文本 | 带币种标记的数字：前缀 `¥` `￥` `CNY` `RMB` `人民币`，后缀 `元`（含 美元/港元/日元/欧元…）`CNY` `RMB` `人民币`；`1.2万元` 也算 | 必须有币种标记；`元组/元素/元数据/元旦/元宵` 不算 |
| `amount_field` | 字段 | 金额类字段里的数字或数字字符串。字段名任一段为 `amount(s)` `amt` `balance(s)` `principal` `cashback` `clawback`；以 `limit` `price` `fee` 开头；以 `_minor` `_limit` `_price` `_fee(s)` `_cents` `_yuan` 结尾；含 `金额/余额/额度/本金/手续费/年费/欠款/应还` | 只看数值；`minor_version`、`rate_limit_window_s`、`feedback_count`、`amount_mismatch: true` 不算 |
| `card_number` | 文本 | 13–19 位数字，连续或 3–6 位一组、组间单个空格/短横，Luhn 校验通过 | 首位须为 2–9（排除 13 位毫秒时间戳）；紧贴字母的数字不算（十六进制串）；与身份证号重叠时只报 `cn_id_card` |
| `card_last4` | 文本 + 字段 | `尾号1234`、`末四位：1234`、`last4=1234`、`last 4 digits 1234`、`ending in 1234`、`**** 1234`、`XXXX-1234`；字段 `last4/card_last4/last_four/card_tail/尾号…` 中的 4 位数 | 必须有上下文，孤立的 4 位数不算 |
| `jwt` | 文本 | `eyJ` 开头、三段 base64url | — |
| `authorization` | 文本 + 字段 | `Authorization:` 后的凭据（`Bearer/Basic/Digest/Token…` + 值，或 16 位以上令牌）、`Bearer` 令牌、`Basic` 凭据；`authorization` 字段中的任何值 | `Bearer` 后是普通单词不算（`Bearer authentication`）；`Basic` 必须能解码出 `user:pass` |
| `credential_field` | 字段 | `token` `secret` `password` `passphrase` `api_key` `cookie` `session_id` `jwt` `kek` `dek` `cvv` `pin` `otp` `sms_code` `密码` `验证码` `令牌` `密钥` 等字段中的任何值 | 空值和纯脱敏标记（`***`、`[REDACTED]`、`<masked>`…）不算；`token_type`、`max_tokens` 不算 |
| `sensitive_field` | 字段 | `merchant` `payee` `payer` `counterparty` `card_number` `card_no` `pan` `id_number` `phone` `mobile` `email` `real_name` `bank_account` `商户` `收款方` `卡号` `手机` `邮箱` `身份证` `姓名` 等字段中的任何值 | 同上；`merchant_id`、`phone_verified` 不算 |
| `cn_id_card` | 文本 | 18 位居民身份证号：出生日期真实存在、校验位正确（`X` 大小写均可） | 日期或校验位不对不算 |
| `cn_mobile` | 文本 | `1[3-9]` 开头 11 位，可带 `+86/0086/86`，允许空格/短横分隔 | 紧贴字母的数字不算 |
| `email` | 文本 | 邮箱地址 | 必须有顶级域（`user@localhost` 不算） |
| `secret_string` | 文本 | 32 位以上：十六进制串；或 base64/base64url 字符集中同时含大小写和数字；或无分隔符的字母数字混合串 | UUID（`8-4-4-4-12`，或带版本/变体位的 32 位十六进制，如 `request_id`）不算；与其他规则重叠时只报那条规则 |

### 白名单（`FIELD_POLICIES`，对应 `services/api/cardflow/log.py` 写出的字段）

| 字段 | 预期形状（符合才跳过） |
|---|---|
| `ts` | ISO-8601 时间戳 |
| `level` | 日志级别名 |
| `logger` | 点分标识符 |
| `request_id` | UUID：32 位十六进制（带版本/变体位）或 `8-4-4-4-12` |
| `method` | 3–10 位大写字母 |
| `status` | 100–599 的整数 |
| `duration_ms` | 非负数 |
| `exc_type`、`exc_chain` | 异常类型名 |
| `exc_frames` | `目录/文件.py:行号:函数` |

白名单字段的值符合形状时**所有**规则都不跑（包括数值类规则，所以 `duration_ms: 13800138000` 不会被当成手机号）；不符合形状时（如 `status: "4111 1111 1111 1111"`）按普通字段扫描。`path` 和 `message` 不在白名单里、始终扫描：路由模板（`/v1/plans/{plan_id}`、`<unmatched>`）不含任何可命中的内容，所以不算命中；具体路径（如 `/v1/cards/` 后接卡号）会被检出。

### 扩展规则

都在 `tools/pii_scan.py` 里改：

- 文本规则：`TEXT_RULES` 加 `TextRule(名称, 说明, 查找函数)`；与通用规则可能重叠时更新 `_SHADOWED_BY`。
- 字段名规则：`FIELD_RULES` 加 `FieldRule(名称, 说明, 键名正则, 值判断)`；键名正则匹配的是 `normalize_key()` 之后的形式。
- 白名单：`cardflow/log.py` 的 `ALLOWED_FIELDS` 增加字段时，在 `FIELD_POLICIES` 加形状校验（不加就按普通字段扫描，只可能多报不会漏报）。
- 每条新规则：在 `pii_samples/dirty.log` 加正例，在测试的 `POSITIVE`/`NEGATIVE` 加正反例并更新 `EXPECTED_DIRTY`；漏加时 `test_every_rule_has_positive_and_negative_examples`、`test_dirty_log_covers_every_rule_and_every_sample_line` 会失败。
- 正则不要用嵌套量词；相邻的可选空白用占有量词（`\s*+`）。`test_pathological_lines_finish_quickly` 带超时，回溯爆炸会让测试失败而不是卡住 CI。

### 已知局限

- 自由文本里的姓名、地址、商户名无法靠模式识别，只能靠字段名（`sensitive_field`）。
- 不检测：15 位旧身份证号、座机号、境外手机号、`$`/`€` 等其他币种符号、紧贴字母的数字（如 `card4111111111111111`）。
- 只有 `key=value` 的值会做 URL 解码。
- `secret_string` 按"≥32 位十六进制即算"的口径，也会命中 SHA-256 等哈希值。以后若日志确需记录哈希（如输入哈希），给该字段在 `FIELD_POLICIES` 加形状白名单，不要放宽规则本身。
- 不要扫描整个 `tools/` 或文档目录：样本、测试和本文件本身含合成 PII；证据文件里的 `sha256sum` 输出也会被 `secret_string` 命中。

## 样本

- `pii_samples/clean.log`（26 行）：由真实运行生成，必须 0 命中。重新生成：
  ```bash
  uv run --project services/api python tools/pii_log_probe.py tools/pii_samples/clean.log
  ```
  `pii_log_probe.py` 用 `create_app()` 和真实的 `configure_logging()`（json、text 两种格式各一遍），经 TestClient 在进程内发出 12 个请求：`/healthz`（查询串带金额/卡号/手机号，`Authorization: Bearer <JWT>`）、404（路径含卡号）、405（请求体带金额和卡号）、5 个 422（查询串、请求体、路径参数、畸形 JSON）、201、200、500（异常消息含金额、卡号、手机号）。M0 还没有接收请求体的端点，所以 422/201/500 用的是只加在应用实例上的测试路由（与 `services/api/tests/test_api_envelope.py` 相同的做法），应用本身不改。任一响应状态与预期不符时脚本以 1 退出。只收集 `cardflow.*` 日志；测试客户端自己的 `httpx` 日志（含原始 URL，会被扫描器检出）不是服务端输出，不收集。请求 ID、时间戳、耗时每次生成都不同。
- `pii_samples/dirty.log`（32 个样本行 + 2 行 `#` 说明）：人工注入，全部为合成数据——公开测试卡号（4111…、5555…、6011…）、GB 11643 示例身份证号、`example.com/.org` 邮箱、138-0013-8000 占位号码、自造的令牌和密钥。每条规则至少一个正例；测试逐行固定期望的字段与规则。

## 测试

```bash
uv run --project services/api pytest tools/tests -v
```

- 不需要数据库；`tools/pytest.ini` 自动生效（rootdir 为 `tools/`）。不要和 `services/api` 的测试放在同一次 pytest 调用里（两边配置不同）。
- 覆盖：每条规则的正反例；白名单与路由模板；输出格式与"不含原文"；退出码 0/1/2；目录递归、stdin、坏 UTF-8 行、BOM；病态输入（带超时）；`clean.log` 0 命中且是完整的探针捕获；`dirty.log` 逐行命中与期望完全一致、覆盖全部规则；以 `python -I -S` 运行脚本（证明只依赖标准库）。
- 端到端（json、text 两种日志格式各一遍）：进程内用 TestClient 对应用发出上述请求（查询串、请求体、路径、header 带金额、卡号、手机号、邮箱、身份证号、JWT），捕获日志后扫描，`cardflow.*` 日志与除测试客户端外的全部日志都必须 0 命中；同时验证发出的请求数据本身能被扫描器检出（不是空测），以及 handler 故意在日志消息里写入金额和卡号时能被检出（正对照）。

代码检查（`tools/ruff.toml` 继承 `services/api/pyproject.toml` 的规则）：

```bash
uv run --project services/api ruff check tools/ && uv run --project services/api ruff format --check tools/
```

## CI 接入（T-015）

建议放在"安全扫描"阶段（test-plan §10），四步都必须按下述退出码判定：

1. 单元与端到端测试：`uv run --project services/api pytest tools/tests` → 必须 0。
2. 样本回归：
   ```bash
   python3 tools/pii_scan.py tools/pii_samples/clean.log                       # 必须 0
   python3 tools/pii_scan.py tools/pii_samples/dirty.log >/dev/null; test $? -eq 1   # 必须恰好 1
   ```
3. 当前代码的实时探针（日志进 CI 产物前先扫）：
   ```bash
   uv run --project services/api python tools/pii_log_probe.py "$RUNNER_TEMP/probe.log"   # 状态码不符时为 1
   python3 tools/pii_scan.py "$RUNNER_TEMP/probe.log"                                      # 必须 0
   ```
4. T-012 的 Compose 栈在 CI 中跑冒烟请求后，扫描全部服务端日志（不只 `cardflow.*`，带 compose 前缀的 JSON 行可直接扫）：
   ```bash
   docker compose -p <CI 专用项目名> logs --no-color api worker > "$RUNNER_TEMP/compose.log"
   python3 tools/pii_scan.py "$RUNNER_TEMP/compose.log"                                    # 必须 0
   ```

退出码：0 通过；1 发现 PII（输出只有 `文件:行:字段:规则名`，可安全保留在 CI 日志中）；2 工具或输入错误，按失败处理。扫描器不需要任何依赖，`python3 tools/pii_scan.py` 在没有 venv 的 job 里也能跑。
