/// 逐账户现金时间线：快照包含关系、同日顺序与情景变换（Python `engine/cash.py`，模型 1.1.0）。
///
/// * 快照当天、未标记为已包含的事件计入当日（不丢弃）；
/// * "已被快照反映"按**原始事件**判定，先于情景变换（engine-spec §12.2）；情景把事件移到快照日
///   之前时，按快照日计入并记假设；
/// * 被情景改动了日期的事件丢弃时间戳（§12.4）；
/// * 情景要求按时间戳且当日每个已有事件都带时间戳时按时间戳排序，否则保守地"先支出后收入"；
///   计划还款与模型的候选还款日不参与这一判断，按时间戳排序的日子里计划还款排在最前；
/// * 账户之间从不相互抵补。
library;

import 'rational.dart';
import 'sort.dart';
import 'time.dart';

/// 现金事件类别。
enum EventClass {
  /// 已确认：已出账单、已约定固定支出、合同/到账确定的流入。
  confirmed('confirmed'),

  /// 预计：工资、返现、退款等未到账流入或估计支出。
  expected('expected'),

  /// 计划：由新消费计划注入的还款（引擎内部），或用户登记的计划收支。
  planned('planned');

  const EventClass(this.code);

  /// 协议中的写法。
  final String code;
}

/// 一笔现金流（不含正在评估的计划）。负数 = 流出。
final class CashEvent {
  /// 现金事件。
  const CashEvent({
    required this.id,
    required this.account,
    required this.on,
    required this.amount,
    required this.cls,
    this.category = '',
    this.label = '',
    this.at,
  });

  /// 事件 ID。
  final String id;

  /// 现金账户 ID。
  final String account;

  /// 业务日期。
  final LocalDate on;

  /// 金额（最小单位；负数 = 流出）。
  final int amount;

  /// 类别。
  final EventClass cls;

  /// income | bill | living | repayment | transfer_in | transfer_out | fee | other。
  final String category;

  /// 显示标签。
  final String label;

  /// 精确时刻（已知时；仅用于同日按时间戳排序）。
  final Timestamp? at;

  /// 改日期、金额或时间戳后的副本（[clearAt] 为 true 时丢弃时间戳）。
  CashEvent copyWith({LocalDate? on, int? amount, bool clearAt = false}) =>
      CashEvent(
        id: id,
        account: account,
        on: on ?? this.on,
        amount: amount ?? this.amount,
        cls: cls,
        category: category,
        label: label,
        at: clearAt ? null : at,
      );
}

/// 账户在业务日 [asOf] 开始时的余额快照。
final class Snapshot {
  /// 快照。
  const Snapshot({
    required this.account,
    required this.balance,
    required this.asOf,
    this.observedAt,
    this.includesEventIds = const <String>{},
  });

  /// 现金账户 ID。
  final String account;

  /// 余额（最小单位）。
  final int balance;

  /// 快照日。
  final LocalDate asOf;

  /// 观测时刻（元数据）。
  final Timestamp? observedAt;

  /// 快照日当天、余额**已经包含**的事件。
  final Set<String> includesEventIds;
}

/// 现金账户。
final class CashAccount {
  /// 现金账户（默认值与 Python `CashAccount` 相同）。
  const CashAccount({
    required this.id,
    required this.name,
    this.currency = 'CNY',
    this.reserveFloor = 0,
    this.usableForRepayment = true,
  });

  /// 账户 ID。
  final String id;

  /// 名称。
  final String name;

  /// 币种。
  final String currency;

  /// 用户最低储备（硬约束）。
  final int reserveFloor;

  /// false = 理财/受限资金：从它还款的卡被排除（REPAY_ACCOUNT_RESTRICTED）。
  final bool usableForRepayment;
}

/// 同日顺序。
enum SameDayOrder {
  /// 先支出后收入。
  conservative('conservative'),

  /// 当日每个已有事件都带时间戳时按时间戳。
  timestamp('timestamp');

  const SameDayOrder(this.code);

  /// 协议中的写法。
  final String code;
}

/// 情景对单个事件的覆盖（日期和/或金额）。
final class EventOverride {
  /// 至少给出一项。
  const EventOverride({this.on, this.amount});

  /// 新日期。
  final LocalDate? on;

  /// 新金额。
  final int? amount;
}

