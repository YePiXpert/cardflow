import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../ids.dart';
import '../mapping/domain_mapping.dart';
import '../mapping/ledger_mapping.dart';
import '../time/business_tz.dart';
import '../time/clock.dart';
import 'ledger_models.dart';
import 'models.dart';
import 'repository_errors.dart';
import 'workspace_scope.dart';

/// 把一笔消费转成分期的输入（R-STMT-10）。
@immutable
final class InstallmentDraft {
  const InstallmentDraft({
    required this.transactionId,
    required this.periods,
    required this.perPeriodRate,
    this.feeMode = InstallmentFeeMode.perPeriod,
    this.remainderTo = RemainderTo.last,
    this.principalMinor,
    this.firstStatementOn,
  });

  final String transactionId;

  /// 期数 1–60。
  final int periods;

  /// 每期费率（0 ≤ 费率 < 1，至多 10 位小数）。
  final Rational perPeriodRate;
  final InstallmentFeeMode feeMode;

  /// 尾差加到末期（默认，建行口径）或首期。
  final RemainderTo remainderTo;

  /// 分期本金（默认 = 交易金额；不能超过它）。
  final int? principalMinor;

  /// 第 1 期所在的账单日（默认：交易入账日与今天中较晚者所在的账期）；必须是规则给出的账单日，且不早于
  /// 交易本身的账期。
  final LocalDate? firstStatementOn;
}

/// 分期计划与各期（当前工作空间）。条款建好后不可改（触发器）；各期本金与费用由领域包
/// `installment.dart` 计算（与 Python `money.py` 同义，F-36）；各期所在账单日按账户的账期规则逐期推出
/// （已出账单优先，领域包 `resolveCycle`）。
final class InstallmentRepository {
  InstallmentRepository(this._scope);

  final WorkspaceScope _scope;

  AppDatabase get _db => _scope.db;
  String get _ws => _scope.workspaceId;

  /// 分期计划（可只取某币种子账户的），按建立时间。
  Future<List<InstallmentPlanRow>> plans({String? currencyAccountId}) =>
      (_db.select(_db.installmentPlans)
            ..where(
              (p) =>
                  p.workspaceId.equals(_ws) &
                  (currencyAccountId == null
                      ? const Constant(true)
                      : p.currencyAccountId.equals(currencyAccountId)),
            )
            ..orderBy([
              (p) => OrderingTerm.asc(p.createdAt),
              (p) => OrderingTerm.asc(p.rowId),
            ]))
          .get();

  Future<InstallmentPlanRow?> byId(String id) =>
      (_db.select(_db.installmentPlans)
            ..where((p) => p.workspaceId.equals(_ws) & p.id.equals(id)))
          .getSingleOrNull();

  Future<InstallmentPlanRow> require(String id) async =>
      await byId(id) ?? (throw const NotFoundException('分期计划'));

  /// 某交易的分期计划。
  Future<InstallmentPlanRow?> byTransaction(String transactionId) =>
      (_db.select(_db.installmentPlans)..where(
            (p) =>
                p.workspaceId.equals(_ws) &
                p.transactionId.equals(transactionId),
          ))
          .getSingleOrNull();

  /// 某计划的各期，按期号。
  Future<List<InstallmentScheduleRow>> schedule(String planId) =>
      (_db.select(_db.installmentSchedule)
            ..where((s) => s.workspaceId.equals(_ws) & s.planId.equals(planId))
            ..orderBy([(s) => OrderingTerm.asc(s.periodNo)]))
          .get();

  /// 本工作空间的全部各期（读模型一次取齐）。
  Future<List<InstallmentScheduleRow>> allPeriods() =>
      (_db.select(_db.installmentSchedule)
            ..where((s) => s.workspaceId.equals(_ws))
            ..orderBy([
              (s) => OrderingTerm.asc(s.planId),
              (s) => OrderingTerm.asc(s.periodNo),
            ]))
          .get();

