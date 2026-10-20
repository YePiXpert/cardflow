/// 卡账首页（简报 U-1 §2）的读模型：每张卡欠多少、哪天出账、哪天还款，顶部汇总，"今天刷哪张"，待处理与
/// "未计入"的应还。只读，纯函数（[LedgerHome.of]），不在 widget 里算。
///
/// 数据口径一律取 F-1 之后读模型 [LedgerData] 的有效状态与本期剩余应还（PRD §6.2 裁决段；简报 §10），**不读
/// `statement.status`**：
/// - 行 = 每个未停用信用账户的每个币种子账户；名称 = 银行简称 + 主卡末四位，右侧产品名；已冻结的标"已冻结"。
/// - 待还 = 本期账单（`currentStatementOf`）的剩余应还（`remaining`，只扣银行已入账的还款）；没有已出账单为 null
///   （界面写"—"，下方小字"未出账 ¥x"）。账单 = 本期当前版本的新增账单（`basis`）。
/// - 状态标签至多一个：已还清（银行确认）、已逾期、已标记还款、已还一部分；另有中性的已入账待确认、已转分期、
///   无需还款。
/// - 出账日：按账期规则从今天起的下一个账单日（`forecastCycles(版本, 今天)` 的 `conservative`，含当天归属）；
///   还款日：未结清账单的到期日（今天、已逾期 N 天），已结清或没有未结清账单时为下一期的预测到期日。
/// - 分组：信用卡（贷款分组在后续版本加入同一结构，汇总也按分组合计）。
library;

import 'package:cardflow_domain/cardflow_domain.dart' show Cycle, LocalDate;
import 'package:flutter/foundation.dart';

import '../banks/bank_names.dart';
import '../db/app_database.dart';
import '../mapping/domain_mapping.dart';
import '../mapping/ledger_mapping.dart' show StatementBalance;
import 'card_wallet_reader.dart';
import 'ledger_models.dart';
import 'ledger_reader.dart';
import 'models.dart';

/// 卡账首页的分组。贷款（PRD R-CASH-11）在后续版本加入。
enum LedgerHomeGroupKind {
  creditCards('信用卡');

  const LedgerHomeGroupKind(this.label);

  final String label;
}

/// 排序（简报 §2"排序"菜单）。
enum LedgerSort {
  /// 默认：未结清的按到期日升序在前，已还清/无待还的按下一期到期日在后，没有规则的最后。
  byDue('按还款日'),

  /// 按下一个账单日。
  byStatement('按出账日'),

  /// 按待还金额（人民币在前，同币种大的在前）。
  byAmount('按待还金额');

  const LedgerSort(this.label);

  final String label;
}

/// 一行的状态标签（至多一个）。
enum CardRowStatus {
  /// 有效状态"已还清"（银行确认）。
  paid('已还清'),

  /// 过了到期日仍未结清。
  overdue('已逾期'),

  /// 用户点了"我已还款"（不是银行确认）。
  markedPaid('已标记还款'),

  /// 账单日之后有银行入账的还款，还没还清。
  partiallyPaid('已还一部分'),

  /// 入账足额、还没有银行确认。
  postedAwaitingBank('已入账待确认'),

  /// 因转分期而结清。
  converted('已转分期'),

  /// 新增账单 ≤ 0，没有要还的。
  nothingDue('无需还款');

  const CardRowStatus(this.label);

  final String label;
}

/// 出账日格。
@immutable
final class StatementCell {
  const StatementCell({required this.date, required this.days});

  /// 下一个账单日。
  final LocalDate date;

  /// 距今天数（0 = 今天出账）。
  final int days;

  bool get isToday => days == 0;
}

/// 还款日格的语气。
enum DueTone {
  /// 未结清账单，还没到期。
  normal,

  /// 未结清账单今天到期（注意色）。
  today,

  /// 未结清账单已过到期日（危险色）。
  overdue,

  /// 已结清或没有未结清账单：下一期的预测到期日（次要文字色）。
  predicted,
}

