import 'package:cardflow/app/routes.dart';
import 'package:cardflow/data/demo/demo_workspace.dart';
import 'package:cardflow/data/repositories/workspace_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

Future<void> exitDemo(WidgetTester t) async {
  await t.tap(find.text('退出演示').first);
  await t.pumpAndSettle();
  await t.tap(find.widgetWithText(FilledButton, '退出演示'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('切换空间清除消费输入、结果和卡片栈', (t) async {
    await pumpCardFlowApp(
      t,
      seed: (scope) async {
        final demo = await ensureDemoWorkspace(scope.db);
        await WorkspaceRepository(scope.db).setCurrent(demo.id);
      },
    );
    await t.enterText(find.widgetWithText(TextField, '消费金额'), '1000');
    await t.tap(find.text('比较用卡'));
    await t.pumpAndSettle();
    final wallet = await readWallet(t);
    await goTo(t, AppRoutes.account(wallet.accounts.first.id));
    await exitDemo(t);
    expect(
      appRouter(t).routeInformationProvider.value.uri.path,
      AppRoutes.home,
    );
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(find.text('推荐使用'), findsNothing);
    await t.tap(navLabel('卡片'));
    await t.pumpAndSettle();
    expect(
      appRouter(t).routeInformationProvider.value.uri.path,
      AppRoutes.cards,
    );
    expect((await readWallet(t)).accounts, isEmpty);
  });
}
