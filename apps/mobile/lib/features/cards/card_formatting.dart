/// 卡包相关页面共用的文案与格式（日期、卡号尾号、规则说明）。只做展示，不含业务计算。
library;

import 'package:cardflow_domain/cardflow_domain.dart';

import '../../app/money/money_format.dart' show currencySpokenNames;
import '../../data/db/app_database.dart';
import '../../data/repositories/models.dart';
import '../../data/time/business_tz.dart';

/// `YYYY-MM-DD`。
String formatDate(LocalDate date) => date.toString();

/// 近期日期的短写法：与 [today] 同一年写 `MM-DD`，否则写完整日期（ui-spec §3.4 例"11-28"）。
String formatShortDate(LocalDate date, LocalDate today) =>
    date.year == today.year
    ? '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
    : date.toString();

/// "今天" / "{n} 天前"（快照时点距今天）。
String ageText(int days) => days <= 0 ? '今天' : '$days 天前';

/// 卡片尾号：`•••• 1234`。
String cardTail(CardRow card) => '•••• ${card.last4}';

/// 卡片的一行说明：尾号 · 主卡/附属卡 · 状态 · 卡组织。
String cardSummary(CardRow card) {
  final parts = <String>[
    cardTail(card),
    card.kind.label,
    card.cardStatus.label,
    if (card.cardNetwork != null) card.cardNetwork!.label,
  ];
  return parts.join(' · ');
}

/// 账单日的写法："每月 10 日"；29–31 日注明月末截断。
String describeStatementDay(int day) =>
    day >= 29 ? '每月 $day 日（小月按月末）' : '每月 $day 日';

/// 到期规则的写法："当月 28 日" / "次月 8 日" / "账单后 20 天"。
String describeDue(DueRule due) => switch (due.kind) {
  DueKind.fixedDay =>
    '${const <String>['当月', '次月', '再下月'][due.monthOffset]} ${due.day} 日',
  DueKind.daysAfterStatement =>
    '账单后 ${due.days} 个${due.dayKind == DayKind.business ? '工作日' : '自然日'}',
};

/// 规则版本行的到期规则（领域对象）。
DueRule dueOf(BillingRuleVersionRow row) => row.dueKind == DueKind.fixedDay.code
    ? DueRule.fixedDay(day: row.dueDay!, monthOffset: row.dueMonthOffset)
    : DueRule.daysAfterStatement(
        days: row.dueDays!,
        dayKind: row.dueDayKind == DayKind.business.code
            ? DayKind.business
            : DayKind.calendar,
      );

/// 账单日当天入账的归属。
String describeInclusive(bool inclusive) =>
    inclusive ? '账单日当天入账计入本期' : '账单日当天入账计入下期';

/// 顺延。
String describeRollover(String code) =>
    code == 'next_business_day' ? '到期日遇节假日顺延到下一个工作日（需已核验日历）' : '到期日不顺延';

/// 入账延迟。
String describePostingDelay(int min, int max) => min == max
    ? (min == 0 ? '交易当天入账' : '交易后 $min 天入账')
    : '交易后 $min–$max 天入账（账单日附近可能落在两个账期）';

/// 截止时点。
String describeCutoff(String? cutoff) =>
    cutoff == null ? '未设置截止时点（按入账日判断）' : '每日 $cutoff 后入账的算次日（按业务时区）';

/// 规则版本的生效区间文字。
String describeEffectiveRange(BillingRuleVersionRow row) {
  final from = row.effectiveFrom;
  final to = row.effectiveTo;
  if (to != null && to.compareTo(from ?? '0001-01-01') <= 0) {
    return '已被更正取代（不再适用于任何日期）';
  }
  final start = from == null ? '全部历史' : '$from 起';
  return to == null ? start : '$start，至 $to 前';
}

/// 业务时区的写法。
String describeZone(String id) => findBusinessTimeZone(id)?.displayName ?? id;

/// "人民币（CNY）"（币种中文名与 MoneyText 的读屏名同一张表）。
String currencyLabel(String code) =>
    '${currencySpokenNames[code] ?? code}（$code）';
