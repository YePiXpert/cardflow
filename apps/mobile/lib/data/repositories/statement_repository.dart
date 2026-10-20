import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../ids.dart';
import '../time/business_tz.dart';
import '../time/clock.dart';
import '../validation/text_rules.dart';
import 'credit_pool_repository.dart' show maxAmountMinor;
import 'ledger_models.dart';
import 'repository_errors.dart';
import 'workspace_scope.dart';

/// 账单要素（R-STMT-01，一个版本的金额）：除新余额外都可空——来源未含此项时为空，界面显示"来源未含
/// 此项"而不是 0。新余额（本期应还）可为负（溢缴）；贷方余额（溢缴款）≥0，有贷方余额时新余额不能为正。
@immutable
final class StatementFigures {
  const StatementFigures({
    required this.newBalanceMinor,
    this.previousBalanceMinor,
    this.minDueMinor,
    this.paymentsMinor,
    this.creditsMinor,
    this.feesMinor,
    this.interestMinor,
    this.installmentDueMinor,
    this.creditBalanceMinor,
  });

  /// 从一个版本行读出（"人工修正"表单的初值）。
  factory StatementFigures.of(StatementVersionRow v) => StatementFigures(
    newBalanceMinor: v.newBalanceMinor,
    previousBalanceMinor: v.previousBalanceMinor,
    minDueMinor: v.minDueMinor,
    paymentsMinor: v.paymentsMinor,
    creditsMinor: v.creditsMinor,
    feesMinor: v.feesMinor,
    interestMinor: v.interestMinor,
    installmentDueMinor: v.installmentDueMinor,
    creditBalanceMinor: v.creditBalanceMinor,
  );

  final int newBalanceMinor;
  final int? previousBalanceMinor;
  final int? minDueMinor;
  final int? paymentsMinor;
  final int? creditsMinor;
  final int? feesMinor;
  final int? interestMinor;
  final int? installmentDueMinor;
  final int? creditBalanceMinor;
}

/// "录入正式账单"的输入（手工录入要素作为 v1）。
@immutable
final class StatementEntryDraft {
  const StatementEntryDraft({
    required this.currencyAccountId,
    required this.statementDate,
    required this.dueDate,
    required this.figures,
  });

  final String currencyAccountId;
  final LocalDate statementDate;
  final LocalDate dueDate;
  final StatementFigures figures;
}

/// 账单与账单版本（当前工作空间）。版本追加只读（R-STMT-07）：录入 = v1，人工修正 = 新版本（理由必填，
/// 原值保留可查）。账单挂在币种子账户上：同一信用账户的多张卡只有一份账单（F-21）。
final class StatementRepository {
  StatementRepository(this._scope);

  final WorkspaceScope _scope;

  AppDatabase get _db => _scope.db;
  String get _ws => _scope.workspaceId;

  /// 账单（可只取某币种子账户的），账单日新的在前。
  Future<List<StatementRow>> list({String? currencyAccountId}) =>
      (_db.select(_db.statements)
            ..where(
              (s) =>
                  s.workspaceId.equals(_ws) &
                  (currencyAccountId == null
                      ? const Constant(true)
                      : s.currencyAccountId.equals(currencyAccountId)),
            )
            ..orderBy([
              (s) => OrderingTerm.desc(s.statementDate),
              (s) => OrderingTerm.asc(s.rowId),
            ]))
          .get();

  Future<StatementRow?> byId(String id) =>
      (_db.select(_db.statements)
            ..where((s) => s.workspaceId.equals(_ws) & s.id.equals(id)))
          .getSingleOrNull();

  Future<StatementRow> require(String id) async =>
      await byId(id) ?? (throw const NotFoundException('账单'));

  /// 某账单的全部版本，按版本号。
  Future<List<StatementVersionRow>> versions(String statementId) =>
      (_db.select(_db.statementVersions)
            ..where(
              (v) =>
                  v.workspaceId.equals(_ws) & v.statementId.equals(statementId),
            )
            ..orderBy([(v) => OrderingTerm.asc(v.versionNo)]))
          .get();

