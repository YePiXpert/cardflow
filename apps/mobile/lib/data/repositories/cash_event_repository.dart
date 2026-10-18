import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate, Timestamp;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../ids.dart';
import '../mapping/cash_mapping.dart';
import '../time/business_tz.dart';
import '../time/clock.dart';
import 'cash_account_repository.dart';
import 'cash_models.dart';
import 'cash_validation.dart';
import 'repository_errors.dart';
import 'workspace_scope.dart';

/// 一笔收支计划的输入（P-08「新增收支」）：金额填正数，正负由 [type] 决定。
@immutable
final class CashEventDraft {
  const CashEventDraft({
    required this.cashAccountId,
    required this.type,
    required this.cls,
    required this.on,
    required this.amountMinor,
    this.at,
    this.label,
  });

  final String cashAccountId;
  final CashPlanType type;

  /// 层级：只能是确定或预计（R-CASH-03：收支必须选层级，没有概率字段）。
  final CashEventClass cls;

  final LocalDate on;

  /// 金额（正数，最小单位）。
  final int amountMinor;

  /// 精确时刻（可选；按现金时区写入，日期必须等于 [on]）。
  final Timestamp? at;

  final String? label;
}

/// 一笔调拨的输入（P-08「新增调拨」）：两端账户不同、币种相同，到账不早于转出。
@immutable
final class TransferDraft {
  const TransferDraft({
    required this.fromAccountId,
    required this.toAccountId,
    required this.amountMinor,
    required this.outOn,
    required this.inOn,
    required this.cls,
    this.outAt,
    this.inAt,
    this.label,
  });

  final String fromAccountId;
  final String toAccountId;

  /// 金额（正数）。
  final int amountMinor;
  final LocalDate outOn;
  final LocalDate inOn;
  final Timestamp? outAt;
  final Timestamp? inAt;
  final CashEventClass cls;
  final String? label;
}

/// 一笔调拨（两条事件）。
@immutable
final class TransferView {
  const TransferView({required this.out, required this.into});

  final CashEventRow out;
  final CashEventRow into;

  String get groupId => out.transferGroupId!;
}

/// 现金事件（当前工作空间）：收支计划、确认发生、删除、调拨，以及给 I-1c 的还款扣款接口。
///
/// 周期事项展开的事件由 `RecurringItemRepository` 管理（单期的修改走覆盖/跳过）。
final class CashEventRepository {
  CashEventRepository(this._scope);

  final WorkspaceScope _scope;

  AppDatabase get _db => _scope.db;
  String get _ws => _scope.workspaceId;

  LocalDate get _today => _scope.clock.today(cashTimeZone);

  /// 未删除的事件（可只取某账户、某日期区间的），按日期与登记顺序。
  Future<List<CashEventRow>> list({
    String? cashAccountId,
    LocalDate? from,
    LocalDate? to,
  }) =>
      (_db.select(_db.cashEvents)
            ..where(
              (e) =>
                  e.workspaceId.equals(_ws) &
                  e.deletedAt.isNull() &
                  (cashAccountId == null
                      ? const Constant(true)
                      : e.cashAccountId.equals(cashAccountId)) &
                  (from == null
                      ? const Constant(true)
                      : e.eventOn.isBiggerOrEqualValue(from.toString())) &
                  (to == null
                      ? const Constant(true)
                      : e.eventOn.isSmallerOrEqualValue(to.toString())),
            )
            ..orderBy([
              (e) => OrderingTerm.asc(e.eventOn),
              (e) => OrderingTerm.asc(e.rowId),
            ]))
          .get();

  /// 按 id 取未删除的事件。
  Future<CashEventRow?> byId(String id) =>
      (_db.select(_db.cashEvents)..where(
            (e) =>
                e.workspaceId.equals(_ws) &
                e.id.equals(id) &
                e.deletedAt.isNull(),
          ))
          .getSingleOrNull();

  /// 按 id 取，不存在抛 [NotFoundException]。
  Future<CashEventRow> require(String id) async =>
      await byId(id) ?? (throw const NotFoundException('收支'));