/// 现金情景。
final class Scenario {
  /// 情景（默认值与 Python `Scenario` 相同）。
  Scenario({
    required this.id,
    this.includeExpected = true,
    this.incomeDelayDays = 0,
    Rational? incomeScale,
    Rational? expenseScale,
    this.eventOverrides = const <String, EventOverride>{},
    this.sameDayOrder = SameDayOrder.conservative,
    this.description = '',
  }) : incomeScale = incomeScale ?? Rational.one,
       expenseScale = expenseScale ?? Rational.one;

  /// 情景 ID。
  final String id;

  /// false = 只看已确认口径（丢弃所有预计事件）。
  final bool includeExpected;

  /// 预计流入的延迟天数。
  final int incomeDelayDays;

  /// 预计流入的系数（HALF_UP 取整到最小单位）。
  final Rational incomeScale;

  /// `living` 类流出的系数（HALF_UP）。
  final Rational expenseScale;

  /// 事件 ID → 覆盖（先于延迟与缩放）。
  final Map<String, EventOverride> eventOverrides;

  /// 同日顺序。
  final SameDayOrder sameDayOrder;

  /// 说明。
  final String description;
}

/// 时间线上的点的种类。
enum PointPhase {
  /// 快照余额。
  snapshot('snapshot'),

  /// 当日最低点（流出之后、流入之前）。
  low('low'),

  /// 当日日终。
  end('end');

  const PointPhase(this.code);

  /// Python 中的写法。
  final String code;
}

/// 时间线上的一个点。
final class Point {
  /// 点。
  const Point(
    this.on,
    this.phase,
    this.balance, [
    this.eventIds = const <String>[],
  ]);

  /// 日期。
  final LocalDate on;

  /// 种类。
  final PointPhase phase;

  /// 余额。
  final int balance;

  /// `low`：当日的流出事件；`end`：当日全部事件。
  final List<String> eventIds;
}

/// 一个账户在一个情景下的时间线。
final class Timeline {
  /// 时间线。
  const Timeline(
    this.account,
    this.scenario,
    this.snapshot,
    this.points,
    this.assumptions,
    this.skippedEventIds,
  );

  /// 账户 ID。
  final String account;

  /// 情景 ID。
  final String scenario;

  /// 快照。
  final Snapshot snapshot;

  /// 点（快照点在前，之后每天一个 low、一个 end）。
  final List<Point> points;

  /// 假设说明。
  final List<String> assumptions;

  /// 已被快照反映而跳过的事件。
  final List<String> skippedEventIds;
}

int _scale(int amount, Rational factor) {
  if (factor == Rational.one) {
    return amount;
  }
  final magnitude = (Rational.fromInt(amount).abs() * factor).roundToInt(
    RoundingMode.halfUp,
  );
  return amount < 0 ? -magnitude : magnitude;
}

/// [scenario] 眼中的事件 [e]；情景丢弃它时返回 null。先覆盖，再对预计流入延迟与缩放，
/// 再对 `living` 流出缩放；日期被改动的事件丢弃时间戳（engine-spec §12.4）。
CashEvent? scenarioEvent(CashEvent e, Scenario scenario) {
  if (e.cls == EventClass.expected && !scenario.includeExpected) {
    return null;
  }
  final ov = scenario.eventOverrides[e.id];
  var on = ov?.on ?? e.on;
  var amount = ov?.amount ?? e.amount;
  if (e.cls == EventClass.expected && amount > 0) {
    on = on.addDays(scenario.incomeDelayDays);
    amount = _scale(amount, scenario.incomeScale);
  }
  if (amount < 0 && e.category == 'living') {
    amount = _scale(amount, scenario.expenseScale);
  }
  return e.copyWith(on: on, amount: amount, clearAt: on != e.on);
}

/// 对一组事件应用情景（丢弃情景不要的事件）。
List<CashEvent> applyScenario(Iterable<CashEvent> events, Scenario scenario) =>
    [for (final e in events) ?scenarioEvent(e, scenario)];

/// 快照余额是否已经包含 [e]：日期早于快照日，或等于快照日且列在 `includes_event_ids` 中。
/// 按**原始事件**判定——任何情景都不能把事件移进或移出余额（engine-spec §12.2）。
bool reflectedInSnapshot(CashEvent e, Snapshot snapshot) =>
    e.on < snapshot.asOf ||
    (e.on == snapshot.asOf && snapshot.includesEventIds.contains(e.id));

