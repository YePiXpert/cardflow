// 还款登记与核对（UF-3，I-1c 数据层；真实 sqlite3mc）：状态机 PRD §6.3 全部转移（仓库层）、F-31 双侧时间
// （现金按扣款日、负债按入账日）、F-28 额度释放（入账前不释放、时滞未知不释放）、F-32 疑似重复（处理前负债
// 只核销一次）、F-33 分配守恒、结清只由银行确认触发、「我已还款」不结清、到期无证据 → 待核对、逾期、
// 金额不符、未匹配的还款、作废登记；F-06 分期尾部责任进入资金日历。
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/mapping/ledger_mapping.dart';
import 'package:cardflow/data/repositories/card_wallet_reader.dart';
import 'package:cardflow/data/repositories/cash_account_repository.dart';
import 'package:cardflow/data/repositories/cash_event_repository.dart';
import 'package:cardflow/data/repositories/cash_forecast_reader.dart';
import 'package:cardflow/data/repositories/cash_models.dart';
import 'package:cardflow/data/repositories/installment_repository.dart';
import 'package:cardflow/data/repositories/ledger_models.dart';
import 'package:cardflow/data/repositories/ledger_reader.dart';
import 'package:cardflow/data/repositories/reconciliation_repository.dart';
import 'package:cardflow/data/repositories/repayment_repository.dart';
import 'package:cardflow/data/repositories/repository_errors.dart';
import 'package:cardflow/data/repositories/statement_repository.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow/data/time/clock.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repository_test_support.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

Timestamp t(String text) => Timestamp.parse(text);

/// 还款状态 → 仓库里把一笔"已登记"的还款推到该状态的步骤（时点都在 10-18 上午）。
Future<void> _driveTo(
  RepaymentRepository repo,
  String id,
  RepaymentStatus target,
) async {
  switch (target) {
    case RepaymentStatus.recorded:
      return;
    case RepaymentStatus.processing:
      await repo.markInitiated(id, t('2026-10-18T08:00:00+08:00'));
    case RepaymentStatus.cashDebited:
      await _driveTo(repo, id, RepaymentStatus.processing);
      await repo.confirmDebit(id, t('2026-10-18T08:30:00+08:00'));
    case RepaymentStatus.creditPosted:
      await _driveTo(repo, id, RepaymentStatus.cashDebited);
      await repo.markCreditPosted(id, t('2026-10-18T09:00:00+08:00'));
    case RepaymentStatus.bankConfirmed:
      await _driveTo(repo, id, RepaymentStatus.creditPosted);
      await repo.confirmByBank(id, t('2026-10-18T09:30:00+08:00'));
    case RepaymentStatus.reversed:
      await _driveTo(repo, id, RepaymentStatus.bankConfirmed);
      await repo.reverse(id);
    case RepaymentStatus.failed:
      await _driveTo(repo, id, RepaymentStatus.processing);
      await repo.markFailed(id);
    case RepaymentStatus.userMarkedPaid:
      await repo.markUserPaid(id);
    case RepaymentStatus.needsReview:
      await repo.markUserPaid(id);
      await repo.markNeedsReview(id);
  }
}

/// 一个仓库动作与它要到达的状态。
typedef _Action = (
  String,
  RepaymentStatus,
  Future<void> Function(RepaymentRepository, String),
);

