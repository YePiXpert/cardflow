// P-07 资金日历（ui-spec P-07）：四态；控制条（窗口、口径、情景、账户）；演示数据下基准口径 30 天一个缺口
// （11-01 定存转出后低于储备）、已确认口径两个、压力情景；全部缺口点含原因事件与距零/距储备；受限账户
// 不计入；日行的 ▲ 与储备线；点日看事件；无缺口用中性色（不用绿色、不说"安全/稳妥"，断言颜色 token）；
// 陈旧 → "假设分析"；缺快照"未计入"；尾部责任（窗口外的计划事件）；没有压力情景时引导新建；数据变化
// 自动重算。
import 'dart:async';

import 'package:cardflow/app/routes.dart';
import 'package:cardflow/app/theme/tokens.dart';
import 'package:cardflow/data/repositories/cash_event_repository.dart';
import 'package:cardflow/data/repositories/cash_forecast_reader.dart';
import 'package:cardflow/data/repositories/providers.dart';
import 'package:cardflow/features/calendar/cash_calendar_page.dart';
import 'package:cardflow/features/cash/cash_account_pages.dart';
import 'package:cardflow/features/scenarios/scenario_pages.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../data/repositories/repository_test_support.dart';
import '../../test_helpers.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _chip(WidgetTester tester, String label) async {
  // 控制条在列表顶部：先回到顶部（列表是懒构建的，滚出视野的标签不存在）。
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 20000));
  await tester.pumpAndSettle();
  final finder = find.widgetWithText(ChoiceChip, label);
  await _scrollTo(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// 页面上不出现"稳妥"绿色（risk.robust 的前景色与底色）：文字、图标与容器底色都检查。
void expectNoRobustColor(WidgetTester tester) {
  final robust = <Color>{
    CardFlowColors.light.robust.fg,
    CardFlowColors.light.robust.bg,
    CardFlowColors.dark.robust.fg,
    CardFlowColors.dark.robust.bg,
  };
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    expect(robust.contains(text.style?.color), isFalse, reason: text.data);
  }
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    expect(robust.contains(rich.text.style?.color), isFalse);
  }
  for (final icon in tester.widgetList<Icon>(find.byType(Icon))) {
    expect(robust.contains(icon.color), isFalse);
  }
  for (final box in tester.widgetList<Container>(find.byType(Container))) {
    final decoration = box.decoration;
    if (decoration is BoxDecoration) {
      expect(robust.contains(decoration.color), isFalse);
    }
  }
}

