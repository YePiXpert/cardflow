# ADR-008 金额与时间表示

状态：已接受 · 2026-10-16

决策：金额 = `amount_minor BIGINT` + `currency CHAR(3)`，最小单位位数来自 `currencies` 表（CNY 2、JPY 0、KWD 3）；禁止 float；利率/汇率 `NUMERIC(20,10)`；取整模式显式字段。时间 = `event_at TIMESTAMPTZ` + `event_tz TEXT` + `time_precision`（datetime/date/month）+ `observed_at` + `recorded_at`；账期计算只用账户业务时区。
后果：Dart 端用 `int` + `decimal` 包；禁止 `double` 出现在领域层（lint 规则）。
