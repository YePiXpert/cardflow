// I-1 阶段末审查（evidence/i1/review-i1.md）探针改写的正式测试：探针断言的是 0.0.1 的错误行为，这里断言
// PRD §6.2 的 2026-10-19 裁决段（账单接续、本期剩余应还、有效状态）与简报 F-1 的期望值。真实 sqlite3mc，
// 金额全部是合成数据。已出账消费转分期（P1、P1b）在 ledger_test.dart 的 F-30 组。
//
// - R-02：P3 迟付（入账日晚于 10 月账单日）→ 10 月剩余应还 500、总负债 500，9 月"已并入 10-10 账单"；
//   0.0.1 已存的分配到旧账单的还款照常读出、金额按入账日期；P3b 10 月按 1,500 还清 → 10 月"已还清"，9 月
//   不在近期到期；P4 09-25 的还款早于 10 月账单日 → 10 月剩余应还仍 800、"待还"、在近期到期里。
// - R-03：冲正后（10-18）剩余应还 1,000、"待还"、在近期到期里；11-05 → "已逾期"。
// - R-06：M1 部分还款后人工修正为已还的金额 → "已还清"，不在近期到期；"已还清"的不能再修正、冲正后又可以。
// - R-07：M2 删除退款交易、M4 直接作废疑似重复中的一笔 → 引用它们的差异项由系统标为已处理并写明原因。
// - R-08：M3 删除已有交易的非主币种子账户 → 给出说明（ConflictException），不抛未包装的异常。
// - Q-3：入账日未知、可能账期跨过本期账单日 → "可能已出账"（负债按未出账计）；补入账日后归入确定的账期。
// - F-33（裁决调整）：还款只分配到本期，分到已并入下一期的旧账单被拒；本期已还清也可以再分配（多还）。
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/repositories/credit_account_repository.dart';
import 'package:cardflow/data/repositories/ledger_models.dart';
import 'package:cardflow/data/repositories/ledger_reader.dart';
import 'package:cardflow/data/repositories/reconciliation_repository.dart';
import 'package:cardflow/data/repositories/repayment_repository.dart';
import 'package:cardflow/data/repositories/repository_errors.dart';
import 'package:cardflow/data/repositories/statement_repository.dart';
import 'package:cardflow/data/repositories/transaction_repository.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow/data/time/clock.dart';
import 'package:cardflow/features/statements/ledger_formatting.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repository_test_support.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

Timestamp t(String text) => Timestamp.parse(text);

