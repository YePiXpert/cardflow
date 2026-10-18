import 'package:cardflow_domain/cardflow_domain.dart'
    show LocalDate, Timestamp, minorDigits;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../ids.dart';
import '../mapping/cash_mapping.dart';
import '../time/business_tz.dart';
import '../time/clock.dart';
import '../validation/text_rules.dart';
import 'cash_models.dart';
import 'cash_validation.dart';
import 'credit_pool_repository.dart' show maxAmountMinor;
import 'models.dart';
import 'repository_errors.dart';
import 'workspace_scope.dart';

/// 新建现金账户的输入（P-08「添加账户」）。
@immutable
final class NewCashAccount {
  const NewCashAccount({
    required this.id,
    required this.name,
    required this.kind,
    this.currency = 'CNY',
    this.usableForRepayment,
    this.availableFrom,
    this.reserveFloorMinor = 0,
  });

  /// 预先生成的 id（重试保存时沿用，不会重复建账户）。
  final String id;
  final String name;
  final CashAccountKind kind;
  final String currency;

  /// 空 = 按种类的默认值（理财/受限默认不可用于还款）。
  final bool? usableForRepayment;

  /// 理财/受限资金可用于还款的起始日。
  final LocalDate? availableFrom;

  /// 最低储备（≥0）。
  final int reserveFloorMinor;
}

/// 现金账户（当前工作空间）。
final class CashAccountRepository {
  CashAccountRepository(this._scope);

  final WorkspaceScope _scope;

  AppDatabase get _db => _scope.db;
  String get _ws => _scope.workspaceId;

  /// 未删除的现金账户（含已停用），按建立时间。
  Future<List<CashAccountRow>> list() =>
      (_db.select(_db.cashAccounts)
            ..where((a) => a.workspaceId.equals(_ws) & a.deletedAt.isNull())
            ..orderBy([
              (a) => OrderingTerm.asc(a.createdAt),
              (a) => OrderingTerm.asc(a.rowId),
            ]))
          .get();

  /// 按 id 取（不属于当前工作空间或已删除时为 null）。
  Future<CashAccountRow?> byId(String id) =>
      (_db.select(_db.cashAccounts)..where(
            (a) =>
                a.workspaceId.equals(_ws) &
                a.id.equals(id) &
                a.deletedAt.isNull(),
          ))
          .getSingleOrNull();

  /// 按 id 取，不存在抛 [NotFoundException]。
  Future<CashAccountRow> require(String id) async =>
      await byId(id) ?? (throw const NotFoundException('现金账户'));