/// 还款日格。
@immutable
final class DueCell {
  const DueCell({required this.date, required this.days, required this.tone});

  final LocalDate date;

  /// 距今天数：> 0 还有 N 天；0 今天；< 0 已过（逾期天数 = −days）。
  final int days;
  final DueTone tone;

  /// 逾期天数（只对 [DueTone.overdue]）。
  int get overdueDays => -days;
}

/// 等银行证据、可以一步推进的还款（简报 §3"还清本期"之后：卡账行与详情上一步推进"银行已入账""银行确认"）。
@immutable
final class PendingRepayment {
  const PendingRepayment({required this.repayment, required this.status});

  final RepaymentRow repayment;

  /// 有效状态（用户已标记到期仍无证据时为"待核对"）。
  final RepaymentStatus status;

  /// 下一步：已登记/处理中/现金已扣 → 银行已入账；银行已入账/用户已标记/待核对 → 银行确认。
  PendingStep get next => switch (status) {
    RepaymentStatus.recorded ||
    RepaymentStatus.processing ||
    RepaymentStatus.cashDebited => PendingStep.creditPosted,
    _ => PendingStep.bankConfirmed,
  };
}

/// 一步推进的目标。
enum PendingStep {
  creditPosted('银行已入账'),
  bankConfirmed('银行确认');

  const PendingStep(this.label);

  final String label;
}

/// 卡账首页的一行：一个信用账户的一个币种子账户。
@immutable
final class CardLedgerRow {
  const CardLedgerRow({
    required this.account,
    required this.sub,
    required this.bankName,
    required this.bankShort,
    required this.last4,
    required this.productName,
    required this.frozen,
    required this.current,
    required this.unbilled,
    required this.status,
    required this.statement,
    required this.due,
    required this.forecast,
    required this.missedStatement,
    required this.pending,
    required this.today,
  });

  final AccountView account;
  final CurrencyAccountView sub;

  /// 银行全称（徽标取色用）。
  final String bankName;

  /// 银行简称（"工行""星海"）。
  final String bankShort;

  /// 主卡（未停用）的末四位；没有未停用的卡时为 null。
  final String? last4;

  final String? productName;

  /// 已冻结（账户冻结，或未停用的卡全部冻结）。
  final bool frozen;

  /// 本期账单（最近一期已出账单）；没有时为 null。
  final StatementBalance? current;

  /// 未出账（负债四分法的"未出账"）。
  final int unbilled;

  /// 状态标签（至多一个）。
  final CardRowStatus? status;

  /// 出账日格；没有账期规则或规则给不出账期时为 null。
  final StatementCell? statement;

  /// 还款日格；没有未结清账单又没有规则时为 null。
  final DueCell? due;

  /// 预测账期（今天入账）。
  final CycleForecast forecast;

  /// 已过的预测账单日：最近一期已录账单之后、今天及以前还有一个账单日（账单出了还没录入）；没有时为 null。
  final Cycle? missedStatement;

  /// 本期账单上最近一笔等银行证据的还款；没有时为 null。
  final PendingRepayment? pending;

  /// 账户业务时区里的今天。
  final LocalDate today;

  String get creditAccountId => account.id;
  String get currencyAccountId => sub.row.id;
  String get currency => sub.currency;

  /// 待还（本期剩余应还）；没有已出账单时为 null。
  int? get remaining => current?.remaining;

  /// 本期新增账单（有符号）；没有已出账单时为 null。
  int? get billed => current?.basis;

  /// 还欠着（剩余应还 > 0）。
  bool get owes => current?.status.owes ?? false;

  /// 没有账期规则：两个日期格改为"设置账期 ›"。
  bool get needsRule => forecast is ForecastNoRule;

  /// 规则给不出账期（规则非法）。
  bool get ruleInvalid => forecast is ForecastInvalid;

  /// 可供新增消费的容量（三层取最小）；没有额度快照时为 null。
  int? get capacity => sub.capacity;

