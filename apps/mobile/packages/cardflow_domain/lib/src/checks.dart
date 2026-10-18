/// 运行前的数据检查与基线检查（Python `engine/plan.py` 的 `data_issues`、`baseline_check`）。
///
/// 无求解器的路径（本地验证器、有限搜索、fixture 的 verify case）与服务端 `plan()` 一样先做数据检查：
/// 有问题时给出 data_issues、不验证、不抛异常（R3E-13）。
library;

import 'allocation.dart';
import 'billing.dart';
import 'cash.dart';
import 'time.dart';
import 'verifier.dart';

/// 数据问题（运行会是 NEEDS_DATA）。
final class DataIssue {
  /// 数据问题。
  const DataIssue(
    this.code, {
    this.account,
    this.card,
    this.pool,
    this.scenario,
    this.asOf,
    this.ageDays,
    this.detail,
  });

  /// MISSING_SNAPSHOT、SNAPSHOT_AFTER_TXN_DATE、STALE_SNAPSHOT、BILLING_RULE_INVALID、
  /// MISSING_POOL_SNAPSHOT、UNKNOWN_DECISION_SCENARIO。
  final String code;

  /// 现金账户 ID。
  final String? account;

  /// 卡 ID。
  final String? card;

  /// 额度池 ID。
  final String? pool;

  /// 情景 ID。
  final String? scenario;

  /// 快照日。
  final LocalDate? asOf;

  /// 快照的天数（交易日 − 快照日）。
  final int? ageDays;

  /// 说明（规则错误的消息）。
  final String? detail;
}

/// 数据问题：缺快照、快照晚于交易日或过期（> [staleAfterDays] 天）、规则给不出账期、
/// 卡的池没有条目。顺序：先各现金账户（输入顺序），再各卡（输入顺序）。
List<DataIssue> dataIssues(ModelInputs inputs, int staleAfterDays) {
  final issues = <DataIssue>[];
  final req = inputs.request;
  for (final a in inputs.accounts) {
    final s = inputs.snapshots[a.id];
    if (s == null) {
      issues.add(DataIssue('MISSING_SNAPSHOT', account: a.id));
      continue;
    }
    if (s.asOf > req.txnDate) {
      issues.add(
        DataIssue('SNAPSHOT_AFTER_TXN_DATE', account: a.id, asOf: s.asOf),
      );
    } else if (req.txnDate.differenceInDays(s.asOf) > staleAfterDays) {
      issues.add(
        DataIssue(
          'STALE_SNAPSHOT',
          account: a.id,
          asOf: s.asOf,
          ageDays: req.txnDate.differenceInDays(s.asOf),
        ),
      );
    }
  }
  for (final c in inputs.cards) {
    try {
      deriveCardInfo(c, req);
    } on BillingRuleError catch (e) {
      issues.add(DataIssue('BILLING_RULE_INVALID', card: c.id, detail: '$e'));
    }
    final poolId = c.poolId;
    if (poolId != null &&
        poolId.isNotEmpty &&
        !inputs.pools.containsKey(poolId)) {
      issues.add(DataIssue('MISSING_POOL_SNAPSHOT', card: c.id, pool: poolId));
    }
  }
  return issues;
}

/// 基线检查中的一个缺口点。
final class BaselineBreach {
  /// 缺口点。
  const BaselineBreach(
    this.on,
    this.balance,
    this.gapToZero,
    this.gapToReserve,
  );

  /// 日期。
  final LocalDate on;

  /// 余额。
  final int balance;

  /// 距零。
  final int gapToZero;

  /// 距储备。
  final int gapToReserve;
}

/// 基线检查中的一个账户。
final class BaselineAccount {
  /// 账户结果。
  const BaselineAccount({
    required this.minBalance,
    required this.minOn,
    required this.endBalance,
    required this.breaches,
  });

  /// 最低余额。
  final int minBalance;

  /// 最低余额首次出现的日期。
  final LocalDate minOn;

  /// 期末余额。
  final int endBalance;

  /// 全部缺口点。
  final List<BaselineBreach> breaches;
}

/// 一个情景**不含新消费**的现金检查（engine-spec §5）。
final class BaselineCheck {
  /// 基线检查。
  const BaselineCheck({
    required this.ok,
    required this.accounts,
    required this.globalBreaches,
    required this.assumptions,
  });

  /// 没有账户低于储备，且合计从不低于全局底线（engine-spec §12.8）。
  final bool ok;

  /// 账户 ID → 结果（输入顺序）。
  final Map<String, BaselineAccount> accounts;

  /// 全局底线缺口。
  final List<GlobalBreach> globalBreaches;

  /// 假设说明（`账户: 说明`）。
  final List<String> assumptions;
}

/// [scenario] 的基线检查：每个账户对其储备，以及（模型 1.1.0 起）所有账户合计对全局底线——
/// 与验证器同一规则。
BaselineCheck baselineCheck(ModelInputs inputs, Scenario scenario) {
  final reports = evaluateAccounts(
    inputs.accounts,
    inputs.snapshots,
    inputs.events,
    scenario,
    inputs.horizonEnd,
  );
  final globalBreaches = globalFloorBreaches(
    reports,
    inputs.globalReserveFloor,
  );
  final accounts = <String, BaselineAccount>{};
  final assumptions = <String>[];
  reports.forEach((accountId, r) {
    accounts[accountId] = BaselineAccount(
      minBalance: r.minBalance,
      minOn: r.minOn,
      endBalance: r.endBalance,
      breaches: [
        for (final b in r.breaches)
          BaselineBreach(b.on, b.balance, b.gapToZero, b.gapToReserve),
      ],
    );
    for (final a in r.assumptions) {
      assumptions.add('$accountId: $a');
    }
  });
  return BaselineCheck(
    ok: reports.values.every((r) => r.ok) && globalBreaches.isEmpty,
    accounts: accounts,
    globalBreaches: globalBreaches,
    assumptions: assumptions,
  );
}
