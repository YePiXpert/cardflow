// 审查 R-I1 探针：账单版本追加只读的数据库兜底能否经 DELETE / INSERT OR REPLACE 绕过（只用原始 SQL；
// App 的仓库代码没有删除账单版本的路径）。运行：cd apps/mobile && flutter test ../../evidence/i1/review-i1/scripts/append_only_probe_test.dart
import 'package:cardflow/data/repositories/ledger_reader.dart';
import 'package:cardflow/data/repositories/statement_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../apps/mobile/test/data/repositories/repository_test_support.dart';

void main() {
  test('A1 同一事务删掉当前版本 v2 并以同一 id、同一版本号重插不同金额', () async {
    final db = await openRealTestDatabase();
    final scope = await createTestWorkspace(db);
    final card = await createTestCard(scope);
    await declareTestRule(scope, card.creditAccountId);
    final sub = (await primaryCurrencyAccount(scope, card.creditAccountId)).id;
    final s = await recordTestStatement(scope, sub, newBalance: 100000);
    final repo = StatementRepository(scope);
    await repo.correct(
      s.id,
      figures: const StatementFigures(newBalanceMinor: 80000, minDueMinor: 8000),
      reason: '银行调整',
    );
    final v2 = (await repo.versions(s.id)).last;
    await db.transaction(() async {
      await db.customStatement("DELETE FROM statement_versions WHERE id = '${v2.id}'");
      await db.customStatement(
        'INSERT INTO statement_versions (id, workspace_id, statement_id, version_no, source_kind, '
        'new_balance_minor, due_date, recorded_by, reason, recorded_at) VALUES '
        "('${v2.id}', '${scope.workspaceId}', '${s.id}', 2, 'correction', 1, '2026-10-28', 'user', "
        "'改写', '${v2.recordedAt}')",
      );
    });
    final now = await repo.versions(s.id);
    print('A1 结果: ${now.map((v) => 'v${v.versionNo}=${v.newBalanceMinor}').join(', ')}；'
        '当前版本 id 未变=${(await repo.require(s.id)).currentVersionId == v2.id}；'
        '读模型本期应还=${(await LedgerReader(scope).load()).balances[s.id]!.amountDue}');
  });

  test('A2 INSERT OR REPLACE 以 v1 的 id 写入一行（版本号 3）', () async {
    final db = await openRealTestDatabase();
    final scope = await createTestWorkspace(db);
    final card = await createTestCard(scope);
    await declareTestRule(scope, card.creditAccountId);
    final sub = (await primaryCurrencyAccount(scope, card.creditAccountId)).id;
    final s = await recordTestStatement(scope, sub, newBalance: 100000);
    final repo = StatementRepository(scope);
    await repo.correct(
      s.id,
      figures: const StatementFigures(newBalanceMinor: 80000),
      reason: '银行调整',
    );
    final v1 = (await repo.versions(s.id)).first;
    try {
      await db.customStatement(
        'INSERT OR REPLACE INTO statement_versions (id, workspace_id, statement_id, version_no, '
        'source_kind, new_balance_minor, due_date, recorded_by, reason, recorded_at) VALUES '
        "('${v1.id}', '${scope.workspaceId}', '${s.id}', 3, 'correction', 5, '2026-10-28', 'user', "
        "'改写', '${v1.recordedAt}')",
      );
      print('A2 INSERT OR REPLACE: 成功');
    } on Object catch (e) {
      print('A2 INSERT OR REPLACE: 被拒 ${'$e'.split('\n').first}');
    }
    print('A2 现在的版本: ${(await repo.versions(s.id)).map((v) => 'v${v.versionNo}=${v.newBalanceMinor}').join(', ')}');
  });
}
