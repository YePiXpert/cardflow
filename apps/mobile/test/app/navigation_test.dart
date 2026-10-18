import 'package:cardflow/app/diagnostics/diagnostic_log.dart';
import 'package:cardflow/app/routes.dart';
import 'package:cardflow/app/widgets/not_found_page.dart';
import 'package:cardflow/features/cards/cards_page.dart';
import 'package:cardflow/features/diagnostics/diagnostics_page.dart';
import 'package:cardflow/features/onboarding/welcome_page.dart';
import 'package:cardflow/features/overview/overview_page.dart';
import 'package:cardflow/features/planner/planner_page.dart';
import 'package:cardflow/features/promotions/promotions_page.dart';
import 'package:cardflow/features/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

/// 五个主导航：(页名, 根路径, 首次空白文案)，顺序与 ui-spec §1.1 一致。
const List<(String, String, String)> tabs = <(String, String, String)>[
  (OverviewPage.title, AppRoutes.overview, OverviewPage.firstRunMessage),
  (CardsPage.title, AppRoutes.cards, CardsPage.firstRunMessage),
  (PlannerPage.title, AppRoutes.planner, PlannerPage.firstRunMessage),
  (PromotionsPage.title, AppRoutes.discover, PromotionsPage.firstRunMessage),
  (SettingsPage.title, AppRoutes.settings, SettingsPage.firstRunMessage),
];

void main() {
  testWidgets('底部导航是五个主 Tab，顺序为 总览/卡包/规划/发现/我的', (tester) async {
    await pumpCardFlowApp(tester);

    final labels = tester
        .widgetList<NavigationDestination>(find.byType(NavigationDestination))
        .map((destination) => destination.label)
        .toList();
    expect(labels, <String>['总览', '卡包', '规划', '发现', '我的']);
    expect(AppRoutes.tabRoots, tabs.map((tab) => tab.$2).toList());
  });

  testWidgets('启动后停在总览，显示页名与首次空白文案', (tester) async {
    await pumpCardFlowApp(tester);

    expect(appBarTitle(OverviewPage.title), findsOneWidget);
    expect(find.text(OverviewPage.firstRunMessage), findsOneWidget);
  });

  testWidgets('点按底部导航可到达全部五个 Tab', (tester) async {
    await pumpCardFlowApp(tester);

    for (final (title, _, message) in tabs) {
      await tester.tap(navLabel(title));
      await tester.pumpAndSettle();
      expect(appBarTitle(title), findsOneWidget, reason: title);
      expect(find.text(message), findsOneWidget, reason: title);
    }
  });

  testWidgets('深链接可直达每个 Tab 根页与诊断页', (tester) async {
    await pumpCardFlowApp(tester);

    for (final (title, path, message) in tabs.reversed) {
      await goTo(tester, path);
      expect(appBarTitle(title), findsOneWidget, reason: path);
      expect(find.text(message), findsOneWidget, reason: path);
    }
    await goTo(tester, AppRoutes.diagnostics);
    expect(appBarTitle(DiagnosticsPage.title), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('切换 Tab 保留栈位置；再次点按当前 Tab 回到根页', (tester) async {
    await pumpCardFlowApp(tester);

    await tester.tap(navLabel(SettingsPage.title));
    await tester.pumpAndSettle();
    await tester.tap(find.text('诊断信息'));
    await tester.pumpAndSettle();
    expect(appBarTitle(DiagnosticsPage.title), findsOneWidget);

    await tester.tap(navLabel(OverviewPage.title));
    await tester.pumpAndSettle();
    expect(find.text(OverviewPage.firstRunMessage), findsOneWidget);

    await tester.tap(navLabel(SettingsPage.title));
    await tester.pumpAndSettle();
    expect(appBarTitle(DiagnosticsPage.title), findsOneWidget);

    await tester.tap(navLabel(SettingsPage.title));
    await tester.pumpAndSettle();
    expect(appBarTitle(SettingsPage.title), findsOneWidget);
  });

  testWidgets('规划的首次空白主操作跳到卡包', (tester) async {
    await pumpCardFlowApp(tester);
    await goTo(tester, AppRoutes.planner);

    await tester.tap(find.text('去卡包添加账户'));
    await tester.pumpAndSettle();
    expect(appBarTitle(CardsPage.title), findsOneWidget);
    expect(find.text(CardsPage.firstRunMessage), findsOneWidget);
  });

  testWidgets('未开放的操作显示为禁用并附说明', (tester) async {
    await pumpCardFlowApp(tester);

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '建卡'),
    );
    expect(button.onPressed, isNull);
    expect(find.textContaining('尚未开放'), findsOneWidget);
  });

  testWidgets('欢迎页全屏覆盖底部导航，返回后回到"我的"', (tester) async {
    await pumpCardFlowApp(tester);
    await goTo(tester, AppRoutes.settings);

    await tester.tap(find.text('欢迎与开始方式'));
    await tester.pumpAndSettle();
    expect(appBarTitle(WelcomePage.title), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    for (final item in WelcomePage.boundaries) {
      expect(find.text(item), findsOneWidget);
    }

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(appBarTitle(SettingsPage.title), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('未知路径显示"已不存在"，可回到总览', (tester) async {
    await pumpCardFlowApp(tester);
    await goTo(tester, '/no-such-page');

    expect(appBarTitle(NotFoundPage.title), findsOneWidget);
    expect(find.text('已不存在'), findsOneWidget);
    await tester.tap(find.text('回到总览'));
    await tester.pumpAndSettle();
    expect(find.text(OverviewPage.firstRunMessage), findsOneWidget);
  });

  testWidgets('路由变化写入诊断日志，只记路由模板', (tester) async {
    await pumpCardFlowApp(tester);
    await goTo(tester, AppRoutes.cards);
    await goTo(tester, AppRoutes.diagnostics);

    final log = appContainer(tester).read(diagnosticLogProvider);
    final routes = log.entries
        .where((entry) => entry.category == 'route')
        .map((entry) => entry.detail)
        .toList();
    expect(
      routes,
      containsAllInOrder(<String>[
        AppRoutes.overview,
        AppRoutes.cards,
        AppRoutes.diagnostics,
      ]),
    );
  });
}