  /// 当前额度：最新快照的固定额度 + 未到期的临时额度（专项额度不算）；没有快照时为 null。
  int? get currentLimit => _limitOf(this);

  /// "星海 ···· 1001"。
  String get title => last4 == null ? bankShort : '$bankShort ···· $last4';
}

/// "今天刷哪张"的一个候选（简报 §2）。
@immutable
final class TodayCardCandidate {
  const TodayCardCandidate({
    required this.row,
    required this.cycle,
    required this.freeDays,
  });

  final CardLedgerRow row;

  /// 保守账期（入账延迟不确定时取最早到期）。
  final Cycle cycle;

  /// 免息天数 = 到期日 − 今天。
  final int freeDays;
}

/// 顶部汇总里"最近一笔到期"。
@immutable
final class NearestDue {
  const NearestDue({required this.row});

  final CardLedgerRow row;

  LocalDate get dueDate => row.current!.dueDate;
  int get amount => row.current!.remaining;
  String get currency => row.currency;
  bool get overdue => row.current!.status == EffectiveStatementStatus.overdue;
}

/// 顶部汇总卡（简报 §2）。
@immutable
final class LedgerHomeSummary {
  const LedgerHomeSummary({
    required this.dueByCurrency,
    required this.owingCards,
    required this.nearest,
    required this.dueSoon,
    required this.totalLimit,
    required this.available,
    required this.missingLimit,
    required this.missedStatements,
  });

  /// 本期待还合计，按币种（不同币种不相加；人民币在前）。
  final Map<String, int> dueByCurrency;

  /// 还欠着的卡（信用账户）数。
  final int owingCards;

  /// 最近一笔到期（还欠着的、到期日最早的；同日金额大的在前）。
  final NearestDue? nearest;

  /// 3 天内到期（含已逾期）的账单数（`LedgerData.upcoming(days: 3)`）。
  final int dueSoon;

  /// 人民币当前总额度（授信池只算一次池上限）；有账户缺额度快照或没有人民币账户时为 null。
  final int? totalLimit;

  /// 人民币可用（`capacityLayers` 口径，池只算一次，冻结的不算）；同上为 null。
  final int? available;

  /// 有账户缺额度快照（写"部分卡缺额度"，不以 0 代替）。
  final bool missingLimit;

  /// 有账单出了还没录入的卡数。
  final int missedStatements;

  int get cnyDue => dueByCurrency['CNY'] ?? 0;
}

/// "未计入"（简报 §9 Q-1）的一张卡：本期还欠着、却没有登记还款进现金时间线的部分。
@immutable
final class UncountedDue {
  const UncountedDue({required this.row, required this.amount});

  final CardLedgerRow row;

  /// 未计入现金时间线的应还（剩余应还 − 已登记、尚未入账、有现金扣款的还款）。
  final int amount;
}

/// 卡账首页的一个分组。
@immutable
final class LedgerHomeGroup {
  const LedgerHomeGroup({required this.kind, required this.rows});

  final LedgerHomeGroupKind kind;
  final List<CardLedgerRow> rows;
}

/// 卡账首页的读模型。
@immutable
final class LedgerHome {
  const LedgerHome({
    required this.groups,
    required this.summary,
    required this.candidates,
    required this.pendingCount,
    required this.uncounted,
  });

  /// "今天刷哪张"弹层里列出的候选数。
  static const int candidateLimit = 5;

  /// 3 天内到期的窗口。
  static const int dueSoonDays = 3;

  /// 从账单读模型推出首页（[sort] 决定行的顺序）。
  factory LedgerHome.of(LedgerData data, {LedgerSort sort = LedgerSort.byDue}) {
    final rows = <CardLedgerRow>[
      for (final account in data.wallet.accounts)
        if (!account.isInactive)
          for (final sub in account.currencies) ledgerRowOf(data, account, sub),
    ];
    final cards = LedgerHomeGroup(
      kind: LedgerHomeGroupKind.creditCards,
      rows: sortRows(rows, sort),
    );
    return LedgerHome(
      groups: <LedgerHomeGroup>[cards],
      summary: _summary(data, rows),
      candidates: todayCandidates(rows),
      pendingCount: data.awaitingEvidence.length + data.openItems.length,
      uncounted: _uncounted(data, rows),
    );
  }

