// 卡账首页（简报 U-1 §2、§7）：首次空白（大号"添加第一张卡"与"体验演示"）、加载与错误、演示空间每张卡一行的
// 金额与日期、汇总卡、"今天刷哪张"的弹层、待处理、排序菜单、没有规则的"设置账期"、汇总卡点开的负债明细、
// 一步推进"银行已入账"。读模型的口径在 test/data/repositories/ledger_home_test.dart。
import 'dart:async';

import 'package:cardflow/app/widgets/state_views.dart';
import 'package:cardflow/data/repositories/ledger_home.dart';
import 'package:cardflow/data/repositories/ledger_models.dart';
import 'package:cardflow/data/repositories/ledger_reader.dart';
import 'package:cardflow/data/repositories/providers.dart';
import 'package:cardflow/features/cards/account_settings_page.dart';
import 'package:cardflow/features/cards/new_card_page.dart';
import 'package:cardflow/features/home/ledger_home_page.dart';
import 'package:cardflow/features/home/repayment_quick_actions.dart';
import 'package:cardflow/features/repayments/repayment_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../data/repositories/repository_test_support.dart';
import '../../support/forbidden_ui.dart';
import '../../test_helpers.dart';

/// 某一行（按标题找到卡账行）。
Finder _row(String title) => find.ancestor(
  of: find.text(title),
  matching: find.byType(CardLedgerRowTile),
);

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
  testWidgets('首次空白：还没有卡 → "还没有信用卡"、大号「添加第一张卡」进新建卡片、另有「体验演示」', (tester) async {
    await pumpCardFlowApp(tester);
    expect(appBarTitle(LedgerHomePage.title), findsOneWidget);
    expect(find.text(LedgerHomePage.firstRunMessage), findsOneWidget);
    final add = find.widgetWithText(FilledButton, '添加第一张卡');
    expect(tester.getSize(add).height, greaterThanOrEqualTo(56));
    expect(tester.getSize(add).width, greaterThan(300));
    expect(find.widgetWithText(OutlinedButton, '体验演示'), findsOneWidget);
    // 页顶不再显示"演示""纯本地"标签（"纯本地"在"我的"里）。
    expect(find.text('纯本地'), findsNothing);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(appBarTitle(NewCardPage.title), findsOneWidget);
  });

  testWidgets('加载：骨架；错误：错误码与「重试」', (tester) async {
    final pending = Completer<LedgerHome>();
    await pumpCardFlowApp(
      tester,
      overrides: <Override>[
        ledgerHomeProvider.overrideWith((ref) => pending.future),
      ],
    );
    expect(find.byType(LoadingSkeleton), findsOneWidget);
  });

  testWidgets('错误：显示错误码与「重试」', (tester) async {
    await pumpCardFlowApp(
      tester,
      overrides: <Override>[
        ledgerHomeProvider.overrideWith(
          (ref) => Future<LedgerHome>.error(StateError('x')),
        ),
      ],
    );
    expect(find.text('卡账读取失败'), findsOneWidget);
    expect(find.text('错误码：StateError'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '重试'), findsOneWidget);
  });

  group('演示空间', () {
    testWidgets('每张卡一行：银行简称 + 末四位、产品名、待还（大字）、账单、N 天后出账、N 天后还款；'
        '没有账单的写"—"与未出账，还款日是下一期（次要色、写"下期"）', (tester) async {
      await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
      await _scrollTo(tester, _row('星海 ···· 1001'));
      final a = _row('星海 ···· 1001');
      // 待还与账单都是 2,393.33（还没有银行入账的还款）。
      expect(
        find.descendant(of: a, matching: find.text('¥2,393.33')),
        findsNWidgets(2),
      );
      for (final text in <String>['白金卡', '待还', '账单', '11-10', '10-28']) {
        expect(
          find.descendant(of: a, matching: find.text(text)),
          findsOneWidget,
          reason: text,
        );
      }
      expect(
        find.descendant(
          of: a,
          matching: find.textContaining('25 天后出账', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: a,
          matching: find.textContaining('12 天后还款', findRichText: true),
        ),
        findsOneWidget,
      );
      await _scrollTo(tester, _row('长江 ···· 2001'));
      final b = _row('长江 ···· 2001');
      expect(find.descendant(of: b, matching: find.text('—')), findsOneWidget);
      expect(
        find.descendant(of: b, matching: find.text('未出账')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: b, matching: find.text('下期 11-08')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: b,
          matching: find.textContaining('4 天后出账', findRichText: true),
        ),
        findsOneWidget,
      );
      // 默认按还款日：未结清的星海在前，其余按下一期到期日（长江 2001 11-08、北辰 11-25、长江 4001 12-05）。
      final order = tester
          .widgetList<CardLedgerRowTile>(find.byType(CardLedgerRowTile))
          .map((t) => t.row.title)
          .toList();
      expect(order.first, '星海 ···· 1001');
    });

    testWidgets('汇总卡：本期待还合计与卡数、最近一笔到期、3 天内到期、总额度（池只算一次）与可用；'
        '点开是负债明细', (tester) async {
      await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
      final hero = find.byType(SummaryHeroCard);
      // 合计与"最近一笔"都是 2,393.33（只有星海一张卡欠着）。
      expect(
        find.descendant(of: hero, matching: find.text('¥2,393.33')),
        findsNWidgets(2),
      );
      for (final text in <String>[
        '本期待还 · 1 张卡',
        '3 天内到期',
        '0 笔',
        '总额度',
        '¥50,000',
        '可用',
        '¥28,800',
      ]) {
        expect(
          find.descendant(of: hero, matching: find.text(text)),
          findsOneWidget,
          reason: text,
        );
      }
      expect(
        find.descendant(of: hero, matching: find.text('最近一笔 10-28 到期 · 星海')),
        findsOneWidget,
      );
      await tester.tap(hero);
      await tester.pumpAndSettle();
      expect(find.text('负债明细'), findsOneWidget);
      expect(find.text('总负债'), findsOneWidget);
    });

    testWidgets('今天刷哪张：免息最长的星海 43 天；点开是前几名与口径说明', (tester) async {
      await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
      final tile = find.byType(TodayPickTile);
      expect(
        find.descendant(of: tile, matching: find.text('今天刷星海 ···· 1001')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile, matching: find.text('11-10 出账 · 11-28 还款')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile, matching: find.text('43')),
        findsOneWidget,
      );
      await tester.tap(tile);
      await tester.pumpAndSettle();
      final sheet = find.byType(TodayCandidatesSheet);
      expect(
        find.descendant(of: sheet, matching: find.text('43 天免息')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('40 天免息')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('23 天免息')),
        findsOneWidget,
      );
      expect(find.text(LedgerHomePage.todayBasis), findsOneWidget);
      // 长江 4001 超限（可用为 0）不在候选里。
      expect(
        find.descendant(of: sheet, matching: find.text('长江 ···· 4001')),
        findsNothing,
      );
    });

    testWidgets('待处理：一行"3 项待处理 ›"进还款与核对', (tester) async {
      await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
      await tester.tap(find.text('3 项待处理'));
      await tester.pumpAndSettle();
      expect(appBarTitle(RepaymentCenterPage.title), findsOneWidget);
    });

    testWidgets('排序菜单：按出账日、按待还金额', (tester) async {
      await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
      List<String> order() => tester
          .widgetList<CardLedgerRowTile>(find.byType(CardLedgerRowTile))
          .map((t) => t.row.title)
          .toList();
      await _scrollTo(tester, find.text('按还款日'));
      await tester.tap(find.text('排序'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('按出账日'));
      await tester.pumpAndSettle();
      expect(find.text('按出账日'), findsOneWidget);
      expect(order().first, '长江 ···· 2001', reason: '10-20 出账最早');
      await tester.tap(find.text('排序'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('按待还金额'));
      await tester.pumpAndSettle();
      expect(order().first, '星海 ···· 1001');
    });

    testWidgets('一步推进：已登记的还款「银行已入账」→ 确认后变为银行已入账，下一步是「银行确认」；文案不写"成功"', (
      tester,
    ) async {
      await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
      await _scrollTo(tester, find.text('银行已入账'));
      await tester.tap(find.text('银行已入账'));
      await tester.pumpAndSettle();
      expect(find.text('银行已入账？'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '银行已入账'));
      await tester.pumpAndSettle();
      expect(
        find.text(advancedMessages[PendingStep.creditPosted]!),
        findsOneWidget,
      );
      final data = await withCurrentScope(
        tester,
        (scope) => LedgerReader(scope).load(),
      );
      final manual = data.repayments.firstWhere((r) => r.method == 'manual');
      expect(manual.status, RepaymentStatus.creditPosted.code);
      await _scrollTo(tester, find.text('银行确认'));
      expect(find.text('银行确认'), findsOneWidget);
      await expectNoForbiddenRepaymentUi(tester, page: '卡账');
    });
  });

  testWidgets('没有账期规则：两个日期格改为「设置账期 ›」，进账期规则设置', (tester) async {
    await pumpCardFlowApp(
      tester,
      seed: (scope) async {
        await createTestCard(scope, bank: '中国银行', last4: '6006');
      },
    );
    final row = _row('中行 ···· 6006');
    expect(row, findsOneWidget);
    await tester.tap(find.descendant(of: row, matching: find.text('设置账期')));
    await tester.pumpAndSettle();
    expect(find.byType(AccountSettingsPage), findsOneWidget);
    expect(
      appRouter(tester)
          .routerDelegate
          .currentConfiguration
          .uri
          .queryParameters['section'],
      'rule',
    );
  });
}
