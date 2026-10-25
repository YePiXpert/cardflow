import 'package:cardflow/app/money/amount_visibility.dart';
import 'package:cardflow/app/routes.dart';
import 'package:cardflow/data/repositories/providers.dart';
import 'package:cardflow/features/cards/amount_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers.dart';

Future<void> compare(WidgetTester t, String amount) async {
  final field = find.widgetWithText(TextField, '消费金额');
  await t.ensureVisible(field);
  await t.enterText(field, amount);
  final button = find.text('比较用卡');
  await t.ensureVisible(button);
  await t.tap(button);
  await t.pumpAndSettle();
}

void main() {
  test('金额精确到币种最小单位，拒绝超精度、负数与超限', () {
    expect(parseAmountMinor('1,234.56', 'CNY').$1, 123456);
    expect(parseAmountMinor('1.001', 'CNY').$2, isNotNull);
    expect(parseAmountMinor('-1', 'CNY').$2, isNotNull);
    expect(parseAmountMinor('100000000000000', 'CNY').$2, isNotNull);
    expect(parseAmountMinor('12.1', 'JPY').$2, isNotNull);
    expect(parseAmountMinor('12.123', 'KWD').$1, 12123);
  });
  testWidgets('空白引导建卡，空金额与零金额阻止推荐', (t) async {
    await pumpCardFlowApp(t);
    await compare(t, '');
    expect(find.text('请填写金额'), findsOneWidget);
    await compare(t, '0');
    expect(find.text('消费金额须大于 0'), findsOneWidget);
    await compare(t, '100');
    await t.scrollUntilVisible(
      find.text('暂无可推荐的卡，请查看下方原因。'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('暂无可推荐的卡，请查看下方原因。'), findsOneWidget);
  });
  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('比较结果、隐藏金额及布局 ${scale}x', (t) async {
      await pumpCardFlowApp(t, workspace: TestWorkspace.demo, textScale: scale);
      await compare(t, '100');
      await t.scrollUntilVisible(
        find.text('推荐使用'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('推荐使用'), findsOneWidget);
      expect(t.takeException(), isNull);
      appContainer(t).read(amountsHiddenProvider.notifier).setHidden(true);
      await t.pumpAndSettle();
      expect(find.text('••••'), findsWidgets);
      for (var i = 0; i < 8; i++) {
        await t.drag(find.byType(ListView).first, const Offset(0, -450));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }
    });
  }
  testWidgets('额度资料变化自动重算，修改消费输入清除旧结果', (t) async {
    await pumpCardFlowApp(t, workspace: TestWorkspace.demo);
    await compare(t, '100');
    final wallet = await readWallet(t);
    await t.runAsync(() async {
      final repo = await appContainer(t).read(cardRepositoryProvider.future);
      for (final a in wallet.accounts) {
        for (final c in a.cards) {
          if (c.status == 'active') {
            await repo.freeze(c.id);
          }
        }
      }
    });
    await t.pumpAndSettle();
    expect(find.text('推荐使用'), findsNothing);
    await compare(t, '0');
    expect(find.text('暂无可推荐的卡，请查看下方原因。'), findsNothing);
    await goTo(t, AppRoutes.cards);
    expect(find.text('现金'), findsNothing);
  });
  testWidgets('首页默认直出当日选卡排行；单卡不足展示多卡组合方案；支持快速改额度', (t) async {
    await pumpCardFlowApp(t, workspace: TestWorkspace.demo);
    expect(find.text('当日选卡排行'), findsOneWidget);

    // 演示空间：卡 A 可用 8000（11-28 到期）、卡 C 可用 6000（11-25 到期）、卡 B 可用 14800（11-08 到期）
    // 输入 15000 超过所有单卡额度，按还款日从晚到早分 3 张卡凑齐（卡 A 8000 + 卡 C 6000 + 卡 B 1000）
    await compare(t, '15000');
    await t.scrollUntilVisible(
      find.text('组合用卡方案'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('组合用卡方案'), findsOneWidget);
    expect(find.textContaining('单张卡可用额度不足，按还款日从晚到早分 3 张卡刷齐'), findsOneWidget);

    // 超过全部可用卡总额度（28800）时提示合计最多可刷
    final scroll = t
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    scroll.jumpTo(0);
    await t.pumpAndSettle();
    await compare(t, '30000');
    await t.scrollUntilVisible(
      find.text('全部可用卡合计最多可刷'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('全部可用卡合计最多可刷'), findsOneWidget);

    // 快速改额度：把卡 A 额度从 8000 改为 20000 后，15000 可单卡直接推荐
    scroll.jumpTo(0);
    await t.pumpAndSettle();
    await compare(t, '100');
    final quickBtn = find.widgetWithText(TextButton, '快速改额度');
    await t.scrollUntilVisible(
      quickBtn,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.ensureVisible(quickBtn);
    await t.tap(quickBtn);
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, '当前可用额度'), '20000');
    await t.tap(find.widgetWithText(FilledButton, '保存额度'));
    await t.pumpAndSettle();
    expect(find.text('已更新可用额度'), findsOneWidget);

    scroll.jumpTo(0);
    await t.pumpAndSettle();
    await compare(t, '15000');
    await t.scrollUntilVisible(
      find.text('推荐使用'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('推荐使用'), findsOneWidget);
  });
}
