// 现金页（简报 U-1 §4、§9 Q-1）：7/30/90/180 天分段、紧凑的口径菜单、余额曲线（逐日最低余额、缺口段与 ▲、读屏
// 摘要）、"表格"切回资金日历、"未计入：信用卡本期应还"与它的弹层（可直接「还清本期」）、"接下来"的收支与缺口点。
// 逐账户计算、账户之间从不相加、没有缺口不用绿色。
import 'package:cardflow/app/routes.dart';
import 'package:cardflow/data/repositories/cash_forecast_reader.dart';
import 'package:cardflow/data/repositories/cash_models.dart';
import 'package:cardflow/features/calendar/cash_calendar_page.dart';
import 'package:cardflow/features/cash/balance_chart.dart';
import 'package:cardflow/features/cash/cash_home_page.dart';
import 'package:cardflow/features/cash/uncounted_dues.dart';
import 'package:cardflow/features/home/quick_pay_sheet.dart';
import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/forbidden_ui.dart';
import '../../test_helpers.dart';

String _location(WidgetTester tester) =>
    appRouter(tester).routerDelegate.currentConfiguration.uri.toString();

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '余额曲线（默认 30 天、基准预期、最差的账户）：最低 ¥300（低于储备）、11-01 · 工资卡、缺口 1 处；读屏摘要',
    (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
      await goTo(tester, AppRoutes.cashHome);
      expect(appBarTitle(CashHomePage.title), findsOneWidget);
      final card = find.byType(BalanceChartCard);
      expect(
        find.descendant(of: card, matching: find.text('30 天内最低')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('¥300')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('11-01 · 工资卡')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('▲ 缺口 1 处')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('30 天内最低 ¥300，11-01，工资卡；缺口 1 处'),
        findsOneWidget,
      );
      handle.dispose();
    },
  );

  testWidgets('分段 7 天：最低点换成窗口内的，没有缺口用中性色并写"没有缺口"', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
    await goTo(tester, AppRoutes.cashHome);
    await tester.tap(find.text('7 天'));
    await tester.pumpAndSettle();
    final card = find.byType(BalanceChartCard);
    expect(
      find.descendant(of: card, matching: find.text('7 天内最低')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('没有缺口')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('7 天内最低 ¥4,800，10-16，工资卡；没有缺口'),
      findsOneWidget,
    );
    await expectNoForbiddenRepaymentUi(tester, page: '现金 7 天');
    handle.dispose();
  });

  testWidgets('口径菜单：改为"已确认"；「表格」带着口径打开资金日历的表格视图', (tester) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
    await goTo(tester, AppRoutes.cashHome);
    await tester.tap(find.text('口径：基准预期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已确认'));
    await tester.pumpAndSettle();
    expect(find.text('口径：已确认'), findsOneWidget);
    await tester.tap(find.text('表格'));
    await tester.pumpAndSettle();
    expect(appBarTitle(CashCalendarPage.title), findsOneWidget);
    expect(_location(tester), AppRoutes.cashCalendarWith(basis: 'confirmed'));
  });

  testWidgets('未计入：信用卡本期应还（星海本期还欠着、登记的两笔疑似重复只计一笔）→ 弹层列出这张卡，可直接「还清本期」', (
    tester,
  ) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
    await goTo(tester, AppRoutes.cashHome);
    final tile = find.byType(UncountedDuesTile);
    await _scrollTo(tester, tile);
    expect(
      find.descendant(of: tile, matching: find.text(UncountedDuesTile.lead)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tile, matching: find.text('¥1,393.33')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tile, matching: find.text('（1 张卡，登记还款后计入）')),
      findsOneWidget,
    );
    await tester.tap(tile);
    await tester.pumpAndSettle();
    final sheet = find.byType(UncountedDuesSheet);
    expect(
      find.descendant(of: sheet, matching: find.text('星海 ···· 1001')),
      findsOneWidget,
    );
    await tester.tap(find.descendant(of: sheet, matching: find.text('还清本期')));
    await tester.pumpAndSettle();
    expect(find.byType(QuickPaySheet), findsOneWidget);
    expect(find.text('还清本期 · 星海 ···· 1001'), findsOneWidget);
  });

  testWidgets('接下来：未来的收支（名称、账户 · 层级、金额）与缺口点（危险色 ▲）', (tester) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
    await goTo(tester, AppRoutes.cashHome);
    await _scrollTo(tester, find.text('水电费'));
    expect(find.text('工资卡 · 确定'), findsWidgets);
    await _scrollTo(tester, find.text('缺口 · 余额'));
    expect(find.text('工资卡 · 低于储备（先支出后收入）'), findsOneWidget);
    await expectNoForbiddenRepaymentUi(tester, page: '现金');
  });

  testWidgets('balanceSeriesOf：从快照日到窗口最后一天逐日的最低余额；缺口段与领域包的缺口点一致', (
    tester,
  ) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
    final forecast = await withCurrentScope(
      tester,
      (scope) => CashForecastReader(scope).forecast(const CashForecastQuery()),
    );
    final salary = forecast.accounts.firstWhere((a) => a.row.name == '工资卡');
    final series = balanceSeriesOf(salary, forecast.today, forecast.horizonEnd);
    expect(series.start, LocalDate(2026, 10, 16));
    expect(series.length, 30);
    expect(series.lows.first, 480000, reason: '快照 5,000 − 当天未包含的水电费 200');
    expect(series.dayAt(series.minIndex), LocalDate(2026, 11, 1));
    expect(series.minBalance, salary.report.minBalance);
    expect(series.reserve, 200000);
    expect(series.breachDays.map(series.dayAt).toList(), <LocalDate>[
      for (final b in salary.report.breaches) b.on,
    ]);
    // 11-01 定存转出后 300，直到 11-06 工资到账（先支出后收入：当日最低点在流入之前）都低于储备。
    final below = <LocalDate>[
      for (var i = 0; i < series.length; i++)
        if (series.below(i)) series.dayAt(i),
    ];
    expect(below.first, LocalDate(2026, 11, 1));
    expect(below.last, LocalDate(2026, 11, 6), reason: '11-06 只有工资流入：当日最低点仍是流入之前的 300');
    expect(CashBasis.baseline.label, '基准预期');
  });
}
