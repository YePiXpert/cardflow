// P-09 情景与假设对比（ui-spec P-09）：四态；内置两条不可改；演示数据的压力情景与计算版本；「重算」生成
// 新版本（旧版保留，"已保存 v{n}"）与"与上一版对比"；数据变化后"已过期"；编辑器的字段校验（延迟、收入
// 比例、支出比例、不与内置同名）；对比两情景（逐账户最低现金、日期、缺口数）；不足两个版本时提示先重算。
import 'dart:async';

import 'package:cardflow/app/routes.dart';
import 'package:cardflow/app/widgets/state_views.dart';
import 'package:cardflow/data/repositories/cash_forecast_reader.dart';
import 'package:cardflow/data/repositories/providers.dart';
import 'package:cardflow/data/repositories/scenario_repository.dart';
import 'package:cardflow/features/scenarios/scenario_pages.dart';
import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../data/repositories/repository_test_support.dart';
import '../../test_helpers.dart';

Finder _field(String label) => find.widgetWithText(TextField, label);

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _scrollTo(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String label, String text) async {
  await _scrollTo(tester, _field(label));
  await tester.enterText(_field(label), text);
  await tester.pumpAndSettle();
}

/// 情景卡片（按名称）。
Finder _card(String scenario) =>
    find.byKey(ValueKey<String>('scenario-$scenario'));

/// 情景卡片（按名称）里的某个按钮。
Finder _cardButton(String scenario, String button) => find.descendant(
  of: _card(scenario),
  matching: find.widgetWithText(TextButton, button),
);

