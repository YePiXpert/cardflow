import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../ids.dart';
import '../mapping/domain_mapping.dart';
import '../time/business_tz.dart';
import '../time/clock.dart';
import '../validation/text_rules.dart';
import 'models.dart';
import 'repository_errors.dart';
import 'workspace_scope.dart';

/// 入账延迟在界面与仓库里的上限（天）。数据库与协议允许到 366，这里取常见的范围。
const int maxPostingDelayDays = 30;

/// 一份账期规则（P-04 编辑器的内容），还没有版本号与生效区间。
@immutable
final class BillingRuleDraft {
  const BillingRuleDraft({
    required this.statementDay,
    required this.due,
    this.statementDayInclusive = true,
    this.holidayRollover = HolidayRollover.none,
    this.cutoffTime,
    this.postingDelayMinDays = 0,
    this.postingDelayMaxDays = 0,
    this.exceptions,
  });

  /// 账单日 1–31（月末截断）。
  final int statementDay;

  /// 到期规则（领域包 [DueRule]）。
  final DueRule due;

  final bool statementDayInclusive;
  final HolidayRollover holidayRollover;

  /// 截止时点 `HH:MM`（业务时区），空 = 不按时刻判断入账日。
  final String? cutoffTime;

  final int postingDelayMinDays;
  final int postingDelayMaxDays;

  /// 例外说明（G2/G5，≤200 字）。
  final String? exceptions;

  /// 对应的领域包规则（预览与校验用）。
  BillingRule toDomain({
    String ruleId = 'draft',
    LocalDate? effectiveFrom,
    LocalDate? effectiveTo,
  }) => BillingRule(
    ruleId: ruleId,
    statementDay: statementDay,
    due: due,
    statementDayInclusive: statementDayInclusive,
    holidayRollover: holidayRollover,
    effectiveFrom: effectiveFrom,
    effectiveTo: effectiveTo,
    source: RuleSource.userDeclared.code,
  );
}

/// 保存新版本时，新版本从哪天起生效。
sealed class RuleEffect {
  const RuleEffect();
}

/// 从某一入账日起按新规则计算：当前版本 `effective_to` 封口为这一天（F-14）。
final class RuleEffectiveFrom extends RuleEffect {
  const RuleEffectiveFrom(this.date);

  final LocalDate date;
}

/// 更正当前版本（例如填错了账单日）：新版本接替当前版本的整个区间，当前版本的区间变为空，
/// 任何日期都不再选中它（仍保留在版本历史里）。
final class RuleCorrection extends RuleEffect {
  const RuleCorrection();
}

/// 一份规则在业务上的问题（保存前检查）：返回文案，没有问题返回 null。
///
/// - 账单日、到期日、偏移、天数、入账延迟、截止时点的取值范围；
/// - 工作日计数与节假日顺延需要已核验的工作日日历，本阶段没有，一律不允许（ui-spec P-04、A-07）；
/// - 到期日必须晚于账单日（UF-1"账期规则非法 → 阻止保存"）：用领域包对连续 48 个账单月逐一
///   计算到期日（覆盖月末截断与闰年），任何一个月不晚于账单日都算非法。
String? billingRuleDraftProblem(BillingRuleDraft draft) {
  if (draft.statementDay < 1 || draft.statementDay > 31) {
    return '账单日须在 1–31 之间';
  }
  final due = draft.due;
  switch (due.kind) {
    case DueKind.fixedDay:
      final day = due.day;
      if (day == null || day < 1 || day > 31) {
        return '到期日须在 1–31 之间';
      }
      if (due.monthOffset < 0 || due.monthOffset > 2) {
        return '到期月份只能是当月、次月或再下月';
      }
    case DueKind.daysAfterStatement:
      final days = due.days;
      if (days == null || days < 1 || days > 60) {
        return '账单后天数须在 1–60 之间';
      }
      if (due.dayKind == DayKind.business) {
        return '按工作日计算需要已核验的工作日日历，本阶段不可用';
      }
  }
  if (draft.holidayRollover == HolidayRollover.nextBusinessDay) {
    return '节假日顺延需要已核验的工作日日历，本阶段不可用';
  }
  if (draft.postingDelayMinDays < 0 ||
      draft.postingDelayMaxDays > maxPostingDelayDays ||
      draft.postingDelayMinDays > draft.postingDelayMaxDays) {
    return '入账延迟须满足 0 ≤ 最少 ≤ 最多 ≤ $maxPostingDelayDays 天';
  }
  final cutoff = draft.cutoffTime;
  if (cutoff != null) {
    try {
      CutoffTime.parse(cutoff);
    } on FormatException {
      return '截止时点格式应为 HH:MM';
    }
  }
  final exceptionsProblem = validateFreeText(
    draft.exceptions,
    maxLength: maxNoteLength,
    fieldName: '例外说明',
  );
  if (exceptionsProblem != null) {
    return exceptionsProblem;
  }
  final rule = draft.toDomain();
  // 2024 年起 48 个月：覆盖大小月、平年与闰年的 2 月。
  for (var i = 0; i < 48; i++) {
    final (year, month) = addMonths(LocalDate(2024, 1, 1), i);
    final statement = clampDay(year, month, draft.statementDay);
    try {
      dueDateForStatement(rule, statement);
    } on BillingRuleError {
      return '到期日须晚于账单日';
    }
  }
  return null;
}

