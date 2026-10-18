/// 数据层 → 领域对象的现金映射（I-1b）：现金账户/余额快照/现金事件 → `CashAccount`/`Snapshot`/
/// `CashEvent`；情景参数 → `Scenario`；交给领域包之前的交叉校验（审查 §4 第 2 条）；输入哈希与
/// 情景计算结果的 JSON。
///
/// 领域包不读写数据库；这里只做映射与数据层语义（可用现金的口径、现金的业务时区），时间线、缺口与
/// 数据问题一律由领域包计算（`buildTimeline`、`evaluate`、`evaluateAccounts`、`dataIssues`）。
library;

import 'dart:convert';

import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../repositories/cash_models.dart';
import '../time/business_tz.dart';

/// 现金的业务时区：现金账户没有自己的时区列，日期与"今天"一律按默认业务时区（Asia/Shanghai）解释，
/// 与手机时区无关。
const BusinessTimeZone cashTimeZone = defaultBusinessTimeZone;

/// 现金数据的计算区间上限（P-07 的最大窗口 180 天）：周期事项展开到"今天 + 180 天"，情景计算版本的
/// 区间也是它。
const int cashHorizonDays = 180;

/// 快照超过多少天算陈旧（R-CASH-09 默认 7 天）：交给领域包 `dataIssues` 的 `staleAfterDays`。
const int cashStaleAfterDays = 7;

final RegExp _protocolId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$');

/// 现金账户行 → 领域 [CashAccount]。`usableForRepayment` 按 [CashAvailability] 在 [today] 的取值
/// （有可用日期时，当天及以后才可用于还款）。
CashAccount cashAccountFromRow(
  CashAccountRow row, {
  required LocalDate today,
}) => CashAccount(
  id: row.id,
  name: row.name,
  currency: row.currency,
  reserveFloor: row.reserveFloorMinor,
  usableForRepayment: CashAvailability.of(row).usableOn(today),
);

/// 余额快照行 + 它已包含的事件 → 领域 [Snapshot]。
Snapshot snapshotFromRow(
  CashSnapshotRow row,
  Iterable<String> includedEventIds,
) => Snapshot(
  account: row.cashAccountId,
  balance: row.balanceMinor,
  asOf: LocalDate.parse(row.balanceAsOf),
  observedAt: Timestamp.parse(row.observedAt),
  includesEventIds: Set<String>.of(includedEventIds),
);

/// 现金事件行 → 领域 [CashEvent]（类别、标签、时刻原样带过去）。
CashEvent cashEventFromRow(CashEventRow row) => CashEvent(
  id: row.id,
  account: row.cashAccountId,
  on: LocalDate.parse(row.eventOn),
  amount: row.amountMinor,
  cls: EventClass.values.firstWhere((c) => c.code == row.cls),
  category: row.category,
  label: row.label ?? '',
  at: row.eventAt == null ? null : Timestamp.parse(row.eventAt!),
);

/// 情景对单个事件的覆盖（`scenarios.event_overrides` 的一项）。
@immutable
final class EventOverrideSpec {
  const EventOverrideSpec({required this.eventId, this.on, this.amountMinor});

  factory EventOverrideSpec.fromJson(Map<String, Object?> json) =>
      EventOverrideSpec(
        eventId: json['event_id']! as String,
        on: json['on'] == null ? null : LocalDate.parse(json['on']! as String),
        amountMinor: json['amount_minor'] as int?,
      );

  final String eventId;
  final LocalDate? on;
  final int? amountMinor;

  Map<String, Object?> toJson() => <String, Object?>{
    'event_id': eventId,
    if (on != null) 'on': on.toString(),
    if (amountMinor != null) 'amount_minor': amountMinor,
  };

  @override
  bool operator ==(Object other) =>
      other is EventOverrideSpec &&
      other.eventId == eventId &&
      other.on == on &&
      other.amountMinor == amountMinor;

  @override
  int get hashCode => Object.hash(eventId, on, amountMinor);
}

/// 情景的额度变化（占位：账户 + 日期 + 变化额，I-2 使用；本期只保存与校验）。
@immutable
final class LimitChangeSpec {
  const LimitChangeSpec({
    required this.creditAccountId,
    required this.on,
    required this.changeMinor,
  });

  factory LimitChangeSpec.fromJson(Map<String, Object?> json) =>
      LimitChangeSpec(
        creditAccountId: json['credit_account_id']! as String,
        on: LocalDate.parse(json['on']! as String),
        changeMinor: json['change_minor']! as int,
      );