void main() {
  testWidgets('首次空白："只有内置口径"「新建」；内置两条在列表里，尚未计算', (tester) async {
    await pumpCardFlowApp(tester);
    await goTo(tester, AppRoutes.scenarios);
    expect(appBarTitle(ScenariosPage.title), findsOneWidget);
    expect(find.text(ScenariosPage.firstRunMessage), findsOneWidget);
    await _scrollTo(tester, find.text('尚未计算').first);
    expect(find.text('已确认'), findsWidgets);
    expect(find.text('基准预期'), findsWidgets);
    await _tap(tester, find.widgetWithText(FilledButton, '新建'));
    expect(appBarTitle(ScenarioEditorPage.newTitle), findsOneWidget);
  });

  testWidgets('加载：骨架', (tester) async {
    final pending = Completer<ScenarioBoard>();
    await pumpCardFlowApp(
      tester,
      overrides: <Override>[
        scenarioBoardProvider.overrideWith((ref) => pending.future),
      ],
    );
    await goTo(tester, AppRoutes.scenarios);
    expect(find.byType(LoadingSkeleton), findsOneWidget);
  });

  testWidgets('错误：错误码与「重新计算」', (tester) async {
    await pumpCardFlowApp(
      tester,
      overrides: <Override>[
        scenarioBoardProvider.overrideWith(
          (ref) => Future<ScenarioBoard>.error(StateError('x')),
        ),
      ],
    );
    await goTo(tester, AppRoutes.scenarios);
    expect(find.text('情景读取失败'), findsOneWidget);
    expect(find.text('重新计算'), findsOneWidget);
  });

  testWidgets('演示：内置不可修改；压力情景参数与 v1；「重算」生成 v2（旧版保留）并可与上一版对比', (tester) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
    await goTo(tester, AppRoutes.scenarios);
    expect(find.text('内置（不可修改）'), findsNWidgets(2));
    await _scrollTo(tester, find.text('收入推迟 3 天'));
    expect(
      find.textContaining('收入延迟 3 天 · 收入 100% · 生活支出 100%'),
      findsOneWidget,
    );
    expect(find.text(ScenariosPage.staleLabel), findsNothing);
    await _tap(tester, _cardButton('收入推迟 3 天', '重算'));
    expect(find.text('已保存 v2'), findsOneWidget);
    await _tap(tester, find.text('历史版本（2）'));
    await _tap(tester, find.widgetWithText(TextButton, '与上一版对比'));
    expect(appBarTitle(ScenarioComparePage.title), findsOneWidget);
    expect(find.text('收入推迟 3 天 v1 与 收入推迟 3 天 v2'), findsOneWidget);
    await _scrollTo(tester, find.textContaining('缺口点：A 4 · B 4 · 差异 0'));
    expect(find.text('工资卡'), findsWidgets);
  });

  testWidgets('输入变化后"已过期"：新增一笔收支，已计算的版本都标"已过期"', (tester) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
    await goTo(tester, AppRoutes.scenarios);
    expect(find.text(ScenariosPage.staleLabel), findsNothing);
    await withCurrentScope(tester, (scope) async {
      final salary = (await CashForecastReader(
        scope,
      ).loadInputs()).accounts.first;
      await addTestCashEvent(
        scope,
        salary.id,
        LocalDate(2026, 10, 30),
        -1000,
        label: '加餐',
      );
    });
    await tester.pumpAndSettle();
    for (final name in <String>['基准预期', '收入推迟 3 天']) {
      await _scrollTo(tester, _card(name));
      expect(
        find.descendant(
          of: _card(name),
          matching: find.text(ScenariosPage.staleLabel),
        ),
        findsOneWidget,
        reason: name,
      );
    }
  });

  testWidgets('编辑器校验：延迟 0–180、收入比例 0–100%、支出比例 ≥100%、不与内置同名；合规的保存后列出', (
    tester,
  ) async {
    await pumpCardFlowApp(tester);
    await goTo(tester, AppRoutes.newScenario);
    const name = '名称（必填，≤20 字，不能与内置同名）';
    await _enter(tester, name, '基准预期');
    await _tap(tester, find.widgetWithText(FilledButton, '保存情景'));
    expect(find.textContaining('不能与内置同名'), findsWidgets);
    await _enter(tester, name, '最坏情况');
    await _enter(tester, '收入延迟（天，0–180）', '181');
    await _tap(tester, find.widgetWithText(FilledButton, '保存情景'));
    expect(find.textContaining('收入延迟须在 0–180 天之间'), findsWidgets);
    await _enter(tester, '收入延迟（天，0–180）', '10');
    await _enter(tester, '收入比例（%，0–100）', '101');
    await _tap(tester, find.widgetWithText(FilledButton, '保存情景'));
    expect(find.textContaining('收入比例须在 0%–100% 之间'), findsWidgets);
    await _enter(tester, '收入比例（%，0–100）', '80');
    await _enter(tester, '生活支出比例（%，100–1000）', '99');
    await _tap(tester, find.widgetWithText(FilledButton, '保存情景'));
    expect(find.textContaining('支出比例须在 100%–1000% 之间'), findsWidgets);
    await _enter(tester, '生活支出比例（%，100–1000）', '120');
    await _tap(tester, find.widgetWithText(FilledButton, '保存情景'));
    final rows = await withCurrentScope(
      tester,
      (scope) => ScenarioRepository(scope).rows(),
    );
    expect(rows.single.name, '最坏情况');
    expect(
      (
        rows.single.incomeDelayDays,
        rows.single.incomeScale,
        rows.single.expenseScale,
      ),
      (10, '0.8', '1.2'),
    );
  });

  testWidgets('内置情景不可修改', (tester) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
    final baseline = (await withCurrentScope(
      tester,
      (scope) => ScenarioRepository(scope).rows(),
    )).firstWhere((r) => r.kind == 'builtin_baseline');
    await goTo(tester, AppRoutes.editScenario(baseline.id));
    expect(find.text('内置情景不可修改'), findsOneWidget);
  });

  testWidgets('不足两个计算版本时，对比页提示先重算', (tester) async {
    await pumpCardFlowApp(tester);
    await goTo(tester, AppRoutes.scenarioCompare());
    expect(find.text(ScenarioComparePage.needTwoRuns), findsOneWidget);
  });

  testWidgets('对比两个情景：基准预期 v1 与 收入推迟 3 天 v1，逐账户最低现金、日期与缺口数', (tester) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
    await goTo(tester, AppRoutes.scenarioCompare());
    final a = find.byKey(const ValueKey<String>('compare-a'));
    final b = find.byKey(const ValueKey<String>('compare-b'));
    await _tap(
      tester,
      find.descendant(
        of: a,
        matching: find.widgetWithText(ChoiceChip, '基准预期 v1'),
      ),
    );
    await _tap(
      tester,
      find.descendant(
        of: b,
        matching: find.widgetWithText(ChoiceChip, '收入推迟 3 天 v1'),
      ),
    );
    expect(find.text('基准预期 v1 与 收入推迟 3 天 v1'), findsOneWidget);
    await _scrollTo(tester, find.textContaining('缺口点：A 2 · B 4 · 差异 +2'));
    expect(find.text('最低日期：A 2026-11-01 · B 2026-11-08'), findsOneWidget);
  });
}
