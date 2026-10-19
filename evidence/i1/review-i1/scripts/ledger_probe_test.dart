// 审查 R-I1 探针（只读，仓库外运行）：负债四分法、账单版本追加只读的数据库兜底、迟付旧账单。
// 运行：cd apps/mobile && flutter test ../../evidence/i1/review-i1/scripts/ledger_probe_test.dart
// 金额全部是合成数据。
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/repositories/installment_repository.dart';
import 'package:cardflow/data/repositories/ledger_models.dart';
import 'package:cardflow/data/repositories/ledger_reader.dart';
import 'package:cardflow/data/repositories/repayment_repository.dart';
import 'package:cardflow/data/repositories/statement_repository.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../apps/mobile/test/data/repositories/repository_test_support.dart';

Future<(WorkspaceScope, String)> _account(AppDatabase db) async {
  final scope = await createTestWorkspace(db);
  final card = await createTestCard(scope);
  await declareTestRule(scope, card.creditAccountId); // 10 日出账、当月 28 日到期
  final sub = await primaryCurrencyAccount(scope, card.creditAccountId);
  return (scope, sub.id);
}

void main() {
  test('P1 已出账（已计入录入账单新余额）的消费再转分期：总负债', () async {
    final db = await openRealTestDatabase();
    final (scope, sub) = await _account(db);
    final txn = await addTestTransaction(
      scope,
      sub,
      amount: 1200000, // 12,000.00
      txnAt: '2026-10-05T10:00:00+08:00',
    );
    await recordTestStatement(
      scope,
      sub,
      newBalance: 1200000, // 10-10 账单：本期新余额含这笔 12,000
      minDue: 120000,
    );
    var ledger = await LedgerReader(scope).load();
    final before = ledger.liabilities[sub]!;
    print('P1 转分期前: billedUnpaid=${before.billedUnpaid} unbilled=${before.unbilled} '
        'futurePrincipal=${before.futureInstallmentPrincipal} total=${before.total}');
    await InstallmentRepository(scope).create(
      InstallmentDraft(
        transactionId: txn.id,
        periods: 12,
        perPeriodRate: Rational.parseDecimal('0.006'),
      ),
    );
    ledger = await LedgerReader(scope).load();
    final after = ledger.liabilities[sub]!;
    print('P1 转分期后（默认首期）: billedUnpaid=${after.billedUnpaid} unbilled=${after.unbilled} '
        'futurePrincipal=${after.futureInstallmentPrincipal} total=${after.total}');
    final periods = ledger.periods.values.single;
    print('P1 各期账单日: ${periods.map((p) => '${p.periodNo}:${p.statementDate}:${p.status}').join(' ')}');
  });

  test('P1b 同上，但首期指定为消费本身所在的 10-10 账单', () async {
    final db = await openRealTestDatabase();
    final (scope, sub) = await _account(db);
    final txn = await addTestTransaction(
      scope,
      sub,
      amount: 1200000,
      txnAt: '2026-10-05T10:00:00+08:00',
    );
    await recordTestStatement(scope, sub, newBalance: 1200000, minDue: 120000);
    await InstallmentRepository(scope).create(
      InstallmentDraft(
        transactionId: txn.id,
        periods: 12,
        perPeriodRate: Rational.parseDecimal('0.006'),
        firstStatementOn: LocalDate(2026, 10, 10),
      ),
    );
    final after = (await LedgerReader(scope).load()).liabilities[sub]!;
    print('P1b 转分期后（首期 10-10）: billedUnpaid=${after.billedUnpaid} unbilled=${after.unbilled} '
        'futurePrincipal=${after.futureInstallmentPrincipal} total=${after.total}');
  });

  test('P2 账单版本：直接 DELETE 旧版本、删掉当前版本后重插不同金额（数据库层）', () async {
    final db = await openRealTestDatabase();
    final (scope, sub) = await _account(db);
    final s = await recordTestStatement(scope, sub, newBalance: 100000);
    final repo = StatementRepository(scope);
    await repo.correct(
      s.id,
      figures: const StatementFigures(newBalanceMinor: 80000, minDueMinor: 8000),
      reason: '银行调整',
    );
    final versions = await repo.versions(s.id);
    final v1 = versions.first;
    final v2 = versions.last;
    print('P2 修正后: ${versions.map((v) => 'v${v.versionNo}=${v.newBalanceMinor}').join(', ')}');

    Future<String> attempt(String label, Future<void> Function() action) async {
      try {
        await action();
        return '$label: 成功';
      } on Object catch (e) {
        final text = '$e';
        return '$label: 被拒（${text.length > 140 ? text.substring(0, 140) : text}）';
      }
    }

    print('P2 ${await attempt('UPDATE v2 金额', () => db.customStatement("UPDATE statement_versions SET new_balance_minor = 1 WHERE id = '${v2.id}'"))}');
    print('P2 ${await attempt('DELETE 旧版本 v1', () => db.customStatement("DELETE FROM statement_versions WHERE id = '${v1.id}'"))}');
    print('P2 ${await attempt('同一事务：DELETE 当前 v2 + 以同一 id 重插 v2（新余额 1）', () => db.transaction(() async {
      await db.customStatement("DELETE FROM statement_versions WHERE id = '${v2.id}'");
      await db.customStatement(
        'INSERT INTO statement_versions (id, workspace_id, statement_id, version_no, source_kind, '
        'new_balance_minor, due_date, recorded_by, reason, recorded_at) VALUES '
        "('${v2.id}', '${scope.workspaceId}', '${s.id}', 2, 'correction', 1, '2026-10-28', 'user', "
        "'改写', '2026-10-18T12:00:00+08:00')");
    }))}');
    final now = await repo.versions(s.id);
    print('P2 现在的版本: ${now.map((v) => 'v${v.versionNo}=${v.newBalanceMinor}').join(', ')}；'
        '当前版本 id 未变=${(await repo.require(s.id)).currentVersionId == v2.id}');
    final ledger = await LedgerReader(scope).load();
    print('P2 读模型本期应还=${ledger.balances[s.id]!.amountDue}');
  });

  test('P3b 9 月未还、10 月新余额已含 9 月：按 10 月全额还清（分配到 10 月）后，9 月仍"已逾期"并留在近期到期', () async {
    final db = await openRealTestDatabase();
    final (scope, sub) = await _account(db);
    final cash = await createTestCashAccount(scope);
    final sep = await recordTestStatement(
      scope,
      sub,
      statementDate: LocalDate(2026, 9, 10),
      dueDate: LocalDate(2026, 9, 28),
      newBalance: 100000,
      minDue: 10000,
    );
    final oct = await recordTestStatement(scope, sub, newBalance: 150000, minDue: 15000);
    final r = await registerTestRepayment(
      scope,
      currencyAccountId: sub,
      cashAccountId: cash.id,
      amount: 150000,
      statementId: oct.id,
      expectedDebitOn: LocalDate(2026, 10, 12),
    );
    final repo = RepaymentRepository(scope);
    await repo.confirmDebit(r.id, Timestamp.parse('2026-10-12T09:00:00+08:00'));
    await repo.markCreditPosted(r.id, Timestamp.parse('2026-10-12T10:00:00+08:00'));
    await repo.confirmByBank(r.id, Timestamp.parse('2026-10-13T10:00:00+08:00'));
    final ledger = await LedgerReader(scope).load();
    final up = ledger.upcoming();
    print('P3b 结果: 10 月=${ledger.statement(oct.id)!.status} 9 月=${ledger.statement(sep.id)!.status} '
        '9 月剩余应还=${ledger.balances[sep.id]!.remaining} 总负债=${ledger.liabilities[sub]!.total} '
        '近期到期=${up.map((b) => '${b.statementDate}:${b.status.name}:${b.remaining}').join(', ')}');
  });

  test('P4 账单日之前已经还过的钱（账单新余额里已扣除）登记后分配到这期账单', () async {
    final db = await openRealTestDatabase();
    final (scope, sub) = await _account(db);
    final cash = await createTestCashAccount(scope);
    // 10-10 账单：上期 1,500 已于 09-25 还清（银行账单的"本期还款"已扣），本期新消费 800 → 新余额 800。
    final oct = await recordTestStatement(scope, sub, newBalance: 80000, minDue: 8000);
    // 用户补登 09-25 那笔 1,500 的还款：App 里只有这一期账单可分配（BL-27：须先有账单），界面要求分配合计 = 还款额。
    final r = await registerTestRepayment(
      scope,
      currencyAccountId: sub,
      cashAccountId: cash.id,
      amount: 150000,
      statementId: oct.id,
      expectedDebitOn: LocalDate(2026, 9, 25),
      initiatedAt: '2026-09-25T09:00:00+08:00',
    );
    final repo = RepaymentRepository(scope);
    await repo.confirmDebit(r.id, Timestamp.parse('2026-09-25T09:05:00+08:00'));
    await repo.markCreditPosted(r.id, Timestamp.parse('2026-09-25T10:00:00+08:00'));
    await repo.confirmByBank(r.id, Timestamp.parse('2026-09-26T10:00:00+08:00'));
    final ledger = await LedgerReader(scope).load();
    final l = ledger.liabilities[sub]!;
    print('P4 结果: 10 月账单状态=${ledger.statement(oct.id)!.status} 剩余应还=${ledger.balances[oct.id]!.remaining} '
        '本期应还=${l.currentDue} 总负债=${l.total} 近期到期=${ledger.upcoming().length}（实际仍欠 800）');
  });

  test('P3 迟付：9 月账单逾期后，10 月账单（新余额含 9 月未还）出账，再登记还 9 月那一笔', () async {
    final db = await openRealTestDatabase();
    final (scope, sub) = await _account(db);
    final cash = await createTestCashAccount(scope);
    final sep = await recordTestStatement(
      scope,
      sub,
      statementDate: LocalDate(2026, 9, 10),
      dueDate: LocalDate(2026, 9, 28),
      newBalance: 100000,
      minDue: 10000,
    );
    await recordTestStatement(
      scope,
      sub,
      newBalance: 150000, // 10-10：上期未还 1,000 + 本期新增 500
      minDue: 15000,
    );
    var ledger = await LedgerReader(scope).load();
    print('P3 登记前: 9 月状态=${ledger.statement(sep.id)!.status} 总负债=${ledger.liabilities[sub]!.total}');
    final r = await registerTestRepayment(
      scope,
      currencyAccountId: sub,
      cashAccountId: cash.id,
      amount: 100000,
      statementId: sep.id,
      expectedDebitOn: LocalDate(2026, 10, 12),
    );
    final repo = RepaymentRepository(scope);
    await repo.confirmDebit(r.id, Timestamp.parse('2026-10-12T09:00:00+08:00'));
    await repo.markCreditPosted(r.id, Timestamp.parse('2026-10-12T10:00:00+08:00'));
    await repo.confirmByBank(r.id, Timestamp.parse('2026-10-13T10:00:00+08:00'));
    ledger = await LedgerReader(scope).load();
    final l = ledger.liabilities[sub]!;
    print('P3 银行确认后: 9 月状态=${ledger.statement(sep.id)!.status} 本期应还=${l.currentDue} 总负债=${l.total}');
  });
}