/// [account] 在 [scenario] 下直到 [horizonEnd] 的时间线。
///
/// [planned]：计划还款（验证器的），日期不早于快照日；它们不参与同日顺序的判断，按时间戳排序的
/// 日子里排在最前。[checkpointDays]：即使没有事件也要有（low, end）点的日子（模型的候选还款日）。
Timeline buildTimeline(
  CashAccount account,
  Snapshot snapshot,
  Iterable<CashEvent> events,
  Scenario scenario,
  LocalDate horizonEnd, {
  Iterable<CashEvent> planned = const <CashEvent>[],
  Iterable<LocalDate> checkpointDays = const <LocalDate>[],
}) {
  if (snapshot.account != account.id) {
    throw ArgumentError('snapshot/account mismatch');
  }
  final asOf = snapshot.asOf;
  final pending = <CashEvent>[];
  final skipped = <String>[];
  final assumptions = <String>[];
  var onSnapshotDay = false;
  for (final e in events) {
    if (e.account != account.id) {
      continue;
    }
    if (reflectedInSnapshot(e, snapshot)) {
      skipped.add(e.id); // 已在余额中，不论情景如何处理它
      continue;
    }
    var t = scenarioEvent(e, scenario);
    if (t == null) {
      continue;
    }
    if (e.on == asOf) {
      onSnapshotDay = true;
    }
    if (t.on < asOf) {
      // 情景把它移到快照日之前：它不在余额里
      assumptions.add('${t.id}: 情景将其日期移到快照日之前，按快照日 $asOf 计入');
      t = t.copyWith(on: asOf, clearAt: true);
    }
    if (t.on <= horizonEnd) {
      pending.add(t);
    }
  }
  if (onSnapshotDay) {
    assumptions.add('$asOf: 快照当天未标记为已包含的事件按未发生处理并计入当日');
  }
  final byDay = <int, (List<CashEvent>, List<CashEvent>)>{};
  (List<CashEvent>, List<CashEvent>) slot(LocalDate d) =>
      byDay.putIfAbsent(d.epochDay, () => (<CashEvent>[], <CashEvent>[]));
  for (final e in pending) {
    slot(e.on).$1.add(e);
  }
  for (final p in planned) {
    if (p.account == account.id && p.on <= horizonEnd) {
      slot(p.on.laterOf(asOf)).$2.add(p);
    }
  }
  for (final d in checkpointDays) {
    if (asOf <= d && d <= horizonEnd) {
      slot(d);
    }
  }
  var balance = snapshot.balance;
  final points = <Point>[Point(asOf, PointPhase.snapshot, balance)];
  final days = byDay.keys.toList()..sort();
  for (final epochDay in days) {
    final d = LocalDate.fromEpochDay(epochDay);
    final (day, planDay) = byDay[epochDay]!;
    if (scenario.sameDayOrder == SameDayOrder.timestamp &&
        day.every((e) => e.at != null)) {
      // 稳定排序：同一时刻保持输入顺序
      final inOrder = stableSorted(day, (a, b) => a.at!.compareTo(b.at!));
      var running = balance;
      for (final p in planDay) {
        running += p.amount; // 计划还款排在最前
      }
      var low = balance < running ? balance : running;
      for (final e in inOrder) {
        running += e.amount;
        if (running < low) {
          low = running;
        }
      }
      if (planDay.isNotEmpty && day.any((e) => e.amount > 0)) {
        assumptions.add('$d: 计划还款没有时间戳，按当日最先发生处理');
      }
      final outflows = [
        for (final e in [...day, ...planDay])
          if (e.amount < 0) e.id,
      ];
      points.add(Point(d, PointPhase.low, low, outflows));
      final endIds = [
        for (final p in planDay) p.id,
        for (final e in inOrder) e.id,
      ];
      points.add(Point(d, PointPhase.end, running, endIds));
      balance = running;
      continue;
    }
    final outs = [
      for (final e in day)
        if (e.amount < 0) e,
      for (final p in planDay)
        if (p.amount < 0) p,
    ];
    final ins = [
      for (final e in day)
        if (e.amount > 0) e,
      for (final p in planDay)
        if (p.amount > 0) p,
    ];
    if (outs.isNotEmpty && ins.isNotEmpty) {
      assumptions.add('$d: 同日收支顺序未知，按保守顺序（先支出后收入）校验');
    }
    var low = balance;
    for (final e in outs) {
      low += e.amount;
    }
    var end = low;
    for (final e in ins) {
      end += e.amount;
    }
    points.add(Point(d, PointPhase.low, low, [for (final e in outs) e.id]));
    points.add(
      Point(d, PointPhase.end, end, [
        for (final e in [...day, ...planDay]) e.id,
      ]),
    );
    balance = end;
  }
  return Timeline(
    account.id,
    scenario.id,
    snapshot,
    points,
    assumptions,
    skipped,
  );
}