  final List<LedgerHomeGroup> groups;
  final LedgerHomeSummary summary;

  /// "今天刷哪张"的候选（免息天数多的在前，至多 [candidateLimit] 个）；第一个就是推荐的那张。
  final List<TodayCardCandidate> candidates;

  /// 待处理：等银行证据的还款与未处理的差异项合计。
  final int pendingCount;

  /// "未计入"的卡（资金日历与汇总处的一行）。
  final List<UncountedDue> uncounted;

  /// 信用卡分组。
  LedgerHomeGroup get cards =>
      groups.firstWhere((g) => g.kind == LedgerHomeGroupKind.creditCards);

  /// 全部行。
  List<CardLedgerRow> get rows => <CardLedgerRow>[
    for (final g in groups) ...g.rows,
  ];

  bool get isEmpty => rows.isEmpty;

  TodayCardCandidate? get todayPick =>
      candidates.isEmpty ? null : candidates.first;

  /// "未计入"按币种的合计。
  Map<String, int> get uncountedByCurrency {
    final totals = <String, int>{};
    for (final u in uncounted) {
      totals[u.row.currency] = (totals[u.row.currency] ?? 0) + u.amount;
    }
    return _cnyFirst(totals);
  }

  /// "未计入"涉及的卡（信用账户）数。
  int get uncountedCards =>
      <String>{for (final u in uncounted) u.row.creditAccountId}.length;

  CardLedgerRow? rowOf(String currencyAccountId) {
    for (final r in rows) {
      if (r.currencyAccountId == currencyAccountId) {
        return r;
      }
    }
    return null;
  }
}