void main() {
  late AppDatabase db;
  late WorkspaceScope scope;
  late String sub;
  late String cash;

  setUp(() async {
    db = await openRealTestDatabase();
    scope = await createTestWorkspace(db); // 今天 = 2026-10-18（北京时间 12:00）
    final card = await createTestCard(scope, alias: '卡 A');
    await declareTestRule(scope, card.creditAccountId); // 10 日出账、当月 28 日到期
    sub = (await primaryCurrencyAccount(scope, card.creditAccountId)).id;
    cash = (await createTestCashAccount(scope)).id;
  });

  /// 银行确认一笔还款：扣款、入账在 [on] 的 09:00/10:00，确认在 [confirmedOn] 10:00。
  Future<void> confirm(
    String repaymentId,
    String on, {
    String? confirmedOn,
  }) async {
    final repo = RepaymentRepository(scope);
    await repo.confirmDebit(repaymentId, t('${on}T09:00:00+08:00'));
    await repo.markCreditPosted(repaymentId, t('${on}T10:00:00+08:00'));
    await repo.confirmByBank(
      repaymentId,
      t('${confirmedOn ?? on}T10:00:00+08:00'),
    );
  }

  Future<StatementRow> september() => recordTestStatement(
    scope,
    sub,
    statementDate: d(2026, 9, 10),
    dueDate: d(2026, 9, 28),
    newBalance: 100000,
    minDue: 10000,
  );

  group('R-02 账单接续与本期剩余应还', () {
    test(
      'P3 迟付：9 月 1,000 没还，10 月新增账单 1,500（含 9 月）；9 月那笔 10-12 入账 → 10 月剩余应还 500、'
      '"已还一部分"、总负债 500；9 月"已并入 10-10 账单"，不计入负债、不进近期到期',
      () async {
        final sep = await september();
        // 9 月还是本期时登记（还款只分配到本期），之后 10 月账单出账。
        final latePayment = await registerTestRepayment(
          scope,
          currencyAccountId: sub,
          cashAccountId: cash,
          amount: 100000,
          statementId: sep.id,
          expectedDebitOn: d(2026, 10, 12),
        );
        final oct = await recordTestStatement(
          scope,
          sub,
          newBalance: 150000,
          minDue: 15000,
        );
        var data = await LedgerReader(scope).load();
        expect(data.statusOf(sep.id), EffectiveStatementStatus.merged);
        expect(data.balances[sep.id]!.mergedInto, d(2026, 10, 10));
        expect(effectiveStatusText(data.balances[sep.id]!), '已并入 10-10 账单');
        expect(data.balances[sep.id]!.remaining, 0);
        expect(data.liabilities[sub]!.total, 150000, reason: '登记了、还没入账');
        expect(data.upcoming().map((b) => b.statement.id), <String>[oct.id]);

        await confirm(latePayment.id, '2026-10-12', confirmedOn: '2026-10-13');
        data = await LedgerReader(scope).load();
        final l = data.liabilities[sub]!;
        expect(data.balances[oct.id]!.paidAfter, 100000);
        expect((l.currentDue, l.total), (50000, 50000));
        expect(data.statusOf(oct.id), EffectiveStatementStatus.partiallyPaid);
        expect(data.statusOf(sep.id), EffectiveStatementStatus.merged);
        expect(
          data.upcoming().map((b) => (b.statement.id, b.remaining)),
          <(String, int)>[(oct.id, 50000)],
        );
      },
    );

    test('0.0.1 已存的、分配到旧账单的还款照常读出：金额按入账日期计算，不按分配', () async {
      final sep = await september();
      final oct = await recordTestStatement(
        scope,
        sub,
        newBalance: 150000,
        minDue: 15000,
      );
      // 0.0.1 允许在 10 月出账之后把还款分配到 9 月：直接写库模拟这份旧数据（银行确认，10-12 入账）。
      const ts = '2026-10-12T10:00:00+08:00';
      await db.customStatement(
        'INSERT INTO repayments (id, workspace_id, currency_account_id, amount_minor, currency, status, '
        'method, payment_initiated_at, cash_debited_at, credit_posted_at, bank_confirmed_at, created_at, '
        "updated_at) VALUES ('legacy-r', ?, ?, 100000, 'CNY', 'bank_confirmed', 'manual', ?, ?, ?, ?, ?, ?)",
        <Object>[scope.workspaceId, sub, ts, ts, ts, ts, ts, ts],
      );
      await db.customStatement(
        'INSERT INTO repayment_allocations (workspace_id, currency_account_id, repayment_id, statement_id, '
        "amount_minor) VALUES (?, ?, 'legacy-r', ?, 100000)",
        <Object>[scope.workspaceId, sub, sep.id],
      );
      final data = await LedgerReader(scope).load();
      expect(data.allocationsOf('legacy-r').single.statementId, sep.id);
      expect(data.balances[oct.id]!.remaining, 50000);
      expect(data.liabilities[sub]!.total, 50000);
      expect(data.statusOf(sep.id), EffectiveStatementStatus.merged);
    });

    test(
      'P3b 10 月按全额 1,500 还清（10-12 入账、银行确认）→ 10 月"已还清"、总负债 0；9 月不在近期到期',
      () async {
        final sep = await september();
        final oct = await recordTestStatement(
          scope,
          sub,
          newBalance: 150000,
          minDue: 15000,
        );
        final full = await registerTestRepayment(
          scope,
          currencyAccountId: sub,
          cashAccountId: cash,
          amount: 150000,
          statementId: oct.id,
          expectedDebitOn: d(2026, 10, 12),
        );
        await confirm(full.id, '2026-10-12', confirmedOn: '2026-10-13');
        final data = await LedgerReader(scope).load();
        expect(data.statusOf(oct.id), EffectiveStatementStatus.paid);
        expect(data.balances[oct.id]!.remaining, 0);
        expect(data.liabilities[sub]!.total, 0);
        expect(data.statusOf(sep.id), EffectiveStatementStatus.merged);
        expect(data.upcoming(), isEmpty);
      },
    );

    test(
      'P4 09-25 就还过的 1,500（10 月新增账单 800 已扣除它）补登并分配到 10 月 → 10 月剩余应还仍 800、"待还"、'
      '在近期到期里；总负债 800',
      () async {
        final oct = await recordTestStatement(
          scope,
          sub,
          newBalance: 80000,
          minDue: 8000,
        );
        final early = await registerTestRepayment(
          scope,
          currencyAccountId: sub,
          cashAccountId: cash,
          amount: 150000,
          statementId: oct.id,
          expectedDebitOn: d(2026, 9, 25),
          initiatedAt: '2026-09-25T08:00:00+08:00',
        );
        await confirm(early.id, '2026-09-25', confirmedOn: '2026-09-26');
        final data = await LedgerReader(scope).load();
        expect(data.creditDates[early.id], d(2026, 9, 25));
        expect(data.balances[oct.id]!.paidAfter, 0, reason: '入账日不晚于账单日：不扣减');
        expect(data.balances[oct.id]!.remaining, 80000);
        expect(data.statusOf(oct.id), EffectiveStatementStatus.due);
        expect(data.upcoming().map((b) => b.statement.id), <String>[oct.id]);
        expect(data.liabilities[sub]!.total, 80000);
      },
    );
  });

  group('R-03 冲正', () {
    test('10-10 账单 1,000 → 银行确认还清 → 冲正：10-18 剩余应还 1,000、"待还"、在近期到期里；11-05（已过 10-28 到期日）'
        '→ "已逾期"、仍在近期到期里', () async {
      final s = await recordTestStatement(scope, sub, newBalance: 100000);
      final r = await registerTestRepayment(
        scope,
        currencyAccountId: sub,
        cashAccountId: cash,
        amount: 100000,
        statementId: s.id,
        expectedDebitOn: d(2026, 10, 15),
      );
      await confirm(r.id, '2026-10-15', confirmedOn: '2026-10-16');
      var data = await LedgerReader(scope).load();
      expect(data.statusOf(s.id), EffectiveStatementStatus.paid);
      expect(data.upcoming(), isEmpty);

      await RepaymentRepository(scope).reverse(r.id);
      data = await LedgerReader(scope).load();
      expect(data.statement(s.id)!.status, 'settled', reason: '存储状态是动作记录');
      expect(data.balances[s.id]!.remaining, 100000);
      expect(data.statusOf(s.id), EffectiveStatementStatus.due);
      expect(data.upcoming().map((b) => b.statement.id), <String>[s.id]);
      expect(data.liabilities[sub]!.total, 100000);

      final later = WorkspaceScope(
        db: db,
        workspaceId: scope.workspaceId,
        clock: FixedClock(DateTime.utc(2026, 11, 5, 4)),
      );
      data = await LedgerReader(later).load();
      expect(data.statusOf(s.id), EffectiveStatementStatus.overdue);
      expect(data.balances[s.id]!.remaining, 100000);
      expect(data.upcoming().map((b) => b.statement.id), <String>[s.id]);
    });
  });

  group('R-06 人工修正后重新推导', () {
    test('M1 账单 1,000、银行确认还了 800（"已还一部分"）→ 银行调整后修正为 800 → "已还清"、剩余应还 0、'
        '不在近期到期', () async {
      final s = await recordTestStatement(scope, sub, newBalance: 100000);
      final r = await registerTestRepayment(
        scope,
        currencyAccountId: sub,
        cashAccountId: cash,
        amount: 80000,
        statementId: s.id,
        expectedDebitOn: d(2026, 10, 15),
      );
      await confirm(r.id, '2026-10-15', confirmedOn: '2026-10-16');
      var data = await LedgerReader(scope).load();
      expect(data.statusOf(s.id), EffectiveStatementStatus.partiallyPaid);
      expect(data.upcoming().single.remaining, 20000);

      await StatementRepository(scope).correct(
        s.id,
        figures: const StatementFigures(newBalanceMinor: 80000),
        reason: '退货冲抵后银行调整',
      );
      data = await LedgerReader(scope).load();
      expect(data.statusOf(s.id), EffectiveStatementStatus.paid);
      expect(data.balances[s.id]!.remaining, 0);
      expect(data.upcoming(), isEmpty);

      // 简报 U-1 §10 裁决：任何有效状态的账单都可以修正（新版本、理由必填、原值可查），之后重新推导。改小到
      // 700：已还的 800 多出 100，仍"已还清"并有贷方余额。冲正后剩余应还 > 0。
      await StatementRepository(scope).correct(
        s.id,
        figures: const StatementFigures(newBalanceMinor: 70000),
        reason: '再改一次',
      );
      data = await LedgerReader(scope).load();
      expect(data.statusOf(s.id), EffectiveStatementStatus.paid);
      expect(data.balances[s.id]!.creditBalance, 10000);
      await RepaymentRepository(scope).reverse(r.id);
      await StatementRepository(scope).correct(
        s.id,
        figures: const StatementFigures(newBalanceMinor: 80000),
        reason: '冲正后按银行账单重录',
      );
      data = await LedgerReader(scope).load();
      expect(data.versions[s.id], hasLength(4));
      expect(data.statusOf(s.id), EffectiveStatementStatus.due);
    });

    test('简报 U-1 §10 裁决：录小了的账单按录的金额还清（银行确认）后，修正为更大的金额 → 重新变为"待还"并进近期到期；'
        '原值可查', () async {
      final s = await recordTestStatement(
        scope,
        sub,
        newBalance: 80000,
        minDue: 8000,
      );
      final r = await registerTestRepayment(
        scope,
        currencyAccountId: sub,
        cashAccountId: cash,
        amount: 80000,
        statementId: s.id,
        expectedDebitOn: d(2026, 10, 15),
      );
      await confirm(r.id, '2026-10-15', confirmedOn: '2026-10-16');
      var data = await LedgerReader(scope).load();
      expect(data.statusOf(s.id), EffectiveStatementStatus.paid);
      expect(data.upcoming(), isEmpty);

      await StatementRepository(scope).correct(
        s.id,
        figures: const StatementFigures(newBalanceMinor: 100000),
        reason: '少录了一笔 200 的消费，按纸质账单更正',
      );
      data = await LedgerReader(scope).load();
      expect(data.statusOf(s.id), EffectiveStatementStatus.partiallyPaid);
      expect(data.balances[s.id]!.remaining, 20000);
      expect(data.upcoming().single.statement.id, s.id);
      final versions = data.versions[s.id]!;
      expect(versions.map((v) => v.newBalanceMinor), <int>[80000, 100000]);
      expect(versions.last.reason, '少录了一笔 200 的消费，按纸质账单更正');
    });
  });

  group('R-07 删除与作废后由系统处理差异项', () {
    test('M2 删除一笔退款交易 → 它的"退款待核对"由系统标为已处理（处理者系统、写明"引用的交易已删除"），'
        '不再计入待办', () async {
      final refund = await addTestTransaction(
        scope,
        sub,
        type: TxnType.refund,
        amount: -5000,
      );
      var data = await LedgerReader(scope).load();
      expect(data.openItems.map((i) => i.kind), <String>['refund_pending']);
      await TransactionRepository(scope).delete(refund.id);
      data = await LedgerReader(scope).load();
      expect(data.transaction(refund.id), isNull);
      expect(data.openItems, isEmpty);
      final item = data.items.single;
      expect(
        (item.status, item.resolution, item.resolvedBy),
        ('resolved', 'dismissed', 'system'),
      );
      expect(data.systemCloseReason(item), '引用的交易已删除');
    });

    test('M4 同日同额的自动扣款与手工还款（疑似重复）→ 在还款详情直接「作废登记」手工那笔 → 差异项由系统标为已处理'
        '（写明"引用的还款登记已作废"）；按差异项"同一笔"作废时仍记为本机用户的处理', () async {
      final s = await recordTestStatement(scope, sub, newBalance: 100000);
      Future<RepaymentRow> register(RepaymentMethod method, LocalDate on) =>
          registerTestRepayment(
            scope,
            currencyAccountId: sub,
            cashAccountId: cash,
            amount: 100000,
            statementId: s.id,
            method: method,
            expectedDebitOn: on,
          );
      await register(RepaymentMethod.autoDebit, d(2026, 10, 15));
      final manual = await register(RepaymentMethod.manual, d(2026, 10, 15));
      var data = await LedgerReader(scope).load();
      expect(data.openItems.map((i) => i.kind), <String>[
        'duplicate_repayment',
      ]);
      await RepaymentRepository(scope).delete(manual.id);
      data = await LedgerReader(scope).load();
      expect(data.repayments, hasLength(1));
      expect(data.openItems, isEmpty);
      final closed = data.items.single;
      expect(closed.resolvedBy, 'system');
      expect(data.systemCloseReason(closed), '引用的还款登记已作废');

      // 另一组：经差异项处理"同一笔"（用户的判断），不被系统的处理覆盖。
      await register(RepaymentMethod.autoDebit, d(2026, 10, 25));
      final manual2 = await register(RepaymentMethod.manual, d(2026, 10, 25));
      final open = (await ReconciliationRepository(
        scope,
      ).list(status: ReconciliationStatus.open)).single;
      await RepaymentRepository(scope)
          .resolveDuplicate(open.id, voidRepaymentId: manual2.id);
      final resolved = (await ReconciliationRepository(scope).byId(open.id))!;
      expect(
        (resolved.status, resolved.resolution, resolved.resolvedBy),
        ('resolved', 'same_payment', 'user'),
      );
    });
  });

  group('R-08 删除币种子账户', () {
    test('M3 USD 子账户已有一笔交易 → 删除被拒并说明（ConflictException，不是未包装的数据库异常）；'
        '交易删除（tombstone）后仍被引用，照样拒绝；没有任何记录的可以删除', () async {
      final card = await createTestCard(scope, bank: '中国银行', last4: '2001');
      final accounts = CreditAccountRepository(scope);
      final usd = await accounts.addCurrencyAccount(
        card.creditAccountId,
        'USD',
      );
      final txn = await addTestTransaction(scope, usd.id, amount: 1000);
      final refused = await expectRepositoryError<ConflictException>(
        () => accounts.removeCurrencyAccount(usd.id),
      );
      expect(refused.message, contains('交易'));
      await TransactionRepository(scope).delete(txn.id);
      await expectRepositoryError<ConflictException>(
        () => accounts.removeCurrencyAccount(usd.id),
      );
      final eur = await accounts.addCurrencyAccount(
        card.creditAccountId,
        'EUR',
      );
      await accounts.removeCurrencyAccount(eur.id);
      expect(
        (await accounts.currencyAccounts(card.creditAccountId))
            .map((c) => c.currency),
        containsAll(<String>['CNY', 'USD']),
      );
      expect(
        (await accounts.currencyAccounts(card.creditAccountId))
            .map((c) => c.currency),
        isNot(contains('EUR')),
      );
    });

    test('有账单的子账户同样拒绝，说明写出是哪类记录', () async {
      final card = await createTestCard(scope, bank: '中国银行', last4: '2002');
      final accounts = CreditAccountRepository(scope);
      final usd = await accounts.addCurrencyAccount(
        card.creditAccountId,
        'USD',
      );
      await recordTestStatement(scope, usd.id, newBalance: 100, minDue: 10);
      final refused = await expectRepositoryError<ConflictException>(
        () => accounts.removeCurrencyAccount(usd.id),
      );
      expect(refused.message, '该子账户已有账单记录，不能删除（删除会丢失这些记录）');
    });
  });

  group('Q-3 入账日未知的交易', () {
    test('可能账期跨过本期账单日（10-10 或 11-10）→ "可能已出账"，负债按未出账计；补入账日（10-11）后归入 11-10、'
        '列在"不在已录账单里的交易"；补成 10-10 则归入本期账单', () async {
      final other = await createTestCard(scope, bank: '中国银行', last4: '2001');
      await declareTestRule(scope, other.creditAccountId, postingDelayMax: 3);
      final otherSub = (await primaryCurrencyAccount(
        scope,
        other.creditAccountId,
      )).id;
      final statement = await recordTestStatement(
        scope,
        otherSub,
        newBalance: 0,
        minDue: 0,
      );
      Future<CardTransactionRow> ticket() => addTestTransaction(
        scope,
        otherSub,
        amount: 120000,
        txnAt: '2026-10-09T20:00:00+08:00',
        unposted: true,
      );
      final a = await ticket();
      final b = await ticket();
      var data = await LedgerReader(scope).load();
      expect(data.mayBeBilled(data.transaction(a.id)!), isTrue);
      expect(data.liabilities[otherSub]!.unbilled, 240000, reason: '偏大、保守');
      expect(
        data.transactionsOf(statement.id).map((e) => e.$1.id),
        containsAll(<String>[a.id, b.id]),
      );
      expect(data.looseTransactions(), isEmpty);

      await TransactionRepository(scope).markPosted(a.id, d(2026, 10, 11));
      await TransactionRepository(scope).markPosted(b.id, d(2026, 10, 10));
      data = await LedgerReader(scope).load();
      expect(data.mayBeBilled(data.transaction(a.id)!), isFalse);
      expect(data.looseTransactions().map((e) => e.$1.id), <String>[a.id]);
      expect(data.transactionsOf(statement.id).map((e) => e.$1.id), <String>[
        b.id,
      ]);
      expect(data.liabilities[otherSub]!.unbilled, 120000);
    });
  });

  group('F-33 还款只分配到本期', () {
    test('分到已并入下一期的 9 月账单被拒；分到本期（10 月）可以，本期已还清后再分配也可以（多还形成贷方余额）', () async {
      final sep = await september();
      final oct = await recordTestStatement(scope, sub, newBalance: 150000);
      final old = await expectRepositoryError<ValidationException>(
        () => registerTestRepayment(
          scope,
          currencyAccountId: sub,
          cashAccountId: cash,
          amount: 100000,
          statementId: sep.id,
        ),
      );
      expect(
        (old.field, old.message),
        ('allocations', '只能分配到本期账单：更早的账单已并入下一期'),
      );
      final full = await registerTestRepayment(
        scope,
        currencyAccountId: sub,
        cashAccountId: cash,
        amount: 150000,
        statementId: oct.id,
        expectedDebitOn: d(2026, 10, 12),
      );
      await confirm(full.id, '2026-10-12');
      expect(
        (await LedgerReader(scope).load()).statusOf(oct.id),
        EffectiveStatementStatus.paid,
      );
      final extra = await registerTestRepayment(
        scope,
        currencyAccountId: sub,
        cashAccountId: cash,
        amount: 20000,
        statementId: oct.id,
        expectedDebitOn: d(2026, 10, 14),
      );
      await confirm(extra.id, '2026-10-14');
      final data = await LedgerReader(scope).load();
      expect(data.balances[oct.id]!.creditBalance, 20000);
      expect(data.liabilities[sub]!.billedUnpaid, -20000);
      expect(data.statusOf(oct.id), EffectiveStatementStatus.paid);
    });
  });
}
