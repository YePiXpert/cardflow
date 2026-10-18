// 额度快照与三层容量（真实 sqlite3mc）：F-23（池内可用合计不超池上限，经 ModelInputs 调
// capacityLayers）、F-25（预授权只扣一次）、F-26（负可用原值保留、容量 0）、F-27（临额到期回落）、
// F-20（快照时点用三种偏移写入，业务日期与排序只取决于绝对时刻与账户时区）、G3 与表单规则。
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/mapping/domain_mapping.dart';
import 'package:cardflow/data/repositories/card_repository.dart';
import 'package:cardflow/data/repositories/card_wallet_reader.dart';
import 'package:cardflow/data/repositories/credit_account_repository.dart';
import 'package:cardflow/data/repositories/credit_pool_repository.dart';
import 'package:cardflow/data/repositories/limit_snapshot_repository.dart';
import 'package:cardflow/data/repositories/models.dart';
import 'package:cardflow/data/repositories/repository_errors.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow/data/time/business_tz.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repository_test_support.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

void main() {
  late AppDatabase db;
  late WorkspaceScope scope;
  late LimitSnapshotRepository snapshots;
  late CreditAccountRepository accounts;

  setUp(() async {
    db = await openRealTestDatabase();
    scope = await createTestWorkspace(db);
    snapshots = LimitSnapshotRepository(scope);
    accounts = CreditAccountRepository(scope);
  });

  Future<(String, String)> accountWithPrimary({
    String bank = '招商银行',
    String last4 = '1234',
  }) async {
    final card = await createTestCard(scope, bank: bank, last4: last4);
    final primary = await primaryCurrencyAccount(scope, card.creditAccountId);
    return (card.creditAccountId, primary.id);
  }

  test('F-26：负可用原值原样保存，容量截为 0，读模型标"超限"', () async {
    final (accountId, currencyId) = await accountWithPrimary();
    final row = await recordTestSnapshot(
      scope,
      currencyId,
      fixed: 1000000,
      used: 1030000,
      available: -30000,
    );
    expect(row.availableRawMinor, -30000);
    final view = (await CardWalletReader(scope).load()).account(accountId)!;
    final cny = view.primaryCurrency;
    expect(cny.availableToday, -30000);
    expect(cny.overLimit, isTrue);
    expect(cny.capacity, 0);
    expect(cny.ownCapacity, 0);
  });

  test('F-25：已含预授权时不再扣减；未含时扣减一次（同一账户两张卡也只扣一次）', () async {
    final (accountId, currencyId) = await accountWithPrimary();
    final second = await createTestCard(
      scope,
      last4: '5678',
      joinAccountId: accountId,
    );
    expect(second.creditAccountId, accountId);

    final included = await recordTestSnapshot(
      scope,
      currencyId,
      available: 800000,
      holds: 50000,
      includesHolds: true,
      balanceAsOf: '2026-10-17T20:00:00+08:00',
    );
    expect(uncountedHoldsOf(included), 0);
    var view = (await CardWalletReader(scope).load()).account(accountId)!;
    expect(view.primaryCurrency.capacity, 800000);

    final excluded = await recordTestSnapshot(
      scope,
      currencyId,
      available: 800000,
      holds: 50000,
      includesHolds: false,
      balanceAsOf: '2026-10-17T21:00:00+08:00',
    );
    expect(uncountedHoldsOf(excluded), 50000);
    view = (await CardWalletReader(scope).load()).account(accountId)!;
    expect(view.primaryCurrency.latestSnapshot!.id, excluded.id);
    expect(view.primaryCurrency.capacity, 750000);

    // 领域包层面：两张卡各一个 CardOption，预授权只记在第一张上，账户层 = 可用 − 预授权。
    final cards = await CardRepository(scope).list(creditAccountId: accountId);
    final model = CapacityModel.build(
      currency: 'CNY',
      on: d(2026, 10, 18),
      accounts: <AccountCapacityInput>[
        AccountCapacityInput(
          accountId: accountId,
          snapshot: excluded,
          cards: cards,
        ),
      ],
    );
    expect(model.inputs.cards, hasLength(2));
    expect(model.inputs.cards.map((c) => c.uncountedHolds), <int>[50000, 0]);
    expect(model.layers.account[accountId], 750000);
    expect(model.accountCapacity(accountId), 750000);
  });

  test('F-27：同一快照在临额到期前/当天/之后的容量（到期日当天起回落）', () async {
    final (accountId, currencyId) = await accountWithPrimary();
    final row = await recordTestSnapshot(
      scope,
      currencyId,
      fixed: 1000000,
      temp: 500000,
      tempExpiresOn: d(2026, 11, 15),
      used: 200000,
    );
    expect(row.availableRawMinor, 1300000);
    int capacityOn(LocalDate on) => CapacityModel.build(
      currency: 'CNY',
      on: on,
      accounts: <AccountCapacityInput>[
        AccountCapacityInput(
          accountId: accountId,
          snapshot: row,
          cards: const [],
        ),
      ],
    ).accountCapacity(accountId)!;
    expect(availableOn(row, d(2026, 11, 14)), 1300000);
    expect(capacityOn(d(2026, 11, 14)), 1300000);
    expect(capacityOn(d(2026, 11, 15)), 800000);
    expect(capacityOn(d(2026, 11, 16)), 800000);
    // 已用超过固定额度时，到期后可用为负 → 容量 0（原值仍是负数）。
    final heavy = await recordTestSnapshot(
      scope,
      currencyId,
      fixed: 1000000,
      temp: 500000,
      tempExpiresOn: d(2026, 11, 15),
      used: 1200000,
      balanceAsOf: '2026-10-17T21:00:00+08:00',
    );
    expect(availableOn(heavy, d(2026, 11, 16)), -200000);
    final heavyModel = CapacityModel.build(
      currency: 'CNY',
      on: d(2026, 11, 16),
      accounts: <AccountCapacityInput>[
        AccountCapacityInput(
          accountId: accountId,
          snapshot: heavy,
          cards: const [],
        ),
      ],
    );
    expect(heavyModel.accountCapacity(accountId), 0);
  });

  test('F-23：池内账户可用合计不超过池上限（ModelInputs → capacityLayers，与领域包语义一致）', () async {
    final (a, aCny) = await accountWithPrimary(bank: '建设银行', last4: '1111');
    final (b, bCny) = await accountWithPrimary(bank: '建设银行', last4: '2222');
    final (c, cCny) = await accountWithPrimary(bank: '招商银行', last4: '3333');
    final bankId = (await accounts.require(a)).bankId;
    final pool = await CreditPoolRepository(scope)
        .create(bankId: bankId, name: '建行共享额度', sharedLimitMinor: 2000000);
    await accounts.joinPool(a, pool.id);
    await accounts.joinPool(b, pool.id);
    await expectRepositoryError<ConflictException>(
      () => accounts.joinPool(c, pool.id),
    );

    await recordTestSnapshot(scope, aCny, fixed: 1500000, used: 300000);
    await recordTestSnapshot(scope, bCny, fixed: 1500000, used: 200000);
    await recordTestSnapshot(scope, cCny, fixed: 1000000, used: 0);

    final wallet = await CardWalletReader(scope).load();
    final poolView = wallet.pools.single;
    // 池可用原值 = 20,000 − (3,000 + 2,000) = 15,000；两账户各自 12,000 与 13,000。
    expect(poolView.usedTotal, 500000);
    expect(poolView.rawAvailable, 1500000);
    expect(poolView.capacity, 1500000);
    expect(wallet.account(a)!.primaryCurrency.ownCapacity, 1200000);
    expect(wallet.account(b)!.primaryCurrency.ownCapacity, 1300000);
    expect(
      poolView.combinedCapacity,
      1500000,
      reason: 'min(15,000, 12,000 + 13,000)',
    );
    expect(wallet.account(a)!.primaryCurrency.capacity, 1200000);
    expect(wallet.account(b)!.primaryCurrency.capacity, 1300000);
    expect(wallet.account(c)!.primaryCurrency.capacity, 1000000);
    expect(wallet.unpooledAccounts.map((v) => v.id), <String>[c]);

    // 直接对照领域包：池层容量 = max(0, 池上限 − Σused − Σ预授权)，账户容量 = 三层最小值。
    final rows = await snapshots.latestByCurrencyAccount();
    final model = CapacityModel.build(
      currency: 'CNY',
      on: d(2026, 10, 18),
      accounts: <AccountCapacityInput>[
        AccountCapacityInput(
          accountId: a,
          snapshot: rows[aCny],
          cards: const [],
          poolId: pool.id,
        ),
        AccountCapacityInput(
          accountId: b,
          snapshot: rows[bCny],
          cards: const [],
          poolId: pool.id,
        ),
      ],
      pools: <PoolCapacityInput>[
        PoolCapacityInput(
          poolId: pool.id,
          sharedLimitMinor: pool.sharedLimitMinor,
          memberAccountIds: <String>[a, b],
        ),
      ],
    );
    expect(model.inputs.pools, <String, int>{pool.id: 1500000});
    final layers = capacityLayers(model.inputs);
    expect(layers.pool[pool.id], 1500000);
    var poolTotal = 0;
    for (final option in model.inputs.cards) {
      final (limit, _) = cardLimit(option, layers);
      poolTotal += limit;
    }
    expect(poolTotal, 2500000, reason: '逐卡上限之和可以超过池（各卡都能用到自己的容量）');
    expect(
      model.poolCombinedCapacity(pool.id, <String>[a, b]),
      lessThanOrEqualTo(pool.sharedLimitMinor - 500000),
    );

    // 池上限调低到 12,000：池可用 7,000，两账户的容量都被池层截到 7,000，合计不超过 7,000。
    await CreditPoolRepository(scope).updateLimit(pool.id, 1200000);
    final tight = await CardWalletReader(scope).load();
    expect(tight.pools.single.capacity, 700000);
    expect(tight.pools.single.combinedCapacity, 700000);
    expect(tight.account(a)!.primaryCurrency.capacity, 700000);
    expect(tight.account(b)!.primaryCurrency.capacity, 700000);

    // 池上限低于已用合计：池可用原值为负（原值保留），池层容量 0。
    await CreditPoolRepository(scope).updateLimit(pool.id, 400000);
    final over = await CardWalletReader(scope).load();
    expect(over.pools.single.rawAvailable, -100000);
    expect(over.pools.single.capacity, 0);
    expect(over.account(a)!.primaryCurrency.capacity, 0);
  });

  test('池内有账户缺快照：池可用未知（不以 0 代替），成员容量不受池限制', () async {
    final (a, aCny) = await accountWithPrimary(bank: '建设银行', last4: '1111');
    final (b, _) = await accountWithPrimary(bank: '建设银行', last4: '2222');
    final pool = await CreditPoolRepository(scope).create(
      bankId: (await accounts.require(a)).bankId,
      name: '池',
      sharedLimitMinor: 500000,
    );
    await accounts.joinPool(a, pool.id);
    await accounts.joinPool(b, pool.id);
    await recordTestSnapshot(scope, aCny, fixed: 1000000);
    final wallet = await CardWalletReader(scope).load();
    expect(wallet.pools.single.missingSnapshots, 1);
    expect(wallet.pools.single.rawAvailable, isNull);
    expect(wallet.pools.single.capacity, isNull);
    expect(wallet.account(a)!.primaryCurrency.capacity, 1000000);
    expect(wallet.account(b)!.primaryCurrency.capacity, isNull);
  });

  test(
    'F-20：快照时点用 +08:00 / +00:00 / −07:00 三种偏移写入，业务日期与新旧顺序只取决于绝对时刻与账户时区',
    () async {
      final (_, currencyId) = await accountWithPrimary();
      // 三个不同瞬间，故意让文本顺序与时间顺序相反。
      final early = await recordTestSnapshot(
        scope,
        currencyId,
        balanceAsOf: '2026-10-17T01:30:00+08:00', // UTC 10-16 17:30
      );
      final middle = await recordTestSnapshot(
        scope,
        currencyId,
        balanceAsOf: '2026-10-16T18:00:00+00:00', // UTC 10-16 18:00
      );
      final late = await recordTestSnapshot(
        scope,
        currencyId,
        balanceAsOf: '2026-10-16T12:00:00-07:00', // UTC 10-16 19:00
      );
      final zone = businessTimeZoneOf('Asia/Shanghai');
      for (final row in <LimitSnapshotRow>[early, middle, late]) {
        expect(
          snapshotBusinessDate(row, zone),
          d(2026, 10, 17),
          reason: row.balanceAsOf,
        );
        expect(
          snapshotBusinessDate(row, businessTimeZoneOf('UTC')),
          d(2026, 10, 16),
        );
      }
      expect((await snapshots.history(currencyId)).map((r) => r.id), <String>[
        late.id,
        middle.id,
        early.id,
      ]);
      expect(
        (await snapshots.latestByCurrencyAccount())[currencyId]!.id,
        late.id,
      );
      // 同一瞬间的三种写法：业务日期相同。
      for (final text in <String>[
        '2026-10-17T01:30:00+08:00',
        '2026-10-16T17:30:00+00:00',
        '2026-10-16T10:30:00-07:00',
      ]) {
        expect(businessDateOf(Timestamp.parse(text), zone), d(2026, 10, 17));
      }
    },
  );

  test('G3 与表单规则：时点不晚于现在、实际时点不晚于观测时点；临额须到期日；专项须用途；金额范围', () async {
    final (_, currencyId) = await accountWithPrimary();
    Future<ValidationException> rejected(Future<Object?> Function() action) =>
        expectRepositoryError<ValidationException>(action);

    expect(
      (await rejected(
        () => recordTestSnapshot(
          scope,
          currencyId,
          balanceAsOf: '2026-10-18T12:00:01+08:00',
        ),
      )).field,
      'balanceAsOf',
    );
    expect(
      (await rejected(
        () => recordTestSnapshot(
          scope,
          currencyId,
          balanceAsOf: '2026-10-17T20:00:00+08:00',
          observedAt: '2026-10-17T19:00:00+08:00',
        ),
      )).message,
      '实际余额时点不能晚于观测时点',
    );
    expect(
      (await rejected(() => recordTestSnapshot(scope, currencyId, temp: 100)))
          .message,
      '临时额度须填写到期日',
    );
    expect(
      (await rejected(
        () => recordTestSnapshot(scope, currencyId, special: 100),
      )).field,
      'specialPurpose',
    );
    expect(
      (await rejected(
        () => recordTestSnapshot(
          scope,
          currencyId,
          special: 100,
          specialPurpose: '卡6222020200112',
        ),
      )).message,
      '卡序不保存完整卡号',
    );
    expect(
      (await rejected(() => recordTestSnapshot(scope, currencyId, fixed: -1)))
          .field,
      'fixed',
    );
    expect(await snapshots.all(), isEmpty);
    final ok = await recordTestSnapshot(
      scope,
      currencyId,
      special: 300000,
      specialPurpose: '装修分期',
      balanceAsOf: '2026-10-18T12:00:00+08:00',
    );
    expect(ok.specialPurpose, '装修分期');
    expect(ok.recordedAt, '2026-10-18T12:00:00+08:00');
    expect(ok.confirmationLevel, ConfirmationLevel.userConfirmed.code);
  });

  test('币种子账户：增删（主子账户不可删，有快照的不可删）、币种只允许 13 种', () async {
    final (accountId, cnyId) = await accountWithPrimary();
    final usd = await accounts.addCurrencyAccount(accountId, 'USD');
    expect(
      (await accounts.currencyAccounts(accountId)).map((c) => c.currency),
      <String>['CNY', 'USD'],
    );
    await expectRepositoryError<ConflictException>(
      () => accounts.addCurrencyAccount(accountId, 'USD'),
    );
    await expectRepositoryError<ValidationException>(
      () => accounts.addCurrencyAccount(accountId, 'XXX'),
    );
    final primaryError = await expectRepositoryError<ConflictException>(
      () => accounts.removeCurrencyAccount(cnyId),
    );
    expect(primaryError.message, '主子账户不可删除');
    await recordTestSnapshot(scope, usd.id, fixed: 100000);
    await expectRepositoryError<ConflictException>(
      () => accounts.removeCurrencyAccount(usd.id),
    );
    final jpy = await accounts.addCurrencyAccount(accountId, 'JPY');
    await accounts.removeCurrencyAccount(jpy.id);
    expect(
      (await accounts.currencyAccounts(accountId)).map((c) => c.currency),
      <String>['CNY', 'USD'],
    );
  });
}
