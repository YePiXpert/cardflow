// 审查 R-15（演示空间里打开的全屏表单在退出演示后仍留在屏幕上，保存会写进真实空间）改写的正式测试：
// 1. 切换工作空间后统一回到首页并清空页面栈：表单关闭、位置回到总览；其余 Tab 在切换前留下的栈作废，下次进入从
//    根页开始。
// 2. 表单打开时记下工作空间 id（WorkspaceBoundForm），保存时不一致就拒绝并提示——即使表单还留在屏幕上也不会写进
//    另一个空间（第二道防线）。
import 'package:cardflow/app/routes.dart';
import 'package:cardflow/data/demo/demo_workspace.dart';
import 'package:cardflow/data/repositories/cash_account_repository.dart';
import 'package:cardflow/data/repositories/providers.dart';
import 'package:cardflow/data/repositories/repository_errors.dart';
import 'package:cardflow/data/repositories/workspace_repository.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow/data/time/clock.dart';
import 'package:cardflow/features/cash/cash_account_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

final Finder _nameField = find.widgetWithText(TextField, '账户名称（≤20 字）');

/// 真实与演示两个空间都在，当前为演示空间（[ids] 记下两个 id）。
Future<void> Function(WorkspaceScope) _bothSpaces(
  void Function(String real, String demo) ids,
) => (scope) async {
  final demo = await ensureDemoWorkspace(scope.db);
  await WorkspaceRepository(scope.db).setCurrent(demo.id);
  ids(scope.workspaceId, demo.id);
};

/// 两个空间的现金账户名称（直接查库）。
Future<(List<String>, List<String>)> _cashNames(
  WidgetTester tester,
  String real,
  String demo,
) async {
  late (List<String>, List<String>) names;
  await tester.runAsync(() async {
    Future<List<String>> namesIn(String ws) async => <String>[
      for (final a in await CashAccountRepository(
        WorkspaceScope(db: testDatabase, workspaceId: ws, clock: demoClock),
      ).list())
        a.name,
    ];
    names = (await namesIn(real), await namesIn(demo));
  });
  return names;
}

Future<void> _exitDemoFromBanner(WidgetTester tester) async {
  await tester.tap(find.text('退出演示').first);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '退出演示'));
  await tester.pumpAndSettle();
}

String _location(WidgetTester tester) =>
    appRouter(tester).routerDelegate.currentConfiguration.uri.path;

void main() {
  testWidgets('演示退出：演示空间里打开"新建现金账户"并填写 → 横幅「退出演示」→ 表单已关闭、回到首页；'
      '真实空间没有新行，演示空间不变', (tester) async {
    late String real;
    late String demo;
    await pumpCardFlowApp(
      tester,
      seed: _bothSpaces((r, d) {
        real = r;
        demo = d;
      }),
    );
    await goTo(tester, AppRoutes.newCashAccount);
    await tester.enterText(_nameField, '演示里填的账户');
    await tester.pumpAndSettle();
    await _exitDemoFromBanner(tester);
    expect(_nameField, findsNothing, reason: '表单已关闭');
    expect(_location(tester), AppRoutes.overview);
    expect(find.text('演示数据 · 与真实数据隔离'), findsNothing);
    final (realNames, demoNames) = await _cashNames(tester, real, demo);
    expect(realNames, isEmpty);
    expect(demoNames, <String>['工资卡', '定期存款']);
  });

  testWidgets('切换空间前留在其他 Tab 的页面栈作废：在演示空间打开卡 A 的详情 → 退出演示 → 再点「卡包」从卡包根页开始'
      '（不再露出演示空间的页面）', (tester) async {
    await pumpCardFlowApp(tester, seed: _bothSpaces((_, _) {}));
    final wallet = await readWallet(tester);
    final a = wallet.accounts.firstWhere((v) => v.displayName == '卡 A').id;
    await tester.tap(navLabel('卡包'));
    await tester.pumpAndSettle();
    await goTo(tester, AppRoutes.account(a));
    expect(_location(tester), AppRoutes.account(a));
    await _exitDemoFromBanner(tester);
    expect(_location(tester), AppRoutes.overview);
    await tester.tap(navLabel('卡包'));
    await tester.pumpAndSettle();
    expect(_location(tester), AppRoutes.cards);
    // 切换之后新开的栈照常保留：在卡包里进到账户设置页，切到总览再切回仍在原处。
    await goTo(tester, AppRoutes.accountSettings('x'));
    await tester.tap(navLabel('总览'));
    await tester.pumpAndSettle();
    expect(_location(tester), AppRoutes.overview);
    await tester.tap(navLabel('卡包'));
    await tester.pumpAndSettle();
    expect(_location(tester), AppRoutes.accountSettings('x'));
  });

  testWidgets('第二道防线：表单打开时记下工作空间，之后切换了空间（表单还在屏幕上）→ 保存被拒绝并提示，不写进真实空间', (
    tester,
  ) async {
    late String real;
    late String demo;
    final db = await createWidgetTestDatabase(
      tester,
      seed: _bothSpaces((r, d) {
        real = r;
        demo = d;
      }),
    );
    usePhoneSurface(tester);
    // 没有路由（不会因切换空间而关掉表单），只看表单自己的检查。
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...fakeDatabaseOverrides(),
          ...testDatabaseOverrides(db),
          inlineInstallmentCosts,
        ],
        child: const MaterialApp(
          locale: Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hans',
            countryCode: 'CN',
          ),
          supportedLocales: <Locale>[
            Locale.fromSubtags(
              languageCode: 'zh',
              scriptCode: 'Hans',
              countryCode: 'CN',
            ),
          ],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: NewCashAccountPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(_nameField, '演示里填的账户');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NewCashAccountPage)),
    );
    final exit = container.read(currentWorkspaceProvider.notifier).exitDemo();
    await tester.pumpAndSettle();
    await exit;
    expect(container.read(currentWorkspaceProvider).value?.id, real);
    final save = find.widgetWithText(FilledButton, '保存');
    await tester.scrollUntilVisible(
      save,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(save);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('没有保存：${const WorkspaceChangedException().message}'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    final (realNames, demoNames) = await _cashNames(tester, real, demo);
    expect(realNames, isEmpty);
    expect(demoNames, <String>['工资卡', '定期存款']);
  });
}