/// 账期规则版本（当前工作空间）。
///
/// 保存规则 = 新版本：当前版本 `effective_to` 封口、`review_status = expired`（F-14 的数据侧）；
/// 同一主体的生效区间 `[effective_from, effective_to)` 不重叠（这里保证，触发器兜底）。
/// 第一个版本的 `effective_from` 为空（适用于全部历史）。按日期选版本用领域包 `selectRule`。
final class BillingRuleRepository {
  BillingRuleRepository(this._scope);

  final WorkspaceScope _scope;

  AppDatabase get _db => _scope.db;
  String get _ws => _scope.workspaceId;

  /// 某主体的全部版本，按版本号。
  Future<List<BillingRuleVersionRow>> versions(RuleSubject subject) =>
      (_db.select(_db.billingRuleVersions)
            ..where(
              (r) =>
                  r.workspaceId.equals(_ws) &
                  r.subjectKind.equals(subject.kind.code) &
                  r.subjectId.equals(subject.id),
            )
            ..orderBy([(r) => OrderingTerm.asc(r.version)]))
          .get();

  /// 本工作空间的全部版本（读模型一次取齐，按主体与版本号）。
  Future<List<BillingRuleVersionRow>> all() =>
      (_db.select(_db.billingRuleVersions)
            ..where((r) => r.workspaceId.equals(_ws))
            ..orderBy([
              (r) => OrderingTerm.asc(r.subjectId),
              (r) => OrderingTerm.asc(r.version),
            ]))
          .get();

  /// 在入账日 [on] 生效的版本（领域包 `selectRule`）；没有版本时为 null，版本重叠或都不生效时
  /// 抛领域包的 [BillingRuleError]。
  Future<BillingRuleVersionRow?> effectiveOn(
    RuleSubject subject,
    LocalDate on,
  ) async {
    final rows = await versions(subject);
    if (rows.isEmpty) {
      return null;
    }
    final selected = selectRule(rows.map(billingRuleFromRow).toList(), on);
    return rows.firstWhere((r) => r.id == selected.ruleId);
  }

