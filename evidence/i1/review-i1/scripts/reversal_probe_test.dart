// 审查 R-I1 探针（BL-29 确认）：银行确认 → 冲正之后，账单状态、剩余应还、近期到期与逾期维护。
// 运行：cd apps/mobile && flutter test ../../evidence/i1/review-i1/scripts/reversal_probe_test.dart
import 'package:cardflow/data/repositories/ledger_reader.dart';
import 'package:cardflow/data/repositories/repayment_repository.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow/data/time/clock.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../apps/mobile/test/data/repositories/repository_test_support.dart';

void main() {
  test('冲正后：已结清不回退；剩余应还 > 0；近期到期不再列出；过了到期日也不变"已逾期"', () async {
    final db = await openRealTestDatabase();
    final scope = await createTestWorkspace(db); // 今天 = 2026-10-18（北京时间 12:00）
    final card = await createTestCard(scope);
    await declareTestRule(scope, card.creditAccountId);
    final sub = (await primaryCurrencyAccount(scope, card.creditAccountId)).id;
    final cash = await createTestCashAccount(scope);
    final s = await recordTestStatement(scope, sub, newBalance: 100000); // 10-10 出账、10-28 到期
    final r = await registerTestRepayment(
      scope,
      currencyAccountId: sub,
      cashAccountId: cash.id,
      amount: 100000,
      statementId: s.id,
      expectedDebitOn: LocalDate(2026, 10, 15),
    );
    final repo = RepaymentRepository(scope);
    await repo.confirmDebit(r.id, Timestamp.parse('2026-10-15T09:00:00+08:00'));
    await repo.markCreditPosted(r.id, Timestamp.parse('2026-10-15T10:00:00+08:00'));
    await repo.confirmByBank(r.id, Timestamp.parse('2026-10-16T10:00:00+08:00'));
    var data = await LedgerReader(scope).load();
    print('银行确认后：状态=${data.statement(s.id)!.status} 剩余应还=${data.balances[s.id]!.remaining} '
        '近期到期=${data.upcoming().length} 总负债=${data.liabilities[sub]!.total}');
    await repo.reverse(r.id);
    data = await LedgerReader(scope).load();
    print('冲正后（10-18）：状态=${data.statement(s.id)!.status} 剩余应还=${data.balances[s.id]!.remaining} '
        '近期到期=${data.upcoming().length} 总负债=${data.liabilities[sub]!.total}');
    // 过了到期日：换一个"今天"为 11-05 的作用域重新读
    final later = WorkspaceScope(db: scope.db, workspaceId: scope.workspaceId, clock: FixedClock(DateTime.utc(2026, 11, 5, 4)));
    data = await LedgerReader(later).load();
    print('冲正后（11-05，已过 10-28 到期日）：状态=${data.statement(s.id)!.status} '
        '剩余应还=${data.balances[s.id]!.remaining} 近期到期=${data.upcoming().length}');
  });
}

