// I-1 阶段末审查（evidence/i1/review-i1.md）探针改写的正式测试：探针断言的是 0.0.1 的错误行为，这里断言
// PRD §6.2 的 2026-10-19 裁决段（账单接续、本期剩余应还、有效状态）与简报 F-1 的期望值。真实 sqlite3mc，
// 金额全部是合成数据。已出账消费转分期（P1、P1b）在 ledger_test.dart 的 F-30 组。
//
// - R-02：P3 迟付（入账日晚于 10 月账单日）→ 10 月剩余应还 500、总负债 500，9 月"已并入 10-10 账单"；
//   0.0.1 已存的分配到旧账单的还款照常读出、金额按入账日期；P3b 10 月按 1,500 还清 → 10 月"已还清"，9 月
//   不在近期到期；P4 09-25 的还款早于 10 月账单日 → 10 月剩余应还仍 800、"待还"、在近期到期里。
// - R-03：冲正后（10-18）剩余应还 1,000、"待还"、在近期到期里；11-05 → "已逾期"。
// - R-06：M1 部分还款后人工修正为已还的金额 → "已还清"，不在近期到期。
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/repositories/ledger_models.dart';
import 'package:cardflow/data/repositories/ledger_reader.dart';
import 'package:cardflow/data/repositories/repayment_repository.dart';
import 'package:cardflow/data/repositories/statement_repository.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow/data/time/clock.dart';
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
    });
  });
}