  /// 新增一笔收支（幂等：同一个 [id] 再次保存直接返回已建的）。
  ///
  /// 校验（P-08、G1/G4/G5）：账户存在且未停用；层级只能是确定或预计；金额为正、≤ 10^13；日期在支持
  /// 范围内；时刻按现金时区的日期等于日期；标签 G2/G5。
  Future<CashEventRow> create(CashEventDraft draft, {String? id}) async {
    final label = optionalCashLabel(draft.label);
    checkUserCashClass(draft.cls);
    checkCashMagnitude(draft.amountMinor);
    checkCashDate('on', draft.on);
    final at = cashAtText(draft.at, draft.on, field: 'at');
    final eventId = id ?? newUuidV4();
    try {
      return await _db.transaction(() async {
        final existing = await byId(eventId);
        if (existing != null) {
          return existing;
        }
        await _activeAccount(draft.cashAccountId);
        final now = _scope.clock.nowText(cashTimeZone);
        await _db
            .into(_db.cashEvents)
            .insert(
              CashEventsCompanion.insert(
                id: eventId,
                workspaceId: _ws,
                cashAccountId: draft.cashAccountId,
                eventOn: draft.on.toString(),
                eventAt: Value(at),
                amountMinor: draft.type.sign * draft.amountMinor,
                cls: draft.cls.code,
                category: draft.type.category.code,
                label: Value(label),
                createdAt: now,
                updatedAt: now,
              ),
            );
        return (await byId(eventId))!;
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 修改一笔收支（日期、时刻、金额、层级、标签）。调拨与周期事项的单期不在这里改。
  Future<void> update(
    String id, {
    LocalDate? on,
    Timestamp? at,
    bool clearAt = false,
    int? amountMinor,
    CashEventClass? cls,
    String? label,
  }) async {
    if (amountMinor != null) {
      checkCashMagnitude(amountMinor);
    }
    if (cls != null) {
      checkUserCashClass(cls);
    }
    if (on != null) {
      checkCashDate('on', on);
    }
    final newLabel = label == null ? null : optionalCashLabel(label);
    try {
      await _db.transaction(() async {
        final row = await require(id);
        _checkEditable(row);
        if (cls != null &&
            row.postingStatus == PostingStatus.posted.code &&
            cls != CashEventClass.confirmed) {
          throw const ConflictException('已发生的收支只能是确定的');
        }
        final newOn = on ?? LocalDate.parse(row.eventOn);
        final String? newAt;
        if (clearAt) {
          newAt = null;
        } else if (at != null) {
          newAt = cashAtText(at, newOn, field: 'at');
        } else if (row.eventAt != null && on != null) {
          // 只改了日期：原时刻不再与日期相符，丢弃（与领域包"改期丢弃时间戳"一致）。
          newAt = Timestamp.parse(row.eventAt!).date == newOn
              ? row.eventAt
              : null;
        } else {
          newAt = row.eventAt;
        }
        final sign = row.amountMinor < 0 ? -1 : 1;
        await (_db.update(
          _db.cashEvents,
        )..where((e) => e.workspaceId.equals(_ws) & e.id.equals(id))).write(
          CashEventsCompanion(
            eventOn: Value(newOn.toString()),
            eventAt: Value(newAt),
            amountMinor: amountMinor == null
                ? const Value.absent()
                : Value(sign * amountMinor),
            cls: cls == null ? const Value.absent() : Value(cls.code),
            label: label == null ? const Value.absent() : Value(newLabel),
            rowVersion: Value(row.rowVersion + 1),
            updatedAt: Value(_scope.clock.nowText(cashTimeZone)),
          ),
        );
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 标记已发生（P-08 状态转移：计划/预计 → 确定）：层级变为确定、发生状态变为已发生；可同时更正
  /// 实际金额（正数）、日期与时刻。G3：实际发生日期不晚于今天，时刻不晚于现在。
  ///
  /// 调拨的一端标记时，另一端一起标记（日期与金额不变）。
  Future<void> markPosted(
    String id, {
    int? amountMinor,
    LocalDate? on,
    Timestamp? at,
  }) async {
    if (amountMinor != null) {
      checkCashMagnitude(amountMinor);
    }
    try {
      await _db.transaction(() async {
        final row = await require(id);
        if (row.transferGroupId != null &&
            (amountMinor != null || on != null || at != null)) {
          throw const ConflictException('调拨的日期与金额不能改；请删除后重新登记');
        }
        final newOn = on ?? LocalDate.parse(row.eventOn);
        if (newOn > _today) {
          throw const ValidationException('on', '还没到这一天，不能标记为已发生');
        }
        if (at != null &&
            at.utcMicros > _scope.clock.now().microsecondsSinceEpoch) {
          throw const ValidationException('at', '发生时刻不能晚于现在');
        }
        final rows = row.transferGroupId == null
            ? <CashEventRow>[row]
            : await _transferLegs(row.transferGroupId!);
        for (final leg in rows) {
          if (leg.transferGroupId != null &&
              LocalDate.parse(leg.eventOn) > _today) {
            throw const ValidationException('on', '到账日还没到，不能标记为已发生');
          }
          final sign = leg.amountMinor < 0 ? -1 : 1;
          final legOn = leg.id == row.id ? newOn : LocalDate.parse(leg.eventOn);
          await (_db.update(_db.cashEvents)
                ..where((e) => e.workspaceId.equals(_ws) & e.id.equals(leg.id)))
              .write(
                CashEventsCompanion(
                  cls: Value(CashEventClass.confirmed.code),
                  postingStatus: Value(PostingStatus.posted.code),
                  eventOn: leg.transferGroupId == null
                      ? Value(legOn.toString())
                      : const Value.absent(),
                  eventAt: leg.transferGroupId != null
                      ? const Value.absent()
                      : at != null
                      ? Value(cashAtText(at, legOn, field: 'at'))
                      : on != null && leg.eventAt != null
                      ? Value(
                          Timestamp.parse(leg.eventAt!).date == legOn
                              ? leg.eventAt
                              : null,
                        )
                      : const Value.absent(),
                  amountMinor: amountMinor == null || leg.id != row.id
                      ? const Value.absent()
                      : Value(sign * amountMinor),
                  rowVersion: Value(leg.rowVersion + 1),
                  updatedAt: Value(_scope.clock.nowText(cashTimeZone)),
                ),
              );
        }
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 删除一笔收支（tombstone）。调拨两端一起删除；周期事项的单期请用"跳过"。
  Future<void> delete(String id) => _db.transaction(() async {
    final row = await require(id);
    if (row.recurringItemId != null) {
      throw const ConflictException('周期事项的单期请在周期事项里跳过');
    }
    final legs = row.transferGroupId == null
        ? <CashEventRow>[row]
        : await _transferLegs(row.transferGroupId!);
    final now = _scope.clock.nowText(cashTimeZone);
    for (final leg in legs) {
      await (_db.update(
        _db.cashEvents,
      )..where((e) => e.workspaceId.equals(_ws) & e.id.equals(leg.id))).write(
        CashEventsCompanion(
          deletedAt: Value(now),
          rowVersion: Value(leg.rowVersion + 1),
          updatedAt: Value(now),
        ),
      );
    }
  });

  // ---- 调拨 ----

  /// 新增调拨：两条事件共享调拨组（转出为负、到账为正），一个事务。返回调拨组 id。
  ///
  /// 校验（P-08）：两端账户不同、都存在且未停用、币种相同；金额为正；到账日不早于转出日，同一天且
  /// 两端都有时刻时到账时刻不早于转出时刻；层级只能是确定或预计。
  Future<String> createTransfer(TransferDraft draft, {String? groupId}) async {
    checkUserCashClass(draft.cls);
    checkCashMagnitude(draft.amountMinor);
    checkCashDate('outOn', draft.outOn);
    checkCashDate('inOn', draft.inOn);
    final label = optionalCashLabel(draft.label);
    if (draft.fromAccountId == draft.toAccountId) {
      throw const ValidationException('toAccount', '转出与转入须是两个不同的账户');
    }
    if (draft.inOn < draft.outOn) {
      throw const ValidationException('inOn', '到账日不能早于转出日');
    }
    final outAt = cashAtText(draft.outAt, draft.outOn, field: 'outAt');
    final inAt = cashAtText(draft.inAt, draft.inOn, field: 'inAt');
    if (draft.outAt != null &&
        draft.inAt != null &&
        draft.inAt!.utcMicros < draft.outAt!.utcMicros) {
      throw const ValidationException('inAt', '到账时刻不能早于转出时刻');
    }
    final group = groupId ?? newUuidV4();
    try {
      return await _db.transaction(() async {
        final existing = await _transferLegs(group);
        if (existing.isNotEmpty) {
          return group;
        }
        final from = await _activeAccount(draft.fromAccountId);
        final to = await _activeAccount(draft.toAccountId);
        if (from.currency != to.currency) {
          throw const ValidationException('toAccount', '两端账户的币种须相同');
        }
        final now = _scope.clock.nowText(cashTimeZone);
        for (final (account, on, at, amount, category)
            in <(String, LocalDate, String?, int, CashCategory)>[
              (
                from.id,
                draft.outOn,
                outAt,
                -draft.amountMinor,
                CashCategory.transferOut,
              ),
              (
                to.id,
                draft.inOn,
                inAt,
                draft.amountMinor,
                CashCategory.transferIn,
              ),
            ]) {
          await _db
              .into(_db.cashEvents)
              .insert(
                CashEventsCompanion.insert(
                  id: newUuidV4(),
                  workspaceId: _ws,
                  cashAccountId: account,
                  eventOn: on.toString(),
                  eventAt: Value(at),
                  amountMinor: amount,
                  cls: draft.cls.code,
                  category: category.code,
                  label: Value(label),
                  transferGroupId: Value(group),
                  createdAt: now,
                  updatedAt: now,
                ),
              );
        }
        return group;
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 未删除的调拨，按转出日期。
  Future<List<TransferView>> transfers() async {
    final legs =
        await (_db.select(_db.cashEvents)
              ..where(
                (e) =>
                    e.workspaceId.equals(_ws) &
                    e.transferGroupId.isNotNull() &
                    e.deletedAt.isNull(),
              )
              ..orderBy([
                (e) => OrderingTerm.asc(e.eventOn),
                (e) => OrderingTerm.asc(e.rowId),
              ]))
            .get();
    final byGroup = <String, List<CashEventRow>>{};
    for (final leg in legs) {
      byGroup
          .putIfAbsent(leg.transferGroupId!, () => <CashEventRow>[])
          .add(leg);
    }
    return <TransferView>[
      for (final group in byGroup.values)
        if (group.length == 2)
          TransferView(
            out: group.firstWhere((e) => e.amountMinor < 0),
            into: group.firstWhere((e) => e.amountMinor > 0),
          ),
    ];
  }

  Future<List<CashEventRow>> _transferLegs(String groupId) =>
      (_db.select(_db.cashEvents)
            ..where(
              (e) =>
                  e.workspaceId.equals(_ws) &
                  e.transferGroupId.equals(groupId) &
                  e.deletedAt.isNull(),
            )
            ..orderBy([(e) => OrderingTerm.asc(e.rowId)]))
          .get();

  // ---- 还款扣款（给 I-1c 的接口）----

  /// 某笔还款对应的未删除现金事件。
  Future<CashEventRow?> byRepayment(String repaymentId) =>
      (_db.select(_db.cashEvents)..where(
            (e) =>
                e.workspaceId.equals(_ws) &
                e.linkedRepaymentId.equals(repaymentId) &
                e.deletedAt.isNull(),
          ))
          .getSingleOrNull();

  /// 由还款生成（或更新）计划扣款：层级 `planned`、类别 `repayment`、尚未发生，
  /// `linked_repayment_id = repaymentId`（每笔还款最多一条未删除的事件，部分唯一索引）。
  /// 现金时间线按预计扣款日 [on] 生效（UF-3 步骤 2）。已发生（已确认扣款）的不再改动。
  Future<CashEventRow> planRepaymentDebit({
    required String repaymentId,
    required String cashAccountId,
    required LocalDate on,
    required int amountMinor,
    Timestamp? at,
    String? label,
  }) async {
    checkCashMagnitude(amountMinor);
    checkCashDate('on', on);
    final text = cashAtText(at, on, field: 'at');
    final eventLabel = optionalCashLabel(label);
    try {
      return await _db.transaction(() async {
        final existing = await byRepayment(repaymentId);
        final now = _scope.clock.nowText(cashTimeZone);
        if (existing != null) {
          if (existing.postingStatus == PostingStatus.posted.code) {
            throw const ConflictException('这笔还款的扣款已确认');
          }
          if (existing.cashAccountId != cashAccountId) {
            // 换了扣款账户：旧的作废，新建一条（事件不在账户之间移动）。
            await _tombstone(existing, now);
          } else {
            await (_db.update(_db.cashEvents)..where(
                  (e) => e.workspaceId.equals(_ws) & e.id.equals(existing.id),
                ))
                .write(
                  CashEventsCompanion(
                    eventOn: Value(on.toString()),
                    eventAt: Value(text),
                    amountMinor: Value(-amountMinor),
                    label: Value(eventLabel),
                    rowVersion: Value(existing.rowVersion + 1),
                    updatedAt: Value(now),
                  ),
                );
            return (await byId(existing.id))!;
          }
        }
        await _activeAccount(cashAccountId);
        final id = newUuidV4();
        await _db
            .into(_db.cashEvents)
            .insert(
              CashEventsCompanion.insert(
                id: id,
                workspaceId: _ws,
                cashAccountId: cashAccountId,
                eventOn: on.toString(),
                eventAt: Value(text),
                amountMinor: -amountMinor,
                cls: CashEventClass.planned.code,
                category: CashCategory.repayment.code,
                label: Value(eventLabel),
                linkedRepaymentId: Value(repaymentId),
                createdAt: now,
                updatedAt: now,
              ),
            );
        return (await byId(id))!;
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 确认扣款（UF-3 步骤 3，`cash_debited`）：该还款的事件变为确定、已发生，日期与时刻改为实际扣款
  /// 时点 [debitedAt]（按现金时区写入；F-31：现金时间线按扣款日生效），可更正实际金额。G3：不晚于现在。
  Future<CashEventRow> confirmRepaymentDebit({
    required String repaymentId,
    required Timestamp debitedAt,
    int? amountMinor,
  }) async {
    if (amountMinor != null) {
      checkCashMagnitude(amountMinor);
    }
    if (debitedAt.utcMicros > _scope.clock.now().microsecondsSinceEpoch) {
      throw const ValidationException('debitedAt', '扣款时点不能晚于现在');
    }
    final local = timestampTextIn(
      DateTime.fromMicrosecondsSinceEpoch(debitedAt.utcMicros, isUtc: true),
      cashTimeZone,
    );
    final on = Timestamp.parse(local).date;
    try {
      return await _db.transaction(() async {
        final row = await byRepayment(repaymentId);
        if (row == null) {
          throw const NotFoundException('还款扣款');
        }
        await (_db.update(
          _db.cashEvents,
        )..where((e) => e.workspaceId.equals(_ws) & e.id.equals(row.id))).write(
          CashEventsCompanion(
            cls: Value(CashEventClass.confirmed.code),
            postingStatus: Value(PostingStatus.posted.code),
            eventOn: Value(on.toString()),
            eventAt: Value(local),
            amountMinor: amountMinor == null
                ? const Value.absent()
                : Value(-amountMinor),
            rowVersion: Value(row.rowVersion + 1),
            updatedAt: Value(_scope.clock.nowText(cashTimeZone)),
          ),
        );
        return (await byId(row.id))!;
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 撤销还款的计划扣款（还款失败、撤销）：事件作废（tombstone）。已发生的不能撤销。
  Future<void> cancelRepaymentDebit(String repaymentId) =>
      _db.transaction(() async {
        final row = await byRepayment(repaymentId);
        if (row == null) {
          return;
        }
        if (row.postingStatus == PostingStatus.posted.code) {
          throw const ConflictException('这笔还款的扣款已确认，不能撤销');
        }
        await _tombstone(row, _scope.clock.nowText(cashTimeZone));
      });

  Future<void> _tombstone(CashEventRow row, String now) =>
      (_db.update(
        _db.cashEvents,
      )..where((e) => e.workspaceId.equals(_ws) & e.id.equals(row.id))).write(
        CashEventsCompanion(
          deletedAt: Value(now),
          rowVersion: Value(row.rowVersion + 1),
          updatedAt: Value(now),
        ),
      );

  Future<CashAccountRow> _activeAccount(String id) async {
    final account = await CashAccountRepository(_scope).require(id);
    if (account.status != CashAccountStatus.active.code) {
      throw const ConflictException('现金账户已停用');
    }
    return account;
  }

  void _checkEditable(CashEventRow row) {
    if (row.transferGroupId != null) {
      throw const ConflictException('调拨的日期与金额不能改；请删除后重新登记');
    }
    if (row.recurringItemId != null) {
      throw const ConflictException('周期事项的单期请在周期事项里覆盖');
    }
  }
}