/// 一个币种子账户在卡账上的一行（卡片详情也用它：本期、出账日格、还款日格、等银行证据的还款）。已停用的
/// 账户也能算（首页不列出它们）。
CardLedgerRow ledgerRowOf(
  LedgerData data,
  AccountView account,
  CurrencyAccountView sub,
) {
  final today = account.today;
  final current = data.currentStatementOf(sub.row.id);
  final forecast = sub.forecast;
  final active = account.activeCards;
  CardRow? main;
  for (final c in active) {
    if (c.kind == HolderKind.primary) {
      main = c;
      break;
    }
  }
  main ??= active.isEmpty ? null : active.first;
  final frozen =
      account.account.status == 'frozen' ||
      (active.isNotEmpty &&
          active.every((c) => c.cardStatus == CardStatus.frozen));

  // 最近一笔还款（还欠着时看它是不是"已标记"）与等银行证据的那一笔。
  final latest = current == null
      ? null
      : data.latestRepaymentOn(current.statement.id);
  final latestStatus = latest == null ? null : data.repaymentStatusOf(latest);
  PendingRepayment? pending;
  if (current != null) {
    for (final (r, _) in data.repaymentsOn(current.statement.id)) {
      final status = data.repaymentStatusOf(r);
      if (_pendingStatuses.contains(status)) {
        pending = PendingRepayment(repayment: r, status: status);
        break;
      }
    }
  }

  final status = switch (current?.status) {
    null => null,
    EffectiveStatementStatus.paid => CardRowStatus.paid,
    EffectiveStatementStatus.overdue => CardRowStatus.overdue,
    EffectiveStatementStatus.due || EffectiveStatementStatus.partiallyPaid
        when latestStatus == RepaymentStatus.userMarkedPaid ||
            latestStatus == RepaymentStatus.needsReview =>
      CardRowStatus.markedPaid,
    EffectiveStatementStatus.partiallyPaid => CardRowStatus.partiallyPaid,
    EffectiveStatementStatus.postedAwaitingBank =>
      CardRowStatus.postedAwaitingBank,
    EffectiveStatementStatus.converted => CardRowStatus.converted,
    EffectiveStatementStatus.nothingDue => CardRowStatus.nothingDue,
    EffectiveStatementStatus.due || EffectiveStatementStatus.merged => null,
  };

  // 出账日：今天入账所属的账单日（保守账期）。
  StatementCell? statement;
  Cycle? predicted;
  if (forecast is ForecastPredicted) {
    predicted = forecast.conservative;
    statement = StatementCell(
      date: predicted.statementDate,
      days: predicted.statementDate.differenceInDays(today),
    );
  }

  // 账单出了还没录入：最近一期已录账单之后、今天及以前还有一个预测账单日。
  Cycle? missed;
  if (current != null && predicted != null) {
    final recent = recentStatementCycle(sub.ruleVersions, today);
    if (recent != null && recent.statementDate > current.statementDate) {
      missed = recent;
    }
  }

  DueCell? due;
  if (current != null && current.status.owes) {
    final days = current.dueDate.differenceInDays(today);
    due = DueCell(
      date: current.dueDate,
      days: days,
      tone: days > 0
          ? DueTone.normal
          : days == 0
          ? DueTone.today
          : DueTone.overdue,
    );
  } else if (missed != null) {
    due = DueCell(
      date: missed.dueDate,
      days: missed.dueDate.differenceInDays(today),
      tone: DueTone.predicted,
    );
  } else if (predicted != null) {
    due = DueCell(
      date: predicted.dueDate,
      days: predicted.dueDate.differenceInDays(today),
      tone: DueTone.predicted,
    );
  }

  return CardLedgerRow(
    account: account,
    sub: sub,
    bankName: account.bank.name,
    bankShort: bankShortName(account.bank.name),
    last4: main?.last4,
    productName: account.account.productName,
    frozen: frozen,
    current: current,
    unbilled: data.liabilities[sub.row.id]?.unbilled ?? 0,
    status: status,
    statement: statement,
    due: due,
    forecast: forecast,
    missedStatement: missed,
    pending: pending,
    today: today,
  );
}

/// 等银行证据、能一步推进的还款状态。
const Set<RepaymentStatus> _pendingStatuses = <RepaymentStatus>{
  RepaymentStatus.recorded,
  RepaymentStatus.processing,
  RepaymentStatus.cashDebited,
  RepaymentStatus.creditPosted,
  RepaymentStatus.userMarkedPaid,
  RepaymentStatus.needsReview,
};

/// 按 [sort] 排序（稳定；同一位置按银行简称、末四位、币种）。
List<CardLedgerRow> sortRows(List<CardLedgerRow> rows, LedgerSort sort) {
  int byName(CardLedgerRow a, CardLedgerRow b) {
    final name = a.bankShort.compareTo(b.bankShort);
    if (name != 0) {
      return name;
    }
    final tail = (a.last4 ?? '').compareTo(b.last4 ?? '');
    if (tail != 0) {
      return tail;
    }
    return _currencyOrder(a.currency).compareTo(_currencyOrder(b.currency));
  }

  int compareDates(LocalDate? a, LocalDate? b) {
    if (a == null && b == null) {
      return 0;
    }
    if (a == null) {
      return 1;
    }
    if (b == null) {
      return -1;
    }
    return a.compareTo(b);
  }

  final indexed = <(int, CardLedgerRow)>[
    for (var i = 0; i < rows.length; i++) (i, rows[i]),
  ];
  int compare((int, CardLedgerRow) x, (int, CardLedgerRow) y) {
    final a = x.$2;
    final b = y.$2;
    final int primary;
    switch (sort) {
      case LedgerSort.byDue:
        // 0：未结清（与账单出了没录入的）按到期日；1：已还清/无待还按下一期到期日；2：没有规则的。
        int tier(CardLedgerRow r) => r.owes || r.missedStatement != null
            ? 0
            : r.due != null
            ? 1
            : 2;
        final t = tier(a).compareTo(tier(b));
        primary = t != 0 ? t : compareDates(a.due?.date, b.due?.date);
      case LedgerSort.byStatement:
        primary = compareDates(a.statement?.date, b.statement?.date);
      case LedgerSort.byAmount:
        // 人民币在前；同币种待还大的在前；没有已出账单的排在同币种最后。
        final c = _currencyOrder(a.currency)
            .compareTo(_currencyOrder(b.currency));
        final int amount;
        if (a.remaining == null || b.remaining == null) {
          amount = a.remaining == null ? (b.remaining == null ? 0 : 1) : -1;
        } else {
          amount = b.remaining!.compareTo(a.remaining!);
        }
        primary = c != 0
            ? c
            : amount != 0
            ? amount
            : compareDates(a.due?.date, b.due?.date);
    }
    if (primary != 0) {
      return primary;
    }
    final name = byName(a, b);
    return name != 0 ? name : x.$1.compareTo(y.$1);
  }

  indexed.sort(compare);
  return <CardLedgerRow>[for (final (_, r) in indexed) r];
}

