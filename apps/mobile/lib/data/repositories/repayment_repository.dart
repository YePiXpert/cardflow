import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate, Timestamp;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../ids.dart';
import '../mapping/cash_mapping.dart' show cashTimeZone;
import '../mapping/ledger_mapping.dart';
import '../time/business_tz.dart';
import '../time/clock.dart';
import '../validation/text_rules.dart';
import 'cash_event_repository.dart';
import 'cash_models.dart';
import 'credit_pool_repository.dart' show maxAmountMinor;
import 'ledger_models.dart';
import 'reconciliation_repository.dart';
import 'repository_errors.dart';
import 'statement_repository.dart';
import 'workspace_scope.dart';

/// 登记一笔还款的输入（P-06 表单）。
@immutable
final class RepaymentDraft {
  const RepaymentDraft({
    required this.currencyAccountId,
    required this.amountMinor,
    required this.method,
    required this.allocations,
    this.cashAccountId,
    this.initiatedAt,
    this.expectedDebitOn,
    this.evidenceNote,
  });

  /// 还哪个币种子账户。
  final String currencyAccountId;

  /// 还款额（正数，最小单位）。
  final int amountMinor;
  final RepaymentMethod method;

  /// 分配到各期账单（账单 id → 金额）：仓库要求 Σ ≤ 还款额，界面要求 Σ = 还款额（F-33）。
  final Map<String, int> allocations;

  /// 从哪个现金账户扣款（同币种、未停用）。
  final String? cashAccountId;

  /// 发起时间（G3：不晚于现在）。
  final Timestamp? initiatedAt;

  /// 预计扣款日：现金时间线按它生成"计划"扣款（UF-3 步骤 2），不早于发起日。
  final LocalDate? expectedDebitOn;

  /// 证据备注（≤200 字，G2）。
  final String? evidenceNote;
}

/// 还款与分配（当前工作空间）：状态机 PRD §6.3 的全部转移在这里实现（非法转移抛
/// [IllegalRepaymentTransitionException]，触发器兜底）。
///
/// 双侧时间（R-STMT-04、F-31）：现金侧经 I-1b 的接口生成/确认 `cash_events`（`linked_repayment_id`）——
/// 预计扣款日生成"计划"事件，确认扣款时按实际扣款时点变为确定、已发生；负债侧按 `credit_posted_at` 的
/// 日期核销（读模型 `paidOnStatement`）；额度释放按"银行入账后 + 释放时滞"，时滞未知时不释放（F-28）。
/// 结清/部分结清只由银行确认触发；「我已还款」只到 `user_marked_paid`，不结清（R-STMT-03）。
///
/// 差异项：同一天、同一子账户、同金额的一笔自动扣款与一笔手工还款 → 疑似重复（F-32，处理前负债只核销
/// 一次）；扣款或入账的金额与登记的不同 → 金额不符。
final class RepaymentRepository {
  RepaymentRepository(this._scope);

  final WorkspaceScope _scope;

  AppDatabase get _db => _scope.db;
  String get _ws => _scope.workspaceId;

  CashEventRepository get _cash => CashEventRepository(_scope);

  /// 未作废的还款（可只取某币种子账户的），登记新的在前。
  Future<List<RepaymentRow>> list({String? currencyAccountId}) =>
      (_db.select(_db.repayments)
            ..where(
              (r) =>
                  r.workspaceId.equals(_ws) &
                  r.deletedAt.isNull() &
                  (currencyAccountId == null
                      ? const Constant(true)
                      : r.currencyAccountId.equals(currencyAccountId)),
            )
            ..orderBy([
              (r) => OrderingTerm.desc(r.createdAt),
              (r) => OrderingTerm.desc(r.rowId),
            ]))
          .get();

  Future<RepaymentRow?> byId(String id) =>
      (_db.select(_db.repayments)..where(
            (r) =>
                r.workspaceId.equals(_ws) &
                r.id.equals(id) &
                r.deletedAt.isNull(),
          ))
          .getSingleOrNull();

  Future<RepaymentRow> require(String id) async =>
      await byId(id) ?? (throw const NotFoundException('还款'));

