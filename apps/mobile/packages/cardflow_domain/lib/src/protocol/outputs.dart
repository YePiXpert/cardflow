/// 领域结果 → 协议 v1 输出文档（Python `protocol.py` 的输出部分）：
/// `PlanOutcome.schema.json` 的 `$defs/VerificationResult` 与 `$defs/CardCycles`，以及基线检查。
///
/// 成员名与写法与 Python 引擎逐字一致：Dart 输出与 Python `--dump` 的规范化 JSON 逐字节相同
/// （CI 的 protocol-parity job 检查）。
library;

import '../allocation.dart';
import '../billing.dart';
import '../checks.dart';
import '../time.dart';
import '../verifier.dart';
import 'adapter.dart';
import 'errors.dart';

Map<String, Object?> _breach(ScenarioBreach b) => <String, Object?>{
  'cash_account_id': b.account,
  'on': '${b.on}',
  'balance': b.balance,
  'gap_to_zero': b.gapToZero,
  'gap_to_reserve': b.gapToReserve,
  'events': List<Object?>.of(b.events),
};

List<Object?> _globalBreaches(List<GlobalBreach> breaches) => <Object?>[
  for (final g in breaches)
    <String, Object?>{'on': '${g.on}', 'total': g.total, 'gap': g.gap},
];

Map<String, Object?> _check(ScenarioCheck c) => <String, Object?>{
  'ok': c.ok,
  'ok_zero': c.okZero,
  'min_balance_by_account': Map<String, Object?>.of(c.minBalanceByAccount),
  'min_on_by_account': <String, Object?>{
    for (final MapEntry(:key, :value) in c.minOnByAccount.entries)
      key: '$value',
  },
  'end_balance_by_account': Map<String, Object?>.of(c.endBalanceByAccount),
  'breaches': <Object?>[for (final b in c.breaches) _breach(b)],
  'first_breach': c.firstBreach == null ? null : _breach(c.firstBreach!),
  'global_breaches': _globalBreaches(c.globalBreaches),
  'assumptions': List<Object?>.of(c.assumptions),
};

/// 验证结果 → `Verification`（分配行另见 [allocationLinesToProtocol]）。
Map<String, Object?> verificationToProtocol(
  Verification v,
) => <String, Object?>{
  'ok': v.ok,
  'structural_ok': v.structuralOk,
  'violations': List<Object?>.of(v.violations),
  'decision_scenario': v.decisionScenario,
  'weighted_buffer_days': v.weightedBufferDays,
  'fees': v.fees,
  'verified_benefit': v.verifiedBenefit,
  'potential_benefit': v.potentialBenefit,
  'checks': <String, Object?>{
    for (final MapEntry(:key, :value) in v.checks.entries) key: _check(value),
  },
};

/// 验证器的分配行 → `AllocationLine`（API-52 的成员名）。
List<Object?> allocationLinesToProtocol(Verification v) => <Object?>[
  for (final line in v.lines)
    <String, Object?>{
      'card_id': line.card,
      'amount_minor': line.amount,
      'statement_date': '${line.statementDate}',
      'due_date': '${line.dueDate}',
      'repay_on': '${line.repayOn}',
      'repay_from_cash_account_id': line.repayFrom,
      'buffer_days': line.bufferDays,
      'fee_minor': line.fee,
      'verified_benefit_minor': line.verifiedBenefit,
      'potential_benefit_minor': line.potentialBenefit,
      'cycle_assumptions': List<Object?>.of(line.cycleAssumptions),
      'alternative_cycles': <Object?>[
        for (final (statement, due) in line.alternativeCycles)
          <String, Object?>{'statement_date': '$statement', 'due_date': '$due'},
      ],
    },
];

/// `VerificationResult`：无求解器的一端（本地验证器）能算出的结果。
Map<String, Object?> verificationResultToProtocol(Verification v) =>
    <String, Object?>{
      'data_issues': <Object?>[],
      'allocation': allocationLinesToProtocol(v),
      'verification': verificationToProtocol(v),
    };