/// 币种排序：人民币在前，其余按代码。
String _currencyOrder(String currency) => currency == 'CNY' ? '' : currency;

Map<String, int> _cnyFirst(Map<String, int> totals) => <String, int>{
  for (final key
      in totals.keys.toList()
        ..sort((a, b) => _currencyOrder(a).compareTo(_currencyOrder(b))))
    key: totals[key]!,
};

LedgerHomeSummary _summary(LedgerData data, List<CardLedgerRow> rows) {
  final due = <String, int>{};
  final owing = <String>{};
  NearestDue? nearest;
  for (final r in rows) {
    final remaining = r.remaining ?? 0;
    if (remaining <= 0) {
      continue;
    }
    due[r.currency] = (due[r.currency] ?? 0) + remaining;
    owing.add(r.creditAccountId);
    final best = nearest;
    if (best == null ||
        r.current!.dueDate < best.dueDate ||
        (r.current!.dueDate == best.dueDate && remaining > best.amount)) {
      nearest = NearestDue(row: r);
    }
  }

  // 人民币额度：不在池里的账户各算各的；同一个池的成员只算一次池（池上限与成员额度之和取小）。
  var missing = false;
  var limit = 0;
  var available = 0;
  var anyCny = false;
  final poolMembers = <String, List<CardLedgerRow>>{};
  for (final r in rows) {
    if (r.currency != 'CNY') {
      continue;
    }
    anyCny = true;
    final pool = r.account.pool;
    if (pool != null && pool.currency == 'CNY') {
      poolMembers.putIfAbsent(pool.id, () => <CardLedgerRow>[]).add(r);
      continue;
    }
    final own = _limitOf(r);
    if (own == null || r.capacity == null) {
      missing = true;
      continue;
    }
    limit += own;
    if (!r.frozen) {
      available += r.capacity!;
    }
  }
  for (final entry in poolMembers.entries) {
    final pool = data.wallet.pools.firstWhere((p) => p.pool.id == entry.key);
    var memberLimits = 0;
    var ownCapacity = 0;
    var poolMissing = false;
    for (final r in entry.value) {
      final own = _limitOf(r);
      if (own == null || r.sub.ownCapacity == null) {
        poolMissing = true;
        continue;
      }
      memberLimits += own;
      if (!r.frozen) {
        ownCapacity += r.sub.ownCapacity!;
      }
    }
    final poolCapacity = pool.capacity;
    if (poolMissing || poolCapacity == null) {
      missing = true;
      continue;
    }
    final shared = pool.pool.sharedLimitMinor;
    limit += memberLimits < shared ? memberLimits : shared;
    available += ownCapacity < poolCapacity ? ownCapacity : poolCapacity;
  }

  return LedgerHomeSummary(
    dueByCurrency: _cnyFirst(due),
    owingCards: owing.length,
    nearest: nearest,
    dueSoon: data.upcoming(days: LedgerHome.dueSoonDays).length,
    totalLimit: missing || !anyCny ? null : limit,
    available: missing || !anyCny ? null : available,
    missingLimit: missing,
    missedStatements: <String>{
      for (final r in rows)
        if (r.missedStatement != null) r.creditAccountId,
    }.length,
  );
}