  /// 某还款的分配（按账单）。
  Future<List<RepaymentAllocationRow>> allocationsOf(String repaymentId) =>
      (_db.select(_db.repaymentAllocations)
            ..where(
              (a) =>
                  a.workspaceId.equals(_ws) & a.repaymentId.equals(repaymentId),
            )
            ..orderBy([(a) => OrderingTerm.asc(a.statementId)]))
          .get();

  /// 本工作空间的全部分配（读模型一次取齐）。
  Future<List<RepaymentAllocationRow>> allAllocations() => (_db.select(
    _db.repaymentAllocations,
  )..where((a) => a.workspaceId.equals(_ws))).get();

  /// 登记还款（UF-3 步骤 1–2；幂等：同一个 [id] 再次保存直接返回已建的）。状态"已登记（待银行确认）"；
  /// 有现金账户与预计扣款日时，现金时间线生成一条"计划"扣款。
  Future<RepaymentRow> create(RepaymentDraft draft, {String? id}) async {
    if (draft.amountMinor <= 0) {
      throw const ValidationException('amount', '还款额须大于 0');
    }
    if (draft.amountMinor > maxAmountMinor) {
      throw const ValidationException('amount', '金额超出范围');
    }
    var allocated = 0;
    for (final amount in draft.allocations.values) {
      if (amount <= 0) {
        throw const ValidationException('allocations', '每期分配的金额须大于 0');
      }
      allocated += amount;
    }
    if (allocated > draft.amountMinor) {
      throw const ValidationException('allocations', '分配合计不能超过还款额');
    }
    final note = _note(draft.evidenceNote);
    final nowMicros = _scope.clock.now().microsecondsSinceEpoch;
    final initiated = draft.initiatedAt;
    if (initiated != null && initiated.utcMicros > nowMicros) {
      throw const ValidationException('initiatedAt', '发起时间不能晚于现在');
    }
    final expected = draft.expectedDebitOn;
    if (initiated != null &&
        expected != null &&
        expected < businessDateOf(initiated, cashTimeZone)) {
      throw const ValidationException('expectedDebitOn', '预计扣款日不能早于发起日');
    }
    final repaymentId = id ?? newUuidV4();
    try {
      return await _db.transaction(() async {
        final existing = await byId(repaymentId);
        if (existing != null) {
          return existing;
        }
        final sub =
            await (_db.select(_db.currencyAccounts)..where(
                  (c) =>
                      c.workspaceId.equals(_ws) &
                      c.id.equals(draft.currencyAccountId),
                ))
                .getSingleOrNull() ??
            (throw const NotFoundException('币种子账户'));
        final cashId = draft.cashAccountId;
        if (cashId != null) {
          final cash =
              await (_db.select(_db.cashAccounts)..where(
                    (c) =>
                        c.workspaceId.equals(_ws) &
                        c.id.equals(cashId) &
                        c.deletedAt.isNull(),
                  ))
                  .getSingleOrNull() ??
              (throw const NotFoundException('现金账户'));
          if (cash.status != CashAccountStatus.active.code) {
            throw const ValidationException('cashAccount', '现金账户已停用');
          }
          if (cash.currency != sub.currency) {
            throw const ValidationException('cashAccount', '现金账户的币种须与还款相同');
          }
        }
        for (final statementId in draft.allocations.keys) {
          final statement =
              await (_db.select(_db.statements)..where(
                    (s) => s.workspaceId.equals(_ws) & s.id.equals(statementId),
                  ))
                  .getSingleOrNull();
          if (statement == null || statement.currencyAccountId != sub.id) {
            throw const ValidationException('allocations', '只能分配到这个账户的账单');
          }
          if (StatementStatus.of(statement.status).isSettled) {
            throw const ValidationException('allocations', '这期账单已结清');
          }
        }
        final now = _scope.clock.nowText(cashTimeZone);
        await _db
            .into(_db.repayments)
            .insert(
              RepaymentsCompanion.insert(
                id: repaymentId,
                workspaceId: _ws,
                currencyAccountId: sub.id,
                cashAccountId: Value(cashId),
                amountMinor: draft.amountMinor,
                currency: sub.currency,
                status: RepaymentStatus.recorded.code,
                method: draft.method.code,
                paymentInitiatedAt: Value(_cashText(initiated)),
                expectedDebitOn: Value(expected?.toString()),
                evidenceNote: Value(note),
                createdAt: now,
                updatedAt: now,
              ),
            );
        for (final entry in draft.allocations.entries) {
          await _db
              .into(_db.repaymentAllocations)
              .insert(
                RepaymentAllocationsCompanion.insert(
                  workspaceId: _ws,
                  currencyAccountId: sub.id,
                  repaymentId: repaymentId,
                  statementId: entry.key,
                  amountMinor: entry.value,
                ),
              );
        }
        if (cashId != null && expected != null) {
          await _cash.planRepaymentDebit(
            repaymentId: repaymentId,
            cashAccountId: cashId,
            on: expected,
            amountMinor: draft.amountMinor,
            label: await _cashLabel(sub),
          );
        }
        final row = (await byId(repaymentId))!;
        await _detectDuplicates(row);
        return row;
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 「标记已发起」：已登记 → 处理中（发起时间不晚于现在）。
  Future<void> markInitiated(String id, Timestamp at) => _guarded(() async {
    final row = await require(id);
    _checkNotFuture(at, 'initiatedAt', '发起时间不能晚于现在');
    await _move(
      row,
      RepaymentStatus.processing,
      RepaymentsCompanion(paymentInitiatedAt: Value(_cashText(at))),
    );
  });

  /// 「确认扣款」（UF-3 步骤 3）：→ 现金已扣。已登记的先经"处理中"（状态机只有处理中 → 现金已扣）。
  /// 扣款时点不晚于现在、不早于发起时间；现金时间线的计划扣款按实际扣款时点变为确定、已发生（F-31），
  /// 可更正实际扣款金额；与登记的金额不同 → 金额不符差异项。
  Future<void> confirmDebit(
    String id,
    Timestamp debitedAt, {
    int? actualAmountMinor,
  }) => _guarded(() async {
    var row = await require(id);
    _checkNotFuture(debitedAt, 'debitedAt', '扣款时点不能晚于现在');
    if (actualAmountMinor != null &&
        (actualAmountMinor <= 0 || actualAmountMinor > maxAmountMinor)) {
      throw const ValidationException('amount', '实际扣款金额须大于 0');
    }
    if (RepaymentStatus.of(row.status) == RepaymentStatus.recorded) {
      await _move(
        row,
        RepaymentStatus.processing,
        RepaymentsCompanion(
          paymentInitiatedAt: Value(
            row.paymentInitiatedAt ?? _cashText(debitedAt),
          ),
        ),
      );
      row = await require(id);
    }
    _checkNotBefore(
      debitedAt,
      row.paymentInitiatedAt,
      'debitedAt',
      '扣款时点不能早于发起时间',
    );
    await _move(
      row,
      RepaymentStatus.cashDebited,
      RepaymentsCompanion(cashDebitedAt: Value(_cashText(debitedAt))),
    );
    final cashId = row.cashAccountId;
    if (cashId != null) {
      if (await _cash.byRepayment(id) == null) {
        final sub = await _currencyAccount(row.currencyAccountId);
        await _cash.planRepaymentDebit(
          repaymentId: id,
          cashAccountId: cashId,
          on: businessDateOf(debitedAt, cashTimeZone),
          amountMinor: row.amountMinor,
          label: await _cashLabel(sub),
        );
      }
      await _cash.confirmRepaymentDebit(
        repaymentId: id,
        debitedAt: debitedAt,
        amountMinor: actualAmountMinor,
      );
    }
    if (actualAmountMinor != null && actualAmountMinor != row.amountMinor) {
      await ReconciliationRepository(_scope)
          .open(ReconciliationKind.amountMismatch, <String, Object?>{
            'repayment_id': id,
            'side': 'cash',
            'expected_minor': row.amountMinor,
            'actual_minor': actualAmountMinor,
          });
    }
    await _detectDuplicates(await require(id));
  });

  /// 「标记失败」：处理中 → 失败；现金时间线的计划扣款作废（UF-3 异常：提醒重排）。
  Future<void> markFailed(String id) => _guarded(() async {
    final row = await require(id);
    await _move(row, RepaymentStatus.failed, const RepaymentsCompanion());
    await _cash.cancelRepaymentDebit(id);
  });

  /// 「重试登记」：失败 → 已登记；给了新的预计扣款日时重新生成计划扣款。
  Future<void> retry(String id, {LocalDate? expectedDebitOn}) =>
      _guarded(() async {
        final row = await require(id);
        await _move(
          row,
          RepaymentStatus.recorded,
          RepaymentsCompanion(
            expectedDebitOn: expectedDebitOn == null
                ? const Value.absent()
                : Value(expectedDebitOn.toString()),
          ),
        );
        final cashId = row.cashAccountId;
        final on =
            expectedDebitOn ??
            (row.expectedDebitOn == null
                ? null
                : LocalDate.parse(row.expectedDebitOn!));
        if (cashId != null && on != null) {
          await _cash.planRepaymentDebit(
            repaymentId: id,
            cashAccountId: cashId,
            on: on,
            amountMinor: row.amountMinor,
            label: await _cashLabel(
              await _currencyAccount(row.currencyAccountId),
            ),
          );
        }
      });

  /// 「我已还款」：已登记 → 用户已标记（不是银行确认：账单不结清、负债不核销，R-STMT-03）。
  Future<void> markUserPaid(String id) => _guarded(() async {
    final row = await require(id);
    await _move(
      row,
      RepaymentStatus.userMarkedPaid,
      const RepaymentsCompanion(),
    );
  });

  /// 「上传入账证据」（UF-3 步骤 4）：现金已扣 → 银行已入账。入账时点不晚于现在、不早于扣款时点；负债从
  /// 入账日起核销（F-31）。入账金额与登记的不同 → 金额不符差异项。
  Future<void> markCreditPosted(
    String id,
    Timestamp postedAt, {
    int? creditedAmountMinor,
  }) => _guarded(() async {
    final row = await require(id);
    _checkNotFuture(postedAt, 'creditPostedAt', '入账时点不能晚于现在');
    _checkNotBefore(
      postedAt,
      row.cashDebitedAt,
      'creditPostedAt',
      '入账时点不能早于扣款时点',
    );
    final zone = await _creditZone(row.currencyAccountId);
    await _move(
      row,
      RepaymentStatus.creditPosted,
      RepaymentsCompanion(creditPostedAt: Value(_textIn(postedAt, zone))),
    );
    if (creditedAmountMinor != null && creditedAmountMinor != row.amountMinor) {
      await ReconciliationRepository(_scope)
          .open(ReconciliationKind.amountMismatch, <String, Object?>{
            'repayment_id': id,
            'side': 'credit',
            'expected_minor': row.amountMinor,
            'actual_minor': creditedAmountMinor,
          });
    }
  });

  /// 「银行确认」：银行已入账 / 用户已标记 / 待核对 → 银行确认（账单或流水核对一致）。从"用户已标记"或
  /// "待核对"来时须给出扣款时点（现金时间线的计划扣款按它确认），入账时点取确认时点。之后按银行确认的
  /// 分配判断各期账单：足额 → 已结清，部分 → 部分结清（PRD §6.2）。
  Future<void> confirmByBank(
    String id,
    Timestamp confirmedAt, {
    Timestamp? debitedAt,
  }) => _guarded(() async {
    final row = await require(id);
    _checkNotFuture(confirmedAt, 'confirmedAt', '确认时点不能晚于现在');
    final from = RepaymentStatus.of(row.status);
    final zone = await _creditZone(row.currencyAccountId);
    var changes = RepaymentsCompanion(
      bankConfirmedAt: Value(_textIn(confirmedAt, zone)),
    );
    if (from == RepaymentStatus.creditPosted) {
      _checkNotBefore(
        confirmedAt,
        row.creditPostedAt,
        'confirmedAt',
        '确认时点不能早于入账时点',
      );
    } else if (from == RepaymentStatus.userMarkedPaid ||
        from == RepaymentStatus.needsReview) {
      final event = await _cash.byRepayment(id);
      final pending =
          event != null && event.postingStatus != PostingStatus.posted.code;
      if (pending && debitedAt == null) {
        throw const ValidationException('debitedAt', '请填写实际扣款时点（现金时间线按它确认扣款）');
      }
      if (debitedAt != null) {
        _checkNotFuture(debitedAt, 'debitedAt', '扣款时点不能晚于现在');
        if (debitedAt.utcMicros > confirmedAt.utcMicros) {
          throw const ValidationException('debitedAt', '扣款时点不能晚于确认时点');
        }
        if (pending) {
          await _cash.confirmRepaymentDebit(
            repaymentId: id,
            debitedAt: debitedAt,
          );
        }
      }
      changes = changes.copyWith(
        cashDebitedAt: debitedAt == null
            ? const Value.absent()
            : Value(_cashText(debitedAt)),
        creditPostedAt: Value(_textIn(confirmedAt, zone)),
      );
    }
    await _move(row, RepaymentStatus.bankConfirmed, changes);
    await _settleStatements(id);
  });

  /// 到期后仍无证据：用户已标记 → 待核对（提醒降级在 I-4，这里只改状态，UF-3 步骤 6）。
  Future<void> markNeedsReview(String id) => _guarded(() async {
    final row = await require(id);
    await _move(row, RepaymentStatus.needsReview, const RepaymentsCompanion());
  });

  /// 「冲正」：银行确认 → 已冲正（不再核销负债；R2-15）。
  Future<void> reverse(String id) => _guarded(() async {
    final row = await require(id);
    await _move(row, RepaymentStatus.reversed, const RepaymentsCompanion());
  });

  /// 作废这笔登记（tombstone）：只有已登记、失败、用户已标记、待核对且现金还没扣的可以作废；计划扣款
  /// 一并作废。
  Future<void> delete(String id) => _guarded(() => _delete(id));

  Future<void> _delete(String id) async {
    final row = await require(id);
    const deletable = <RepaymentStatus>{
      RepaymentStatus.recorded,
      RepaymentStatus.failed,
      RepaymentStatus.userMarkedPaid,
      RepaymentStatus.needsReview,
    };
    if (!deletable.contains(RepaymentStatus.of(row.status))) {
      throw const ConflictException('这笔还款已在处理中或已扣款，不能作废；失败请先「标记失败」');
    }
    final event = await _cash.byRepayment(id);
    if (event != null && event.postingStatus == PostingStatus.posted.code) {
      throw const ConflictException('这笔还款的扣款已确认，不能作废');
    }
    await _cash.cancelRepaymentDebit(id);
    final now = _scope.clock.nowText(cashTimeZone);
    await (_db.update(
      _db.repayments,
    )..where((r) => r.workspaceId.equals(_ws) & r.id.equals(id))).write(
      RepaymentsCompanion(
        deletedAt: Value(now),
        rowVersion: Value(row.rowVersion + 1),
        updatedAt: Value(now),
      ),
    );
  }

  /// 证据备注（≤200 字，G2）；空白 = 清除。
  Future<void> setEvidenceNote(String id, String? note) => _guarded(() async {
    final row = await require(id);
    await (_db.update(
      _db.repayments,
    )..where((r) => r.workspaceId.equals(_ws) & r.id.equals(id))).write(
      RepaymentsCompanion(
        evidenceNote: Value(_note(note)),
        rowVersion: Value(row.rowVersion + 1),
        updatedAt: Value(_scope.clock.nowText(cashTimeZone)),
      ),
    );
  });

  /// 处理疑似重复（F-32）：[voidRepaymentId] 为空 = 确为两笔还款；否则是同一笔，作废其中这一笔登记
  /// （必须属于这一组、可以作废）。
  Future<void> resolveDuplicate(String itemId, {String? voidRepaymentId}) =>
      _guarded(() async {
        final items = ReconciliationRepository(_scope);
        final item = await items.require(itemId);
        if (item.kind != ReconciliationKind.duplicateRepayment.code) {
          throw const ValidationException('item', '这不是疑似重复还款');
        }
        if (voidRepaymentId == null) {
          await items.resolve(itemId, ReconciliationResolution.distinct);
          return;
        }
        if (!referencedRepayments(item).contains(voidRepaymentId)) {
          throw const ValidationException('repayment', '只能作废这一组里的登记');
        }
        await _delete(voidRepaymentId);
        await items.resolve(itemId, ReconciliationResolution.samePayment);
      });

  /// 到期后仍无证据的"用户已标记"→ 待核对：分配到的账单里有到期日早于 [today]（信用账户业务时区的今天，
  /// 按子账户给）的。返回改动的笔数（没有要改的时不写库）。
  Future<int> markOverdueMarkedPaid(
    Map<String, LocalDate> todayByAccount,
  ) async {
    var changed = 0;
    final rows =
        await (_db.select(_db.repayments)..where(
              (r) =>
                  r.workspaceId.equals(_ws) &
                  r.deletedAt.isNull() &
                  r.status.equals(RepaymentStatus.userMarkedPaid.code),
            ))
            .get();
    for (final row in rows) {
      final today = todayByAccount[row.currencyAccountId];
      if (today == null) {
        continue;
      }
      final statements = await _allocatedStatements(row.id);
      if (statements.any((s) => LocalDate.parse(s.dueDate) < today)) {
        await _move(
          row,
          RepaymentStatus.needsReview,
          const RepaymentsCompanion(),
        );
        changed++;
      }
    }
    return changed;
  }

  // ---- 内部 ----

  Future<void> _guarded(Future<void> Function() action) async {
    try {
      await _db.transaction(action);
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  Future<void> _move(
    RepaymentRow row,
    RepaymentStatus to,
    RepaymentsCompanion changes,
  ) async {
    final from = RepaymentStatus.of(row.status);
    if (!from.canBecome(to)) {
      throw IllegalRepaymentTransitionException(from, to);
    }
    await (_db.update(
      _db.repayments,
    )..where((r) => r.workspaceId.equals(_ws) & r.id.equals(row.id))).write(
      changes.copyWith(
        status: Value(to.code),
        rowVersion: Value(row.rowVersion + 1),
        updatedAt: Value(_scope.clock.nowText(cashTimeZone)),
      ),
    );
  }

  Future<List<StatementRow>> _allocatedStatements(String repaymentId) async {
    final allocations = await allocationsOf(repaymentId);
    final ids = allocations.map((a) => a.statementId).toList();
    if (ids.isEmpty) {
      return const <StatementRow>[];
    }
    return (_db.select(
      _db.statements,
    )..where((s) => s.workspaceId.equals(_ws) & s.id.isIn(ids))).get();
  }

  /// 银行确认后，各期账单按银行确认的分配判断结清（PRD §6.2：结清只由银行确认触发）。
  Future<void> _settleStatements(String repaymentId) async {
    final statements = StatementRepository(_scope);
    final allocations = await allAllocations();
    final repayments = {
      for (final r in await (_db.select(
        _db.repayments,
      )..where((r) => r.workspaceId.equals(_ws) & r.deletedAt.isNull())).get())
        r.id: r,
    };
    final pairs = await ReconciliationRepository(_scope).openDuplicatePairs();
    for (final statement in await _allocatedStatements(repaymentId)) {
      final current = (await statements.versions(statement.id)).last;
      final due = amountDueOf(current);
      final paid = paidOnStatement(
        statementId: statement.id,
        allocations: allocations,
        repayments: repayments,
        creditDates: <String, LocalDate?>{
          // 结清看的是银行确认，不看入账日：所有银行确认的都计入。
          for (final r in repayments.values) r.id: LocalDate(1970, 1, 1),
        },
        on: LocalDate(9999, 12, 31),
        openDuplicates: pairs,
        bankConfirmedOnly: true,
      );
      if (paid >= due) {
        await statements.moveStatus(statement.id, StatementStatus.settled);
      } else if (paid > 0) {
        await statements.moveStatus(
          statement.id,
          StatementStatus.partiallySettled,
        );
      }
    }
  }

  /// 疑似重复（F-32）：同一天（扣款日 → 预计扣款日 → 发起日，现金时区）、同一子账户、同金额，一笔自动扣款
  /// 一笔手工，两笔都没有作废、失败或冲正 → 生成差异项（已处理过的同一组不再生成）。
  Future<void> _detectDuplicates(RepaymentRow row) async {
    final day = paymentDayOf(row);
    if (day == null || _inactive(row)) {
      return;
    }
    final candidates =
        await (_db.select(_db.repayments)..where(
              (r) =>
                  r.workspaceId.equals(_ws) &
                  r.deletedAt.isNull() &
                  r.currencyAccountId.equals(row.currencyAccountId) &
                  r.amountMinor.equals(row.amountMinor) &
                  r.id.isNotIn(<String>[row.id]),
            ))
            .get();
    final mine = RepaymentMethod.of(row.method);
    for (final other in candidates) {
      final theirs = RepaymentMethod.of(other.method);
      if (_inactive(other) ||
          paymentDayOf(other) != day ||
          mine.isManual == theirs.isManual) {
        continue;
      }
      await ReconciliationRepository(_scope)
          .open(ReconciliationKind.duplicateRepayment, <String, Object?>{
            'repayment_ids': <String>[row.id, other.id],
          });
    }
  }

  bool _inactive(RepaymentRow row) =>
      const <String>{'failed', 'reversed'}.contains(row.status);

  Future<CurrencyAccountRow> _currencyAccount(String id) => (_db.select(
    _db.currencyAccounts,
  )..where((c) => c.workspaceId.equals(_ws) & c.id.equals(id))).getSingle();

  Future<BusinessTimeZone> _creditZone(String currencyAccountId) async {
    final sub = await _currencyAccount(currencyAccountId);
    final account =
        await (_db.select(_db.creditAccounts)..where(
              (a) =>
                  a.workspaceId.equals(_ws) & a.id.equals(sub.creditAccountId),
            ))
            .getSingle();
    return businessTimeZoneOf(account.businessTz);
  }

  /// 现金时间线上这笔扣款的名称（≤20 字）。
  Future<String?> _cashLabel(CurrencyAccountRow sub) async {
    final card =
        await (_db.select(_db.cards)
              ..where(
                (k) =>
                    k.workspaceId.equals(_ws) &
                    k.creditAccountId.equals(sub.creditAccountId) &
                    k.status.isIn(<String>['active', 'frozen']),
              )
              ..orderBy([(k) => OrderingTerm.asc(k.rowId)])
              ..limit(1))
            .getSingleOrNull();
    final name = card?.alias;
    final label = name == null
        ? '信用卡还款 ${card?.last4 ?? ''}'.trim()
        : '$name 还款';
    return textLength(label) <= maxNameLength ? label : '信用卡还款';
  }

  void _checkNotFuture(Timestamp at, String field, String message) {
    if (at.utcMicros > _scope.clock.now().microsecondsSinceEpoch) {
      throw ValidationException(field, message);
    }
  }

  void _checkNotBefore(
    Timestamp at,
    String? earlier,
    String field,
    String message,
  ) {
    if (earlier != null && at.utcMicros < Timestamp.parse(earlier).utcMicros) {
      throw ValidationException(field, message);
    }
  }

  String? _cashText(Timestamp? at) =>
      at == null ? null : _textIn(at, cashTimeZone);

  String _textIn(Timestamp at, BusinessTimeZone zone) => timestampTextIn(
    DateTime.fromMicrosecondsSinceEpoch(at.utcMicros, isUtc: true),
    zone,
  );

  String? _note(String? text) {
    final value = text?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    final problem = validateFreeText(
      value,
      maxLength: maxNoteLength,
      fieldName: '证据备注',
    );
    if (problem != null) {
      throw ValidationException('evidenceNote', problem);
    }
    return value;
  }
}

/// 还款的"那一天"（现金时区）：实际扣款日 → 预计扣款日 → 发起日；都没有时为 null（疑似重复按它判断）。
LocalDate? paymentDayOf(RepaymentRow row) {
  if (row.cashDebitedAt case final t?) {
    return businessDateOf(Timestamp.parse(t), cashTimeZone);
  }
  if (row.expectedDebitOn case final d?) {
    return LocalDate.parse(d);
  }
  if (row.paymentInitiatedAt case final t?) {
    return businessDateOf(Timestamp.parse(t), cashTimeZone);
  }
  return null;
}
