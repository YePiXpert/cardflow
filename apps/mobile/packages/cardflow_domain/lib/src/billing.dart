/// 账期规则：由入账日推出账单日与到期还款日（bank-rules-spec §3；Python `engine/billing.py`）。
///
/// 交易日、银行记账日、账单日、到期还款日、建议还款日、现金实际扣款日、银行确认还款日是七个
/// 不同的时间点；本模块只由入账日与一个规则版本推出（账单日, 到期日）。
library;

import 'pytext.dart';
import 'time.dart';

/// 到期规则的种类。
enum DueKind {
  /// 账单所在月加 `month_offset` 个月的固定日（月末截断）。
  fixedDay('fixed_day'),

  /// 账单日后 N 个自然日或工作日。
  daysAfterStatement('days_after_statement');

  const DueKind(this.code);

  /// 协议中的写法。
  final String code;
}

/// 天数口径。
enum DayKind {
  /// 自然日。
  calendar('calendar'),

  /// 工作日（需要已核验的工作日日历）。
  business('business');

  const DayKind(this.code);

  /// 协议中的写法。
  final String code;
}

/// 节假日顺延。
enum HolidayRollover {
  /// 不顺延。
  none('none'),

  /// 顺延到下一个工作日（需要已核验的工作日日历）。
  nextBusinessDay('next_business_day');

  const HolidayRollover(this.code);

  /// 协议中的写法。
  final String code;
}

/// 规则核验状态（元数据）。
enum RuleStatus {
  /// 草稿。
  draft('draft'),

  /// 已核验。
  verified('verified'),

  /// 用户声明。
  userDeclared('user_declared');

  const RuleStatus(this.code);

  /// 协议中的写法。
  final String code;
}

/// 到期规则。
final class DueRule {
  /// 通用构造（字段与 Python `DueRule` 相同）。
  const DueRule({
    required this.kind,
    this.day,
    this.monthOffset = 0,
    this.days,
    this.dayKind = DayKind.calendar,
  });

  /// 固定日：账单所在月 + [monthOffset]（0 当月、1 次月）的第 [day] 日（月末截断）。
  const DueRule.fixedDay({required int this.day, this.monthOffset = 0})
    : kind = DueKind.fixedDay,
      days = null,
      dayKind = DayKind.calendar;

  /// 账单日后 [days] 天（[dayKind] 自然日或工作日）。
  const DueRule.daysAfterStatement({
    required int this.days,
    this.dayKind = DayKind.calendar,
  }) : kind = DueKind.daysAfterStatement,
       day = null,
       monthOffset = 0;

  /// 种类。
  final DueKind kind;

  /// fixed_day：1–31（月末截断）。
  final int? day;

  /// fixed_day：0 = 账单所在月，1 = 次月，2 = 再下月。
  final int monthOffset;

  /// days_after_statement：N。
  final int? days;

  /// days_after_statement：自然日或工作日。
  final DayKind dayKind;
}

/// 一个账期规则版本。
final class BillingRule {
  /// 默认值与 Python `BillingRule` 相同。
  BillingRule({
    required this.ruleId,
    required this.statementDay,
    required this.due,
    this.statementDayInclusive = true,
    this.holidayRollover = HolidayRollover.none,
    this.effectiveFrom,
    this.effectiveTo,
    this.source = '',
    this.verifiedOn,
    this.status = RuleStatus.userDeclared,
  });

  /// 规则 ID。
  final String ruleId;

  /// 账单日 1–31（月末截断）。
  final int statementDay;

  /// 到期规则。
  final DueRule due;

  /// 账单日当天入账是否计入本期（银行差异，需核验；默认 true）。
  final bool statementDayInclusive;

  /// 节假日顺延。
  final HolidayRollover holidayRollover;

  /// 生效首日（含；null = 不限）。
  final LocalDate? effectiveFrom;

  /// 失效日（不含；null = 不限）。
  final LocalDate? effectiveTo;

  /// 规则来源。
  final String source;

  /// 核验日期。
  final LocalDate? verifiedOn;

  /// 核验状态。
  final RuleStatus status;

  /// 该版本在入账日 [date] 是否生效（`effective_from <= date < effective_to`）。
  bool isEffectiveOn(LocalDate date) {
    final from = effectiveFrom;
    if (from != null && date < from) {
      return false;
    }
    final to = effectiveTo;
    if (to != null && date >= to) {
      return false;
    }
    return true;
  }
}

/// 一个账期：账单日与到期日。
final class Cycle {
  /// 账期。
  const Cycle(
    this.statementDate,
    this.dueDate,
    this.ruleId, [
    this.assumptions = const <String>[],
  ]);

  /// 账单日。
  final LocalDate statementDate;

  /// 到期还款日。
  final LocalDate dueDate;

  /// 规则 ID（已出账单为 `issued:<来源>`）。
  final String ruleId;

  /// 假设说明（如入账延迟）。
  final List<String> assumptions;
}

/// 工作日判定（需要已核验的日历）。
typedef BusinessDayFn = bool Function(LocalDate date);

/// 规则对该入账日给不出账期：版本不生效、配置错误（到期不晚于账单日）或需要工作日日历。
///
/// 交易日上是数据问题（`BILLING_RULE_INVALID`）；推迟日期搜索中的平移日期上，该卡当日不可用
/// （engine-spec §12.9）。`toString()` 就是消息本身（与 Python `str(e)` 相同）。
final class BillingRuleError implements Exception {
  /// 规则错误。
  BillingRuleError(this.message);

  /// 消息。
  final String message;

  @override
  String toString() => message;
}

