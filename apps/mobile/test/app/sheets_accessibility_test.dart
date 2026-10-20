// 新的底部弹层与菜单（简报 U-1 §2–§4）也满足可访问性要求：卡账的"今天刷哪张"、负债明细、添加菜单、排序菜单；
// 卡片详情的"⋯"菜单、记本期账单、还清本期；现金页的口径菜单与"未计入"。1 倍字号检查触控尺寸、标签与文字
// 对比度（深浅两种），2/3 倍字号检查布局没有溢出；卡账行在放大后改为金额在上、日期格在下。
import 'package:cardflow/app/routes.dart';
import 'package:cardflow/features/cash/uncounted_dues.dart';
import 'package:cardflow/features/home/ledger_home_page.dart';
import 'package:cardflow/features/home/quick_pay_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

/// 一个弹层：先到哪个页面、点什么打开它。
typedef SheetCase = (String, Future<String> Function(WidgetTester), Finder);

Future<String> _accountA(WidgetTester tester) async {
  final wallet = await readWallet(tester);
  return wallet.accounts.firstWhere((a) => a.bank.name == '星海银行').id;
}

final List<SheetCase> sheets = <SheetCase>[
  ('今天刷哪张', (_) async => AppRoutes.home, find.byType(TodayPickTile)),
  ('负债明细', (_) async => AppRoutes.home, find.byType(SummaryHeroCard)),
  ('添加菜单', (_) async => AppRoutes.home, find.byTooltip('添加')),
  ('排序菜单', (_) async => AppRoutes.home, find.text('排序')),
  (
    '卡片"⋯"菜单',
    (t) async => AppRoutes.account(await _accountA(t)),
    find.byTooltip('更多操作'),
  ),
  ('现金口径菜单', (_) async => AppRoutes.cashHome, find.text('口径：基准预期')),
  ('现金添加菜单', (_) async => AppRoutes.cashHome, find.byTooltip('添加')),
];

/// 在页面的主列表里往下滚，直到找到 [finder]（可能有多个，取第一个），再让它完整露出来。
Future<void> _scrollToFirst(
  WidgetTester tester,
  Finder finder, {
  Finder? scrollable,
}) async {
  final list = scrollable ?? find.byType(Scrollable).first;
  for (var i = 0; i < 50 && finder.evaluate().isEmpty; i++) {
    await tester.drag(list, const Offset(0, -200));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, SheetCase c) async {
  await goTo(tester, await c.$2(tester));
  // 同一个页面会保留滚动位置：先回到顶部，再往下找要点的东西。
  tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .jumpTo(0);
  await tester.pumpAndSettle();
  await _scrollToFirst(tester, c.$3);
  // 3 倍字号时汇总卡比一屏还高：点它露在屏幕里的部分。
  final screen =
      Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
  await tester.tapAt(tester.getRect(c.$3.first).intersect(screen).center);
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester) async {
  // 弹层与菜单都挂在根导航器上：关掉最上面的一个。
  final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
  navigator.pop();
  await tester.pumpAndSettle();
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('弹层与菜单（$brightness）：触控尺寸、标签与文字对比度', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCardFlowApp(
        tester,
        brightness: brightness,
        workspace: TestWorkspace.demo,
      );
      for (final c in sheets) {
        await _open(tester, c);
        for (final guideline in <AccessibilityGuideline>[
          iOSTapTargetGuideline,
          androidTapTargetGuideline,
          labeledTapTargetGuideline,
          textContrastGuideline,
        ]) {
          await expectLater(tester, meetsGuideline(guideline), reason: c.$1);
        }
        await _close(tester);
      }
      handle.dispose();
    });
  }

  for (final scale in <double>[2.0, 3.0]) {
    testWidgets('弹层与菜单在 ${scale}x 字号下正常布局；记本期账单与还清本期的弹层也是', (tester) async {
      await pumpCardFlowApp(
        tester,
        textScale: scale,
        workspace: TestWorkspace.demo,
      );
      for (final c in sheets) {
        await _open(tester, c);
        expect(tester.takeException(), isNull, reason: c.$1);
        await _close(tester);
      }
      // 记本期账单（⋯ 菜单里）。
      await goTo(tester, AppRoutes.account(await _accountA(tester)));
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('记本期账单').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '记本期账单');
      await _close(tester);
      // 未计入 → 还清本期。
      await goTo(tester, AppRoutes.cashHome);
      await _scrollToFirst(tester, find.byType(UncountedDuesTile));
      await tester.tap(find.byType(UncountedDuesTile));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '未计入');
      // 放大字号后弹层里的行很高，「还清本期」可能还没露出来：先在弹层里滚到它。
      final pay = find.descendant(
        of: find.byType(UncountedDuesSheet),
        matching: find.text(QuickPaySheet.title),
      );
      await _scrollToFirst(
        tester,
        pay,
        scrollable: find
            .descendant(
              of: find.byType(UncountedDuesSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(pay.first);
      await tester.pumpAndSettle();
      expect(find.byType(QuickPaySheet), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '还清本期');
    });
  }

  testWidgets('动态字体：2 倍字号时卡账行改为纵向（金额在上，两个日期格在下），金额完整显示', (tester) async {
    await pumpCardFlowApp(tester, textScale: 2, workspace: TestWorkspace.demo);
    await _scrollToFirst(tester, find.byType(CardLedgerRowTile));
    final row = find.byType(CardLedgerRowTile).first;
    final amount = find.descendant(of: row, matching: find.text('待还'));
    final cell = find.descendant(
      of: row,
      matching: find.textContaining('天后出账', findRichText: true),
    );
    expect(
      tester.getTopLeft(amount).dy,
      lessThan(tester.getTopLeft(cell).dy),
      reason: '金额在上',
    );
    expect(
      find.descendant(of: row, matching: find.text('¥2,393.33')),
      findsNWidgets(2),
    );
    expect(tester.takeException(), isNull);
  });
}