/// 一个币种子账户的当前额度：最新快照的固定额度 + 未到期的临时额度（专项额度不用于普通消费，不算）。
int? _limitOf(CardLedgerRow r) {
  final snapshot = r.sub.latestSnapshot;
  if (snapshot == null) {
    return null;
  }
  final expires = parseOptionalDate(snapshot.tempExpiresOn);
  final tempActive =
      snapshot.tempMinor > 0 && (expires == null || r.today < expires);
  return snapshot.fixedMinor + (tempActive ? snapshot.tempMinor : 0);
}

/// "今天刷哪张"的候选（简报 §2）：未冻结、有有效规则、可用容量 > 0 的人民币子账户；免息天数 = 保守账期的
/// 到期日 − 今天（入账延迟不确定时按最早到期）。天数多的在前；并列时可用容量大的在前，再按名称。
List<TodayCardCandidate> todayCandidates(List<CardLedgerRow> rows) {
  final candidates = <TodayCardCandidate>[];
  for (final r in rows) {
    final forecast = r.forecast;
    final capacity = r.capacity;
    if (r.currency != 'CNY' ||
        r.frozen ||
        forecast is! ForecastPredicted ||
        capacity == null ||
        capacity <= 0) {
      continue;
    }
    final cycle = forecast.conservative;
    candidates.add(
      TodayCardCandidate(
        row: r,
        cycle: cycle,
        freeDays: cycle.dueDate.differenceInDays(r.today),
      ),
    );
  }
  candidates.sort((a, b) {
    final days = b.freeDays.compareTo(a.freeDays);
    if (days != 0) {
      return days;
    }
    final capacity = b.row.capacity!.compareTo(a.row.capacity!);
    if (capacity != 0) {
      return capacity;
    }
    return a.row.title.compareTo(b.row.title);
  });
  return candidates.take(LedgerHome.candidateLimit).toList();
}

/// "未计入"（简报 §9 Q-1）：本期还欠着的账单，减去已登记、尚未银行入账、在现金时间线上有扣款的还款（疑似重复只
/// 计一次）之后还剩的部分。信用卡应还要不要自动作为计划流出，后续再定（BL-33）。
List<UncountedDue> _uncounted(LedgerData data, List<CardLedgerRow> rows) {
  final list = <UncountedDue>[];
  for (final r in rows) {
    final current = r.current;
    if (current == null || !current.status.owes) {
      continue;
    }
    final covered = <String, int>{};
    for (final (repayment, amount) in data.repaymentsOn(current.statement.id)) {
      final status = data.repaymentStatusOf(repayment);
      if (_coveringStatuses.contains(status) &&
          data.repaymentEvents.containsKey(repayment.id)) {
        covered[repayment.id] = (covered[repayment.id] ?? 0) + amount;
      }
    }
    var total = 0;
    for (final amount in covered.values) {
      total += amount;
    }
    for (final (a, b) in data.openDuplicates) {
      final x = covered[a];
      final y = covered[b];
      if (x != null && y != null) {
        total -= x < y ? x : y;
      }
    }
    final amount = current.remaining - total;
    if (amount > 0) {
      list.add(UncountedDue(row: r, amount: amount));
    }
  }
  return list;
}

/// 还没银行入账、扣款已经（或将要）在现金时间线上的还款状态。
const Set<RepaymentStatus> _coveringStatuses = <RepaymentStatus>{
  RepaymentStatus.recorded,
  RepaymentStatus.processing,
  RepaymentStatus.cashDebited,
  RepaymentStatus.userMarkedPaid,
  RepaymentStatus.needsReview,
};