/// 入账日 [posting] 所属的账单日：`posting < S` 或（`posting == S` 且计入当天）→ 本月，否则下月。
LocalDate statementDateForPosting(BillingRule rule, LocalDate posting) {
  final thisStatement = clampDay(
    posting.year,
    posting.month,
    rule.statementDay,
  );
  if (posting < thisStatement ||
      (posting == thisStatement && rule.statementDayInclusive)) {
    return thisStatement;
  }
  final (year, month) = addMonths(posting, 1);
  return clampDay(year, month, rule.statementDay);
}

/// 账单日 [statement] 的到期还款日。
LocalDate dueDateForStatement(
  BillingRule rule,
  LocalDate statement, [
  BusinessDayFn? isBusinessDay,
]) {
  final r = rule.due;
  LocalDate due;
  switch (r.kind) {
    case DueKind.fixedDay:
      final day = r.day;
      if (day == null) {
        throw BillingRuleError('fixed_day rule needs day');
      }
      final (year, month) = addMonths(statement, r.monthOffset);
      due = clampDay(year, month, day);
      if (due <= statement) {
        throw BillingRuleError(
          'rule ${rule.ruleId}: due $due is not after statement $statement '
          '(month_offset/day misconfigured)',
        );
      }
    case DueKind.daysAfterStatement:
      final days = r.days;
      if (days == null) {
        throw BillingRuleError('days_after_statement rule needs days');
      }
      if (r.dayKind == DayKind.calendar) {
        due = statement.addDays(days);
      } else {
        if (isBusinessDay == null) {
          throw BillingRuleError(
            'business-day counting requires a verified calendar',
          );
        }
        due = statement;
        var counted = 0;
        while (counted < days) {
          due = due.addDays(1);
          if (isBusinessDay(due)) {
            counted++;
          }
        }
      }
  }
  if (rule.holidayRollover == HolidayRollover.nextBusinessDay) {
    if (isBusinessDay == null) {
      throw BillingRuleError(
        'holiday_rollover requires a verified business-day calendar',
      );
    }
    while (!isBusinessDay(due)) {
      due = due.addDays(1);
    }
  }
  return due;
}

/// 入账日 [posting] 的账期（规则版本必须在该日生效）。
Cycle cycleForPosting(
  BillingRule rule,
  LocalDate posting, [
  BusinessDayFn? isBusinessDay,
]) {
  if (!rule.isEffectiveOn(posting)) {
    throw BillingRuleError('rule ${rule.ruleId} not effective on $posting');
  }
  final statement = statementDateForPosting(rule, posting);
  return Cycle(
    statement,
    dueDateForStatement(rule, statement, isBusinessDay),
    rule.ruleId,
  );
}

/// 入账窗口（交易日 + [postingDelayMin] … [postingDelayMax] 天）内所有去重后的可能账期，
/// 最早到期在前。多于一个 = 账单日附近的入账不确定；保守情景按最早到期校验（F-15）。
List<Cycle> cyclesForTransaction(
  BillingRule rule,
  LocalDate txnDate, {
  int postingDelayMin = 0,
  int postingDelayMax = 0,
  BusinessDayFn? isBusinessDay,
}) {
  final seen = <(int, int), Cycle>{};
  for (var delay = postingDelayMin; delay <= postingDelayMax; delay++) {
    final posting = txnDate.addDays(delay);
    final c = cycleForPosting(rule, posting, isBusinessDay);
    final key = (c.statementDate.epochDay, c.dueDate.epochDay);
    if (!seen.containsKey(key)) {
      seen[key] = Cycle(c.statementDate, c.dueDate, c.ruleId, <String>[
        'posting delay ${delay}d -> posting $posting',
      ]);
    }
  }
  final cycles = seen.values.toList();
  // 稳定排序（插入排序；入账窗口至多 367 天）：同一到期日保持入账延迟的先后。
  for (var i = 1; i < cycles.length; i++) {
    final item = cycles[i];
    var j = i - 1;
    while (j >= 0 && cycles[j].dueDate > item.dueDate) {
      cycles[j + 1] = cycles[j];
      j--;
    }
    cycles[j + 1] = item;
  }
  return cycles;
}

/// 入账日 [on] 生效的唯一规则版本；没有或多于一个时抛 [BillingRuleError]。
/// 已出账单的处理在调用方：已出账单永远优先于预测（[resolveCycle]）。
BillingRule selectRule(List<BillingRule> rules, LocalDate on) {
  final candidates = rules.where((r) => r.isEffectiveOn(on)).toList();
  if (candidates.isEmpty) {
    throw BillingRuleError('no billing rule effective on $on');
  }
  if (candidates.length > 1) {
    throw BillingRuleError(
      'overlapping billing rule versions on $on: '
      '${pyListRepr(candidates.map((r) => r.ruleId))}',
    );
  }
  return candidates.single;
}

/// 已出账单（银行事实）。
final class IssuedStatement {
  /// 已出账单。
  const IssuedStatement(
    this.statementDate,
    this.dueDate, [
    this.source = 'bank_statement',
  ]);

  /// 账单日。
  final LocalDate statementDate;

  /// 到期还款日。
  final LocalDate dueDate;

  /// 来源。
  final String source;
}

/// 已出账单优先于预测；预测用入账日生效的规则版本（F-14：规则变更不改写已出账单）。
Cycle resolveCycle(
  List<BillingRule> rules,
  List<IssuedStatement> issued,
  LocalDate posting, [
  BusinessDayFn? isBusinessDay,
]) {
  final predicted = cycleForPosting(
    selectRule(rules, posting),
    posting,
    isBusinessDay,
  );
  for (final s in issued) {
    if (s.statementDate == predicted.statementDate) {
      return Cycle(
        s.statementDate,
        s.dueDate,
        'issued:${s.source}',
        const <String>['issued statement overrides prediction'],
      );
    }
  }
  return predicted;
}