  final String creditAccountId;
  final LocalDate on;

  /// 额度变化（最小单位，负数 = 降额）。
  final int changeMinor;

  Map<String, Object?> toJson() => <String, Object?>{
    'credit_account_id': creditAccountId,
    'on': on.toString(),
    'change_minor': changeMinor,
  };

  @override
  bool operator ==(Object other) =>
      other is LimitChangeSpec &&
      other.creditAccountId == creditAccountId &&
      other.on == on &&
      other.changeMinor == changeMinor;

  @override
  int get hashCode => Object.hash(creditAccountId, on, changeMinor);
}

/// 情景参数（数据库行与内置情景共用）。系数是规范十进制文本（`Rational.parseDecimal` 可读）。
@immutable
final class ScenarioParams {
  const ScenarioParams({
    required this.includeExpected,
    this.incomeDelayDays = 0,
    this.incomeScale = '1',
    this.expenseScale = '1',
    this.sameDayOrder = SameDayOrderChoice.conservative,
    this.eventOverrides = const <EventOverrideSpec>[],
    this.limitChanges = const <LimitChangeSpec>[],
  });

  factory ScenarioParams.fromRow(ScenarioRow row) => ScenarioParams(
    includeExpected: row.includeExpected,
    incomeDelayDays: row.incomeDelayDays,
    incomeScale: row.incomeScale,
    expenseScale: row.expenseScale,
    sameDayOrder: SameDayOrderChoice.of(row.sameDayOrder),
    eventOverrides: <EventOverrideSpec>[
      for (final item in jsonDecode(row.eventOverrides) as List<Object?>)
        EventOverrideSpec.fromJson(item! as Map<String, Object?>),
    ],
    limitChanges: <LimitChangeSpec>[
      for (final item in jsonDecode(row.limitChanges) as List<Object?>)
        LimitChangeSpec.fromJson(item! as Map<String, Object?>),
    ],
  );

  /// 内置"已确认"：只看确定的收支（R-CASH-03，F-01）。
  static const ScenarioParams confirmed = ScenarioParams(
    includeExpected: false,
  );

  /// 内置"基准预期"：预计收支按期发生。
  static const ScenarioParams baseline = ScenarioParams(includeExpected: true);

  final bool includeExpected;
  final int incomeDelayDays;
  final String incomeScale;
  final String expenseScale;
  final SameDayOrderChoice sameDayOrder;
  final List<EventOverrideSpec> eventOverrides;
  final List<LimitChangeSpec> limitChanges;

  /// 输入哈希里的写法。
  Map<String, Object?> toJson() => <String, Object?>{
    'include_expected': includeExpected,
    'income_delay_days': incomeDelayDays,
    'income_scale': incomeScale,
    'expense_scale': expenseScale,
    'same_day_order': sameDayOrder.code,
    'event_overrides': <Object?>[for (final o in eventOverrides) o.toJson()],
    'limit_changes': <Object?>[for (final c in limitChanges) c.toJson()],
  };
}

/// 情景参数 → 领域 [Scenario]。只带指向 [liveEventIds] 中事件的覆盖：指向已删除事件的覆盖"未生效"
/// （P-09 九态"数据不全"），不交给领域包（领域包与规则协议都要求覆盖指向已有事件）。
Scenario scenarioFromParams(
  String id,
  ScenarioParams params, {
  required Set<String> liveEventIds,
  String description = '',
}) => Scenario(
  id: id,
  includeExpected: params.includeExpected,
  incomeDelayDays: params.incomeDelayDays,
  incomeScale: Rational.parseDecimal(params.incomeScale),
  expenseScale: Rational.parseDecimal(params.expenseScale),
  sameDayOrder: params.sameDayOrder == SameDayOrderChoice.timestamp
      ? SameDayOrder.timestamp
      : SameDayOrder.conservative,
  eventOverrides: <String, EventOverride>{
    for (final o in params.eventOverrides)
      if (liveEventIds.contains(o.eventId))
        o.eventId: EventOverride(on: o.on, amount: o.amountMinor),
  },
  description: description,
);

/// 交给领域包的数据违反了交叉规则（只有绕过数据库约束与仓库校验时才会出现）。[rule] 是规则标识，
/// 不含任何数据（与规则协议 v1 的 ProtocolError 一样不回显取值）。
final class CashInputsException implements Exception {
  const CashInputsException(this.rule);

