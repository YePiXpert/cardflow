// 审查 R-I1 探针：人工修正后的状态、删除交易后的差异项、删除有交易的币种子账户。
// 运行：cd apps/mobile && flutter test ../../evidence/i1/review-i1/scripts/misc_probe_test.dart
import 'package:cardflow/data/repositories/credit_account_repository.dart';
import 'package:cardflow/data/repositories/ledger_models.dart';
import 'package:cardflow/data/repositories/ledger_reader.dart';
import 'package:cardflow/data/repositories/repayment_repository.dart';
import 'package:cardflow/data/repositories/statement_repository.dart';
import 'package:cardflow/data/repositories/transaction_repository.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../apps/mobile/test/data/repositories/repository_test_support.dart';

void main() {
  test('M1 部分结清后人工修正为已付清的金额：状态与近期到期', () async {
    final db = await openRealTestDatabase();
    final scope = await createTestWorkspace(db);
    final card = await createTestCard(scope);
    await declareTestRule(scope, card.creditAccountId);
    final sub = (await primaryCurrencyAccount(scope, card.creditAccountId)).id;
    final cash = await createTestCashAccount(scope);
    final s = await recordTestStatement(scope, sub, newBalance: 100000); // 10-28 到期
    final r = await registerTestRepayment(
      scope,
      currencyAccountId: sub,
      cashAccountId: cash.id,
      amount: 80000,
      statementId: s.id,
      expectedDebitOn: LocalDate(2026, 10, 15),
    );
    final repo = RepaymentRepository(scope);
    await repo.confirmDebit(r.id, Timestamp.parse('2026-10-15T09:00:00+08:00'));
    await repo.markCreditPosted(r.id, Timestamp.parse('2026-10-15T10:00:00+08:00'));
    await repo.confirmByBank(r.id, Timestamp.parse('2026-10-16T10:00:00+08:00'));
    await StatementRepository(scope).correct(
      s.id,
      figures: const StatementFigures(newBalanceMinor: 80000),
      reason: '退货冲抵后银行调整',
    );
    final data = await LedgerReader(scope).load();
    print('M1 修正后：状态=${data.statement(s.id)!.status} 剩余应还=${data.balances[s.id]!.remaining} '
        '近期到期=${data.upcoming().map((b) => '${b.status.name}:${b.remaining}').join(',')}');
  });

  test('M2 删除退款交易后，它的"退款待核对"差异项', () async {
    final db = await openRealTestDatabase();
    final scope = await createTestWorkspace(db);
    final card = await createTestCard(scope);
    await declareTestRule(scope, card.creditAccountId);
    final sub = (await primaryCurrencyAccount(scope, card.creditAccountId)).id;
    final refund = await addTestTransaction(scope, sub, type: TxnType.refund, amount: -5000);
    await TransactionRepository(scope).delete(refund.id);
    final data = await LedgerReader(scope).load();
    print('M2 删除退款后：未处理差异项=${data.openItems.map((i) => i.kind).toList()} '
        '交易仍在=${data.transaction(refund.id) != null}');
  });

  test('M3 删除已有交易的非主币种子账户', () async {
    final db = await openRealTestDatabase();
    final scope = await createTestWorkspace(db);
    final card = await createTestCard(scope);
    final accounts = CreditAccountRepository(scope);
    final usd = await accounts.addCurrencyAccount(card.creditAccountId, 'USD');
    await addTestTransaction(scope, usd.id, amount: 1000);
    try {
      await accounts.removeCurrencyAccount(usd.id);
      print('M3 删除成功');
    } on Object catch (e) {
      print('M3 删除被拒：异常类型=${e.runtimeType}；${'$e'.split('\n').first}');
    }
  });

  test('M4 疑似重复的一笔直接「作废登记」（不经差异项处理）后，差异项仍待处理', () async {
    final db = await openRealTestDatabase();
    final scope = await createTestWorkspace(db);
    final card = await createTestCard(scope);
    await declareTestRule(scope, card.creditAccountId);
    final sub = (await primaryCurrencyAccount(scope, card.creditAccountId)).id;
    final cash = await createTestCashAccount(scope);
    final s = await recordTestStatement(scope, sub, newBalance: 100000);
    await registerTestRepayment(
      scope,
      currencyAccountId: sub,
      cashAccountId: cash.id,
      amount: 100000,
      statementId: s.id,
      method: RepaymentMethod.autoDebit,
      expectedDebitOn: LocalDate(2026, 10, 15),
    );
    final manual = await registerTestRepayment(
      scope,
      currencyAccountId: sub,
      cashAccountId: cash.id,
      amount: 100000,
      statementId: s.id,
      expectedDebitOn: LocalDate(2026, 10, 15),
    );
    var data = await LedgerReader(scope).load();
    print('M4 作废前：未处理差异项=${data.openItems.map((i) => i.kind).toList()}');
    await RepaymentRepository(scope).delete(manual.id);
    data = await LedgerReader(scope).load();
    print('M4 作废手工那笔后：还款=${data.repayments.length} 笔；未处理差异项=${data.openItems.map((i) => i.kind).toList()}');
  });
}