final List<_Action> _actions = <_Action>[
  (
    '标记已发起',
    RepaymentStatus.processing,
    (r, id) => r.markInitiated(id, t('2026-10-18T10:00:00+08:00')),
  ),
  (
    '确认扣款',
    RepaymentStatus.cashDebited,
    (r, id) => r.confirmDebit(id, t('2026-10-18T10:30:00+08:00')),
  ),
  ('标记失败', RepaymentStatus.failed, (r, id) => r.markFailed(id)),
  ('重试登记', RepaymentStatus.recorded, (r, id) => r.retry(id)),
  ('我已还款', RepaymentStatus.userMarkedPaid, (r, id) => r.markUserPaid(id)),
  (
    '上传入账证据',
    RepaymentStatus.creditPosted,
    (r, id) => r.markCreditPosted(id, t('2026-10-18T11:00:00+08:00')),
  ),
  (
    '银行确认',
    RepaymentStatus.bankConfirmed,
    (r, id) => r.confirmByBank(
      id,
      t('2026-10-18T11:30:00+08:00'),
      debitedAt: t('2026-10-18T10:45:00+08:00'),
    ),
  ),
  ('到期无证据', RepaymentStatus.needsReview, (r, id) => r.markNeedsReview(id)),
  ('冲正', RepaymentStatus.reversed, (r, id) => r.reverse(id)),
];

