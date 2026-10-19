// 交易、账单与版本、分期与负债四分法（I-1c 数据层；真实 sqlite3mc）：F-15 可能账期、F-21 同账户两卡一份
// 账单、F-24 换卡后交易与分配不变、F-30 负债四分法与一笔 12 期分期的归属、F-34 退款待核对、F-36/F-37
// 分期拆分与成本、F-38 贷方余额；版本追加（修正 = 新版本、理由必填、原值可查）。
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/mapping/ledger_mapping.dart';
import 'package:cardflow/data/repositories/card_repository.dart';
import 'package:cardflow/data/repositories/cash_event_repository.dart';
import 'package:cardflow/data/repositories/installment_repository.dart';
import 'package:cardflow/data/repositories/ledger_models.dart';
import 'package:cardflow/data/repositories/ledger_reader.dart';
import 'package:cardflow/data/repositories/reconciliation_repository.dart';
import 'package:cardflow/data/repositories/repository_errors.dart';
import 'package:cardflow/data/repositories/statement_repository.dart';
import 'package:cardflow/data/repositories/transaction_repository.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow/data/time/business_tz.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repository_test_support.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

Rational r(String text) => Rational.parseDecimal(text);

void main() {
  late AppDatabase db;
  late WorkspaceScope scope;
  late String accountId;
  late String sub;
  late String cardId;

  setUp(() async {
    db = await openRealTestDatabase();
    scope = await createTestWorkspace(db);
    final card = await createTestCard(scope, last4: '1001', alias: '卡 A');
    accountId = card.creditAccountId;
    cardId = card.cardId;
    await declareTestRule(scope, accountId);
    sub = (await primaryCurrencyAccount(scope, accountId)).id;
  });

  Future<LiabilityBreakdown> liability() async =>
      (await LedgerReader(scope).load()).liabilities[sub]!;

  group('F-30 负债四分法：一笔 12 期分期的归属', () {
    test('未来分期本金只计未出账各期的本金（不含费用）；当期账单只计当期本金 + 费用；原消费不进未出账；'
        '总负债 = 已出账未还 + 未出账 + 未来分期本金', () async {
      final big = await addTestTransaction(
        scope,
        sub,
        amount: 1200000,
        txnAt: '2026-09-21T10:00:00+08:00',
        cardId: cardId,
        merchant: '家电城',
      );
      final plan = await InstallmentRepository(scope).create(
        InstallmentDraft(
          transactionId: big.id,
          periods: 12,
          perPeriodRate: r('0.006'),
          firstStatementOn: d(2026, 10, 10),
        ),
      );
      // 9 月账期里的另一笔消费（已出账）与 10-12 的一笔（未出账）。
      await addTestTransaction(
        scope,
        sub,
        amount: 50000,
        txnAt: '2026-09-25T10:00:00+08:00',
      );
      await addTestTransaction(scope, sub, amount: 30000);
      final periods = await InstallmentRepository(scope).schedule(plan.id);
      expect(periods.map((p) => p.principalMinor).toSet(), <int>{100000});
      expect(periods.map((p) => p.feeMinor).toSet(), <int>{7200});
      expect(periods.first.statementDate, '2026-10-10');
      expect(periods.last.statementDate, '2027-09-10');
      expect(periods.first.status, 'scheduled');

      // 10-10 的正式账单：当期分期本金 1,000 + 费用 72 = 1,072，另有 500 消费 → 本期应还 1,572。
      final statement = await recordTestStatement(
        scope,
        sub,
        newBalance: 157200,
        minDue: 15720,
        installmentDue: 107200,
      );
      final after = await InstallmentRepository(scope).schedule(plan.id);
      expect(after.first.status, 'billed', reason: '录入 10-10 的账单后第 1 期已出账');
      expect(after.skip(1).every((p) => p.status == 'scheduled'), isTrue);

      final l = await liability();
      expect(l.currentDue, 157200);
      expect(
        l.latest!.current.installmentDueMinor,
        after.first.principalMinor + after.first.feeMinor,
        reason: '当期账单只计当期本金 + 费用',
      );
      expect(l.unbilled, 30000, reason: '已转分期的原消费、已出账的 9 月消费都不计入未出账');
      expect(l.futureInstallmentPrincipal, 11 * 100000);
      expect(l.futureInstallmentFees, 11 * 7200, reason: '未计提的费用单列，不计入总负债');
      expect(l.billedUnpaid, 157200);
      expect(l.total, 157200 + 30000 + 1100000);
      expect(l.latest!.statement.id, statement.id);

      // 作废分期（录错了）：已有出账的期次不能作废。
      await expectRepositoryError<ConflictException>(
        () => InstallmentRepository(scope).cancel(plan.id),
      );
    });

    test('没有账单时：全部交易都是未出账；分期未出账的各期都在未来分期本金里', () async {
      final big = await addTestTransaction(scope, sub, amount: 600000);
      await InstallmentRepository(scope).create(
        InstallmentDraft(
          transactionId: big.id,
          periods: 6,
          perPeriodRate: r('0'),
        ),
      );
      await addTestTransaction(scope, sub, amount: 2000);
      final l = await liability();
      expect(l.latest, isNull);
      expect(l.currentDue, 0);
      expect(l.unbilled, 2000);
      expect(l.futureInstallmentPrincipal, 600000);
      expect(l.futureInstallmentFees, 0);
      expect(l.total, 602000);
    });
  });

  group('F-36/F-37 分期拆分与成本（领域包 installment.dart）', () {
    test('12 期拆分守恒、尾差在末期；默认首期为入账日与今天中较晚者所在账期；名义与实际年化并列', () async {
      final txn = await addTestTransaction(
        scope,
        sub,
        amount: 1000000,
        txnAt: '2026-10-05T10:00:00+08:00',
      );
      final plan = await InstallmentRepository(scope).create(
        InstallmentDraft(
          transactionId: txn.id,
          periods: 12,
          perPeriodRate: r('0.006'),
        ),
      );
      final periods = await InstallmentRepository(scope).schedule(plan.id);
      expect(periods.map((p) => p.principalMinor).toList(), <int>[
        ...List<int>.filled(11, 83333),
        83337,
      ]);
      expect(periods.fold<int>(0, (a, p) => a + p.principalMinor), 1000000);
      // 今天 10-18 已过 10-10 账单日：第 1 期在 11-10 账单（11-28 到期）。
      expect(
        (periods.first.statementDate, periods.first.dueDate),
        ('2026-11-10', '2026-11-28'),
      );
      expect(plan.perPeriodRate, '0.006');
      expect(plan.rounding, 'HALF_UP');

      final cost = (await LedgerReader(scope).load()).costOf(plan);
      expect(cost.nominal, r('0.072'));
      expect(percentText(cost.nominal), '7.2%');
      expect(cost.monthlyIrr == cost.perPeriodRate, isFalse);
      expect(
        cost.effective > cost.nominal,
        isTrue,
        reason: '实际年化（复利，按 IRR）高于名义',
      );
      expect(percentText(cost.effective), isNot(percentText(cost.nominal)));
    });

    test('F-37：月费率 1.5% → 名义 18%、实际年化按 IRR 复利；首期一次收取的费用在第 1 期', () async {
      final txn = await addTestTransaction(scope, sub, amount: 100000);
      final plan = await InstallmentRepository(scope).create(
        InstallmentDraft(
          transactionId: txn.id,
          periods: 12,
          perPeriodRate: r('0.015'),
        ),
      );
      final cost = (await LedgerReader(scope).load()).costOf(plan);
      expect(percentText(cost.nominal), '18%');
      expect(percentText(cost.effective), '36.7571%');
      expect(percentText(cost.monthlyIrr), '2.643%');

      final other = await addTestTransaction(scope, sub, amount: 120000);
      final upfront = await InstallmentRepository(scope).create(
        InstallmentDraft(
          transactionId: other.id,
          periods: 12,
          perPeriodRate: r('0.006'),
          feeMode: InstallmentFeeMode.upfront,
          remainderTo: RemainderTo.first,
        ),
      );
      final periods = await InstallmentRepository(scope).schedule(upfront.id);
      expect(periods.first.feeMinor, 8640, reason: '1,200 × 0.6% × 12 在首期一次收取');
      expect(periods.skip(1).every((p) => p.feeMinor == 0), isTrue);
    });

    test('校验：只有消费能转分期、不能重复转；期数 1–60；费率 0 ≤ r < 1；首期账单日须是规则的账单日；'
        '没有规则时无法排期；全部未出账的计划可以作废，原消费回到未出账', () async {
      final repo = InstallmentRepository(scope);
      final txn = await addTestTransaction(scope, sub, amount: 100000);
      final refund = await addTestTransaction(
        scope,
        sub,
        type: TxnType.refund,
        amount: -100,
      );
      Future<void> bad(InstallmentDraft draft, String field) async {
        final e = await expectRepositoryError<ValidationException>(
          () => repo.create(draft),
        );
        expect(e.field, field);
      }

      await bad(
        InstallmentDraft(
          transactionId: refund.id,
          periods: 3,
          perPeriodRate: r('0'),
        ),
        'transaction',
      );
      await bad(
        InstallmentDraft(
          transactionId: txn.id,
          periods: 0,
          perPeriodRate: r('0'),
        ),
        'periods',
      );
      await bad(
        InstallmentDraft(
          transactionId: txn.id,
          periods: 61,
          perPeriodRate: r('0'),
        ),
        'periods',
      );
      await bad(
        InstallmentDraft(
          transactionId: txn.id,
          periods: 3,
          perPeriodRate: r('1'),
        ),
        'rate',
      );
      await bad(
        InstallmentDraft(
          transactionId: txn.id,
          periods: 3,
          perPeriodRate: r('0.00000000001'),
        ),
        'rate',
      );
      await bad(
        InstallmentDraft(
          transactionId: txn.id,
          periods: 3,
          perPeriodRate: r('0.01'),
          firstStatementOn: d(2026, 11, 11),
        ),
        'firstStatementOn',
      );
      await bad(
        InstallmentDraft(
          transactionId: txn.id,
          periods: 3,
          perPeriodRate: r('0.01'),
          principalMinor: 100001,
        ),
        'principal',
      );
      final plan = await repo.create(
        InstallmentDraft(
          transactionId: txn.id,
          periods: 3,
          perPeriodRate: r('0.01'),
        ),
      );
      await expectRepositoryError<ConflictException>(
        () => repo.create(
          InstallmentDraft(
            transactionId: txn.id,
            periods: 3,
            perPeriodRate: r('0.01'),
          ),
        ),
      );
      expect((await liability()).unbilled, 0, reason: '退款待核对不计入；原消费已转分期');
      await repo.cancel(plan.id);
      expect(
        (await repo.schedule(plan.id)).every((p) => p.status == 'cancelled'),
        isTrue,
      );
      expect((await liability()).unbilled, 100000);
      expect((await liability()).futureInstallmentPrincipal, 0);

      // 没有规则的账户。
      final other = await createTestCard(scope, bank: '中国银行', last4: '2001');
      final otherSub = (await primaryCurrencyAccount(
        scope,
        other.creditAccountId,
      )).id;
      final t2 = await addTestTransaction(scope, otherSub, amount: 100);
      await bad(
        InstallmentDraft(
          transactionId: t2.id,
          periods: 3,
          perPeriodRate: r('0'),
        ),
        'rule',
      );
    });
  });

  group('交易与账期归属', () {
    test('F-15：入账日未知且入账延迟 0–3 天、交易在账单日前一天 → 两个可能账期（保守取最早到期）；'
        '入账日已知 → 已出账单优先的唯一账期', () async {
      final other = await createTestCard(scope, bank: '中国银行', last4: '2001');
      await declareTestRule(scope, other.creditAccountId, postingDelayMax: 3);
      final otherSub = (await primaryCurrencyAccount(
        scope,
        other.creditAccountId,
      )).id;
      final unknown = await addTestTransaction(
        scope,
        otherSub,
        txnAt: '2026-10-09T20:00:00+08:00',
        unposted: true,
      );
      expect(unknown.status, 'pending');
      final known = await addTestTransaction(
        scope,
        otherSub,
        txnAt: '2026-10-09T20:00:00+08:00',
        postedOn: d(2026, 10, 11),
      );
      final data = await LedgerReader(scope).load();
      final possible = data.cycles[unknown.id]! as TxnCyclePossible;
      expect(
        possible.cycles.map((c) => (c.statementDate, c.dueDate)).toList(),
        [
          (d(2026, 10, 10), d(2026, 10, 28)),
          (d(2026, 11, 10), d(2026, 11, 28)),
        ],
      );
      final certain = data.cycles[known.id]! as TxnCycleKnown;
      expect(certain.cycle.statementDate, d(2026, 11, 10));

      // 10-10 的账单录入后：已知入账日的那笔在 11-10 账期 → 未出账；可能账期跨两期的那笔仍按未出账计。
      await recordTestStatement(scope, otherSub, newBalance: 0, minDue: 0);
      final after = (await LedgerReader(scope).load()).liabilities[otherSub]!;
      expect(after.unbilled, 20000);
      final fromIssued = (await LedgerReader(scope).load()).cycles[unknown.id]!;
      expect(
        (fromIssued as TxnCyclePossible).cycles.first.ruleId,
        'issued:statement',
        reason: '已出账单优先于预测',
      );
    });

    test('记一笔的校验（G1~G3）：符号按类型、交易时间不晚于现在、入账日不早于交易日且不晚于今天、卡片须属于该账户、'
        '商户 G2/G5', () async {
      Future<void> bad(TransactionDraft draft, String field) async {
        final e = await expectRepositoryError<ValidationException>(
          () => TransactionRepository(scope).create(draft),
        );
        expect(e.field, field);
      }

      TransactionDraft draft({
        TxnType type = TxnType.purchase,
        int amount = 100,
        String at = '2026-10-12T10:00:00+08:00',
        LocalDate? posted,
        String? card,
        String? merchant,
      }) => TransactionDraft(
        currencyAccountId: sub,
        type: type,
        amountMinor: amount,
        txnAt: Timestamp.parse(at),
        postedOn: posted,
        cardId: card,
        merchant: merchant,
      );

      await bad(draft(amount: -100), 'amount');
      await bad(draft(type: TxnType.refund, amount: 100), 'amount');
      await bad(draft(amount: 0), 'amount');
      await bad(draft(at: '2026-10-18T12:00:01+08:00'), 'txnAt');
      await bad(draft(posted: d(2026, 10, 11)), 'postedOn');
      await bad(draft(posted: d(2026, 10, 19)), 'postedOn');
      final other = await createTestCard(scope, bank: '中国银行', last4: '2001');
      await bad(draft(card: other.cardId), 'card');
      final pan = await expectRepositoryError<ValidationException>(
        () =>
            TransactionRepository(scope)
                .create(draft(merchant: '6222020200112233')),
      );
      expect(pan.message, '卡序不保存完整卡号');
      await bad(draft(merchant: '一二三四五六七八九十一二三四五六七八九十一'), 'merchant');
      // 同一瞬间写成 UTC：按账户业务时区存储。
      final row = await TransactionRepository(scope)
          .create(draft(at: '2026-10-12T02:00:00Z', posted: d(2026, 10, 12)));
      expect(row.txnAt, '2026-10-12T10:00:00+08:00');
      expect(row.txnTz, 'Asia/Shanghai');
      expect(row.fingerprint, hasLength(64));
      expect(row.confirmationLevel, 'user_confirmed');
      // 删除（tombstone）；已转分期的不能删。
      await TransactionRepository(scope).delete(row.id);
      expect(await TransactionRepository(scope).byId(row.id), isNull);
    });

    test('F-21：同一信用账户的主卡与附属卡共用一份账单；同账期再录一次被拒（只有一个 statement）', () async {
      final supp = await createTestCard(
        scope,
        last4: '1002',
        joinAccountId: accountId,
        primaryCardId: cardId,
      );
      final a = await addTestTransaction(
        scope,
        sub,
        txnAt: '2026-09-25T10:00:00+08:00',
        cardId: cardId,
      );
      final b = await addTestTransaction(
        scope,
        sub,
        txnAt: '2026-09-26T10:00:00+08:00',
        cardId: supp.cardId,
      );
      final statement = await recordTestStatement(
        scope,
        sub,
        newBalance: 20000,
      );
      final again = await expectRepositoryError<ConflictException>(
        () => recordTestStatement(scope, sub, newBalance: 20000),
      );
      expect(again.message, contains('同一信用账户的各张卡共用一份账单'));
      expect(await StatementRepository(scope).list(), hasLength(1));
      final data = await LedgerReader(scope).load();
      expect(
        data.transactionsOf(statement.id).map((e) => e.$1.id).toSet(),
        <String>{a.id, b.id},
      );
    });

    test('F-24：换卡后旧卡交易仍归属同一币种子账户、还款分配不变；新卡的交易进同一子账户', () async {
      final cash = await createTestCashAccount(scope);
      final old = await addTestTransaction(
        scope,
        sub,
        txnAt: '2026-09-25T10:00:00+08:00',
        cardId: cardId,
      );
      final statement = await recordTestStatement(
        scope,
        sub,
        newBalance: 10000,
      );
      final repayment = await registerTestRepayment(
        scope,
        currencyAccountId: sub,
        cashAccountId: cash.id,
        amount: 10000,
        statementId: statement.id,
      );
      final replaced = await CardRepository(scope)
          .replace(cardId, newLast4: '1009', effectiveFrom: d(2026, 10, 15));
      final kept = (await TransactionRepository(scope).byId(old.id))!;
      expect((kept.currencyAccountId, kept.cardId), (sub, cardId));
      final fresh = await addTestTransaction(scope, sub, cardId: replaced.id);
      expect(fresh.currencyAccountId, sub);
      final data = await LedgerReader(scope).load();
      expect(data.allocationsOf(repayment.id).single.statementId, statement.id);
      expect(data.allocationsOf(repayment.id).single.amountMinor, 10000);
      expect(data.transactionsOf(statement.id).single.$1.id, old.id);
    });

    test('F-34：退款在规则未知时进入"退款待核对"，账单应还不变、不计入未出账、不进现金（不当收入）；'
        '确认冲抵后才计入', () async {
      final statement = await recordTestStatement(
        scope,
        sub,
        newBalance: 50000,
      );
      final purchase = await addTestTransaction(scope, sub, amount: 30000);
      final refund = await addTestTransaction(
        scope,
        sub,
        type: TxnType.refund,
        amount: -15000,
        txnAt: '2026-10-14T10:00:00+08:00',
        parentTransactionId: purchase.id,
      );
      final items = await ReconciliationRepository(scope).list();
      expect(items.single.kind, 'refund_pending');
      expect(referencedTransaction(items.single), refund.id);
      var l = await liability();
      expect(l.currentDue, 50000, reason: '账单应还不变');
      expect(l.unbilled, 30000);
      expect(l.pendingRefunds, 15000);
      expect(
        await CashEventRepository(scope).list(),
        isEmpty,
        reason: '退款不当现金收入',
      );
      expect(TxnType.refund.countsAsSpending, isFalse);

      await ReconciliationRepository(scope)
          .resolve(items.single.id, ReconciliationResolution.offset);
      l = await liability();
      expect(l.unbilled, 15000);
      expect(l.pendingRefunds, 0);
      expect(l.currentDue, 50000);
      // 同一项不重开、不能再处理。
      await expectRepositoryError<ConflictException>(
        () => ReconciliationRepository(scope).dismiss(items.single.id),
      );
      expect(statement.status, 'issued');
    });
  });

  group('账单与版本（R-STMT-07）', () {
    test('录入 = v1（已出账）；人工修正 = 新版本、理由必填、原值可查，已出账 → 已修正；当前版本前移', () async {
      final repo = StatementRepository(scope);
      final statement = await recordTestStatement(
        scope,
        sub,
        newBalance: 389333,
        minDue: 38000,
      );
      expect(statement.status, 'issued');
      await expectRepositoryError<ValidationException>(
        () => repo.correct(
          statement.id,
          figures: const StatementFigures(
            newBalanceMinor: 389333,
            minDueMinor: 38933,
          ),
          reason: '  ',
        ),
      );
      final v2 = await repo.correct(
        statement.id,
        figures: const StatementFigures(
          newBalanceMinor: 389333,
          minDueMinor: 38933,
        ),
        reason: '最低还款额抄错，按账单更正',
      );
      expect(
        (v2.versionNo, v2.sourceKind, v2.reason),
        (2, 'correction', '最低还款额抄错，按账单更正'),
      );
      final versions = await repo.versions(statement.id);
      expect(versions.map((v) => (v.versionNo, v.minDueMinor)).toList(), [
        (1, 38000),
        (2, 38933),
      ]);
      final updated = (await repo.byId(statement.id))!;
      expect((updated.status, updated.currentVersionId), ('amended', v2.id));
      // 再修正一次：状态保持"已修正"，到期日可更正。
      await repo.correct(
        statement.id,
        figures: StatementFigures.of(v2),
        reason: '到期日按账单更正',
        dueDate: d(2026, 10, 29),
      );
      expect((await repo.byId(statement.id))!.dueDate, '2026-10-29');
      expect(await repo.versions(statement.id), hasLength(3));
    });

    test('录入的校验：账单日不晚于今天、到期晚于账单日、最低还款不超过应还、金额范围', () async {
      Future<void> bad(StatementEntryDraft draft, String field) async {
        final e = await expectRepositoryError<ValidationException>(
          () => StatementRepository(scope).recordIssued(draft),
        );
        expect(e.field, field);
      }

      StatementEntryDraft entry({
        LocalDate? on,
        LocalDate? due,
        int balance = 100,
        int? minDue,
        int? credit,
      }) => StatementEntryDraft(
        currencyAccountId: sub,
        statementDate: on ?? d(2026, 10, 10),
        dueDate: due ?? d(2026, 10, 28),
        figures: StatementFigures(
          newBalanceMinor: balance,
          minDueMinor: minDue,
          creditBalanceMinor: credit,
        ),
      );
      await bad(
        entry(on: d(2026, 11, 10), due: d(2026, 11, 28)),
        'statementDate',
      );
      await bad(entry(due: d(2026, 10, 10)), 'dueDate');
      await bad(entry(minDue: 101), 'minDue');
      await bad(entry(balance: 10000000000001), 'newBalance');
      await bad(entry(credit: 100), 'creditBalance');
    });

    test('F-38：溢缴款——账单显示贷方余额、本期应还为 0，总负债里已出账未还为负（负债为负）', () async {
      final statement = await recordTestStatement(
        scope,
        sub,
        newBalance: -10000,
        minDue: 0,
        creditBalance: 10000,
      );
      await addTestTransaction(scope, sub, amount: 3000);
      final data = await LedgerReader(scope).load();
      final balance = data.balances[statement.id]!;
      expect(
        (balance.amountDue, balance.creditBalance, balance.remaining),
        (0, 10000, 0),
      );
      final l = data.liabilities[sub]!;
      expect(
        (l.currentDue, l.creditBalance, l.billedUnpaid),
        (0, 10000, -10000),
      );
      expect(l.total, -10000 + 3000);
      // 只录了负的新余额、没有单独录贷方余额：贷方余额取其绝对值。
      expect(creditBalanceOf(balance.current), 10000);
    });
  });

  test('交易的入账日与业务时区：同一瞬间不同偏移写入，交易日只取决于账户时区（F-20 的延伸）', () async {
    final tokyo = await createTestCard(
      scope,
      bank: '三井住友',
      last4: '3001',
      businessTz: 'Asia/Tokyo',
    );
    final tokyoSub = (await primaryCurrencyAccount(
      scope,
      tokyo.creditAccountId,
    )).id;
    final row = await addTestTransaction(
      scope,
      tokyoSub,
      txnAt: '2026-10-12T15:30:00Z',
      unposted: true,
    );
    expect(row.txnAt, '2026-10-13T00:30:00+09:00');
    expect(txnDateOf(row, businessTimeZoneOf('Asia/Tokyo')), d(2026, 10, 13));
  });
}