  /// 把一笔消费转成分期（幂等：同一个 [id] 再次保存直接返回已建的）。
  ///
  /// 校验：交易是消费且未删除、没有转过分期；本金为正且不超过交易金额；期数 1–60；费率 0 ≤ r < 1、至多
  /// 10 位小数；账户有可用的账期规则（没有规则时无法排出各期）。已出账单覆盖的各期直接标为已出账。
  Future<InstallmentPlanRow> create(
    InstallmentDraft draft, {
    String? id,
  }) async {
    if (draft.periods < 1 || draft.periods > 60) {
      throw const ValidationException('periods', '期数须为 1–60');
    }
    final rate = draft.perPeriodRate;
    if (rate.isNegative || rate >= Rational.one) {
      throw const ValidationException('rate', '每期费率须不小于 0、小于 100%');
    }
    final String rateText;
    try {
      rateText = decimalText(rate);
    } on ArgumentError {
      throw const ValidationException('rate', '每期费率须是有限小数');
    }
    if (rateText.length > 12) {
      throw const ValidationException('rate', '每期费率至多 10 位小数');
    }
    final planId = id ?? newUuidV4();
    try {
      return await _db.transaction(() async {
        final existing = await byId(planId);
        if (existing != null) {
          return existing;
        }
        final txn =
            await (_db.select(_db.cardTransactions)..where(
                  (t) =>
                      t.workspaceId.equals(_ws) &
                      t.id.equals(draft.transactionId) &
                      t.deletedAt.isNull(),
                ))
                .getSingleOrNull() ??
            (throw const NotFoundException('交易'));
        if (txn.txnType != TxnType.purchase.code) {
          throw const ValidationException('transaction', '只有消费可以转分期');
        }
        if (await byTransaction(txn.id) != null) {
          throw const ConflictException('这笔消费已经转过分期');
        }
        final principal = draft.principalMinor ?? txn.amountMinor;
        if (principal <= 0 || principal > txn.amountMinor) {
          throw const ValidationException('principal', '分期本金须大于 0、不超过消费金额');
        }
        final context = await _ruleContext(txn.currencyAccountId);
        final zone = context.zone;
        final base = txn.postedOn == null
            ? txnDateOf(txn, zone)
            : LocalDate.parse(txn.postedOn!);
        final cycles = _cycles(
          context,
          base: base,
          first: draft.firstStatementOn,
          today: _scope.clock.today(zone),
          count: draft.periods,
        );
        final periods = installmentPeriodsOf(
          principalMinor: principal,
          periods: draft.periods,
          perPeriodRate: rate,
          feeMode: draft.feeMode,
          remainderTo: draft.remainderTo,
        );
        final latestIssued = context.issued.isEmpty
            ? null
            : context.issued
                  .map((s) => s.statementDate)
                  .reduce((a, b) => a > b ? a : b);
        final now = _scope.clock.nowText(zone);
        await _db
            .into(_db.installmentPlans)
            .insert(
              InstallmentPlansCompanion.insert(
                id: planId,
                workspaceId: _ws,
                currencyAccountId: txn.currencyAccountId,
                transactionId: txn.id,
                principalMinor: principal,
                periods: draft.periods,
                perPeriodRate: rateText,
                feeMode: draft.feeMode.code,
                remainderPolicy: draft.remainderTo.code,
                rounding: RoundingMode.halfUp.code,
                status: InstallmentPlanStatus.active.code,
                createdAt: now,
                updatedAt: now,
              ),
            );
        for (var k = 0; k < periods.length; k++) {
          final cycle = cycles[k];
          final billed =
              latestIssued != null && cycle.statementDate <= latestIssued;
          await _db
              .into(_db.installmentSchedule)
              .insert(
                InstallmentScheduleCompanion.insert(
                  workspaceId: _ws,
                  planId: planId,
                  periodNo: periods[k].periodNo,
                  principalMinor: periods[k].principal,
                  feeMinor: periods[k].fee,
                  statementDate: cycle.statementDate.toString(),
                  dueDate: cycle.dueDate.toString(),
                  status: billed
                      ? InstallmentPeriodStatus.billed.code
                      : InstallmentPeriodStatus.scheduled.code,
                ),
              );
        }
        return (await byId(planId))!;
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 作废分期计划（录错了）：只有各期都还没出账时可以作废；原交易重新按一笔消费计入未出账。
  Future<void> cancel(String planId) async {
    try {
      await _db.transaction(() async {
        final plan = await require(planId);
        if (plan.status != InstallmentPlanStatus.active.code) {
          throw const ConflictException('只有进行中的分期可以作废');
        }
        final periods = await schedule(planId);
        if (periods.any(
          (p) => p.status != InstallmentPeriodStatus.scheduled.code,
        )) {
          throw const ConflictException('已有出账的期次，不能作废（提前结清在后续版本提供）');
        }
        await (_db.update(_db.installmentSchedule)..where(
              (s) => s.workspaceId.equals(_ws) & s.planId.equals(planId),
            ))
            .write(
              InstallmentScheduleCompanion(
                status: Value(InstallmentPeriodStatus.cancelled.code),
              ),
            );
        await (_db.update(
          _db.installmentPlans,
        )..where((p) => p.workspaceId.equals(_ws) & p.id.equals(planId))).write(
          InstallmentPlansCompanion(
            status: Value(InstallmentPlanStatus.cancelled.code),
            rowVersion: Value(plan.rowVersion + 1),
            updatedAt: Value(_scope.clock.nowText()),
          ),
        );
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 第 1 期起连续 [count] 个账期：每期从上一期账单日的次日入账推出（已出账单优先）。
  List<Cycle> _cycles(
    _RuleContext context, {
    required LocalDate base,
    required LocalDate? first,
    required LocalDate today,
    required int count,
  }) {
    final rules = context.versions.map(billingRuleFromRow).toList();
    Cycle at(LocalDate posting) {
      try {
        return resolveCycle(rules, context.issued, posting);
      } on BillingRuleError {
        throw const ValidationException(
          'rule',
          '账期规则给不出这期的账单日（规则非法或不生效），请先在账户设置里核对',
        );
      }
    }

    final own = at(base);
    Cycle start;
    if (first == null) {
      start = at(base > today ? base : today);
    } else {
      start = at(first.addDays(-1));
      if (start.statementDate != first) {
        throw const ValidationException(
          'firstStatementOn',
          '首期账单日须是账期规则给出的账单日',
        );
      }
      if (first < own.statementDate) {
        throw const ValidationException('firstStatementOn', '首期不能早于这笔消费本身的账期');
      }
    }
    final cycles = <Cycle>[start];
    while (cycles.length < count) {
      cycles.add(at(cycles.last.statementDate.addDays(1)));
    }
    return cycles;
  }

  Future<_RuleContext> _ruleContext(String currencyAccountId) async {
    final sub =
        await (_db.select(_db.currencyAccounts)..where(
              (c) => c.workspaceId.equals(_ws) & c.id.equals(currencyAccountId),
            ))
            .getSingle();
    final account =
        await (_db.select(_db.creditAccounts)..where(
              (a) =>
                  a.workspaceId.equals(_ws) & a.id.equals(sub.creditAccountId),
            ))
            .getSingle();
    Future<List<BillingRuleVersionRow>> rulesOf(RuleSubject subject) =>
        (_db.select(_db.billingRuleVersions)
              ..where(
                (r) =>
                    r.workspaceId.equals(_ws) &
                    r.subjectKind.equals(subject.kind.code) &
                    r.subjectId.equals(subject.id),
              )
              ..orderBy([(r) => OrderingTerm.asc(r.version)]))
            .get();
    final own = await rulesOf(RuleSubject.currencyAccount(sub.id));
    final versions = own.isNotEmpty
        ? own
        : await rulesOf(RuleSubject.creditAccount(account.id));
    if (versions.isEmpty) {
      throw const ValidationException('rule', '这个账户还没有账期规则：先在账户设置里设置账单日与到期日');
    }
    final statements =
        await (_db.select(_db.statements)..where(
              (s) =>
                  s.workspaceId.equals(_ws) &
                  s.currencyAccountId.equals(sub.id),
            ))
            .get();
    return _RuleContext(
      zone: businessTimeZoneOf(account.businessTz),
      versions: versions,
      issued: <IssuedStatement>[
        for (final s in statements)
          IssuedStatement(
            LocalDate.parse(s.statementDate),
            LocalDate.parse(s.dueDate),
            'statement',
          ),
      ],
    );
  }
}

final class _RuleContext {
  const _RuleContext({
    required this.zone,
    required this.versions,
    required this.issued,
  });

  final BusinessTimeZone zone;
  final List<BillingRuleVersionRow> versions;
  final List<IssuedStatement> issued;
}