void main() {
  late AppDatabase db;
  late WorkspaceScope scope;
  late String sub;
  late String cashId;
  late StatementRow statement;

  Future<void> setUpWith(AppClock clock) async {
    db = await openRealTestDatabase();
    scope = await createTestWorkspace(db, clock: clock);
    final card = await createTestCard(scope, last4: '1001', alias: '卡 A');
    await declareTestRule(scope, card.creditAccountId);
    sub = (await primaryCurrencyAccount(scope, card.creditAccountId)).id;
    cashId = (await createTestCashAccount(scope)).id;
    await recordTestCashSnapshot(scope, cashId, d(2026, 10, 15), 1000000);
    statement = await recordTestStatement(scope, sub, newBalance: 100000);
  }

  Future<RepaymentRow> register({
    int amount = 100000,
    RepaymentMethod method = RepaymentMethod.manual,
    LocalDate? expected,
    Map<String, int>? allocations,
  }) => registerTestRepayment(
    scope,
    currencyAccountId: sub,
    cashAccountId: cashId,
    amount: amount,
    method: method,
    expectedDebitOn: expected ?? d(2026, 10, 20),
    allocations: allocations ?? <String, int>{statement.id: amount},
  );

  group('今天 10-18', () {
    setUp(() => setUpWith(testClock));

    test('状态机（PRD §6.3）：每个状态 × 每个动作，只有登记的转移成功，其余抛 IllegalRepaymentTransitionException、'
        '状态不变', () async {
      final repo = RepaymentRepository(scope);
      var legal = 0;
      for (final from in RepaymentStatus.values) {
        for (final (name, to, action) in _actions) {
          final row = await register(amount: 1000 + legal);
          await _driveTo(repo, row.id, from);
          expect((await repo.require(row.id)).status, from.code);
          // "确认扣款"在已登记时先经"处理中"（两步都是登记的转移）。
          final allowed =
              from.canBecome(to) ||
              (to == RepaymentStatus.cashDebited &&
                  from == RepaymentStatus.recorded);
          if (allowed) {
            await action(repo, row.id);
            expect(
              (await repo.require(row.id)).status,
              to.code,
              reason: '$from → $name',
            );
            legal++;
          } else {
            await expectRepositoryError<IllegalRepaymentTransitionException>(
              () => action(repo, row.id),
            );
            expect(
              (await repo.require(row.id)).status,
              from.code,
              reason: '$from → $name 不应改变状态',
            );
          }
        }
      }
      expect(legal, 12, reason: '11 条状态机转移 + 已登记时的「确认扣款」（经处理中）');
    });

    test(
      '「我已还款」只到"用户已标记"：账单不结清、负债不核销（R-STMT-03）；银行确认后才结清，期间文案无"还款成功"',
      () async {
        final repo = RepaymentRepository(scope);
        final row = await register();
        expect(RepaymentStatus.recorded.label, '已登记（待银行确认）');
        await repo.markUserPaid(row.id);
        var data = await LedgerReader(scope).load();
        expect(data.balances[statement.id]!.remaining, 100000);
        expect(data.statement(statement.id)!.status, 'issued');
        await repo.confirmByBank(
          row.id,
          t('2026-10-18T11:00:00+08:00'),
          debitedAt: t('2026-10-18T09:00:00+08:00'),
        );
        data = await LedgerReader(scope).load();
        expect(data.statement(statement.id)!.status, 'settled');
        expect(data.balances[statement.id]!.remaining, 0);
        final event = (await CashEventRepository(scope).byRepayment(row.id))!;
        expect((event.postingStatus, event.eventOn), ('posted', '2026-10-18'));
        for (final s in RepaymentStatus.values) {
          expect(s.label, isNot(contains('成功')));
        }
      },
    );

    test('F-33：一笔还款分配到两期账单，分配和等于还款额；超过还款额、跨账户、已结清的账单都被拒', () async {
      final earlier = await recordTestStatement(
        scope,
        sub,
        statementDate: d(2026, 9, 10),
        dueDate: d(2026, 9, 28),
        newBalance: 50000,
      );
      final row = await register(
        amount: 150000,
        allocations: <String, int>{earlier.id: 50000, statement.id: 100000},
      );
      final allocations = await RepaymentRepository(scope)
          .allocationsOf(row.id);
      expect(allocations.fold<int>(0, (a, x) => a + x.amountMinor), 150000);
      final over = await expectRepositoryError<ValidationException>(
        () => register(
          amount: 1000,
          allocations: <String, int>{statement.id: 600, earlier.id: 401},
        ),
      );
      expect(over.field, 'allocations');
      final other = await createTestCard(scope, bank: '中国银行', last4: '2001');
      await declareTestRule(scope, other.creditAccountId);
      final otherSub = (await primaryCurrencyAccount(
        scope,
        other.creditAccountId,
      )).id;
      final foreign = await recordTestStatement(
        scope,
        otherSub,
        newBalance: 100,
        minDue: 10,
      );
      await expectRepositoryError<ValidationException>(
        () =>
            register(amount: 100, allocations: <String, int>{foreign.id: 100}),
      );
      // 银行确认后结清：两期都足额。
      final repo = RepaymentRepository(scope);
      await repo.confirmDebit(row.id, t('2026-10-18T09:00:00+08:00'));
      await repo.markCreditPosted(row.id, t('2026-10-18T10:00:00+08:00'));
      await repo.confirmByBank(row.id, t('2026-10-18T11:00:00+08:00'));
      final statements = StatementRepository(scope);
      expect((await statements.byId(earlier.id))!.status, 'settled');
      expect((await statements.byId(statement.id))!.status, 'settled');
      await expectRepositoryError<ValidationException>(
        () => register(
          amount: 100,
          allocations: <String, int>{statement.id: 100},
        ),
      );
      // 已结清的账单不能再修正。
      await expectRepositoryError<ConflictException>(
        () => statements.correct(
          statement.id,
          figures: const StatementFigures(newBalanceMinor: 1),
          reason: '试图修正',
        ),
      );
    });

    test('部分还款经银行确认 → 部分结清；「银行已入账」只核销负债、不结清', () async {
      final repo = RepaymentRepository(scope);
      final row = await register(amount: 40000);
      await repo.confirmDebit(row.id, t('2026-10-18T09:00:00+08:00'));
      await repo.markCreditPosted(row.id, t('2026-10-18T10:00:00+08:00'));
      var data = await LedgerReader(scope).load();
      expect(data.balances[statement.id]!.remaining, 60000);
      expect(data.statement(statement.id)!.status, 'issued');
      await repo.confirmByBank(row.id, t('2026-10-18T11:00:00+08:00'));
      data = await LedgerReader(scope).load();
      expect(data.statement(statement.id)!.status, 'partially_settled');
      expect(data.balances[statement.id]!.bankConfirmed, 40000);
    });

    test('F-32：同日、同账户、同金额的一笔自动扣款与一笔手工还款 → 疑似重复；处理前负债只核销一次；'
        '"同一笔"作废重复的登记（连带作废计划扣款）；"确为两笔"后两笔都核销', () async {
      final repo = RepaymentRepository(scope);
      final auto = await register(
        amount: 30000,
        method: RepaymentMethod.autoDebit,
        expected: d(2026, 10, 18),
      );
      final manual = await register(amount: 30000, expected: d(2026, 10, 18));
      // 不同金额、或两笔都是手工：不生成。
      await register(amount: 30001, expected: d(2026, 10, 18));
      await register(amount: 20000, expected: d(2026, 10, 19));
      var items = await ReconciliationRepository(scope).list();
      expect(items, hasLength(1));
      expect(items.single.kind, 'duplicate_repayment');
      expect(referencedRepayments(items.single).toSet(), <String>{
        auto.id,
        manual.id,
      });

      for (final id in <String>[auto.id, manual.id]) {
        await repo.confirmDebit(id, t('2026-10-18T09:00:00+08:00'));
        await repo.markCreditPosted(id, t('2026-10-18T10:00:00+08:00'));
      }
      var data = await LedgerReader(scope).load();
      expect(data.openDuplicates, hasLength(1));
      expect(data.balances[statement.id]!.credited, 30000, reason: '负债只核销一次');
      // 两笔都已扣款：不能按"同一笔"作废。
      await expectRepositoryError<ConflictException>(
        () =>
            repo.resolveDuplicate(items.single.id, voidRepaymentId: manual.id),
      );
      await repo.resolveDuplicate(items.single.id);
      data = await LedgerReader(scope).load();
      expect(data.balances[statement.id]!.credited, 60000);

      // 另一组（都还没扣款）：同一笔 → 作废手工那笔，它的计划扣款一并作废。
      final auto2 = await register(
        amount: 5000,
        method: RepaymentMethod.autoDebit,
        expected: d(2026, 10, 25),
      );
      final manual2 = await register(amount: 5000, expected: d(2026, 10, 25));
      items = await ReconciliationRepository(scope)
          .list(status: ReconciliationStatus.open);
      expect(items, hasLength(1));
      expect(
        await CashEventRepository(scope).byRepayment(manual2.id),
        isNotNull,
      );
      await repo.resolveDuplicate(items.single.id, voidRepaymentId: manual2.id);
      expect(await repo.byId(manual2.id), isNull);
      expect(await repo.byId(auto2.id), isNotNull);
      expect(await CashEventRepository(scope).byRepayment(manual2.id), isNull);
      final resolved = (await ReconciliationRepository(scope)
          .byId(items.single.id))!;
      expect(
        (resolved.status, resolved.resolution, resolved.resolvedBy),
        ('resolved', 'same_payment', 'user'),
      );
    });

    test('金额不符：确认扣款或入账的金额与登记的不同 → 差异项；已核对后关闭', () async {
      final repo = RepaymentRepository(scope);
      final row = await register(amount: 100000);
      await repo.confirmDebit(
        row.id,
        t('2026-10-18T09:00:00+08:00'),
        actualAmountMinor: 99500,
      );
      final event = (await CashEventRepository(scope).byRepayment(row.id))!;
      expect(event.amountMinor, -99500, reason: '现金侧按实际扣款金额');
      final items = await ReconciliationRepository(scope).list();
      expect(items.single.kind, 'amount_mismatch');
      expect(reconciliationRefsOf(items.single), <String, Object?>{
        'actual_minor': 99500,
        'expected_minor': 100000,
        'repayment_id': row.id,
        'side': 'cash',
      });
      await ReconciliationRepository(scope)
          .resolve(items.single.id, ReconciliationResolution.acknowledged);
      // 处理结果须是该类型可用的：金额不符不能标"退款已冲抵"。
      final other = await register(amount: 1);
      await repo.confirmDebit(other.id, t('2026-10-18T09:00:00+08:00'));
      await repo.markCreditPosted(
        other.id,
        t('2026-10-18T09:00:00+08:00'),
        creditedAmountMinor: 2,
      );
      final mismatch = (await ReconciliationRepository(
        scope,
      ).list(status: ReconciliationStatus.open)).single;
      expect(reconciliationRefsOf(mismatch)['side'], 'credit');
      await expectRepositoryError<ValidationException>(
        () =>
            ReconciliationRepository(scope)
                .resolve(mismatch.id, ReconciliationResolution.offset),
      );
    });

    test('未匹配的还款：银行记录里有一笔还款入账而没有登记 → 差异项；有同额、日期相近的登记时不生成', () async {
      await register(amount: 100000, expected: d(2026, 10, 16));
      await addTestTransaction(
        scope,
        sub,
        type: TxnType.repayment,
        amount: -100000,
        txnAt: '2026-10-17T10:00:00+08:00',
      );
      expect(await ReconciliationRepository(scope).list(), isEmpty);
      final orphan = await addTestTransaction(
        scope,
        sub,
        type: TxnType.repayment,
        amount: -12300,
        txnAt: '2026-10-17T11:00:00+08:00',
      );
      final items = await ReconciliationRepository(scope).list();
      expect(items.single.kind, 'unmatched_repayment');
      expect(referencedTransaction(items.single), orphan.id);
      // 还款入账行不进负债计算（负债按登记的还款核销）。
      expect((await LedgerReader(scope).load()).liabilities[sub]!.unbilled, 0);
    });

    test('作废登记：已登记的可作废（计划扣款一并作废）；扣款后不能作废；P-08 不能直接确认或删除还款生成的事件', () async {
      final repo = RepaymentRepository(scope);
      final row = await register();
      final event = (await CashEventRepository(scope).byRepayment(row.id))!;
      await expectRepositoryError<ConflictException>(
        () => CashEventRepository(scope).markPosted(event.id),
      );
      await expectRepositoryError<ConflictException>(
        () => CashEventRepository(scope).delete(event.id),
      );
      await repo.delete(row.id);
      expect(await repo.byId(row.id), isNull);
      expect(await CashEventRepository(scope).byRepayment(row.id), isNull);
      final debited = await register();
      await repo.confirmDebit(debited.id, t('2026-10-18T09:00:00+08:00'));
      await expectRepositoryError<ConflictException>(
        () => repo.delete(debited.id),
      );
    });

    test('登记的校验：现金账户须同币种、未停用；发起时间不晚于现在；预计扣款日不早于发起日；时点顺序；证据备注 G2', () async {
      final usd = await createTestCashAccount(
        scope,
        name: '美元户',
        currency: 'USD',
      );
      final closed = await createTestCashAccount(scope, name: '旧卡');
      await CashAccountRepository(scope)
          .setStatus(closed.id, CashAccountStatus.closed);
      Future<void> bad(RepaymentDraft draft, String field) async {
        final e = await expectRepositoryError<ValidationException>(
          () => RepaymentRepository(scope).create(draft),
        );
        expect(e.field, field);
      }

      RepaymentDraft draft({
        String? cash,
        String? initiated,
        LocalDate? expected,
        String? note,
        int amount = 100,
      }) => RepaymentDraft(
        currencyAccountId: sub,
        cashAccountId: cash ?? cashId,
        amountMinor: amount,
        method: RepaymentMethod.manual,
        allocations: <String, int>{statement.id: amount},
        initiatedAt: initiated == null ? null : t(initiated),
        expectedDebitOn: expected,
        evidenceNote: note,
      );
      await bad(draft(cash: usd.id), 'cashAccount');
      await bad(draft(cash: closed.id), 'cashAccount');
      await bad(draft(initiated: '2026-10-18T12:00:01+08:00'), 'initiatedAt');
      await bad(
        draft(
          initiated: '2026-10-18T09:00:00+08:00',
          expected: d(2026, 10, 17),
        ),
        'expectedDebitOn',
      );
      await bad(draft(note: '流水号 6222020200112233'), 'evidenceNote');
      await bad(draft(amount: 0), 'amount');
      final repo = RepaymentRepository(scope);
      final row = await repo.create(
        draft(initiated: '2026-10-18T09:00:00+08:00'),
      );
      await repo.markInitiated(row.id, t('2026-10-18T09:00:00+08:00'));
      final early = await expectRepositoryError<ValidationException>(
        () => repo.confirmDebit(row.id, t('2026-10-18T08:59:00+08:00')),
      );
      expect(early.message, '扣款时点不能早于发起时间');
      await repo.confirmDebit(row.id, t('2026-10-18T09:30:00+08:00'));
      final beforeDebit = await expectRepositoryError<ValidationException>(
        () => repo.markCreditPosted(row.id, t('2026-10-18T09:29:00+08:00')),
      );
      expect(beforeDebit.message, '入账时点不能早于扣款时点');
    });

    test('F-06：分期在窗口外的到期期次进入资金日历的尾部责任（来源 installment），窗口变大时移入窗口', () async {
      final txn = await addTestTransaction(scope, sub, amount: 1200000);
      final plan = await InstallmentRepository(scope).create(
        InstallmentDraft(
          transactionId: txn.id,
          periods: 12,
          perPeriodRate: Rational.parseDecimal('0.006'),
        ),
      );
      final reader = CashForecastReader(scope);
      final f30 = await reader.forecast(
        const CashForecastQuery(windowDays: 30),
      );
      final tail = f30.tail.where((x) => x.source == 'installment').toList();
      // 今天 10-18、窗口到 11-16：11-28 起的 12 期全部在窗口外（第 12 期 2027-10-28）。
      expect(tail, hasLength(12));
      expect(tail.first.on, d(2026, 11, 28));
      expect(tail.last.on, d(2027, 10, 28));
      expect(tail.first.amountMinor, -(100000 + 7200));
      expect(tail.first.label, '分期 第 1/12 期');
      expect(tail.first.accountName, '卡 A');
      expect(tail.first.refId, '${plan.id}/1');
      final f180 = await reader.forecast(
        const CashForecastQuery(windowDays: 180),
      );
      final beyond = f180.tail.where((x) => x.source == 'installment').toList();
      // 窗口到 2027-04-15：2027-04-28 起的 7 期在窗口外，F-06"180 天外仍列出"。
      expect(beyond.first.on, d(2027, 4, 28));
      expect(beyond, hasLength(7));
      // 只看一个现金账户时照样列出（分期不属于任何现金账户）。
      final filtered = await reader.forecast(
        CashForecastQuery(windowDays: 180, accountId: cashId),
      );
      expect(
        filtered.tail.where((x) => x.source == 'installment'),
        hasLength(7),
      );
    });
  });

  test('F-31：扣款日与入账日不同——现金时间线按扣款日生效，负债按入账日核销；F-28：入账前不释放额度，'
      '释放时滞未知时入账后也不释放', () async {
    // 今天 10-25（北京时间中午）。
    await setUpWith(FixedClock(DateTime.utc(2026, 10, 25, 4)));
    await recordTestSnapshot(
      scope,
      sub,
      fixed: 1000000,
      used: 500000,
      balanceAsOf: '2026-10-20T20:00:00+08:00',
    );
    final repo = RepaymentRepository(scope);
    final row = await register(expected: d(2026, 10, 22));
    var event = (await CashEventRepository(scope).byRepayment(row.id))!;
    expect(
      (event.cls, event.eventOn, event.amountMinor),
      ('planned', '2026-10-22', -100000),
    );

    await repo.markInitiated(row.id, t('2026-10-21T08:00:00+08:00'));
    // 现金在 10-21 已扣（早于预计）：时间线改到扣款日。
    await repo.confirmDebit(row.id, t('2026-10-21T08:30:00+08:00'));
    event = (await CashEventRepository(scope).byRepayment(row.id))!;
    expect(
      (event.cls, event.postingStatus, event.eventOn),
      ('confirmed', 'posted', '2026-10-21'),
    );
    var data = await LedgerReader(scope).load();
    expect(
      data.balances[statement.id]!.remaining,
      100000,
      reason: '扣款了但银行还没入账：负债未核销',
    );
    expect(LedgerReader.unreleasedRepayments(data, sub), 0);

    // 银行 10-23 入账：负债从 10-23 起核销。
    await repo.markCreditPosted(row.id, t('2026-10-23T09:00:00+08:00'));
    data = await LedgerReader(scope).load();
    final allocations = data.allocations;
    final repayments = {for (final r in data.repayments) r.id: r};
    int paidOn(LocalDate on) => paidOnStatement(
      statementId: statement.id,
      allocations: allocations,
      repayments: repayments,
      creditDates: data.creditDates,
      on: on,
    );
    expect(data.creditDates[row.id], d(2026, 10, 23));
    expect(paidOn(d(2026, 10, 22)), 0);
    expect(paidOn(d(2026, 10, 23)), 100000);
    expect(data.balances[statement.id]!.remaining, 0);

    // 现金时间线：10-21 当日流出（快照 10-15）。
    final forecast = await CashForecastReader(scope)
        .forecast(const CashForecastQuery(windowDays: 30));
    final day = forecast.accounts.single.days.firstWhere(
      (x) => x.on == d(2026, 10, 21),
    );
    expect(day.outflow, -100000);

    // F-28：释放时滞未知 → 不释放，可用容量仍按快照（10,000 − 5,000 = 5,000）。
    expect(LedgerReader.unreleasedRepayments(data, sub), 100000);
    final wallet = await CardWalletReader(scope).load();
    expect(wallet.accounts.single.primaryCurrency.capacity, 500000);
    final snapshotDate = d(2026, 10, 20);
    int released(LocalDate on, int? lag, {LocalDate? snap}) =>
        releasedRepaymentsOn(
          repayments: data.repayments,
          creditDates: data.creditDates,
          snapshotDate: snap ?? snapshotDate,
          on: on,
          releaseLagDays: lag,
        );
    expect(released(d(2026, 10, 25), null), 0, reason: '时滞未知 → 保守不释放');
    expect(released(d(2026, 10, 23), 1), 0, reason: '入账日 + 1 天之前不释放');
    expect(released(d(2026, 10, 24), 1), 100000);
    expect(
      released(d(2026, 10, 24), 1, snap: d(2026, 10, 23)),
      0,
      reason: '快照日及以前入账的已反映在快照里',
    );
  });

  test(
    '到期后：未还清的账单 → 已逾期；"用户已标记"仍无证据 → 待核对（UF-3 步骤 6）；取得证据后银行确认 → 结清',
    () async {
      // 今天 10-30，账单 10-28 到期。
      await setUpWith(FixedClock(DateTime.utc(2026, 10, 30, 4)));
      final repo = RepaymentRepository(scope);
      final row = await register(expected: d(2026, 10, 27));
      await repo.markUserPaid(row.id);
      final data = await LedgerReader(scope).load();
      expect(data.statement(statement.id)!.status, 'overdue');
      expect((await repo.require(row.id)).status, 'needs_review');
      expect(data.awaitingEvidence.map((r) => r.id), <String>[row.id]);
      // 再读一次不再写库（没有要改的）。
      await LedgerReader(scope).load();
      await expectRepositoryError<ValidationException>(
        () => repo.confirmByBank(row.id, t('2026-10-29T10:00:00+08:00')),
      );
      await repo.confirmByBank(
        row.id,
        t('2026-10-29T10:00:00+08:00'),
        debitedAt: t('2026-10-27T09:00:00+08:00'),
      );
      final after = await LedgerReader(scope).load();
      expect(after.statement(statement.id)!.status, 'settled');
      expect(
        (await repo.require(row.id)).creditPostedAt,
        '2026-10-29T10:00:00+08:00',
      );
    },
  );
}