/// 数据问题 → `DataIssue`（只写出有值的成员）。
List<Object?> dataIssuesToProtocol(List<DataIssue> issues) => <Object?>[
  for (final i in issues)
    <String, Object?>{
      'code': i.code,
      if (i.account != null) 'cash_account_id': i.account,
      if (i.card != null) 'card_id': i.card,
      if (i.pool != null) 'pool_id': i.pool,
      if (i.scenario != null) 'scenario_id': i.scenario,
      if (i.asOf != null) 'as_of': '${i.asOf}',
      if (i.ageDays != null) 'age_days': i.ageDays,
      if (i.detail != null) 'detail': i.detail,
    },
];

/// 基线检查 → `BaselineCheck`。
Map<String, Object?> baselineCheckToProtocol(BaselineCheck b) =>
    <String, Object?>{
      'ok': b.ok,
      'accounts': <String, Object?>{
        for (final MapEntry(key: accountId, value: a) in b.accounts.entries)
          accountId: <String, Object?>{
            'min_balance': a.minBalance,
            'min_on': '${a.minOn}',
            'end_balance': a.endBalance,
            'breaches': <Object?>[
              for (final br in a.breaches)
                <String, Object?>{
                  'on': '${br.on}',
                  'balance': br.balance,
                  'gap_to_zero': br.gapToZero,
                  'gap_to_reserve': br.gapToReserve,
                },
            ],
          },
      },
      'global_breaches': _globalBreaches(b.globalBreaches),
      'assumptions': List<Object?>.of(b.assumptions),
    };

/// `CardCycles`：每张卡在交易日的保守账期（fixture 的 cycles case）。规则给不出账期或日期越界
/// 时该卡为 `{"error": 消息}`（与 Python `str(e)` 相同）。
Map<String, Object?> cardCyclesToProtocol(ModelInputs inputs) {
  final out = <String, Object?>{};
  for (final c in inputs.cards) {
    final CardPlanInfo info;
    try {
      info = deriveCardInfo(c, inputs.request);
    } on BillingRuleError catch (e) {
      out[c.id] = <String, Object?>{'error': '$e'};
      continue;
    } on DateRangeError catch (e) {
      out[c.id] = <String, Object?>{'error': '$e'};
      continue;
    }
    out[c.id] = <String, Object?>{
      'statement_date': '${info.cycle.statementDate}',
      'due_date': '${info.cycle.dueDate}',
      'repay_on': '${info.repayOn}',
      'buffer_days': info.bufferDays,
      'cycle_assumptions': List<Object?>.of(info.cycle.assumptions),
      'alternative_cycles': <Object?>[
        for (final x in info.allCycles.skip(1))
          <String, Object?>{
            'statement_date': '${x.statementDate}',
            'due_date': '${x.dueDate}',
          },
      ],
    };
  }
  return out;
}

/// 对 PlanInput 的给定分配运行独立验证器（无求解器；Python `verify_from_protocol`）。
///
/// 先做与 `plan()` 相同的数据检查（R3E-13）：协议接受、但引擎会答 NEEDS_DATA 的文档（缺快照、
/// 快照过期、规则需要日历、池无条目）得到 `data_issues` 与空的验证，而不是异常。只有非法的文档或
/// 请求才抛 [ProtocolError]（决策情景不在情景中也是 [ProtocolError]）。
Map<String, Object?> verifyFromProtocol(
  Object? document,
  Object? allocation,
  Object? decisionScenario,
) {
  final parsed = inputsFromProtocol(document);
  final alloc = allocationFromProtocol(allocation);
  final scenarioId = scenarioIdFromProtocol(
    decisionScenario,
    '/decision_scenario',
  );
  if (!parsed.scenarios.containsKey(scenarioId)) {
    throw const ProtocolError('/decision_scenario', 'unknown scenario');
  }
  final issues = dataIssues(parsed.inputs, parsed.options.staleAfterDays);
  if (issues.isNotEmpty) {
    return <String, Object?>{
      'data_issues': dataIssuesToProtocol(issues),
      'allocation': <Object?>[],
      'verification': null,
    };
  }
  return verificationResultToProtocol(
    verify(parsed.inputs, alloc, parsed.scenarios, scenarioId),
  );
}
