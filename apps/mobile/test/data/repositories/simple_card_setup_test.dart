import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/repositories/card_recommendation.dart';
import 'package:cardflow/data/repositories/card_repository.dart';
import 'package:cardflow/data/repositories/card_wallet_reader.dart';
import 'package:cardflow/data/repositories/credit_account_repository.dart';
import 'package:cardflow/data/repositories/credit_pool_repository.dart';
import 'package:cardflow/data/repositories/simple_card_setup.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repository_test_support.dart';

void main() {
  late AppDatabase db;
  late WorkspaceScope scope;
  setUp(() async {
    db = await openRealTestDatabase();
    scope = await createTestWorkspace(db);
  });
  tearDown(() => db.close());
  Future<void> create({int due = 5}) => createSimpleCard(
    scope,
    cardId: 'simple-card',
    accountId: 'simple-account',
    name: '生活卡',
    last4: '4321',
    available: 123456,
    statementDay: 20,
    dueDay: due,
  );

  test('原子保存、重试不重复；跨月还款且额度边界准确', () async {
    await create();
    await create();
    final wallet = await CardWalletReader(scope).load();
    expect(wallet.accounts, hasLength(1));
    expect(wallet.accounts.single.ruleVersions, hasLength(1));
    expect(wallet.accounts.single.currentRule!.dueMonthOffset, 1);
    final accepted = recommendCards(
      wallet: wallet,
      amount: 123456,
      currency: 'CNY',
      on: LocalDate(2026, 10, 21),
    );
    expect(accepted.eligible.single.dueDate, LocalDate(2026, 12, 5));
    expect(
      recommendCards(
        wallet: wallet,
        amount: 123457,
        currency: 'CNY',
        on: LocalDate(2026, 10, 21),
      ).eligible,
      isEmpty,
    );
  });
  test('只填可用额度的卡加入共享池后不能把未填的已用当作零', () async {
    await create();
    final account = (await CardWalletReader(scope).load()).accounts.single;
    final pool = await CreditPoolRepository(scope)
        .create(bankId: account.bank.id, name: '共享', sharedLimitMinor: 500000);
    await CreditAccountRepository(scope).joinPool(account.id, pool.id);
    final wallet = await CardWalletReader(scope).load();
    final result = recommendCards(
      wallet: wallet,
      amount: 100,
      currency: 'CNY',
      on: LocalDate(2026, 10, 21),
    );
    expect(result.eligible, isEmpty);
    expect(result.excluded.single.reason, contains('共享额度资料不全'));
  });
  test('账期保存失败回滚卡片、账户与额度，可以重试', () async {
    await expectLater(create(due: 99), throwsA(isA<Exception>()));
    expect(await CardRepository(scope).byId('simple-card'), isNull);
    expect((await CardWalletReader(scope).load()).accounts, isEmpty);
    await create();
    expect((await CardWalletReader(scope).load()).accounts, hasLength(1));
  });
}