void main() {
  testWidgets('首次空白："还没有现金账户"「添加」', (tester) async {
    await pumpCardFlowApp(tester);
    await goTo(tester, AppRoutes.cashCalendar);
    expect(appBarTitle(CashCalendarPage.title), findsOneWidget);
    expect(find.text(CashCalendarPage.firstRunMessage), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '添加'));
    await tester.pumpAndSettle();
    expect(appBarTitle(NewCashAccountPage.title), findsOneWidget);
  });

  testWidgets('加载：控制条照常、摘要"更新中"与骨架', (tester) async {
    final pending = Completer<CashForecast>();
    await pumpCardFlowApp(
      tester,
      overrides: <Override>[
        cashForecastProvider.overrideWith((ref, query) => pending.future),
      ],
    );
    await goTo(tester, AppRoutes.cashCalendar);
    expect(find.text('摘要更新中…'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '30 天'), findsOneWidget);
  });

  testWidgets('错误：错误码与「重新计算」', (tester) async {
    await pumpCardFlowApp(
      tester,
      overrides: <Override>[
        cashForecastProvider.overrideWith(
          (ref, query) => Future<CashForecast>.error(StateError('x')),
        ),
      ],
    );
    await goTo(tester, AppRoutes.cashCalendar);
    expect(find.text('资金日历计算失败'), findsOneWidget);
    expect(find.text('重新计算'), findsOneWidget);
  });

  testWidgets('演示：基准口径 30 天一个缺口（11-01），摘要、距零/距储备、缺口原因、日行 ▲、储备线、受限账户不计入', (
    tester,
  ) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
    await goTo(tester, AppRoutes.cashCalendar);
    expect(find.text('▲ 1 个缺口点 · 首个 11-01（工资卡）'), findsOneWidget);
    expect(find.text('基准预期 · 未来 30 天 · 人民币（CNY）'), findsOneWidget);
    expect(find.text('¥300.00'), findsWidgets);
    expect(find.text('距储备：低于储备'), findsOneWidget);
    expect(find.text('¥1,700.00'), findsWidgets);
    expect(find.text('距零：高于零'), findsOneWidget);
    expect(find.text('定期存款：不计入可用现金（受限资金，未设可用日期）'), findsOneWidget);
    await _scrollTo(tester, find.text('储备线'));
    final day = find.byKey(
      ValueKey<String>(
        'day-${(await readCashPlan(tester)).accounts.first.row.id}-2026-11-01',
      ),
    );
    await _scrollTo(tester, day);
    expect(
      find.descendant(of: day, matching: find.text('▲ 缺口')),
      findsOneWidget,
    );
    await tester.tap(find.descendant(of: day, matching: find.text('11-01')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: day, matching: find.text('定存')),
      findsOneWidget,
      reason: '点日看事件',
    );
    await _scrollTo(tester, find.text('全部缺口（1）'));
    await _scrollTo(tester, find.text('▲ 11-01 · 工资卡'));
    expect(find.text('原因：定存'), findsOneWidget);
    await _scrollTo(tester, find.textContaining('快照当天未标记为已包含的事件'));
  });

  testWidgets('切换口径与窗口：已确认 2 个缺口；压力情景（收入推迟 3 天）；180 天基准 2 个缺口；只看一个账户', (
    tester,
  ) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
    await goTo(tester, AppRoutes.cashCalendar);
    await _chip(tester, '已确认');
    await _scrollTo(tester, find.text('▲ 2 个缺口点 · 首个 11-01（工资卡）'));
    await _chip(tester, '压力情景');
    expect(find.widgetWithText(ChoiceChip, '收入推迟 3 天'), findsOneWidget);
    await _scrollTo(tester, find.textContaining('压力情景：收入推迟 3 天'));
    expect(find.text('▲ 2 个缺口点 · 首个 11-01（工资卡）'), findsOneWidget);
    await _chip(tester, '基准预期');
    await _chip(tester, '180 天');
    await _scrollTo(tester, find.text('▲ 2 个缺口点 · 首个 11-01（工资卡）'));
    expect(find.text('基准预期 · 未来 180 天 · 人民币（CNY）'), findsOneWidget);
  });

  testWidgets('没有缺口：中性色"窗口内没有缺口"，页面上没有任何绿色（颜色 token），不出现"安全/稳妥"', (
    tester,
  ) async {
    await pumpCardFlowApp(
      tester,
      seed: (scope) async {
        final acc = await createTestCashAccount(scope, reserve: 100000);
        await recordTestCashSnapshot(scope, acc.id, d(2026, 10, 17), 500000);
        await addTestCashEvent(scope, acc.id, d(2026, 10, 25), -100000);
      },
    );
    await goTo(tester, AppRoutes.cashCalendar);
    expect(find.text(CashCalendarPage.noGapText), findsWidgets);
    final summary = tester.widget<Container>(
      find.byKey(const ValueKey<String>('cash-summary-CNY')),
    );
    final decoration = summary.decoration! as BoxDecoration;
    expect(decoration.color, CardFlowColors.light.surface);
    expectNoRobustColor(tester);
    expect(find.textContaining('安全'), findsNothing);
    expect(find.textContaining('稳妥'), findsNothing);
  });

  testWidgets('陈旧快照 → "假设分析"徽标与说明（不补零）；缺快照的账户"未计入"', (tester) async {
    await pumpCardFlowApp(
      tester,
      realClock: StaleAwareClock(DateTime.utc(2026, 10, 18, 4)),
      seed: (scope) async {
        final acc = await createTestCashAccount(scope);
        await recordTestCashSnapshot(scope, acc.id, d(2026, 10, 8), 500000);
        await createTestCashAccount(scope, name: '零钱');
      },
    );
    await goTo(tester, AppRoutes.cashCalendar);
    expect(find.text('数据不全：零钱缺快照，未计入'), findsOneWidget);
    expect(find.text('工资卡的余额快照已是 10 天前，结果为假设分析（未补零）'), findsOneWidget);
    await _scrollTo(tester, find.text('假设分析'));
    expect(find.text('假设分析'), findsOneWidget);
    expect(find.text('¥5,000.00'), findsWidgets, reason: '从快照余额起算');
  });

  testWidgets('尾部责任：窗口外的计划还款列出并可展开', (tester) async {
    await pumpCardFlowApp(
      tester,
      seed: (scope) async {
        final acc = await createTestCashAccount(scope);
        await recordTestCashSnapshot(scope, acc.id, d(2026, 10, 17), 500000);
        await CashEventRepository(scope).planRepaymentDebit(
          repaymentId: await insertTestRepaymentRow(
            scope,
            cashAccountId: acc.id,
          ),
          cashAccountId: acc.id,
          on: d(2026, 12, 20),
          amountMinor: 120000,
          label: '卡 A 还款',
        );
      },
    );
    await goTo(tester, AppRoutes.cashCalendar);
    await _scrollTo(tester, find.text('窗口外还有 1 笔计划中的支出'));
    await tester.tap(find.text('窗口外还有 1 笔计划中的支出'));
    await tester.pumpAndSettle();
    expect(find.text('2026-12-20 · 卡 A 还款'), findsOneWidget);
    // 窗口拉到 90 天，它就在窗口内了。
    await _chip(tester, '90 天');
    await _scrollTo(tester, find.text(CashCalendarPage.noTailText));
  });

  testWidgets('压力口径但还没有压力情景：引导「新建情景」', (tester) async {
    await pumpCardFlowApp(
      tester,
      seed: (scope) async {
        final acc = await createTestCashAccount(scope);
        await recordTestCashSnapshot(scope, acc.id, d(2026, 10, 17), 500000);
      },
    );
    await goTo(tester, AppRoutes.cashCalendar);
    await _chip(tester, '压力情景');
    expect(find.textContaining('还没有压力情景'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '新建情景'));
    await tester.pumpAndSettle();
    expect(appBarTitle(ScenarioEditorPage.newTitle), findsOneWidget);
  });

  testWidgets('数据变化自动重算：新增一笔大额支出后缺口数随之变化', (tester) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
    await goTo(tester, AppRoutes.cashCalendar);
    expect(find.text('▲ 1 个缺口点 · 首个 11-01（工资卡）'), findsOneWidget);
    await withCurrentScope(tester, (scope) async {
      final salary = (await CashForecastReader(
        scope,
      ).loadInputs()).accounts.first;
      await addTestCashEvent(
        scope,
        salary.id,
        d(2026, 10, 20),
        -400000,
        label: '换电脑',
      );
    });
    await tester.pumpAndSettle();
    // 10-20 余额 800 起连续低于储备：10-20、10-27、10-28、11-01、11-08 共 5 个缺口点。
    expect(find.text('▲ 5 个缺口点 · 首个 10-20（工资卡）'), findsOneWidget);
  });
}