/// 一个缺口点（余额低于储备）。
final class Breach {
  /// 缺口点。
  const Breach(
    this.on,
    this.phase,
    this.balance,
    this.gapToZero,
    this.gapToReserve,
    this.eventIds,
  );

  /// 日期。
  final LocalDate on;

  /// 快照点或当日最低点。
  final PointPhase phase;

  /// 余额。
  final int balance;

  /// 距零（≥ 0）。
  final int gapToZero;

  /// 距储备（≥ 0）。
  final int gapToReserve;

  /// 当日流出事件。
  final List<String> eventIds;
}

/// 一个账户的检查结果。
final class CashReport {
  /// 检查结果。
  const CashReport({
    required this.account,
    required this.scenario,
    required this.ok,
    required this.okZero,
    required this.minBalance,
    required this.minOn,
    required this.breaches,
    required this.firstBreach,
    required this.firstZeroBreach,
    required this.endBalance,
    required this.assumptions,
    required this.timeline,
  });

  /// 账户 ID。
  final String account;

  /// 情景 ID。
  final String scenario;

  /// 没有低于储备的缺口点。
  final bool ok;

  /// 没有低于零的点。
  final bool okZero;

  /// 最低余额（快照点与各日最低点中）。
  final int minBalance;

  /// 最低余额首次出现的日期。
  final LocalDate minOn;

  /// **全部**缺口点，按时间顺序（从不只给第一个）。
  final List<Breach> breaches;

  /// 第一个缺口点。
  final Breach? firstBreach;

  /// 第一个低于零的点。
  final Breach? firstZeroBreach;

  /// 期末余额。
  final int endBalance;

  /// 假设说明。
  final List<String> assumptions;

  /// 时间线。
  final Timeline timeline;
}

/// 按储备 [reserveFloor] 检查时间线。
///
/// 缺口点是：(a) 快照本身已低于储备；(b) 当日**流出**使余额低于（或继续低于）储备的日子。
/// 只有流入的日子不再增加缺口条目：缺口已记录，剩余状态见最低与期末余额。
CashReport evaluate(Timeline timeline, int reserveFloor) {
  final breaches = <Breach>[];
  Breach? firstZero;
  int? minBalance;
  LocalDate? minOn;
  for (final p in timeline.points) {
    if (p.phase == PointPhase.end) {
      continue; // 同日 end >= low，从不是约束点
    }
    if (minBalance == null || p.balance < minBalance) {
      minBalance = p.balance;
      minOn = p.on;
    }
    if (p.balance < reserveFloor) {
      final b = Breach(
        p.on,
        p.phase,
        p.balance,
        p.balance < 0 ? -p.balance : 0,
        reserveFloor - p.balance,
        p.eventIds,
      );
      if (p.phase == PointPhase.snapshot ||
          (p.phase == PointPhase.low && p.eventIds.isNotEmpty)) {
        breaches.add(b);
      }
      if (p.balance < 0 && firstZero == null) {
        firstZero = b;
      }
    }
  }
  return CashReport(
    account: timeline.account,
    scenario: timeline.scenario,
    ok: breaches.isEmpty,
    okZero: firstZero == null,
    minBalance: minBalance!,
    minOn: minOn!,
    breaches: breaches,
    firstBreach: breaches.isEmpty ? null : breaches.first,
    firstZeroBreach: firstZero,
    endBalance: timeline.points.last.balance,
    assumptions: List<String>.of(timeline.assumptions),
    timeline: timeline,
  );
}

/// 每个账户（按输入顺序）在 [scenario] 下的检查结果；缺快照时抛 [StateError]
/// （调用方先做数据检查：MISSING_SNAPSHOT）。
Map<String, CashReport> evaluateAccounts(
  List<CashAccount> accounts,
  Map<String, Snapshot> snapshots,
  Iterable<CashEvent> events,
  Scenario scenario,
  LocalDate horizonEnd, {
  Iterable<CashEvent> planned = const <CashEvent>[],
}) {
  final eventList = List<CashEvent>.of(events);
  final plannedList = List<CashEvent>.of(planned);
  final out = <String, CashReport>{};
  for (final a in accounts) {
    final snapshot = snapshots[a.id];
    if (snapshot == null) {
      throw StateError(
        'NEEDS_DATA: no balance snapshot for cash account ${a.id}',
      );
    }
    final timeline = buildTimeline(
      a,
      snapshot,
      eventList,
      scenario,
      horizonEnd,
      planned: plannedList,
    );
    out[a.id] = evaluate(timeline, a.reserveFloor);
  }
  return out;
}
