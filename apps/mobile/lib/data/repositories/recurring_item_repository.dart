import 'package:cardflow_domain/cardflow_domain.dart'
    show LocalDate, Timestamp, addMonths, clampDay, daysInMonth;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../ids.dart';
import '../mapping/cash_mapping.dart';
import '../time/clock.dart';
import 'cash_account_repository.dart';
import 'cash_models.dart';
import 'cash_validation.dart';
import 'repository_errors.dart';
import 'workspace_scope.dart';

/// 周期规则（[recurringOccurrences] 的输入）。
@immutable
final class RecurringSchedule {
  const RecurringSchedule({
    required this.frequency,
    required this.anchorOn,
    required this.startOn,
    this.dayRule = DayRule.anchorDay,
    this.endOn,
  });

  factory RecurringSchedule.ofRow(RecurringItemRow row) => RecurringSchedule(
    frequency: RecurringFrequency.of(row.frequency),
    anchorOn: LocalDate.parse(row.anchorOn),
    startOn: LocalDate.parse(row.startOn),
    dayRule: DayRule.of(row.dayRule),
    endOn: row.endOn == null ? null : LocalDate.parse(row.endOn!),
  );

  final RecurringFrequency frequency;
  final LocalDate anchorOn;
  final LocalDate startOn;
  final DayRule dayRule;
  final LocalDate? endOn;

  @override
  bool operator ==(Object other) =>
      other is RecurringSchedule &&
      other.frequency == frequency &&
      other.anchorOn == anchorOn &&
      other.startOn == startOn &&
      other.dayRule == dayRule &&
      other.endOn == endOn;

  @override
  int get hashCode => Object.hash(frequency, anchorOn, startOn, dayRule, endOn);
}

/// 周期事项在 `[from, to]` 内的各期（原定日期，升序）：`anchor + k·周期`（k ≥ 0），且在
/// `[start_on, end_on]` 内。按月/按年：`anchor_day` 取锚定日的日号（小月截到月末，2 月 29 日在
/// 平年是 2 月 28 日），`month_end` 取每月最后一天；每周/每两周：每 7/14 天。
List<LocalDate> recurringOccurrences(
  RecurringSchedule schedule,
  LocalDate from,
  LocalDate to,
) {
  final low = schedule.startOn.laterOf(from);
  final end = schedule.endOn;
  final high = end != null && end < to ? end : to;
  if (high < low) {
    return const <LocalDate>[];
  }
  final anchor = schedule.anchorOn;
  final out = <LocalDate>[];
  switch (schedule.frequency) {
    case RecurringFrequency.weekly || RecurringFrequency.biweekly:
      final step = schedule.frequency == RecurringFrequency.weekly ? 7 : 14;
      final gap = low.differenceInDays(anchor);
      final k = gap <= 0 ? 0 : (gap + step - 1) ~/ step;
      for (var d = anchor.addDays(k * step); d <= high; d = d.addDays(step)) {
        out.add(d);
      }
    case RecurringFrequency.monthly || RecurringFrequency.yearly:
      final months = schedule.frequency == RecurringFrequency.monthly ? 1 : 12;
      final monthsToLow =
          (low.year - anchor.year) * 12 + (low.month - anchor.month);
      var k = monthsToLow <= months ? 0 : monthsToLow ~/ months - 1;
      while (true) {
        final (year, month) = addMonths(anchor, k * months);
        final day = schedule.dayRule == DayRule.monthEnd
            ? daysInMonth(year, month)
            : anchor.day;
        final d = clampDay(year, month, day);
        if (d > high) {
          break;
        }
        if (d >= low) {
          out.add(d);
        }
        k++;
      }
  }
  return out;
}

/// 新建或修改周期事项的输入（P-08「新增周期事项」）：金额填正数，正负由 [type] 决定。
@immutable
final class RecurringItemDraft {
  const RecurringItemDraft({
    required this.cashAccountId,
    required this.label,
    required this.type,
    required this.cls,
    required this.amountMinor,
    required this.frequency,
    required this.startOn,
    this.dayRule = DayRule.anchorDay,
    this.endOn,
  });

