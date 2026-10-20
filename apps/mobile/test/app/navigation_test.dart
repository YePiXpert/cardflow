import 'package:cardflow/app/diagnostics/diagnostic_log.dart';
import 'package:cardflow/app/routes.dart';
import 'package:cardflow/app/widgets/not_found_page.dart';
import 'package:cardflow/features/calendar/cash_calendar_page.dart';
import 'package:cardflow/features/cards/cards_page.dart';
import 'package:cardflow/features/cards/new_card_page.dart';
import 'package:cardflow/features/cash/cash_home_page.dart';
import 'package:cardflow/features/cash/cash_page.dart';
import 'package:cardflow/features/diagnostics/diagnostics_page.dart';
import 'package:cardflow/features/home/ledger_home_page.dart';
import 'package:cardflow/features/onboarding/welcome_page.dart';
import 'package:cardflow/features/planner/planner_page.dart';
import 'package:cardflow/features/promotions/promotions_page.dart';
import 'package:cardflow/features/scenarios/scenario_pages.dart';
import 'package:cardflow/features/settings/settings_page.dart';
import 'package:cardflow/features/statements/statement_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

/// 四个主导航：(页名, 根路径, 首次空白文案)，顺序与底部导航一致（简报 U-1 §1）。
const List<(String, String, String)> tabs = <(String, String, String)>[
  (LedgerHomePage.title, AppRoutes.home, LedgerHomePage.firstRunMessage),
  (CashHomePage.title, AppRoutes.cashHome, CashPage.firstRunMessage),
  (ScenariosPage.title, AppRoutes.planner, ScenariosPage.firstRunMessage),
  (SettingsPage.title, AppRoutes.settings, SettingsPage.firstRunMessage),
];

String _location(WidgetTester tester) =>
    appRouter(tester).routerDelegate.currentConfiguration.uri.toString();

void main() {
  testWidgets('底部导航是四个主 Tab，顺序为 卡账/现金/规划/我的（"发现"去掉）', (tester) async {
    await pumpCardFlowApp(tester);

    final labels = tester
        .widgetList<NavigationDestination>(find.byType(NavigationDestination))
        .map((destination) => destination.label)
        .toList();
    expect(labels, <String>['卡账', '现金', '规划', '我的']);
    expect(AppRoutes.tabRoots, tabs.map((tab) => tab.$2).toList());
  });

  testWidgets('启动后停在卡账，显示页名与首次空白文案', (tester) async {
    await pumpCardFlowApp(tester);

    expect(appBarTitle(LedgerHomePage.title), findsOneWidget);
    expect(find.text(LedgerHomePage.firstRunMessage), findsOneWidget);
    expect(_location(tester), AppRoutes.home);
  });

  testWidgets('点按底部导航可到达全部四个 Tab', (tester) async {
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

    await tester.tap(navLabel(LedgerHomePage.title));
    await tester.pumpAndSettle();
    expect(find.text(LedgerHomePage.firstRunMessage), findsOneWidget);

    await tester.tap(navLabel(SettingsPage.title));
    await tester.pumpAndSettle();
    expect(appBarTitle(DiagnosticsPage.title), findsOneWidget);

    await tester.tap(navLabel(SettingsPage.title));
    await tester.pumpAndSettle();
    expect(appBarTitle(SettingsPage.title), findsOneWidget);
  });

  testWidgets('原有页面都能从新结构进入：卡账右上"管理全部卡片"、规划里的消费规划与活动', (tester) async {
    await pumpCardFlowApp(tester);

    await tester.tap(find.byTooltip('管理全部卡片'));
    await tester.pumpAndSettle();
    expect(appBarTitle(CardsPage.title), findsOneWidget);
    expect(_location(tester), AppRoutes.cards);

    await goTo(tester, AppRoutes.planner);
    await tester.tap(find.text('消费规划'));
    await tester.pumpAndSettle();
    expect(appBarTitle(PlannerPage.title), findsOneWidget);
    expect(find.text(PlannerPage.firstRunMessage), findsOneWidget);
    await tester.tap(find.text('去管理卡片'));
    await tester.pumpAndSettle();
    expect(appBarTitle(CardsPage.title), findsOneWidget);

    await goTo(tester, AppRoutes.planner);
    await tester.tap(find.text('活动与权益'));
    await tester.pumpAndSettle();
    expect(appBarTitle(PromotionsPage.title), findsOneWidget);
    expect(find.text(PromotionsPage.firstRunMessage), findsOneWidget);

    await goTo(tester, AppRoutes.home);
    await tester.tap(find.byTooltip('添加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加卡片'));
    await tester.pumpAndSettle();
    expect(appBarTitle(NewCardPage.title), findsOneWidget);
  });

  testWidgets('0.0.1 的旧路由重定向到新位置，查询参数保留，深链仍可用', (tester) async {
    await pumpCardFlowApp(tester);

    final cases = <(String, String, String)>[
      ('/overview', AppRoutes.home, LedgerHomePage.title),
      (
        '/overview/statements',
        AppRoutes.statements(),
        StatementCenterPage.title,
      ),
      ('/cards', AppRoutes.cards, CardsPage.title),
      ('/cards/new', AppRoutes.newCard, NewCardPage.title),
      ('/planner/cash', AppRoutes.cashHome, CashHomePage.title),
      (
        '/planner/calendar?basis=confirmed',
        '${AppRoutes.cashCalendar}?basis=confirmed',
        CashCalendarPage.title,
      ),
      ('/planner/scenarios', AppRoutes.planner, ScenariosPage.title),
      ('/discover', AppRoutes.discover, PromotionsPage.title),
    ];
    for (final (old, expected, title) in cases) {
      await goTo(tester, old);
      expect(_location(tester), expected, reason: old);
      expect(appBarTitle(title), findsOneWidget, reason: old);
    }
    // 账户详情的旧深链（含子路径）与 legacyRedirect 的映射。
    expect(
      legacyRedirect(Uri.parse('/cards/accounts/abc/settings?section=rule')),
      '${AppRoutes.accountSettings('abc')}?section=rule',
    );
    expect(
      legacyRedirect(Uri.parse('/overview/repayments/r1')),
      AppRoutes.repayment('r1'),
    );
    expect(
      legacyRedirect(Uri.parse('/planner/cash/accounts/x/snapshot')),
      AppRoutes.recordCashSnapshot('x'),
    );
    expect(legacyRedirect(Uri.parse(AppRoutes.home)), isNull);
    expect(legacyRedirect(Uri.parse(AppRoutes.newScenario)), isNull);
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

  testWidgets('未知路径显示"已不存在"，可回到卡账', (tester) async {
    await pumpCardFlowApp(tester);
    await goTo(tester, '/no-such-page');

    expect(appBarTitle(NotFoundPage.title), findsOneWidget);
    expect(find.text('已不存在'), findsOneWidget);
    await tester.tap(find.text('回到卡账'));
    await tester.pumpAndSettle();
    expect(find.text(LedgerHomePage.firstRunMessage), findsOneWidget);
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
        AppRoutes.home,
        AppRoutes.cards,
        AppRoutes.diagnostics,
      ]),
    );
  });
}
