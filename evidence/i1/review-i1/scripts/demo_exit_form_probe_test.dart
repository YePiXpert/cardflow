// 审查 R-I1 探针：在演示空间打开全屏表单，填写后点横幅「退出演示」，表单仍在，再点「保存」——写进了哪个空间？
// 运行：cd apps/mobile && flutter test ../../evidence/i1/review-i1/scripts/demo_exit_form_probe_test.dart
import 'package:cardflow/app/routes.dart';
import 'package:cardflow/data/db/database_providers.dart';
import 'package:cardflow/data/demo/demo_workspace.dart';
import 'package:cardflow/data/repositories/cash_account_repository.dart';
import 'package:cardflow/data/repositories/workspace_repository.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow/data/time/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../apps/mobile/test/test_helpers.dart';

void main() {
  testWidgets('演示空间里打开"新建现金账户"→ 退出演示 → 保存', (tester) async {
    late String realId;
    late String demoId;
    // 真实空间与演示空间都存在，当前为演示空间。
    await pumpCardFlowApp(
      tester,
      seed: (scope) async {
        realId = scope.workspaceId;
        final demo = await ensureDemoWorkspace(scope.db);
        demoId = demo.id;
        await WorkspaceRepository(scope.db).setCurrent(demo.id);
      },
    );
    await goTo(tester, AppRoutes.newCashAccount);
    await tester.enterText(find.widgetWithText(TextField, '账户名称（≤20 字）'), '演示里填的账户');
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出演示').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '退出演示'));
    await tester.pumpAndSettle();
    final stillOnForm = find.widgetWithText(TextField, '账户名称（≤20 字）').evaluate().isNotEmpty;
    // ignore: avoid_print
    print('退出演示后表单仍在=$stillOnForm');
    if (stillOnForm) {
      final vertical = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      );
      final position = tester.state<ScrollableState>(vertical.first).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
    }
    final names = await tester.runAsync(() async {
      final container = appContainer(tester);
      final db = await container.read(databaseProvider.future);
      Future<List<String>> namesIn(String ws) async => <String>[
        for (final a in await CashAccountRepository(
          WorkspaceScope(db: db, workspaceId: ws, clock: const SystemClock()),
        ).list())
          a.name,
      ];
      return (await namesIn(realId), await namesIn(demoId));
    });
    // ignore: avoid_print
    print('真实空间的现金账户=${names!.$1}；演示空间的现金账户=${names.$2}');
  });
}