  final String cashAccountId;
  final String label;
  final CashPlanType type;

  /// 层级：确定或预计。
  final CashEventClass cls;

  /// 金额（正数）。
  final int amountMinor;
  final RecurringFrequency frequency;

  /// 第一期的日期（同时是锚定日）。
  final LocalDate startOn;
  final DayRule dayRule;
  final LocalDate? endOn;

  RecurringSchedule get schedule => RecurringSchedule(
    frequency: frequency,
    anchorOn: startOn,
    startOn: startOn,
    dayRule: dayRule,
    endOn: endOn,
  );
}

/// 周期事项的一期：展开后的事件（跳过的为 null）与该期的例外。
@immutable
final class RecurringOccurrence {
  const RecurringOccurrence({
    required this.key,
    required this.event,
    required this.override,
  });

  /// 原定日期（期键）。
  final LocalDate key;
  final CashEventRow? event;
  final RecurringOverrideRow? override;

  bool get skipped => override?.action == 'skip';

  bool get overridden => override?.action == 'override';

  bool get posted => event?.postingStatus == PostingStatus.posted.code;
}

/// 周期事项（当前工作空间）：增改、停用、单期覆盖/跳过/恢复，以及按需展开成现金事件。
///
/// 展开（[expandUntil]）：每个启用的周期事项（账户未停用）在 `[max(start_on, 该账户最新快照日 或 今天), 截止日]`
/// 内的每一期，没有未删除的事件、也没有被跳过时，写入一条事件（`occurrence_key` = 原定日期，有覆盖时
/// 用覆盖的金额/日期/时刻）。早于最新快照日的期已反映在余额里，不再展开。没有要补的期时不写库（读模型
/// 每次计算前都调用它，不会引起无谓的重算）。
final class RecurringItemRepository {
  RecurringItemRepository(this._scope);

  final WorkspaceScope _scope;

  AppDatabase get _db => _scope.db;
  String get _ws => _scope.workspaceId;

  LocalDate get _today => _scope.clock.today(cashTimeZone);

  /// 全部周期事项，按建立时间。
  Future<List<RecurringItemRow>> list() =>
      (_db.select(_db.recurringItems)
            ..where((r) => r.workspaceId.equals(_ws))
            ..orderBy([
              (r) => OrderingTerm.asc(r.createdAt),
              (r) => OrderingTerm.asc(r.rowId),
            ]))
          .get();

  /// 按 id 取。
  Future<RecurringItemRow?> byId(String id) =>
      (_db.select(_db.recurringItems)
            ..where((r) => r.workspaceId.equals(_ws) & r.id.equals(id)))
          .getSingleOrNull();

  /// 按 id 取，不存在抛 [NotFoundException]。
  Future<RecurringItemRow> require(String id) async =>
      await byId(id) ?? (throw const NotFoundException('周期事项'));