  /// 规则标识，如 `event_at_date`、`includes_after_as_of`。
  final String rule;

  /// 界面文案（错误码另显示 [rule]）。
  String get message => '本机现金数据不一致，已停止计算';

  @override
  String toString() => 'CashInputsException($rule)';
}

/// 资金日历交给领域包之前的交叉校验：复刻规则协议 v1 `inputsFromProtocol` 里与现金时间线有关的规则
/// （审查 §4 第 2 条，I-1b 简报 §5；领域对象的构造函数不做这些检查，与 Python 数据类相同）：
///
/// - ID 唯一（账户、事件；每个账户至多一个快照）且符合协议的 Id 格式，事件 ID 不以 `plan_repay_` 开头；
/// - 金额绝对值 ≤ 10^13（快照余额、事件、储备、情景覆盖）；
/// - 事件、快照指向已有账户；事件 `at` 按自身偏移的日期等于 `on`；
/// - 快照的 `includes` 只列本账户的已有事件，且事件日期不晚于快照日；
/// - 币种一致：账户币种是 13 种之一；调拨两端币种相同（且两端账户不同、方向相反、金额相反、到账日
///   不早于转出日，[transferGroups] 是调拨组 → 两端事件 ID）；
/// - 情景覆盖只指向已有事件、每个事件至多一次。
///
/// 违反时抛 [CashInputsException]。
void checkCashTimelineInputs({
  required List<CashAccount> accounts,
  required Map<String, Snapshot> snapshots,
  required List<CashEvent> events,
  Map<String, List<String>> transferGroups = const <String, List<String>>{},
  Iterable<EventOverrideSpec> overrides = const <EventOverrideSpec>[],
}) {
  bool inRange(int value) => value >= -moneyLimit && value <= moneyLimit;
  final accountById = <String, CashAccount>{};
  for (final a in accounts) {
    if (!_protocolId.hasMatch(a.id)) {
      throw const CashInputsException('account_id_format');
    }
    if (accountById.containsKey(a.id)) {
      throw const CashInputsException('duplicate_account_id');
    }
    if (!minorDigits.containsKey(a.currency)) {
      throw const CashInputsException('currency');
    }
    if (a.reserveFloor < 0 || !inRange(a.reserveFloor)) {
      throw const CashInputsException('reserve_range');
    }
    accountById[a.id] = a;
  }
  final eventById = <String, CashEvent>{};
  for (final e in events) {
    if (!_protocolId.hasMatch(e.id) || e.id.startsWith(reservedEventPrefix)) {
      throw const CashInputsException('event_id_format');
    }
    if (eventById.containsKey(e.id)) {
      throw const CashInputsException('duplicate_event_id');
    }
    if (!accountById.containsKey(e.account)) {
      throw const CashInputsException('event_unknown_account');
    }
    if (!inRange(e.amount)) {
      throw const CashInputsException('amount_range');
    }
    final at = e.at;
    if (at != null && at.date != e.on) {
      throw const CashInputsException('event_at_date');
    }
    eventById[e.id] = e;
  }
  snapshots.forEach((accountId, s) {
    if (s.account != accountId || !accountById.containsKey(s.account)) {
      throw const CashInputsException('snapshot_unknown_account');
    }
    if (!inRange(s.balance)) {
      throw const CashInputsException('amount_range');
    }
    for (final id in s.includesEventIds) {
      final event = eventById[id];
      if (event == null || event.account != s.account) {
        throw const CashInputsException('includes_other_account');
      }
      if (event.on > s.asOf) {
        throw const CashInputsException('includes_after_as_of');
      }
    }
  });
  transferGroups.forEach((group, legs) {
    if (legs.length != 2) {
      throw const CashInputsException('transfer_pair');
    }
    final a = eventById[legs[0]];
    final b = eventById[legs[1]];
    if (a == null || b == null) {
      throw const CashInputsException('transfer_pair');
    }
    final (out, into) = a.amount < 0 ? (a, b) : (b, a);
    if (out.account == into.account ||
        out.amount >= 0 ||
        into.amount != -out.amount ||
        into.on < out.on) {
      throw const CashInputsException('transfer_pair');
    }
    if (accountById[out.account]!.currency !=
        accountById[into.account]!.currency) {
      throw const CashInputsException('currency');
    }
  });
  final overridden = <String>{};
  for (final o in overrides) {
    if (!eventById.containsKey(o.eventId)) {
      throw const CashInputsException('override_unknown_event');
    }
    if (!overridden.add(o.eventId)) {
      throw const CashInputsException('override_twice');
    }
    final amount = o.amountMinor;
    if (amount != null && !inRange(amount)) {
      throw const CashInputsException('amount_range');
    }
  }
}