  /// 新建现金账户（幂等：同一个 id 再次保存直接返回已建的）。
  ///
  /// 校验：名称 G2/G5 且同一空间里不重名；币种为 13 种之一（G4）；储备 ≥0（G1）；受限资金不能直接
  /// 标为可用于还款（只能设可用日期）。
  Future<CashAccountRow> create(NewCashAccount draft) async {
    final name = draft.name.trim();
    _check('name', validateFreeText(name, required: true, fieldName: '账户名称'));
    if (!minorDigits.containsKey(draft.currency)) {
      throw const ValidationException('currency', '不支持的币种');
    }
    _checkReserve(draft.reserveFloorMinor);
    final usable = draft.usableForRepayment ?? draft.kind.usableByDefault;
    _checkUsable(draft.kind, usable);
    _checkAvailableFrom(draft.availableFrom);
    try {
      return await _db.transaction(() async {
        final existing = await byId(draft.id);
        if (existing != null) {
          return existing;
        }
        await _checkNameFree(name);
        final now = _scope.clock.nowText(cashTimeZone);
        await _db
            .into(_db.cashAccounts)
            .insert(
              CashAccountsCompanion.insert(
                id: draft.id,
                workspaceId: _ws,
                name: name,
                currency: draft.currency,
                kind: draft.kind.code,
                usableForRepayment: Value(usable),
                availableFrom: Value(draft.availableFrom?.toString()),
                reserveFloorMinor: Value(draft.reserveFloorMinor),
                createdAt: now,
                updatedAt: now,
              ),
            );
        return (await byId(draft.id))!;
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 修改账户：名称、种类、可用于还款、可用日期（[clearAvailableFrom] 清除）、储备。币种不可改。
  Future<void> update(
    String id, {
    String? name,
    CashAccountKind? kind,
    bool? usableForRepayment,
    LocalDate? availableFrom,
    bool clearAvailableFrom = false,
    int? reserveFloorMinor,
  }) async {
    final trimmed = name?.trim();
    if (trimmed != null) {
      _check(
        'name',
        validateFreeText(trimmed, required: true, fieldName: '账户名称'),
      );
    }
    if (reserveFloorMinor != null) {
      _checkReserve(reserveFloorMinor);
    }
    _checkAvailableFrom(availableFrom);
    try {
      await _db.transaction(() async {
        final row = await require(id);
        final newKind = kind ?? CashAccountKind.of(row.kind);
        final usable = usableForRepayment ?? row.usableForRepayment;
        _checkUsable(newKind, usable);
        if (trimmed != null && trimmed != row.name) {
          await _checkNameFree(trimmed);
        }
        await (_db.update(
          _db.cashAccounts,
        )..where((a) => a.workspaceId.equals(_ws) & a.id.equals(id))).write(
          CashAccountsCompanion(
            name: trimmed == null ? const Value.absent() : Value(trimmed),
            kind: kind == null ? const Value.absent() : Value(kind.code),
            usableForRepayment: Value(usable),
            availableFrom: clearAvailableFrom
                ? const Value(null)
                : availableFrom == null
                ? const Value.absent()
                : Value(availableFrom.toString()),
            reserveFloorMinor: reserveFloorMinor == null
                ? const Value.absent()
                : Value(reserveFloorMinor),
            rowVersion: Value(row.rowVersion + 1),
            updatedAt: Value(_scope.clock.nowText(cashTimeZone)),
          ),
        );
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 停用（不再进入资金日历与可用现金，历史保留）或恢复使用。
  Future<void> setStatus(String id, CashAccountStatus status) =>
      _db.transaction(() async {
        final row = await require(id);
        if (row.status == status.code) {
          return;
        }
        await (_db.update(
          _db.cashAccounts,
        )..where((a) => a.workspaceId.equals(_ws) & a.id.equals(id))).write(
          CashAccountsCompanion(
            status: Value(status.code),
            rowVersion: Value(row.rowVersion + 1),
            updatedAt: Value(_scope.clock.nowText(cashTimeZone)),
          ),
        );
      });

  Future<void> _checkNameFree(String name) async {
    final same =
        await (_db.select(_db.cashAccounts)..where(
              (a) =>
                  a.workspaceId.equals(_ws) &
                  a.name.equals(name) &
                  a.deletedAt.isNull(),
            ))
            .get();
    if (same.isNotEmpty) {
      throw const ConflictException('已有同名的现金账户');
    }
  }
}

void _checkReserve(int value) {
  if (value < 0 || value > maxAmountMinor) {
    throw const ValidationException('reserveFloor', '储备须为不小于 0 的金额');
  }
}

void _checkUsable(CashAccountKind kind, bool usable) {
  if (kind == CashAccountKind.restricted && usable) {
    throw const ValidationException(
      'usableForRepayment',
      '受限资金不能直接用于还款；可以设置可用日期',
    );
  }
}

void _checkAvailableFrom(LocalDate? date) {
  if (date != null && !isSupportedCashDate(date)) {
    throw const ValidationException('availableFrom', '日期超出支持的范围');
  }
}

void _check(String field, String? problem) {
  if (problem != null) {
    throw ValidationException(field, problem);
  }
}

/// 记录一次余额快照的输入（P-08「记录新快照」）。
@immutable
final class CashSnapshotDraft {
  const CashSnapshotDraft({
    required this.cashAccountId,
    required this.balanceMinor,
    required this.balanceAsOf,
    required this.observedAt,
    this.source = SnapshotSource.bankApp,
    this.confirmationLevel = ConfirmationLevel.userConfirmed,
    this.sameDayAnswers = const <String, bool>{},
  });

  final String cashAccountId;

  /// 余额（可为负：透支）。
  final int balanceMinor;

  /// 余额对应的日期（不晚于今天）。
  final LocalDate balanceAsOf;

  /// 实际时点（G3：不晚于现在；按现金时区的日期不早于 [balanceAsOf]）。缺实际时点不可存。
  final Timestamp observedAt;

  final SnapshotSource source;
  final ConfirmationLevel confirmationLevel;

  /// 快照日当天（及以前）已登记的事件 → "余额是否已包含它"的回答。快照日当天的每一笔未删除事件
  /// 都必须回答（R-CASH-06：逐条询问）；回答"已包含"的写进 `snapshot_included_events`。
  final Map<String, bool> sameDayAnswers;

  /// 回答"已包含"的事件。
  Set<String> get includedEventIds => <String>{
    for (final e in sameDayAnswers.entries)
      if (e.value) e.key,
  };
}

/// 现金余额快照（当前工作空间）。只追加，不修改。
final class CashSnapshotRepository {
  CashSnapshotRepository(this._scope);

  final WorkspaceScope _scope;

  AppDatabase get _db => _scope.db;
  String get _ws => _scope.workspaceId;

  /// 本工作空间的全部快照。
  Future<List<CashSnapshotRow>> all() => (_db.select(
    _db.cashBalanceSnapshots,
  )..where((s) => s.workspaceId.equals(_ws))).get();

  /// 某账户的快照历史，最新在前（[sortCashSnapshotsNewestFirst]）。
  Future<List<CashSnapshotRow>> history(String cashAccountId) async =>
      sortCashSnapshotsNewestFirst(
        await (_db.select(_db.cashBalanceSnapshots)..where(
              (s) =>
                  s.workspaceId.equals(_ws) &
                  s.cashAccountId.equals(cashAccountId),
            ))
            .get(),
      );

  /// 每个账户的最新快照。
  Future<Map<String, CashSnapshotRow>> latestByAccount() async {
    final latest = <String, CashSnapshotRow>{};
    for (final row in sortCashSnapshotsNewestFirst(await all())) {
      latest.putIfAbsent(row.cashAccountId, () => row);
    }
    return latest;
  }

  /// 每个快照已包含的事件 id。
  Future<Map<String, Set<String>>> includedEventIds() async {
    final rows = await (_db.select(
      _db.snapshotIncludedEvents,
    )..where((i) => i.workspaceId.equals(_ws))).get();
    final out = <String, Set<String>>{};
    for (final row in rows) {
      out.putIfAbsent(row.snapshotId, () => <String>{}).add(row.cashEventId);
    }
    return out;
  }

  /// 某快照已包含的事件 id。
  Future<Set<String>> includedIn(String snapshotId) async => <String>{
    for (final row
        in await (_db.select(_db.snapshotIncludedEvents)..where(
              (i) =>
                  i.workspaceId.equals(_ws) & i.snapshotId.equals(snapshotId),
            ))
            .get())
      row.cashEventId,
  };

  /// 某账户在 [on] 这一天的未删除事件（记录快照时逐条询问"余额是否已包含"），按时刻与登记顺序。
  Future<List<CashEventRow>> sameDayEvents(
    String cashAccountId,
    LocalDate on,
  ) async {
    final rows =
        await (_db.select(_db.cashEvents)
              ..where(
                (e) =>
                    e.workspaceId.equals(_ws) &
                    e.cashAccountId.equals(cashAccountId) &
                    e.eventOn.equals(on.toString()) &
                    e.deletedAt.isNull(),
              )
              ..orderBy([(e) => OrderingTerm.asc(e.rowId)]))
            .get();
    return rows;
  }

  /// 记录一次快照与它已包含的事件（一个事务）。
  ///
  /// 校验（P-08、G1/G3、R-CASH-06）：余额 |v| ≤ 10^13；余额日期不晚于今天；实际时点不晚于现在、
  /// 按现金时区的日期不早于余额日期；当天的每一笔事件都已回答"是否已包含"；包含的只能是本账户、
  /// 快照日当天及以前的未删除事件（规则协议 v1 的交叉规则 R3E-14，触发器兜底）。
  Future<CashSnapshotRow> record(CashSnapshotDraft draft) async {
    if (draft.balanceMinor.abs() > maxAmountMinor) {
      throw const ValidationException('balance', '金额超出范围');
    }
    final today = _scope.clock.today(cashTimeZone);
    if (draft.balanceAsOf > today) {
      throw const ValidationException('balanceAsOf', '余额日期不能晚于今天');
    }
    if (!isSupportedCashDate(draft.balanceAsOf)) {
      throw const ValidationException('balanceAsOf', '日期超出支持的范围');
    }
    final nowMicros = _scope.clock.now().microsecondsSinceEpoch;
    if (draft.observedAt.utcMicros > nowMicros) {
      throw const ValidationException('observedAt', '实际时点不能晚于现在');
    }
    if (businessDateOf(draft.observedAt, cashTimeZone) < draft.balanceAsOf) {
      throw const ValidationException('observedAt', '实际时点不能早于余额日期');
    }
    try {
      return await _db.transaction(() async {
        final account = await CashAccountRepository(_scope)
            .require(draft.cashAccountId);
        final sameDay = await sameDayEvents(account.id, draft.balanceAsOf);
        final unanswered = sameDay.where(
          (e) => !draft.sameDayAnswers.containsKey(e.id),
        );
        if (unanswered.isNotEmpty) {
          throw const ValidationException('includes', '请逐条确认当天的收支是否已包含在余额里');
        }
        for (final eventId in draft.includedEventIds) {
          final event =
              await (_db.select(_db.cashEvents)..where(
                    (e) =>
                        e.workspaceId.equals(_ws) &
                        e.id.equals(eventId) &
                        e.deletedAt.isNull(),
                  ))
                  .getSingleOrNull();
          if (event == null || event.cashAccountId != account.id) {
            throw const ValidationException('includes', '只能包含本账户已登记的收支');
          }
          if (LocalDate.parse(event.eventOn) > draft.balanceAsOf) {
            throw const ValidationException('includes', '余额只能包含快照日当天及以前的收支');
          }
        }
        final id = newUuidV4();
        await _db
            .into(_db.cashBalanceSnapshots)
            .insert(
              CashBalanceSnapshotsCompanion.insert(
                id: id,
                workspaceId: _ws,
                cashAccountId: account.id,
                balanceMinor: draft.balanceMinor,
                balanceAsOf: draft.balanceAsOf.toString(),
                observedAt: draft.observedAt.text,
                sourceKind: draft.source.code,
                confirmationLevel: draft.confirmationLevel.code,
                recordedAt: _scope.clock.nowText(cashTimeZone),
              ),
            );
        for (final eventId in draft.includedEventIds) {
          await _db
              .into(_db.snapshotIncludedEvents)
              .insert(
                SnapshotIncludedEventsCompanion.insert(
                  workspaceId: _ws,
                  cashAccountId: account.id,
                  snapshotId: id,
                  cashEventId: eventId,
                ),
              );
        }
        return (await (_db.select(_db.cashBalanceSnapshots)
              ..where((s) => s.workspaceId.equals(_ws) & s.id.equals(id)))
            .getSingle());
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }
}

/// 快照按"最新在前"排序：余额日期，再按实际时点的绝对时刻，再按记录时点，再按 id（确定的顺序）。
List<CashSnapshotRow> sortCashSnapshotsNewestFirst(
  Iterable<CashSnapshotRow> rows,
) {
  final list = rows.toList();
  int micros(String text) => Timestamp.parse(text).utcMicros;
  list.sort((a, b) {
    final byDate = b.balanceAsOf.compareTo(a.balanceAsOf);
    if (byDate != 0) {
      return byDate;
    }
    final byObserved = micros(b.observedAt).compareTo(micros(a.observedAt));
    if (byObserved != 0) {
      return byObserved;
    }
    final byRecorded = micros(b.recordedAt).compareTo(micros(a.recordedAt));
    return byRecorded != 0 ? byRecorded : b.id.compareTo(a.id);
  });
  return list;
}