  /// 新建周期事项并展开到 `今天 + 180 天`（幂等：同一个 [id] 再次保存直接返回已建的）。
  ///
  /// 校验：名称必填（G2/G5）；层级确定或预计；金额为正、≤ 10^13；按周/两周不能选"月末"；结束日不早于
  /// 第一期；账户存在且未停用。
  Future<RecurringItemRow> create(
    RecurringItemDraft draft, {
    String? id,
  }) async {
    final label = _validate(draft);
    final itemId = id ?? newUuidV4();
    try {
      final row = await _db.transaction(() async {
        final existing = await byId(itemId);
        if (existing != null) {
          return existing;
        }
        await _activeAccount(draft.cashAccountId);
        final now = _scope.clock.nowText(cashTimeZone);
        await _db
            .into(_db.recurringItems)
            .insert(
              RecurringItemsCompanion.insert(
                id: itemId,
                workspaceId: _ws,
                cashAccountId: draft.cashAccountId,
                label: label,
                amountMinor: draft.type.sign * draft.amountMinor,
                cls: draft.cls.code,
                category: draft.type.category.code,
                frequency: draft.frequency.code,
                anchorOn: draft.startOn.toString(),
                dayRule: Value(draft.dayRule.code),
                startOn: draft.startOn.toString(),
                endOn: Value(draft.endOn?.toString()),
                createdAt: now,
                updatedAt: now,
              ),
            );
        return (await byId(itemId))!;
      });
      await expandUntil(_today.addDays(cashHorizonDays));
      return row;
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 修改周期事项（账户不可改）。今天之后、尚未发生、没有单期例外的各期跟着更新；改了周期规则
  /// （频率、第一期、日规则、结束日）时，今天之后尚未发生的各期（连同它们的覆盖与跳过）按新规则
  /// 重新展开。已发生的期与今天及以前的期不变。
  Future<void> update(String id, RecurringItemDraft draft) async {
    final label = _validate(draft);
    try {
      await _db.transaction(() async {
        final row = await require(id);
        if (row.cashAccountId != draft.cashAccountId) {
          throw const ConflictException('周期事项不能换账户；请停用后新建');
        }
        final scheduleChanged = RecurringSchedule.ofRow(row) != draft.schedule;
        final now = _scope.clock.nowText(cashTimeZone);
        final amount = draft.type.sign * draft.amountMinor;
        await (_db.update(
          _db.recurringItems,
        )..where((r) => r.workspaceId.equals(_ws) & r.id.equals(id))).write(
          RecurringItemsCompanion(
            label: Value(label),
            amountMinor: Value(amount),
            cls: Value(draft.cls.code),
            category: Value(draft.type.category.code),
            frequency: Value(draft.frequency.code),
            anchorOn: Value(draft.startOn.toString()),
            dayRule: Value(draft.dayRule.code),
            startOn: Value(draft.startOn.toString()),
            endOn: Value(draft.endOn?.toString()),
            rowVersion: Value(row.rowVersion + 1),
            updatedAt: Value(now),
          ),
        );
        final future = await _futurePlannedOccurrences(id);
        final overrides = {
          for (final o in await overridesOf(id)) o.occurrenceKey: o,
        };
        if (scheduleChanged) {
          for (final event in future) {
            await _tombstone(event, now);
          }
          final today = _today.toString();
          await (_db.delete(_db.recurringOverrides)..where(
                (o) =>
                    o.workspaceId.equals(_ws) &
                    o.recurringItemId.equals(id) &
                    o.occurrenceKey.isBiggerThanValue(today),
              ))
              .go();
        } else {
          for (final event in future) {
            final override = overrides[event.occurrenceKey];
            final keepAmount = override?.amountMinor != null;
            await (_db.update(_db.cashEvents)..where(
                  (e) => e.workspaceId.equals(_ws) & e.id.equals(event.id),
                ))
                .write(
                  CashEventsCompanion(
                    label: Value(label),
                    cls: Value(draft.cls.code),
                    category: Value(draft.type.category.code),
                    amountMinor: keepAmount
                        ? const Value.absent()
                        : Value(amount),
                    rowVersion: Value(event.rowVersion + 1),
                    updatedAt: Value(now),
                  ),
                );
          }
        }
      });
      await expandUntil(_today.addDays(cashHorizonDays));
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 停用（今天之后尚未发生的各期作废）或重新启用（重新展开）。
  Future<void> setActive(String id, bool active) async {
    await _db.transaction(() async {
      final row = await require(id);
      if (row.active == active) {
        return;
      }
      final now = _scope.clock.nowText(cashTimeZone);
      await (_db.update(
        _db.recurringItems,
      )..where((r) => r.workspaceId.equals(_ws) & r.id.equals(id))).write(
        RecurringItemsCompanion(
          active: Value(active),
          rowVersion: Value(row.rowVersion + 1),
          updatedAt: Value(now),
        ),
      );
      if (!active) {
        for (final event in await _futurePlannedOccurrences(id)) {
          await _tombstone(event, now);
        }
      }
    });
    if (active) {
      await expandUntil(_today.addDays(cashHorizonDays));
    }
  }

  /// 某周期事项的单期例外。
  Future<List<RecurringOverrideRow>> overridesOf(String itemId) =>
      (_db.select(_db.recurringOverrides)
            ..where(
              (o) =>
                  o.workspaceId.equals(_ws) & o.recurringItemId.equals(itemId),
            )
            ..orderBy([(o) => OrderingTerm.asc(o.occurrenceKey)]))
          .get();

  /// 某周期事项已展开的各期（含被跳过的），按原定日期。
  Future<List<RecurringOccurrence>> occurrences(String itemId) async {
    await require(itemId);
    final events =
        await (_db.select(_db.cashEvents)..where(
              (e) =>
                  e.workspaceId.equals(_ws) &
                  e.recurringItemId.equals(itemId) &
                  e.deletedAt.isNull(),
            ))
            .get();
    final byKey = {for (final e in events) e.occurrenceKey!: e};
    final overrides = {
      for (final o in await overridesOf(itemId)) o.occurrenceKey: o,
    };
    final keys = <String>{...byKey.keys, ...overrides.keys}.toList()..sort();
    return <RecurringOccurrence>[
      for (final key in keys)
        RecurringOccurrence(
          key: LocalDate.parse(key),
          event: byKey[key],
          override: overrides[key],
        ),
    ];
  }

  /// 跳过一期（不影响他期，R-CASH-02）：记下例外，作废该期尚未发生的事件。已发生的期不能跳过。
  Future<void> skip(String itemId, LocalDate key) async {
    try {
      await _db.transaction(() async {
        final item = await require(itemId);
        _checkKey(item, key);
        final event = await _occurrenceEvent(itemId, key);
        if (event != null && event.postingStatus == PostingStatus.posted.code) {
          throw const ConflictException('这一期已发生，不能跳过');
        }
        final now = _scope.clock.nowText(cashTimeZone);
        await _upsertOverride(
          RecurringOverridesCompanion.insert(
            workspaceId: _ws,
            recurringItemId: itemId,
            occurrenceKey: key.toString(),
            action: 'skip',
            createdAt: now,
            updatedAt: now,
          ),
        );
        if (event != null) {
          await _tombstone(event, now);
        }
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 覆盖一期的金额（正数）和/或日期、时刻（不影响他期，R-CASH-02）。已发生的期不能覆盖。
  Future<void> overrideOccurrence(
    String itemId,
    LocalDate key, {
    int? amountMinor,
    LocalDate? on,
    Timestamp? at,
  }) async {
    if (amountMinor == null && on == null && at == null) {
      throw const ValidationException('override', '请填写这一期的新金额或新日期');
    }
    if (amountMinor != null) {
      checkCashMagnitude(amountMinor);
    }
    final newOn = on ?? (at == null ? null : key);
    if (newOn != null) {
      checkCashDate('on', newOn);
    }
    final atText = newOn == null ? null : cashAtText(at, newOn);
    try {
      await _db.transaction(() async {
        final item = await require(itemId);
        _checkKey(item, key);
        final event = await _occurrenceEvent(itemId, key);
        if (event != null && event.postingStatus == PostingStatus.posted.code) {
          throw const ConflictException('这一期已发生，不能覆盖');
        }
        final sign = item.amountMinor < 0 ? -1 : 1;
        final amount = amountMinor == null ? null : sign * amountMinor;
        final now = _scope.clock.nowText(cashTimeZone);
        await _upsertOverride(
          RecurringOverridesCompanion.insert(
            workspaceId: _ws,
            recurringItemId: itemId,
            occurrenceKey: key.toString(),
            action: 'override',
            amountMinor: Value(amount),
            eventOn: Value(newOn?.toString()),
            eventAt: Value(atText),
            createdAt: now,
            updatedAt: now,
          ),
        );
        final values = (
          on: newOn ?? key,
          at: atText,
          amount: amount ?? item.amountMinor,
        );
        if (event != null) {
          await (_db.update(_db.cashEvents)..where(
                (e) => e.workspaceId.equals(_ws) & e.id.equals(event.id),
              ))
              .write(
                CashEventsCompanion(
                  eventOn: Value(values.on.toString()),
                  eventAt: Value(values.at),
                  amountMinor: Value(values.amount),
                  rowVersion: Value(event.rowVersion + 1),
                  updatedAt: Value(now),
                ),
              );
        } else {
          await _insertOccurrence(
            item,
            key,
            on: values.on,
            at: values.at,
            amount: values.amount,
            now: now,
          );
        }
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 恢复一期（去掉覆盖或跳过，回到周期规则的金额与日期）。
  Future<void> restore(String itemId, LocalDate key) async {
    try {
      await _db.transaction(() async {
        final item = await require(itemId);
        final event = await _occurrenceEvent(itemId, key);
        if (event != null && event.postingStatus == PostingStatus.posted.code) {
          throw const ConflictException('这一期已发生，不能恢复');
        }
        await (_db.delete(_db.recurringOverrides)..where(
              (o) =>
                  o.workspaceId.equals(_ws) &
                  o.recurringItemId.equals(itemId) &
                  o.occurrenceKey.equals(key.toString()),
            ))
            .go();
        final now = _scope.clock.nowText(cashTimeZone);
        if (event != null) {
          await (_db.update(_db.cashEvents)..where(
                (e) => e.workspaceId.equals(_ws) & e.id.equals(event.id),
              ))
              .write(
                CashEventsCompanion(
                  eventOn: Value(key.toString()),
                  eventAt: const Value(null),
                  amountMinor: Value(item.amountMinor),
                  rowVersion: Value(event.rowVersion + 1),
                  updatedAt: Value(now),
                ),
              );
        } else if (item.active) {
          await _insertOccurrence(
            item,
            key,
            on: key,
            at: null,
            amount: item.amountMinor,
            now: now,
          );
        }
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 把启用的周期事项展开到 [to]（含）。返回新写入的事件数；没有要补的期时不写库。
  Future<int> expandUntil(LocalDate to) => _db.transaction(() async {
    final items = (await list()).where((i) => i.active).toList();
    if (items.isEmpty) {
      return 0;
    }
    final accounts = {
      for (final a in await CashAccountRepository(_scope).list()) a.id: a,
    };
    final latest = await CashSnapshotRepository(_scope).latestByAccount();
    final existing = <String>{
      for (final e
          in await (_db.select(_db.cashEvents)..where(
                (e) =>
                    e.workspaceId.equals(_ws) &
                    e.recurringItemId.isNotNull() &
                    e.deletedAt.isNull(),
              ))
              .get())
        '${e.recurringItemId}/${e.occurrenceKey}',
    };
    final overrides = <String, RecurringOverrideRow>{
      for (final o in await (_db.select(
        _db.recurringOverrides,
      )..where((o) => o.workspaceId.equals(_ws))).get())
        '${o.recurringItemId}/${o.occurrenceKey}': o,
    };
    final today = _today;
    final pending = <(RecurringItemRow, LocalDate, RecurringOverrideRow?)>[];
    for (final item in items) {
      final account = accounts[item.cashAccountId];
      if (account == null || account.status != CashAccountStatus.active.code) {
        continue;
      }
      final snapshot = latest[item.cashAccountId];
      final from = snapshot == null
          ? today
          : LocalDate.parse(snapshot.balanceAsOf);
      for (final key in recurringOccurrences(
        RecurringSchedule.ofRow(item),
        from,
        to,
      )) {
        final id = '${item.id}/$key';
        final override = overrides[id];
        if (existing.contains(id) || override?.action == 'skip') {
          continue;
        }
        pending.add((item, key, override));
      }
    }
    if (pending.isEmpty) {
      return 0;
    }
    final now = _scope.clock.nowText(cashTimeZone);
    for (final (item, key, override) in pending) {
      await _insertOccurrence(
        item,
        key,
        on: override?.eventOn == null
            ? key
            : LocalDate.parse(override!.eventOn!),
        at: override?.eventAt,
        amount: override?.amountMinor ?? item.amountMinor,
        now: now,
      );
    }
    return pending.length;
  });

  Future<void> _insertOccurrence(
    RecurringItemRow item,
    LocalDate key, {
    required LocalDate on,
    required String? at,
    required int amount,
    required String now,
  }) => _db
      .into(_db.cashEvents)
      .insert(
        CashEventsCompanion.insert(
          id: newUuidV4(),
          workspaceId: _ws,
          cashAccountId: item.cashAccountId,
          eventOn: on.toString(),
          eventAt: Value(at),
          amountMinor: amount,
          cls: item.cls,
          category: item.category,
          label: Value(item.label),
          recurringItemId: Value(item.id),
          occurrenceKey: Value(key.toString()),
          createdAt: now,
          updatedAt: now,
        ),
        mode: InsertMode.insertOrIgnore,
      );

  Future<void> _upsertOverride(RecurringOverridesCompanion row) => _db
      .into(_db.recurringOverrides)
      .insert(
        row,
        onConflict: DoUpdate(
          (_) => RecurringOverridesCompanion(
            action: row.action,
            amountMinor: row.amountMinor.present
                ? row.amountMinor
                : const Value(null),
            eventOn: row.eventOn.present ? row.eventOn : const Value(null),
            eventAt: row.eventAt.present ? row.eventAt : const Value(null),
            updatedAt: row.updatedAt,
          ),
          target: <Column<Object>>[
            _db.recurringOverrides.recurringItemId,
            _db.recurringOverrides.occurrenceKey,
          ],
        ),
      );

  Future<CashEventRow?> _occurrenceEvent(String itemId, LocalDate key) =>
      (_db.select(_db.cashEvents)..where(
            (e) =>
                e.workspaceId.equals(_ws) &
                e.recurringItemId.equals(itemId) &
                e.occurrenceKey.equals(key.toString()) &
                e.deletedAt.isNull(),
          ))
          .getSingleOrNull();

  /// 今天之后、尚未发生的各期事件。
  Future<List<CashEventRow>> _futurePlannedOccurrences(String itemId) =>
      (_db.select(_db.cashEvents)..where(
            (e) =>
                e.workspaceId.equals(_ws) &
                e.recurringItemId.equals(itemId) &
                e.deletedAt.isNull() &
                e.postingStatus.equals(PostingStatus.planned.code) &
                e.eventOn.isBiggerThanValue(_today.toString()),
          ))
          .get();

  Future<void> _tombstone(CashEventRow event, String now) =>
      (_db.update(
        _db.cashEvents,
      )..where((e) => e.workspaceId.equals(_ws) & e.id.equals(event.id))).write(
        CashEventsCompanion(
          deletedAt: Value(now),
          rowVersion: Value(event.rowVersion + 1),
          updatedAt: Value(now),
        ),
      );

  Future<void> _activeAccount(String id) async {
    final account = await CashAccountRepository(_scope).require(id);
    if (account.status != CashAccountStatus.active.code) {
      throw const ConflictException('现金账户已停用');
    }
  }

  /// 期键必须是周期规则里的一期。
  void _checkKey(RecurringItemRow item, LocalDate key) {
    final dates = recurringOccurrences(RecurringSchedule.ofRow(item), key, key);
    if (dates.isEmpty) {
      throw const ValidationException('occurrence', '这一天不是该周期事项的一期');
    }
  }

  String _validate(RecurringItemDraft draft) {
    final label = requiredCashLabel(draft.label);
    checkUserCashClass(draft.cls);
    checkCashMagnitude(draft.amountMinor);
    checkCashDate('startOn', draft.startOn);
    final end = draft.endOn;
    if (end != null) {
      checkCashDate('endOn', end);
      if (end < draft.startOn) {
        throw const ValidationException('endOn', '结束日不能早于第一期');
      }
    }
    if (draft.dayRule == DayRule.monthEnd && !draft.frequency.allowsMonthEnd) {
      throw const ValidationException('dayRule', '按周的周期事项不能选"月末"');
    }
    return label;
  }
}
