import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/repositories/billing_rule_repository.dart';
import 'package:cardflow/data/repositories/card_recommendation.dart';
import 'package:cardflow/data/repositories/card_repository.dart';
import 'package:cardflow/data/repositories/card_wallet_reader.dart';
import 'package:cardflow/data/repositories/credit_account_repository.dart';
import 'package:cardflow/data/repositories/credit_pool_repository.dart';
import 'package:cardflow/data/repositories/workspace_repository.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repository_test_support.dart';

void main() {
  late AppDatabase db;
  late WorkspaceScope scope;
  setUp(() async {
    db = openMemoryTestDatabase();
    scope = await createTestWorkspace(db);
  });
  tearDown(() => db.close());
  Future<NewCardResult> card(
    String tail, {
    int available = 1000000,
    int statementDay = 10,
    bool rule = true,
    bool snapshot = true,
  }) async {
    final c = await createTestCard(scope, last4: tail);
    if (rule) {
      await declareTestRule(
        scope,
        c.creditAccountId,
        statementDay: statementDay,
      );
    }
    if (snapshot) {
      await recordTestSnapshot(
        scope,
        (await primaryCurrencyAccount(scope, c.creditAccountId)).id,
        available: available,
      );
    }
    return c;
  }

  Future<RecommendationResult> compare({
    int amount = 10000,
    String currency = 'CNY',
    LocalDate? on,
  }) async => recommendCards(
    wallet: await CardWalletReader(scope).load(),
    amount: amount,
    currency: currency,
    on: on ?? LocalDate(2026, 10, 18),
  );

  test('没有现金、账单或还款数据也可推荐；比较和重算不写任何表', () async {
    await card('1111');
    final before = await WorkspaceRepository(db).countRows(scope.workspaceId);
    expect(before['cash_accounts'] ?? 0, 0);
    expect(before['statements'] ?? 0, 0);
    expect((await compare()).eligible.single.card.last4, '1111');
    await compare(amount: 999999);
    expect(await WorkspaceRepository(db).countRows(scope.workspaceId), before);
  });
  test('先按较晚还款日，再按额度，再按末四位稳定排序；精确额度边界', () async {
    await card('3333', statementDay: 20, available: 900000);
    await card('2222', available: 800000);
    await card('1111', available: 800000);
    await card('4444', available: 900000);
    expect((await compare()).eligible.map((r) => r.card.last4), [
      '4444',
      '1111',
      '2222',
      '3333',
    ]);
    expect((await compare(amount: 900000)).eligible.length, 2);
    expect((await compare(amount: 900001)).eligible, isEmpty);
  });
  test('缺资料、冻结、停用、币种不匹配分别说明，不阻断其他卡', () async {
    await card('1111');
    await card('2222', rule: false);
    await card('3333', snapshot: false);
    final frozen = await card('4444');
    await CardRepository(scope).freeze(frozen.cardId);
    final closed = await card('5555');
    await CardRepository(scope)
        .close(closed.cardId, closedOn: LocalDate(2026, 10, 18));
    final r = await compare();
    expect(r.eligible.single.card.last4, '1111');
    expect(
      r.excluded.map((r) => r.reason),
      containsAll(['请设置账期规则', '请补充可用额度', '卡片已冻结', '卡片已停用']),
    );
    expect((await compare(currency: 'USD')).eligible, isEmpty);
    expect((await compare(currency: 'USD')).excluded.first.reason, '不支持本次币种');
  });
  test('按消费日回落临时额度、扣预授权，同账户两张卡不重复扣', () async {
    final c = await card('1111', snapshot: false);
    await createTestCard(
      scope,
      last4: '2222',
      joinAccountId: c.creditAccountId,
    );
    await recordTestSnapshot(
      scope,
      (await primaryCurrencyAccount(scope, c.creditAccountId)).id,
      fixed: 100000,
      temp: 50000,
      tempExpiresOn: LocalDate(2026, 10, 20),
      holds: 10000,
      includesHolds: false,
    );
    expect(
      (await compare(on: LocalDate(2026, 10, 19))).eligible
          .map((r) => r.capacity),
      [140000, 140000],
    );
    expect(
      (await compare(on: LocalDate(2026, 10, 20))).eligible
          .map((r) => r.capacity),
      [90000, 90000],
    );
    expect(
      (await compare(on: LocalDate(2026, 10, 20), amount: 90001)).eligible,
      isEmpty,
    );
  });
  test('共享池上限限制单卡；成员快照缺失时不假设池额度充足', () async {
    final a = await card('1111');
    final b = await card('2222', snapshot: false);
    final accounts = CreditAccountRepository(scope);
    final row = (await accounts.byId(a.creditAccountId))!;
    final pool = await CreditPoolRepository(scope)
        .create(bankId: row.bankId, name: '共享额度', sharedLimitMinor: 50000);
    await accounts.joinPool(a.creditAccountId, pool.id);
    await accounts.joinPool(b.creditAccountId, pool.id);
    expect((await compare()).eligible, isEmpty);
    expect((await compare()).excluded.first.reason, contains('共享额度资料不全'));
    await recordTestSnapshot(
      scope,
      (await primaryCurrencyAccount(scope, b.creditAccountId)).id,
      used: 20000,
    );
    expect((await compare()).eligible.map((r) => r.capacity), [30000, 30000]);
    expect((await compare(amount: 30001)).eligible, isEmpty);
  });
  test('入账延迟跨账期：展示范围，保守按较早还款日比较；未来规则生效', () async {
    final c = await card('1111', rule: false);
    await declareTestRule(
      scope,
      c.creditAccountId,
      statementDay: 20,
      postingDelayMin: 0,
      postingDelayMax: 2,
    );
    final r = (await compare(on: LocalDate(2026, 10, 19))).eligible.single;
    expect(r.forecast!.cycles.map((c) => c.dueDate.toString()), [
      '2026-10-28',
      '2026-11-28',
    ]);
    expect(r.dueDate, LocalDate(2026, 10, 28));
    await declareTestRule(
      scope,
      c.creditAccountId,
      statementDay: 15,
      due: const DueRule.fixedDay(day: 5, monthOffset: 1),
      effect: RuleEffectiveFrom(LocalDate(2026, 11, 1)),
    );
    expect(
      (await compare(on: LocalDate(2026, 11, 2))).eligible.single.dueDate,
      LocalDate(2026, 12, 5),
    );
  });
  test('月末、跨年与闰日使用领域账期规则，不以固定30天代替月份', () async {
    final c = await card('1111', rule: false);
    await declareTestRule(
      scope,
      c.creditAccountId,
      statementDay: 31,
      due: const DueRule.daysAfterStatement(days: 20),
    );
    expect(
      (await compare(on: LocalDate(2028, 2, 29))).eligible.single.dueDate,
      LocalDate(2028, 3, 20),
    );
    expect(
      (await compare(on: LocalDate(2026, 12, 31))).eligible.single.dueDate,
      LocalDate(2027, 1, 20),
    );
  });
  test('单卡额度不足时按还款日从晚到早生成多卡组合方案，同账户与共享池不超扣', () async {
    final a = await card('1111', statementDay: 10, available: 800000);
    await createTestCard(
      scope,
      last4: '1112',
      joinAccountId: a.creditAccountId,
    );
    final b = await card('2222', statementDay: 5, available: 600000);
    final c = await card('3333', statementDay: 20, available: 500000);
    final accounts = CreditAccountRepository(scope);
    final rowB = (await accounts.byId(b.creditAccountId))!;
    final pool = await CreditPoolRepository(scope)
        .create(bankId: rowB.bankId, name: '共享池', sharedLimitMinor: 700000);
    await accounts.joinPool(b.creditAccountId, pool.id);
    await accounts.joinPool(c.creditAccountId, pool.id);
    await recordTestSnapshot(
      scope,
      (await primaryCurrencyAccount(scope, b.creditAccountId)).id,
      fixed: 600000,
      used: 0,
      available: 600000,
    );
    await recordTestSnapshot(
      scope,
      (await primaryCurrencyAccount(scope, c.creditAccountId)).id,
      fixed: 500000,
      used: 0,
      available: 500000,
    );

    // 2026-10-18：1111(10日出账→11-28到期, 8000)、2222(5日出账→11-28到期, 6000)、3333(20日出账→10-28到期, 5000，与2222共享7000池上限)
    // 合计可刷 = 8000 + min(6000+5000, 7000) = 15000 (1500000)
    final r = await compare(amount: 1450000, on: LocalDate(2026, 10, 18));
    expect(r.eligible, isEmpty);
    expect(r.totalCapacity, 1500000);
    expect(r.splitPlan.map((s) => (s.card.card.last4, s.amount)).toList(), [
      ('1111', 800000),
      ('2222', 600000),
      ('3333', 50000),
    ]);

    final over = await compare(amount: 1600000, on: LocalDate(2026, 10, 18));
    expect(over.splitPlan, isEmpty);
    expect(over.totalCapacity, 1500000);
  });
  test('临近账单日（含当天及前3天内）给出延后刷卡跨账期提示', () async {
    await card('1111', statementDay: 20, available: 500000);
    // 10-16 距 20 日还有 4 天，不提示
    final far = (await compare(on: LocalDate(2026, 10, 16))).eligible.single;
    expect(far.nextCycleHint, isNull);
    // 10-19 距 20 日还有 1 天，再等 2 天（10-21）刷可跨入下一账期
    final near = (await compare(on: LocalDate(2026, 10, 19))).eligible.single;
    expect(near.nextCycleHint, isNotNull);
    expect(near.nextCycleHint!.waitDays, 2);
    expect(near.nextCycleHint!.swipeOn, LocalDate(2026, 10, 21));
    expect(near.nextCycleHint!.nextDueDate, LocalDate(2026, 11, 28));
    expect(near.nextCycleHint!.extraDays, 31);
  });
}