  /// 保存一个新版本（来源：用户声明）。[effect] 决定新版本的生效区间：
  /// - 第一个版本：不论 [effect]，`effective_from` 为空（全部历史）；
  /// - [RuleEffectiveFrom]：日期必须晚于当前版本的 `effective_from`；当前版本封口到这一天；
  /// - [RuleCorrection]：新版本接替当前版本的区间，当前版本区间变为空。
  /// 返回新版本。
  Future<BillingRuleVersionRow> saveVersion(
    RuleSubject subject,
    BillingRuleDraft draft, {
    RuleEffect effect = const RuleCorrection(),
  }) async {
    final problem = billingRuleDraftProblem(draft);
    if (problem != null) {
      throw ValidationException('rule', problem);
    }
    try {
      return await _db.transaction(() async {
        await _requireSubject(subject);
        final existing = await versions(subject);
        final current = existing
            .where((r) => r.effectiveTo == null && !isEmptyRange(r))
            .toList();
        LocalDate? newFrom;
        if (current.isNotEmpty) {
          final open = current.single;
          final openFrom = parseOptionalDate(open.effectiveFrom);
          String sealTo;
          switch (effect) {
            case RuleEffectiveFrom(:final date):
              if (openFrom != null && date <= openFrom) {
                throw ValidationException(
                  'effectiveFrom',
                  '生效日须晚于当前版本的生效日（$openFrom）',
                );
              }
              newFrom = date;
              sealTo = date.toString();
            case RuleCorrection():
              newFrom = openFrom;
              sealTo = open.effectiveFrom ?? emptyRangeEnd;
          }
          await (_db.update(
                _db.billingRuleVersions,
              )..where((r) => r.workspaceId.equals(_ws) & r.id.equals(open.id)))
              .write(
                BillingRuleVersionsCompanion(
                  effectiveTo: Value(sealTo),
                  reviewStatus: Value(ReviewStatus.expired.code),
                ),
              );
        }
        final planned = <({LocalDate? from, LocalDate? to})>[
          for (final r in await versions(subject))
            (
              from: parseOptionalDate(r.effectiveFrom),
              to: parseOptionalDate(r.effectiveTo),
            ),
          (from: newFrom, to: null),
        ];
        if (rangesOverlap(planned)) {
          throw const ConflictException('规则版本的生效区间重叠');
        }
        final id = newUuidV4();
        final version = existing.isEmpty
            ? 1
            : existing.map((r) => r.version).reduce((a, b) => a > b ? a : b) +
                  1;
        final due = draft.due;
        await _db
            .into(_db.billingRuleVersions)
            .insert(
              BillingRuleVersionsCompanion.insert(
                id: id,
                workspaceId: _ws,
                subjectKind: subject.kind.code,
                subjectId: subject.id,
                statementDay: draft.statementDay,
                statementDayInclusive: Value(draft.statementDayInclusive),
                dueKind: due.kind.code,
                dueDay: Value(due.kind == DueKind.fixedDay ? due.day : null),
                dueMonthOffset: Value(
                  due.kind == DueKind.fixedDay ? due.monthOffset : 0,
                ),
                dueDays: Value(
                  due.kind == DueKind.daysAfterStatement ? due.days : null,
                ),
                dueDayKind: Value(due.dayKind.code),
                holidayRollover: Value(draft.holidayRollover.code),
                cutoffTime: Value(draft.cutoffTime),
                postingDelayMinDays: Value(draft.postingDelayMinDays),
                postingDelayMaxDays: Value(draft.postingDelayMaxDays),
                source: RuleSource.userDeclared.code,
                effectiveFrom: Value(newFrom?.toString()),
                version: version,
                reviewStatus: ReviewStatus.userDeclared.code,
                exceptions: Value(_optionalText(draft.exceptions)),
                createdAt: _scope.clock.nowText(),
              ),
            );
        return (await (_db.select(_db.billingRuleVersions)
              ..where((r) => r.workspaceId.equals(_ws) & r.id.equals(id)))
            .getSingle());
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  Future<void> _requireSubject(RuleSubject subject) async {
    final found = switch (subject.kind) {
      RuleSubjectKind.creditAccount =>
        await (_db.select(_db.creditAccounts)..where(
              (a) =>
                  a.workspaceId.equals(_ws) &
                  a.id.equals(subject.id) &
                  a.deletedAt.isNull(),
            ))
            .getSingleOrNull(),
      RuleSubjectKind.currencyAccount =>
        await (_db.select(_db.currencyAccounts)..where(
              (c) => c.workspaceId.equals(_ws) & c.id.equals(subject.id),
            ))
            .getSingleOrNull(),
    };
    if (found == null) {
      throw const NotFoundException('规则主体');
    }
  }
}

/// 空区间的结束日：`effective_from` 为空的版本被更正取代时，`effective_to` 写成最早的日期，
/// 区间 (−∞, 0001-01-01) 里没有任何有效日期。
const String emptyRangeEnd = '0001-01-01';

/// 版本的生效区间是否为空（被更正取代）。
bool isEmptyRange(BillingRuleVersionRow row) {
  final to = row.effectiveTo;
  return to != null && to.compareTo(row.effectiveFrom ?? emptyRangeEnd) <= 0;
}

/// 一组 `[from, to)` 区间（空 = 不限）在有效日期范围内是否有重叠；空区间不参与。
bool rangesOverlap(List<({LocalDate? from, LocalDate? to})> ranges) {
  final minDay = LocalDate(1, 1, 1).epochDay;
  final maxDayExclusive = LocalDate(9999, 12, 31).epochDay + 1;
  final spans = <(int, int)>[];
  for (final r in ranges) {
    final start = r.from?.epochDay ?? minDay;
    final end = r.to?.epochDay ?? maxDayExclusive;
    if (end > start) {
      spans.add((start, end));
    }
  }
  for (var i = 0; i < spans.length; i++) {
    for (var j = i + 1; j < spans.length; j++) {
      final (s1, e1) = spans[i];
      final (s2, e2) = spans[j];
      if ((s1 > s2 ? s1 : s2) < (e1 < e2 ? e1 : e2)) {
        return true;
      }
    }
  }
  return false;
}

String? _optionalText(String? text) {
  final value = text?.trim();
  return value == null || value.isEmpty ? null : value;
}