  /// 本工作空间的全部版本（读模型一次取齐）。
  Future<List<StatementVersionRow>> allVersions() =>
      (_db.select(_db.statementVersions)
            ..where((v) => v.workspaceId.equals(_ws))
            ..orderBy([
              (v) => OrderingTerm.asc(v.statementId),
              (v) => OrderingTerm.asc(v.versionNo),
            ]))
          .get();

  /// 录入正式账单（手工录入要素作为 v1，状态"已出账"）。
  ///
  /// 校验：账单日不晚于今天（账户业务时区，G3）；到期日晚于账单日；要素的范围与一致性；同一币种子账户
  /// 同一账单日已有账单时拒绝（F-21：同一信用账户的各张卡共用一份账单；更正请用「人工修正」）。录入后，
  /// 该子账户账单日不晚于它的分期各期标为已出账。
  Future<StatementRow> recordIssued(
    StatementEntryDraft draft, {
    String? id,
  }) async {
    _checkFigures(draft.figures);
    if (draft.dueDate <= draft.statementDate) {
      throw const ValidationException('dueDate', '到期还款日须晚于账单日');
    }
    final statementId = id ?? newUuidV4();
    try {
      return await _db.transaction(() async {
        final existingById = await byId(statementId);
        if (existingById != null) {
          return existingById;
        }
        final sub =
            await (_db.select(_db.currencyAccounts)..where(
                  (c) =>
                      c.workspaceId.equals(_ws) &
                      c.id.equals(draft.currencyAccountId),
                ))
                .getSingleOrNull() ??
            (throw const NotFoundException('币种子账户'));
        final zone = await _zoneOf(sub.creditAccountId);
        if (draft.statementDate > _scope.clock.today(zone)) {
          throw const ValidationException(
            'statementDate',
            '账单日不能晚于今天（未出的账单是预测账期）',
          );
        }
        final duplicate =
            await (_db.select(_db.statements)..where(
                  (s) =>
                      s.workspaceId.equals(_ws) &
                      s.currencyAccountId.equals(sub.id) &
                      s.statementDate.equals(draft.statementDate.toString()),
                ))
                .getSingleOrNull();
        if (duplicate != null) {
          throw const ConflictException(
            '这一期账单已录入（同一信用账户的各张卡共用一份账单）；如需更正请用「人工修正」',
          );
        }
        final now = _scope.clock.nowText(zone);
        await _db
            .into(_db.statements)
            .insert(
              StatementsCompanion.insert(
                id: statementId,
                workspaceId: _ws,
                currencyAccountId: sub.id,
                statementDate: draft.statementDate.toString(),
                dueDate: draft.dueDate.toString(),
                status: StatementStatus.issued.code,
                createdAt: now,
                updatedAt: now,
              ),
            );
        final versionId = await _insertVersion(
          statementId: statementId,
          versionNo: 1,
          source: StatementSource.manual,
          figures: draft.figures,
          dueDate: draft.dueDate,
          reason: null,
          now: now,
        );
        await (_db.update(_db.statements)..where(
              (s) => s.workspaceId.equals(_ws) & s.id.equals(statementId),
            ))
            .write(StatementsCompanion(currentVersionId: Value(versionId)));
        await _markPeriodsBilled(sub.id, draft.statementDate);
        return (await byId(statementId))!;
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 人工修正：生成新版本（来源"人工修正"，理由必填，原值保留可查，R-STMT-07）；可同时更正到期日。
  /// 存储状态：已出账的变为"已修正"，其余不变（动作记录）。任何有效状态的账单都可以修正（简报 U-1 §10 的
  /// 2026-10-20 裁决放宽了 F-1 的"已还清不能修正"：录小了的账单按录的金额还清后，修正为更大的金额会重新
  /// 变为"待还"）；修正后有效状态由读模型重新推导。
  Future<StatementVersionRow> correct(
    String statementId, {
    required StatementFigures figures,
    required String reason,
    LocalDate? dueDate,
  }) async {
    _checkFigures(figures);
    final why = reason.trim();
    final problem = validateFreeText(
      why,
      required: true,
      maxLength: maxNoteLength,
      fieldName: '修正理由',
    );
    if (problem != null) {
      throw ValidationException('reason', problem);
    }
    try {
      return await _db.transaction(() async {
        final statement = await require(statementId);
        final status = StatementStatus.of(statement.status);
        final due = dueDate ?? LocalDate.parse(statement.dueDate);
        if (due <= LocalDate.parse(statement.statementDate)) {
          throw const ValidationException('dueDate', '到期还款日须晚于账单日');
        }
        final latest = (await versions(statementId)).last;
        final sub =
            await (_db.select(_db.currencyAccounts)..where(
                  (c) =>
                      c.workspaceId.equals(_ws) &
                      c.id.equals(statement.currencyAccountId),
                ))
                .getSingle();
        final now = _scope.clock.nowText(await _zoneOf(sub.creditAccountId));
        final versionId = await _insertVersion(
          statementId: statementId,
          versionNo: latest.versionNo + 1,
          source: StatementSource.correction,
          figures: figures,
          dueDate: due,
          reason: why,
          now: now,
        );
        await (_db.update(_db.statements)..where(
              (s) => s.workspaceId.equals(_ws) & s.id.equals(statementId),
            ))
            .write(
              StatementsCompanion(
                currentVersionId: Value(versionId),
                dueDate: Value(due.toString()),
                status: status == StatementStatus.issued
                    ? Value(StatementStatus.amended.code)
                    : const Value.absent(),
                rowVersion: Value(statement.rowVersion + 1),
                updatedAt: Value(now),
              ),
            );
        return (await (_db.select(
              _db.statementVersions,
            )..where((v) => v.workspaceId.equals(_ws) & v.id.equals(versionId)))
            .getSingle());
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 改账单的存储状态（状态机 PRD §6.2，动作记录；不允许的转移不写、返回 false）。由还款的银行确认（结清、
  /// 部分结清）调用；逾期等有效状态由读模型推导，不写库。
  Future<bool> moveStatus(String statementId, StatementStatus to) async {
    final statement = await require(statementId);
    final from = StatementStatus.of(statement.status);
    if (from == to || !from.canBecome(to)) {
      return false;
    }
    await (_db.update(_db.statements)
          ..where((s) => s.workspaceId.equals(_ws) & s.id.equals(statementId)))
        .write(
          StatementsCompanion(
            status: Value(to.code),
            rowVersion: Value(statement.rowVersion + 1),
            updatedAt: Value(_scope.clock.nowText()),
          ),
        );
    if (to == StatementStatus.settled) {
      await _markPeriodsSettled(
        statement.currencyAccountId,
        LocalDate.parse(statement.statementDate),
      );
    }
    return true;
  }

  Future<String> _insertVersion({
    required String statementId,
    required int versionNo,
    required StatementSource source,
    required StatementFigures figures,
    required LocalDate dueDate,
    required String? reason,
    required String now,
  }) async {
    final id = newUuidV4();
    await _db
        .into(_db.statementVersions)
        .insert(
          StatementVersionsCompanion.insert(
            id: id,
            workspaceId: _ws,
            statementId: statementId,
            versionNo: versionNo,
            sourceKind: source.code,
            previousBalanceMinor: Value(figures.previousBalanceMinor),
            newBalanceMinor: figures.newBalanceMinor,
            minDueMinor: Value(figures.minDueMinor),
            paymentsMinor: Value(figures.paymentsMinor),
            creditsMinor: Value(figures.creditsMinor),
            feesMinor: Value(figures.feesMinor),
            interestMinor: Value(figures.interestMinor),
            installmentDueMinor: Value(figures.installmentDueMinor),
            creditBalanceMinor: Value(figures.creditBalanceMinor),
            dueDate: dueDate.toString(),
            recordedBy: 'user',
            reason: Value(reason),
            recordedAt: now,
          ),
        );
    return id;
  }

  /// 该子账户账单日不晚于 [statementDate] 的分期各期：未出账 → 已出账。
  Future<void> _markPeriodsBilled(
    String currencyAccountId,
    LocalDate statementDate,
  ) => _db.customUpdate(
    'UPDATE installment_schedule SET status = ? '
    'WHERE workspace_id = ? AND status = ? AND statement_date <= ? '
    'AND plan_id IN (SELECT id FROM installment_plans WHERE workspace_id = ? '
    'AND currency_account_id = ? AND status = ?)',
    variables: <Variable<Object>>[
      Variable<String>(InstallmentPeriodStatus.billed.code),
      Variable<String>(_ws),
      Variable<String>(InstallmentPeriodStatus.scheduled.code),
      Variable<String>(statementDate.toString()),
      Variable<String>(_ws),
      Variable<String>(currencyAccountId),
      Variable<String>(InstallmentPlanStatus.active.code),
    ],
    updates: <TableInfo<Table, Object?>>{_db.installmentSchedule},
    updateKind: UpdateKind.update,
  );

  /// 账单结清时，该子账户账单日不晚于它的已出账各期 → 已结清；全部结清的计划 → 已还完。
  Future<void> _markPeriodsSettled(
    String currencyAccountId,
    LocalDate statementDate,
  ) async {
    await _db.customUpdate(
      'UPDATE installment_schedule SET status = ? '
      'WHERE workspace_id = ? AND status = ? AND statement_date <= ? '
      'AND plan_id IN (SELECT id FROM installment_plans WHERE workspace_id = ? '
      'AND currency_account_id = ? AND status = ?)',
      variables: <Variable<Object>>[
        Variable<String>(InstallmentPeriodStatus.settled.code),
        Variable<String>(_ws),
        Variable<String>(InstallmentPeriodStatus.billed.code),
        Variable<String>(statementDate.toString()),
        Variable<String>(_ws),
        Variable<String>(currencyAccountId),
        Variable<String>(InstallmentPlanStatus.active.code),
      ],
      updates: <TableInfo<Table, Object?>>{_db.installmentSchedule},
      updateKind: UpdateKind.update,
    );
    await _db.customUpdate(
      'UPDATE installment_plans SET status = ?, row_version = row_version + 1, '
      'updated_at = ? WHERE workspace_id = ? AND currency_account_id = ? '
      'AND status = ? AND NOT EXISTS (SELECT 1 FROM installment_schedule AS s '
      'WHERE s.workspace_id = installment_plans.workspace_id '
      'AND s.plan_id = installment_plans.id AND s.status <> ?)',
      variables: <Variable<Object>>[
        Variable<String>(InstallmentPlanStatus.completed.code),
        Variable<String>(_scope.clock.nowText()),
        Variable<String>(_ws),
        Variable<String>(currencyAccountId),
        Variable<String>(InstallmentPlanStatus.active.code),
        Variable<String>(InstallmentPeriodStatus.settled.code),
      ],
      updates: <TableInfo<Table, Object?>>{_db.installmentPlans},
      updateKind: UpdateKind.update,
    );
  }

  Future<BusinessTimeZone> _zoneOf(String creditAccountId) async {
    final account =
        await (_db.select(_db.creditAccounts)..where(
              (a) => a.workspaceId.equals(_ws) & a.id.equals(creditAccountId),
            ))
            .getSingle();
    return businessTimeZoneOf(account.businessTz);
  }

  void _checkFigures(StatementFigures f) {
    void range(String field, int? value, {bool signed = false}) {
      if (value == null) {
        return;
      }
      final low = signed ? -maxAmountMinor : 0;
      if (value < low || value > maxAmountMinor) {
        throw ValidationException(field, signed ? '金额超出范围' : '金额须为不小于 0 的数');
      }
    }

    range('newBalance', f.newBalanceMinor, signed: true);
    range('previousBalance', f.previousBalanceMinor, signed: true);
    range('minDue', f.minDueMinor);
    range('payments', f.paymentsMinor);
    range('credits', f.creditsMinor);
    range('fees', f.feesMinor);
    range('interest', f.interestMinor);
    range('installmentDue', f.installmentDueMinor);
    range('creditBalance', f.creditBalanceMinor);
    if ((f.creditBalanceMinor ?? 0) > 0 && f.newBalanceMinor > 0) {
      throw const ValidationException(
        'creditBalance',
        '有贷方余额（溢缴款）时，本期应还须为 0 或负数',
      );
    }
    final minDue = f.minDueMinor;
    if (minDue != null &&
        minDue > (f.newBalanceMinor > 0 ? f.newBalanceMinor : 0)) {
      throw const ValidationException('minDue', '最低还款额不能大于本期应还');
    }
  }
}
