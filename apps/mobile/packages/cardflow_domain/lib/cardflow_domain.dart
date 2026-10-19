/// 卡序 CardFlow 纯 Dart 领域层（无 Flutter、无数据库依赖，不使用二进制浮点）。
///
/// 语义与服务端 Python 引擎 1.1.0（`services/api/cardflow/planner/engine/`）一一对应，以
/// `docs/30-rules-engine/engine-spec.md` §12/§12.1 为准；双端一致性由规则协议 v1 的 golden
/// fixture 与 CI 的 protocol-parity job 保证。
///
/// | 模块 | 内容 |
/// |---|---|
/// | money | `minorDigits`、`toMinor`/`fromMinor`（超精度拒绝）、`RoundingMode`、`applyRate`、`decimalText`、`Money` |
/// | time | `LocalDate`（业务日期）、`Timestamp`（RFC 3339，自带偏移）、`TimePrecision` |
/// | billing | `BillingRule`、`cyclesForTransaction`、`selectRule`、`resolveCycle`、`BillingRuleError` |
/// | installment | `splitInstallments`、`installmentCashFlows`、`irrMonthly`、`annualize`（分期拆分与成本，I-1c） |
/// | cash | `CashEvent`、`Snapshot`、`Scenario`、`buildTimeline`、`evaluate`、`evaluateAccounts` |
/// | verifier | `verify`、`checkScenario`、`cardFee`、`globalFloorBreaches` |
/// | checks | `dataIssues`、`baselineCheck` |
/// | search | `boundedSearch`（K ≤ 3，非最优证明） |
/// | protocol | `parseJson`、`canonicalJson`、`protocolInputHash`、`inputsFromProtocol`、`inputsToProtocol`、`verifyFromProtocol`、`cardCyclesToProtocol` |
///
/// 读写文件的 fixture 运行器在 `package:cardflow_domain/fixture_runner.dart`（依赖 dart:io，
/// 不由本库导出）。
library;

export 'src/allocation.dart';
export 'src/billing.dart';
export 'src/cash.dart';
export 'src/checks.dart';
export 'src/installment.dart';
export 'src/money.dart';
export 'src/protocol/adapter.dart';
export 'src/protocol/binary64.dart';
export 'src/protocol/canonical.dart';
export 'src/protocol/errors.dart';
export 'src/protocol/json.dart';
export 'src/protocol/outputs.dart';
export 'src/protocol/pointer.dart';
export 'src/rational.dart';
export 'src/search.dart';
export 'src/time.dart';
export 'src/verifier.dart';

/// 本领域包对应的 Python 引擎模型版本（engine-spec §12；`cardflow.planner.engine.MODEL_VERSION`）。
const String engineModelVersion = '1.1.0';