/// 计算的输入哈希（小写十六进制 sha256，用领域包的规范化 JSON）：情景计算版本据此判断"过期"。
/// 只含影响结果的数据：区间、计入的账户、快照与包含关系、区间内的事件、情景参数。
String cashInputsHash({
  required LocalDate from,
  required LocalDate to,
  required List<CashAccount> accounts,
  required Map<String, Snapshot> snapshots,
  required List<CashEvent> events,
  required ScenarioParams params,
  Map<String, LocalDate?> usableFrom = const <String, LocalDate?>{},
}) => protocolInputHash(<String, Object?>{
  'kind': 'cardflow.cash_timeline',
  'version': 1,
  'horizon_from': from.toString(),
  'horizon_to': to.toString(),
  'accounts': <Object?>[
    for (final a in accounts)
      <String, Object?>{
        'id': a.id,
        'currency': a.currency,
        'reserve_floor_minor': a.reserveFloor,
        'usable_from': usableFrom[a.id]?.toString(),
      },
  ],
  'snapshots': <Object?>[
    for (final a in accounts)
      if (snapshots[a.id] case final s?)
        <String, Object?>{
          'account': s.account,
          'balance_minor': s.balance,
          'as_of': s.asOf.toString(),
          'includes': s.includesEventIds.toList()..sort(),
        },
  ],
  'events': <Object?>[
    for (final e in events)
      if (e.on <= to)
        <String, Object?>{
          'id': e.id,
          'account': e.account,
          'on': e.on.toString(),
          'at': e.at?.isoformat(),
          'amount_minor': e.amount,
          'cls': e.cls.code,
          'category': e.category,
        },
  ],
  'scenario': params.toJson(),
});

/// 一个缺口点（情景计算结果里的写法）。
@immutable
final class RunBreach {
  const RunBreach({
    required this.on,
    required this.phase,
    required this.balance,
    required this.gapToZero,
    required this.gapToReserve,
    required this.eventIds,
  });

  factory RunBreach.fromBreach(Breach b) => RunBreach(
    on: b.on,
    phase: b.phase.code,
    balance: b.balance,
    gapToZero: b.gapToZero,
    gapToReserve: b.gapToReserve,
    eventIds: List<String>.of(b.eventIds),
  );

  factory RunBreach.fromJson(Map<String, Object?> json) => RunBreach(
    on: LocalDate.parse(json['on']! as String),
    phase: json['phase']! as String,
    balance: json['balance']! as int,
    gapToZero: json['gap_to_zero']! as int,
    gapToReserve: json['gap_to_reserve']! as int,
    eventIds: <String>[
      for (final id in json['event_ids']! as List<Object?>) id! as String,
    ],
  );

  final LocalDate on;

  /// `snapshot` / `low`。
  final String phase;
  final int balance;
  final int gapToZero;
  final int gapToReserve;
  final List<String> eventIds;

  Map<String, Object?> toJson() => <String, Object?>{
    'on': on.toString(),
    'phase': phase,
    'balance': balance,
    'gap_to_zero': gapToZero,
    'gap_to_reserve': gapToReserve,
    'event_ids': eventIds,
  };
}

/// 一个账户在情景计算结果里的摘要。
@immutable
final class RunAccountResult {
  const RunAccountResult({
    required this.accountId,
    required this.name,
    required this.currency,
    required this.reserveFloor,
    required this.ok,
    required this.okZero,
    required this.minBalance,
    required this.minOn,
    required this.endBalance,
    required this.breaches,
  });

  factory RunAccountResult.fromReport(CashAccount account, CashReport r) =>
      RunAccountResult(
        accountId: account.id,
        name: account.name,
        currency: account.currency,
        reserveFloor: account.reserveFloor,
        ok: r.ok,
        okZero: r.okZero,
        minBalance: r.minBalance,
        minOn: r.minOn,
        endBalance: r.endBalance,
        breaches: <RunBreach>[
          for (final b in r.breaches) RunBreach.fromBreach(b),
        ],
      );

