// 卡片与信用账户（真实 sqlite3mc）：F-21、F-22、F-24、卡片状态机、G2 与末四位、幂等建卡。
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/ids.dart';
import 'package:cardflow/data/mapping/domain_mapping.dart';
import 'package:cardflow/data/repositories/card_repository.dart';
import 'package:cardflow/data/repositories/card_wallet_reader.dart';
import 'package:cardflow/data/repositories/credit_account_repository.dart';
import 'package:cardflow/data/repositories/models.dart';
import 'package:cardflow/data/repositories/repository_errors.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow/data/validation/text_rules.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repository_test_support.dart';

void main() {
  late AppDatabase db;
  late WorkspaceScope scope;
  late CardRepository cards;
  late CreditAccountRepository accounts;

  setUp(() async {
    db = await openRealTestDatabase();
    scope = await createTestWorkspace(db);
    cards = CardRepository(scope);
    accounts = CreditAccountRepository(scope);
  });

  test('建卡：同时生成信用账户与 CNY 主子账户，卡片 draft → active', () async {
    final result = await createTestCard(
      scope,
      alias: '工资卡',
      productName: '经典白',
    );
    expect(result.createdAccount, isTrue);
    final card = await cards.require(result.cardId);
    expect(card.cardStatus, CardStatus.active);
    expect(card.rowVersion, 2, reason: '插入为 draft，再按状态机转为 active');
    final account = await accounts.require(result.creditAccountId);
    expect(account.holderAlias, defaultHolderAlias);
    expect(account.businessTz, 'Asia/Shanghai');
    expect(account.productName, '经典白');
    final subs = await accounts.currencyAccounts(account.id);
    expect(subs.map((c) => (c.currency, c.isPrimary)), <(String, bool)>[
      ('CNY', true),
    ]);
    expect(isUuidV4(card.id) && isUuidV4(account.id), isTrue);
  });

  test('F-21：同一信用账户的两张卡 → 一个信用账户、一个币种子账户、一个预测账期', () async {
    final first = await createTestCard(scope, last4: '1111', alias: '主卡');
    await createTestCard(
      scope,
      last4: '2222',
      alias: '另一张主卡',
      joinAccountId: first.creditAccountId,
    );
    await createTestCard(
      scope,
      last4: '3333',
      alias: '附属卡',
      primaryCardId: first.cardId,
    );
    await declareTestRule(scope, first.creditAccountId);

    expect(await accounts.list(), hasLength(1));
    expect(await accounts.currencyAccounts(), hasLength(1));
    expect(await cards.list(), hasLength(3));
    final wallet = await CardWalletReader(scope).load();
    expect(wallet.accounts, hasLength(1));
    final forecast = wallet.accounts.single.forecast as ForecastPredicted;
    expect(forecast.cycles, hasLength(1));
    // 2026-10-18 入账：账单 11-10，到期 11-28。
    expect(forecast.conservative.statementDate, LocalDate(2026, 11, 10));
    expect(forecast.conservative.dueDate, LocalDate(2026, 11, 28));
    expect(wallet.accounts.single.displayName, '主卡');
  });

  test('F-22：同一银行两个独立授信 → 两个信用账户、两套预测账期', () async {
    final a = await createTestCard(scope, last4: '1111', alias: '甲');
    final b = await createTestCard(scope, last4: '2222', alias: '乙');
    expect(a.creditAccountId, isNot(b.creditAccountId));
    await declareTestRule(scope, a.creditAccountId);
    await declareTestRule(
      scope,
      b.creditAccountId,
      statementDay: 20,
      due: const DueRule.fixedDay(day: 8, monthOffset: 1),
    );

    final wallet = await CardWalletReader(scope).load();
    expect(wallet.accounts, hasLength(2));
    expect(wallet.accounts.map((v) => v.bank.id).toSet(), hasLength(1));
    final dues = wallet.accounts
        .map((v) => (v.forecast as ForecastPredicted).conservative.dueDate)
        .toList();
    expect(dues, <LocalDate>[LocalDate(2026, 11, 28), LocalDate(2026, 11, 8)]);
    expect(await accounts.currencyAccounts(), hasLength(2));
  });

  test('F-24：换卡后旧卡 replaced 指向新卡，新卡 active；账户与子账户 id 不变', () async {
    final first = await createTestCard(scope, last4: '1111', alias: '工资卡');
    final subsBefore = await accounts.currencyAccounts(first.creditAccountId);

    final replacement = await cards.replace(
      first.cardId,
      newLast4: '9999',
      effectiveFrom: LocalDate(2026, 10, 18),
    );

    final old = await cards.require(first.cardId);
    expect(old.cardStatus, CardStatus.replaced);
    expect(old.replacedByCardId, replacement.id);
    expect(replacement.cardStatus, CardStatus.active);
    expect(replacement.creditAccountId, first.creditAccountId);
    expect(replacement.last4, '9999');
    expect(replacement.alias, '工资卡');
    expect(replacement.effectiveFrom, '2026-10-18');
    expect(await accounts.list(), hasLength(1));
    expect(
      (await accounts.currencyAccounts(first.creditAccountId)).map((c) => c.id),
      subsBefore.map((c) => c.id),
    );
    // 已换卡是终态：不能再换、冻结或销卡。
    await expectRepositoryError<IllegalCardTransitionException>(
      () => cards.replace(
        first.cardId,
        newLast4: '8888',
        effectiveFrom: LocalDate(2026, 10, 18),
      ),
    );
  });

  test('卡片状态机：非法转移在仓库层拒绝（PRD §6.1）', () async {
    final card = (await createTestCard(scope)).cardId;
    await cards.freeze(card);
    expect((await cards.require(card)).cardStatus, CardStatus.frozen);
    // 冻结的卡不能换卡（先解冻）。
    final frozenReplace =
        await expectRepositoryError<IllegalCardTransitionException>(
          () => cards.replace(
            card,
            newLast4: '9999',
            effectiveFrom: LocalDate(2026, 10, 18),
          ),
        );
    expect(frozenReplace.message, '卡片不能从「已冻结」变为「已换卡」');
    await expectRepositoryError<IllegalCardTransitionException>(
      () => cards.freeze(card),
    );
    await cards.unfreeze(card);
    await expectRepositoryError<IllegalCardTransitionException>(
      () => cards.unfreeze(card),
    );
    await cards.close(card, closedOn: LocalDate(2026, 10, 18));
    final closed = await cards.require(card);
    expect(closed.cardStatus, CardStatus.closed);
    expect(closed.closedOn, '2026-10-18');
    for (final action in <Future<void> Function()>[
      () => cards.freeze(card),
      () => cards.unfreeze(card),
      () => cards.close(card, closedOn: LocalDate(2026, 10, 18)),
    ]) {
      await expectRepositoryError<IllegalCardTransitionException>(action);
    }
  });

  test('销卡日不能晚于今天（账户业务时区）；冻结的卡可以直接销卡', () async {
    final card = (await createTestCard(scope)).cardId;
    final future = await expectRepositoryError<ValidationException>(
      () => cards.close(card, closedOn: LocalDate(2026, 10, 19)),
    );
    expect(future.field, 'closedOn');
    await cards.freeze(card);
    await cards.close(card, closedOn: LocalDate(2026, 10, 1));
    expect((await cards.require(card)).cardStatus, CardStatus.closed);
  });

  test('G2：任一文本字段含 13 位连续数字（含粘贴的全角）都拒绝保存，且不落库', () async {
    for (final draft in <NewCardDraft Function(String)>[
      (t) => _draft(alias: t),
      (t) => _draft(productName: t),
      (t) => _draft(holderAlias: t),
      (t) => _draft(bankName: t),
    ]) {
      for (final text in <String>['卡6222020200112', '６２２２０２０２００１１２']) {
        final error = await expectRepositoryError<ValidationException>(
          () => cards.create(draft(text)),
        );
        expect(error.message, fullCardNumberMessage);
      }
    }
    expect(await cards.list(), isEmpty);
    expect(await accounts.list(), isEmpty);
    expect(await db.select(db.banks).get(), isEmpty, reason: '校验失败时连银行也不写');
  });

  test('末四位：恰好 4 位数字；粘贴完整卡号给 G2 文案而不是截断', () async {
    for (final bad in <String>['123', '12345', '12a4', '']) {
      final error = await expectRepositoryError<ValidationException>(
        () => cards.create(_draft(last4: bad)),
      );
      expect(error.field, 'last4');
      expect(error.message, last4Message);
    }
    final pasted = await expectRepositoryError<ValidationException>(
      () => cards.create(_draft(last4: '6222020200112233445')),
    );
    expect(pasted.message, fullCardNumberMessage);
    final fullWidth = await cards.create(_draft(last4: '１２３４'));
    expect((await cards.require(fullWidth.cardId)).last4, '1234');
  });

  test('同一 cardId 重试保存不会重复建卡（幂等）', () async {
    final draft = _draft(last4: '5678');
    final first = await cards.create(draft);
    final retry = await cards.create(draft);
    expect(retry.cardId, first.cardId);
    expect(retry.creditAccountId, first.creditAccountId);
    expect(await cards.list(), hasLength(1));
    expect(await accounts.list(), hasLength(1));
  });

  test('同银行同末四位查询（"可能是同一信用账户的另一张卡"）；已停用的不算', () async {
    final first = await createTestCard(scope, bank: '招商银行', last4: '1234');
    await createTestCard(scope, bank: '中信银行', last4: '1234');
    final hits = await cards.sameBankSameLast4(bankName: '招商银行', last4: '1234');
    expect(hits.map((c) => c.id), <String>[first.cardId]);
    expect(
      await cards.sameBankSameLast4(bankName: '招商银行', last4: '9999'),
      isEmpty,
    );
    await cards.close(first.cardId, closedOn: LocalDate(2026, 10, 18));
    expect(
      await cards.sameBankSameLast4(bankName: '招商银行', last4: '1234'),
      isEmpty,
    );
  });

  test('附属卡须指定未停用的主卡；加入既有账户须同一银行', () async {
    final missing = await expectRepositoryError<ValidationException>(
      () => cards.create(_draft(holderKind: HolderKind.supplementary)),
    );
    expect(missing.message, '附属卡须指定主卡');
    final primary = await createTestCard(scope, bank: '招商银行');
    final supplementary = await createTestCard(
      scope,
      last4: '5555',
      primaryCardId: primary.cardId,
    );
    final notPrimary = await expectRepositoryError<ValidationException>(
      () => cards.create(
        _draft(
          holderKind: HolderKind.supplementary,
          primaryCardId: supplementary.cardId,
        ),
      ),
    );
    expect(notPrimary.field, 'primaryCard');
    final otherBank = await expectRepositoryError<ValidationException>(
      () => cards.create(
        _draft(bankName: '中信银行', joinAccountId: primary.creditAccountId),
      ),
    );
    expect(otherBank.message, '只能加入同一银行的信用账户');
  });

  test('不属于当前工作空间的卡片、账户：一律"已不存在"', () async {
    final other = await createTestWorkspace(
      db,
      kind: WorkspaceKind.demo,
      makeCurrent: false,
    );
    final foreign = await createTestCard(other);
    expect(await cards.byId(foreign.cardId), isNull);
    expect(await accounts.byId(foreign.creditAccountId), isNull);
    await expectRepositoryError<NotFoundException>(
      () => cards.freeze(foreign.cardId),
    );
    await expectRepositoryError<NotFoundException>(
      () => cards.create(_draft(joinAccountId: foreign.creditAccountId)),
    );
    expect(
      (await CardRepository(other).require(foreign.cardId)).cardStatus,
      CardStatus.active,
    );
  });
}

NewCardDraft _draft({
  String last4 = '1234',
  String? alias,
  String? productName,
  String holderAlias = '本人',
  String bankName = '招商银行',
  HolderKind holderKind = HolderKind.primary,
  String? primaryCardId,
  String? joinAccountId,
}) => NewCardDraft(
  cardId: newUuidV4(),
  newAccountId: newUuidV4(),
  bankName: bankName,
  last4: last4,
  alias: alias,
  productName: productName,
  holderAlias: holderAlias,
  holderKind: holderKind,
  primaryCardId: primaryCardId,
  joinAccountId: joinAccountId,
);
