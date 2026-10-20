// 卡账首页读模型（简报 U-1 §2、§7；真实 sqlite3mc）：出账/还款天数（今天、逾期、月末、闰年、无规则、冻结）、
// 状态映射（取 F-1 之后的有效状态，不读存储状态）、三种排序、汇总（多币种不相加、授信池只算一次、缺额度快照）、
// 今天刷哪张（并列、可用为 0 排除、入账延迟取保守账期）、账单出了没录入、"未计入"的应还。
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/repositories/card_repository.dart';
import 'package:cardflow/data/repositories/credit_account_repository.dart';
import 'package:cardflow/data/repositories/credit_pool_repository.dart';
import 'package:cardflow/data/repositories/ledger_home.dart';
import 'package:cardflow/data/repositories/ledger_models.dart';
import 'package:cardflow/data/repositories/ledger_reader.dart';
import 'package:cardflow/data/repositories/repayment_repository.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repository_test_support.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

void main() {
  late AppDatabase db;
  late SteppingClock clock;
  late WorkspaceScope scope;

  setUp(() async {
    db = await openRealTestDatabase();
    // 北京时间 2026-10-18 12:00。
    clock = SteppingClock();
    scope = await createTestWorkspace(db, clock: clock);
  });

  Future<LedgerHome> home([LedgerSort sort = LedgerSort.byDue]) async =>
      LedgerHome.of(await LedgerReader(scope).load(), sort: sort);

  /// 新建一张卡（可选规则与快照），返回（信用账户 id, 主子账户 id, 卡 id）。
  Future<(String, String, String)> card({
    String bank = '招商银行',
    String last4 = '1234',
    String? product,
    int? statementDay = 10,
    DueRule due = const DueRule.fixedDay(day: 28),
    bool inclusive = true,
    int delayMin = 0,
    int delayMax = 0,
    int? fixed = 1000000,
    int used = 0,
    int? available,
  }) async {
    final created = await createTestCard(
      scope,
      bank: bank,
      last4: last4,
      productName: product,
    );
    final account = created.creditAccountId;
    if (statementDay != null) {
      await declareTestRule(
        scope,
        account,
        statementDay: statementDay,
        due: due,
        inclusive: inclusive,
        postingDelayMin: delayMin,
        postingDelayMax: delayMax,
      );
    }
    final sub = (await primaryCurrencyAccount(scope, account)).id;
    if (fixed != null) {
      await recordTestSnapshot(
        scope,
        sub,
        fixed: fixed,
        used: used,
        available: available,
      );
    }
    return (account, sub, created.cardId);
  }

  /// 登记一笔还款并推进到 [to]（入账时点 = 现在，晚于账单日）。
  Future<RepaymentRow> pay(
    String sub,
    String statementId,
    int amount, {
    RepaymentStatus to = RepaymentStatus.bankConfirmed,
  }) async {
    final repo = RepaymentRepository(scope);
    final row = await registerTestRepayment(
      scope,
      currencyAccountId: sub,
      cashAccountId: null,
      amount: amount,
      statementId: statementId,
    );
    final now = Timestamp.parse('2026-10-18T12:00:00+08:00');
    if (to == RepaymentStatus.userMarkedPaid) {
      await repo.markUserPaid(row.id);
      return repo.require(row.id);
    }
    if (to == RepaymentStatus.recorded) {
      return row;
    }
    await repo.confirmDebit(row.id, now);
    await repo.markCreditPosted(row.id, now);
    if (to == RepaymentStatus.bankConfirmed) {
      await repo.confirmByBank(row.id, now);
    }
    return repo.require(row.id);
  }

  group('行：名称、待还与账单、出账日与还款日', () {
    test('名称 = 银行简称 + 主卡末四位，右侧产品名；待还 = 本期剩余应还，账单 = 新增账单；'
        '出账日 = 今天入账的账单日，还款日 = 未结清账单的到期日', () async {
      final (_, sub, _) = await card(product: '经典白');
      final s = await recordTestStatement(scope, sub, newBalance: 1230000);
      final row = (await home()).rows.single;
      expect(row.title, '招行 ···· 1234');
      expect(row.productName, '经典白');
      expect(row.remaining, 1230000);
      expect(row.billed, 1230000);
      expect(row.current!.statement.id, s.id);
      expect(row.status, isNull, reason: '待还不显示标签');
      expect(row.statement!.date, d(2026, 11, 10));
      expect(row.statement!.days, 23);
      expect(row.due!.date, d(2026, 10, 28));
      expect(row.due!.days, 10);
      expect(row.due!.tone, DueTone.normal);
    });

    test('没有已出账单：待还为 null（"—"），未出账另给；还款日 = 下一期的预测到期日（次要色）', () async {
      final (_, sub, _) = await card();
      await addTestTransaction(scope, sub, amount: 26800);
      final row = (await home()).rows.single;
      expect(row.remaining, isNull);
      expect(row.billed, isNull);
      expect(row.unbilled, 26800);
      expect(row.due!.date, d(2026, 11, 28));
      expect(row.due!.tone, DueTone.predicted);
    });

    test('今天出账、今天还款（注意色）、已逾期 N 天（危险色）', () async {
      final (_, todaySub, _) = await card(last4: '0001', statementDay: 18);
      await recordTestStatement(
        scope,
        todaySub,
        statementDate: d(2026, 10, 1),
        dueDate: d(2026, 10, 18),
      );
      final (_, lateSub, _) = await card(last4: '0002', statementDay: 20);
      await recordTestStatement(
        scope,
        lateSub,
        statementDate: d(2026, 9, 20),
        dueDate: d(2026, 10, 15),
      );
      final rows = (await home()).rows;
      final today = rows.firstWhere((r) => r.currencyAccountId == todaySub);
      expect(today.statement!.isToday, isTrue, reason: '账单日当天入账计入本期');
      expect(today.statement!.date, d(2026, 10, 18));
      expect(today.due!.tone, DueTone.today);
      expect(today.due!.days, 0);
      final late = rows.firstWhere((r) => r.currencyAccountId == lateSub);
      expect(late.status, CardRowStatus.overdue);
      expect(late.due!.tone, DueTone.overdue);
      expect(late.due!.overdueDays, 3);
    });

    test('当天归属"计入下期"：账单日当天出账日是下个月', () async {
      await card(statementDay: 18, inclusive: false);
      final row = (await home()).rows.single;
      expect(row.statement!.date, d(2026, 11, 18));
      expect(row.statement!.days, 31);
    });

    test('月末：账单日 31 在 11 月是 11-30', () async {
      clock = SteppingClock(DateTime.utc(2026, 11, 15, 4));
      scope = await createTestWorkspace(db, clock: clock);
      await card(
        statementDay: 31,
        due: const DueRule.daysAfterStatement(days: 20),
      );
      final row = (await home()).rows.single;
      expect(row.statement!.date, d(2026, 11, 30));
      expect(row.statement!.days, 15);
      expect(row.due!.date, d(2026, 12, 20));
    });

    test('闰年：账单日 30 在 2028 年 2 月是 02-29，2027 年 2 月是 02-28', () async {
      clock = SteppingClock(DateTime.utc(2028, 2, 10, 4));
      scope = await createTestWorkspace(db, clock: clock);
      await card(
        statementDay: 30,
        due: const DueRule.daysAfterStatement(days: 20),
      );
      final leap = (await home()).rows.single;
      expect(leap.statement!.date, d(2028, 2, 29));
      expect(leap.statement!.days, 19);

      final db2 = await openRealTestDatabase();
      clock = SteppingClock(DateTime.utc(2027, 2, 10, 4));
      scope = await createTestWorkspace(db2, clock: clock);
      await card(
        statementDay: 30,
        due: const DueRule.daysAfterStatement(days: 20),
      );
      final common = (await home()).rows.single;
      expect(common.statement!.date, d(2027, 2, 28));
      expect(common.due!.date, d(2027, 3, 20));
    });

    test('没有账期规则：两个日期格都没有（改为"设置账期"）；有已出账单时还款日仍取账单的到期日', () async {
      final (_, sub, _) = await card(statementDay: null);
      var row = (await home()).rows.single;
      expect(row.needsRule, isTrue);
      expect(row.statement, isNull);
      expect(row.due, isNull);
      await recordTestStatement(scope, sub);
      row = (await home()).rows.single;
      expect(row.statement, isNull);
      expect(row.due!.date, d(2026, 10, 28));
    });

    test('冻结：标"已冻结"；不进"今天刷哪张"，可用不算它，总额度照算', () async {
      final (_, _, cardId) = await card(last4: '0001');
      await card(bank: '中国银行', last4: '0002', fixed: 500000);
      await CardRepository(scope).freeze(cardId);
      final h = await home();
      final frozen = h.rows.firstWhere((r) => r.last4 == '0001');
      expect(frozen.frozen, isTrue);
      expect(h.candidates.map((c) => c.row.last4), <String?>['0002']);
      expect(h.summary.totalLimit, 1500000);
      expect(h.summary.available, 500000);
    });

    test('已停用（销卡）的账户不列出', () async {
      final (_, _, cardId) = await card(last4: '0001');
      await card(last4: '0002');
      await CardRepository(scope).close(cardId, closedOn: d(2026, 10, 18));
      expect((await home()).rows.map((r) => r.last4), <String?>['0002']);
    });
  });

  group('状态标签（有效状态，至多一个）', () {
    late String sub;
    late String statementId;

    setUp(() async {
      final (_, s, _) = await card();
      sub = s;
      statementId = (await recordTestStatement(
        scope,
        sub,
        newBalance: 100000,
      )).id;
    });

    Future<CardLedgerRow> row() async => (await home()).rows.single;

    test('银行确认足额 → 已还清，待还 0，还款日换成下一期的预测到期日（次要色）', () async {
      await pay(sub, statementId, 100000);
      final r = await row();
      expect(r.status, CardRowStatus.paid);
      expect(r.remaining, 0);
      expect(r.billed, 100000);
      expect(r.due!.tone, DueTone.predicted);
      expect(r.due!.date, d(2026, 11, 28));
      expect(r.pending, isNull);
    });

    test('部分入账 → 已还一部分；入账足额未确认 → 已入账待确认（可一步"银行确认"）', () async {
      await pay(sub, statementId, 40000, to: RepaymentStatus.creditPosted);
      var r = await row();
      expect(r.status, CardRowStatus.partiallyPaid);
      expect(r.remaining, 60000);
      expect(r.pending!.next, PendingStep.bankConfirmed);
      await pay(sub, statementId, 60000, to: RepaymentStatus.creditPosted);
      r = await row();
      expect(r.status, CardRowStatus.postedAwaitingBank);
      expect(r.remaining, 0);
    });

    test('"我已还款" → 已标记还款（不是还清，待还不变）；已登记 → 无标签、可一步"银行已入账"', () async {
      final marked = await pay(
        sub,
        statementId,
        100000,
        to: RepaymentStatus.userMarkedPaid,
      );
      var r = await row();
      expect(r.status, CardRowStatus.markedPaid);
      expect(r.remaining, 100000);
      expect(r.pending!.repayment.id, marked.id);
      expect(r.pending!.next, PendingStep.bankConfirmed);
      await RepaymentRepository(scope).delete(marked.id);
      await pay(sub, statementId, 100000, to: RepaymentStatus.recorded);
      r = await row();
      expect(r.status, isNull);
      expect(r.pending!.next, PendingStep.creditPosted);
    });

    test('不读存储状态：直接把存储状态写成"已结清"，有效状态仍是待还', () async {
      await db.customStatement(
        "UPDATE statements SET status = 'settled' WHERE id = '$statementId'",
      );
      final r = await row();
      expect(r.status, isNull);
      expect(r.remaining, 100000);
      expect(r.owes, isTrue);
    });
  });

  group('排序', () {
    test('按还款日（默认）：未结清的按到期日在前，已还清/无待还的按下一期到期日，没有规则的最后；'
        '按出账日；按待还金额（大的在前，没有账单的最后）', () async {
      // A：未结清，10-28 到期，待还 1,000。
      final (_, a, _) = await card(bank: '星海银行', last4: '1111');
      await recordTestStatement(scope, a);
      // B：未结清，10-25 到期，待还 500（账单日 5 日）。
      final (_, b, _) = await card(
        bank: '长江银行',
        last4: '2222',
        statementDay: 5,
        due: const DueRule.fixedDay(day: 25),
      );
      await recordTestStatement(
        scope,
        b,
        statementDate: d(2026, 10, 5),
        dueDate: d(2026, 10, 25),
        newBalance: 50000,
      );
      // C：已还清；下一期 11-28 到期。
      final (_, c, _) = await card(bank: '北辰银行', last4: '3333');
      final paid = await recordTestStatement(scope, c, newBalance: 80000);
      await pay(c, paid.id, 80000);
      // D：没有账单，账单日 20 日、次月 8 日到期 → 下一期 10-20 出账、11-08 到期。
      await card(
        bank: '南湖银行',
        last4: '4444',
        statementDay: 20,
        due: const DueRule.fixedDay(day: 8, monthOffset: 1),
      );
      // E：没有规则。
      await card(bank: '东方银行', last4: '5555', statementDay: null);

      List<String?> order(LedgerHome h) => h.rows.map((r) => r.last4).toList();
      expect(order(await home()), <String>[
        '2222',
        '1111',
        '4444',
        '3333',
        '5555',
      ]);
      expect(order(await home(LedgerSort.byStatement)), <String>[
        '4444',
        '2222',
        '3333',
        '1111',
        '5555',
      ], reason: 'D 10-20、B 11-05，C 与 A 都是 11-10（同日按名称的码位：北辰在星海前），没有规则的最后');
      expect(order(await home(LedgerSort.byAmount)), <String>[
        '1111',
        '2222',
        '3333',
        '4444',
        '5555',
      ], reason: '1,000 > 500 > 0；没有账单的在最后（有下一期到期日的 D 在前）');
    });
  });

  group('顶部汇总', () {
    test('本期待还按币种分别合计（不相加）；还欠着的卡数；最近一笔到期；3 天内到期', () async {
      final (account, a, _) = await card(last4: '1111');
      await recordTestStatement(scope, a, newBalance: 1230000);
      final usd = await CreditAccountRepository(scope)
          .addCurrencyAccount(account, 'USD');
      await recordTestStatement(scope, usd.id, newBalance: 5000, minDue: 500);
      final (_, b, _) = await card(bank: '中国银行', last4: '2222');
      await recordTestStatement(
        scope,
        b,
        statementDate: d(2026, 10, 1),
        dueDate: d(2026, 10, 20),
        newBalance: 345000,
      );
      final s = (await home()).summary;
      expect(s.dueByCurrency, <String, int>{'CNY': 1575000, 'USD': 5000});
      expect(s.dueByCurrency.keys.first, 'CNY');
      expect(s.owingCards, 2, reason: '同一信用账户的两个币种算一张卡');
      expect(s.nearest!.row.last4, '2222');
      expect(s.nearest!.dueDate, d(2026, 10, 20));
      expect(s.nearest!.amount, 345000);
      expect(s.dueSoon, 1);
    });

    test('总额度：授信池只算一次池上限（与成员额度之和取小）；可用 = capacityLayers 口径，池只算一次', () async {
      final (pa, _, _) = await card(
        bank: '星海银行',
        last4: '1111',
        fixed: 1000000,
      );
      final (pb, _, _) = await card(
        bank: '星海银行',
        last4: '2222',
        fixed: 1000000,
        used: 300000,
      );
      await card(bank: '中国银行', last4: '3333', fixed: 500000, used: 100000);
      final bankId = (await CreditAccountRepository(scope).require(pa)).bankId;
      final pool = await CreditPoolRepository(scope)
          .create(bankId: bankId, name: '星海共享', sharedLimitMinor: 1500000);
      await CreditAccountRepository(scope).joinPool(pa, pool.id);
      await CreditAccountRepository(scope).joinPool(pb, pool.id);
      final s = (await home()).summary;
      expect(s.missingLimit, isFalse);
      // 池：min(10,000 + 10,000, 15,000) = 15,000；另加中行 5,000。
      expect(s.totalLimit, 2000000);
      // 池可用原值 = 15,000 − 3,000 = 12,000，成员自身容量 10,000 + 7,000 = 17,000 → 12,000；中行 4,000。
      expect(s.available, 1600000);
    });

    test('有账户缺额度快照："部分卡缺额度"，总额度与可用都不给数（不以 0 代替）', () async {
      await card(last4: '1111');
      await card(bank: '中国银行', last4: '2222', fixed: null);
      final s = (await home()).summary;
      expect(s.missingLimit, isTrue);
      expect(s.totalLimit, isNull);
      expect(s.available, isNull);
    });

    test('待处理 = 等银行证据的还款 + 未处理的差异项', () async {
      final (_, sub, _) = await card();
      final statement = await recordTestStatement(scope, sub);
      await pay(sub, statement.id, 30000, to: RepaymentStatus.userMarkedPaid);
      expect((await home()).pendingCount, 1);
    });
  });

  group('今天刷哪张', () {
    test('免息天数 = 保守账期的到期日 − 今天；天数多的在前；并列时可用大的在前；可用为 0 与缺快照的不算', () async {
      // 11-17 出账、12-05 到期 → 48 天。
      await card(
        bank: '星海银行',
        last4: '1111',
        statementDay: 17,
        due: const DueRule.fixedDay(day: 5, monthOffset: 1),
        fixed: 500000,
      );
      await card(
        bank: '长江银行',
        last4: '2222',
        statementDay: 17,
        due: const DueRule.fixedDay(day: 5, monthOffset: 1),
        fixed: 800000,
      );
      // 11-10 出账、11-28 到期 → 41 天。
      await card(bank: '北辰银行', last4: '3333');
      // 可用为 0（超限）与没有快照的不算。
      await card(
        bank: '南湖银行',
        last4: '4444',
        statementDay: 17,
        due: const DueRule.fixedDay(day: 5, monthOffset: 1),
        fixed: 500000,
        used: 520000,
        available: -20000,
      );
      await card(
        bank: '东方银行',
        last4: '5555',
        statementDay: 17,
        due: const DueRule.fixedDay(day: 5, monthOffset: 1),
        fixed: null,
      );
      final h = await home();
      expect(h.candidates.map((c) => c.row.last4), <String>[
        '2222',
        '1111',
        '3333',
      ]);
      expect(h.todayPick!.freeDays, 48);
      expect(h.todayPick!.cycle.statementDate, d(2026, 11, 17));
      expect(h.todayPick!.cycle.dueDate, d(2026, 12, 5));
      expect(h.candidates.last.freeDays, 41);
    });

    test('入账可能延迟时取保守账期（最早到期）：账单日当天的交易可能落在本期或下期，按本期算', () async {
      await card(
        statementDay: 18,
        due: const DueRule.fixedDay(day: 5, monthOffset: 1),
        delayMin: 0,
        delayMax: 2,
      );
      final pick = (await home()).todayPick!;
      expect(pick.cycle.statementDate, d(2026, 10, 18));
      expect(pick.cycle.dueDate, d(2026, 11, 5));
      expect(pick.freeDays, 18);
    });

    test('没有候选（没有规则、只有外币）：不推荐', () async {
      await card(statementDay: null);
      expect((await home()).todayPick, isNull);
    });
  });

  test('账单出了还没录入：最近一期已录账单之后、今天及以前还有一个账单日 → 提示，还款日用那一期的预测到期日', () async {
    final (_, sub, _) = await card();
    final september = await recordTestStatement(
      scope,
      sub,
      statementDate: d(2026, 9, 10),
      dueDate: d(2026, 9, 28),
    );
    await pay(sub, september.id, 100000);
    final h = await home();
    final row = h.rows.single;
    expect(row.status, CardRowStatus.paid);
    expect(row.missedStatement!.statementDate, d(2026, 10, 10));
    expect(row.due!.date, d(2026, 10, 28));
    expect(row.due!.tone, DueTone.predicted);
    expect(h.summary.missedStatements, 1);
  });

  test('"未计入"：本期还欠着的减去已登记、有现金扣款、尚未入账的还款；没有现金账户的登记不算', () async {
    final cash = await createTestCashAccount(scope);
    final (_, sub, _) = await card();
    final statement = await recordTestStatement(scope, sub, newBalance: 100000);
    var h = await home();
    expect(h.uncounted.single.amount, 100000);
    expect(h.uncountedByCurrency, <String, int>{'CNY': 100000});
    expect(h.uncountedCards, 1);
    await registerTestRepayment(
      scope,
      currencyAccountId: sub,
      cashAccountId: cash.id,
      amount: 40000,
      statementId: statement.id,
      expectedDebitOn: d(2026, 10, 20),
    );
    await registerTestRepayment(
      scope,
      currencyAccountId: sub,
      cashAccountId: null,
      amount: 10000,
      statementId: statement.id,
    );
    h = await home();
    expect(h.uncounted.single.amount, 60000);
  });
}