  factory RunAccountResult.fromJson(Map<String, Object?> json) =>
      RunAccountResult(
        accountId: json['account_id']! as String,
        name: json['name']! as String,
        currency: json['currency']! as String,
        reserveFloor: json['reserve_floor_minor']! as int,
        ok: json['ok']! as bool,
        okZero: json['ok_zero']! as bool,
        minBalance: json['min_balance']! as int,
        minOn: LocalDate.parse(json['min_on']! as String),
        endBalance: json['end_balance']! as int,
        breaches: <RunBreach>[
          for (final b in json['breaches']! as List<Object?>)
            RunBreach.fromJson(b! as Map<String, Object?>),
        ],
      );

  final String accountId;
  final String name;
  final String currency;
  final int reserveFloor;
  final bool ok;
  final bool okZero;
  final int minBalance;
  final LocalDate minOn;
  final int endBalance;
  final List<RunBreach> breaches;

  Map<String, Object?> toJson() => <String, Object?>{
    'account_id': accountId,
    'name': name,
    'currency': currency,
    'reserve_floor_minor': reserveFloor,
    'ok': ok,
    'ok_zero': okZero,
    'min_balance': minBalance,
    'min_on': minOn.toString(),
    'end_balance': endBalance,
    'breaches': <Object?>[for (final b in breaches) b.toJson()],
  };
}

/// 情景计算的结果（`scenario_runs.result`）：逐账户最低点与缺口点、假设、数据问题、未计入的账户、
/// 未生效的覆盖。
@immutable
final class CashRunResult {
  const CashRunResult({
    required this.accounts,
    required this.assumptions,
    required this.dataIssues,
    required this.excluded,
    required this.missingSnapshot,
    required this.inactiveOverrides,
  });

  factory CashRunResult.fromJson(Map<String, Object?> json) => CashRunResult(
    accounts: <RunAccountResult>[
      for (final a in json['accounts']! as List<Object?>)
        RunAccountResult.fromJson(a! as Map<String, Object?>),
    ],
    assumptions: <String>[
      for (final a in json['assumptions']! as List<Object?>) a! as String,
    ],
    dataIssues: <Map<String, Object?>>[
      for (final i in json['data_issues']! as List<Object?>)
        i! as Map<String, Object?>,
    ],
    excluded: <String>[
      for (final a in json['excluded']! as List<Object?>) a! as String,
    ],
    missingSnapshot: <String>[
      for (final a in json['missing_snapshot']! as List<Object?>) a! as String,
    ],
    inactiveOverrides: <String>[
      for (final a in json['inactive_overrides']! as List<Object?>)
        a! as String,
    ],
  );

  /// 解析 `scenario_runs.result`。
  factory CashRunResult.parse(String text) =>
      CashRunResult.fromJson(jsonDecode(text) as Map<String, Object?>);

  final List<RunAccountResult> accounts;
  final List<String> assumptions;

  /// 领域包 `dataIssues` 的结果（code、account、as_of、age_days）。
  final List<Map<String, Object?>> dataIssues;

  /// 不计入可用现金的账户名称。
  final List<String> excluded;

  /// 缺快照、未计入的账户名称。
  final List<String> missingSnapshot;

  /// 指向已删除事件、未生效的情景覆盖（事件 ID）。
  final List<String> inactiveOverrides;

  /// 缺口点总数。
  int get gapCount =>
      accounts.fold<int>(0, (sum, a) => sum + a.breaches.length);

  /// 数据过期（陈旧）：结果是"假设分析"。
  bool get assumptionAnalysis =>
      dataIssues.any((i) => i['code'] == 'STALE_SNAPSHOT');

  Map<String, Object?> toJson() => <String, Object?>{
    'accounts': <Object?>[for (final a in accounts) a.toJson()],
    'assumptions': assumptions,
    'data_issues': dataIssues,
    'excluded': excluded,
    'missing_snapshot': missingSnapshot,
    'inactive_overrides': inactiveOverrides,
  };

  /// 存库的文本（规范化 JSON：同一结果只有一种写法）。
  String encode() => canonicalJsonText(toJson());
}

/// 领域包的数据问题 → 情景计算结果里的写法。
Map<String, Object?> dataIssueToJson(DataIssue issue) => <String, Object?>{
  'code': issue.code,
  if (issue.account != null) 'account': issue.account,
  if (issue.asOf != null) 'as_of': issue.asOf.toString(),
  if (issue.ageDays != null) 'age_days': issue.ageDays,
};
