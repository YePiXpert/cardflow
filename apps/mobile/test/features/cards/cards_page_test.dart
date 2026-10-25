// P-02 卡包与新建弹层（ui-spec P-02）：四态、层级列表（授信池 › 账户 › 卡片）、超限标注、
// 新建卡片（生成账户与 CNY 子账户、"已添加 › 设置账期"）、G2（粘贴完整卡号即拦下且不落库）、
// 末四位、同银行同末四位提示、附卡须指定主卡、关闭系统自动填充。
import 'dart:async';

import 'package:cardflow/app/routes.dart';
import 'package:cardflow/app/widgets/money_text.dart';
import 'package:cardflow/app/widgets/state_views.dart';
import 'package:cardflow/data/repositories/card_recommendation.dart';
import 'package:cardflow/data/repositories/card_wallet_reader.dart';
import 'package:cardflow/data/repositories/providers.dart';
import 'package:cardflow/data/validation/text_rules.dart';
import 'package:cardflow/features/cards/cards_page.dart';
import 'package:cardflow/features/cards/new_card_page.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/simple_card_form.dart';
import '../../test_helpers.dart';

Finder _field(String label) => find.widgetWithText(TextField, label);

Future<void> _openNewCard(WidgetTester tester) async {
  await goTo(tester, AppRoutes.cards);
  await tester.tap(find.byTooltip('添加卡片'));
  await tester.pumpAndSettle();
  expect(appBarTitle(NewCardPage.title), findsOneWidget);
}

/// 新建卡片页里的滚动区域（后面还压着卡包页，不能用默认的"唯一 Scrollable"）。
Finder get _formScrollable => find
    .descendant(of: find.byType(NewCardPage), matching: find.byType(Scrollable))
    .first;

Future<void> _scrollTo(
  WidgetTester tester,
  Finder finder, {
  double delta = 200,
}) async {
  await tester.scrollUntilVisible(finder, delta, scrollable: _formScrollable);
  // scrollUntilVisible 只保证已构建（可能还在顶栏下面），再整个滚进可见区。
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  final save = find.widgetWithText(FilledButton, '保存');
  await _scrollTo(tester, save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

Future<WalletView> _wallet(WidgetTester tester) => readWallet(tester);

void main() {
  testWidgets('首次空白：说明、手工建卡、从账单文件开始（后续版本提供，禁用）、体验演示', (tester) async {
    await pumpCardFlowApp(tester);
    await goTo(tester, AppRoutes.cards);
    expect(find.text(CardsPage.firstRunMessage), findsOneWidget);
    expect(find.text('从账单文件开始'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '手工建卡'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('加载：骨架（读屏"读取中"）', (tester) async {
    final pending = Completer<WalletView>();
    await pumpCardFlowApp(
      tester,
      overrides: <Override>[
        walletProvider.overrideWith((ref) => pending.future),
      ],
    );
    await goTo(tester, AppRoutes.cards);
    expect(find.byType(LoadingSkeleton), findsOneWidget);
    expect(
      find.bySemanticsLabel(LoadingSkeleton.semanticsLabel),
      findsOneWidget,
    );
  });

  testWidgets('错误：显示错误与「重试」，不当成空白', (tester) async {
    await pumpCardFlowApp(
      tester,
      overrides: <Override>[
        walletProvider.overrideWith(
          (ref) => Future<WalletView>.error(StateError('boom')),
        ),
      ],
    );
    await goTo(tester, AppRoutes.cards);
    expect(find.text(CardsPage.errorTitle), findsOneWidget);
    expect(find.text('错误码：StateError'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text(CardsPage.firstRunMessage), findsNothing);
  });

  testWidgets('成功（演示数据）：共享额度 › 账户 › 卡片；超限账户标"超限"、容量 0', (tester) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
    await goTo(tester, AppRoutes.cards);
    expect(find.text('共享额度 · 长江共享额度'), findsOneWidget);
    expect(find.text('共享上限'), findsOneWidget);
    for (final name in <String>['卡 A', '卡 B', '卡 D', '卡 C']) {
      await tester.scrollUntilVisible(find.text(name), 200);
      expect(find.text(name), findsOneWidget, reason: name);
    }
    await tester.scrollUntilVisible(find.text('卡 D'), -200);
    final dTile = find.ancestor(
      of: find.text('卡 D'),
      matching: find.byType(AccountTile),
    );
    expect(
      find.descendant(of: dTile, matching: find.text('超限')),
      findsOneWidget,
    );
    final capacity = tester.widget<MoneyText>(
      find.descendant(of: dTile, matching: find.byType(MoneyText)),
    );
    expect(capacity.minor, 0);
    expect(capacity.semanticsPrefix, '可用容量');
  });

  testWidgets('一次建卡后可直接按金额和账期推荐', (tester) async {
    await pumpCardFlowApp(tester);
    await _openNewCard(tester);
    expect(find.text('持卡人'), findsNothing);
    expect(find.text('固定额度'), findsNothing);
    await fillSimpleCard(tester);
    await _save(tester);
    expect(appBarTitle('这笔消费，用哪张卡'), findsOneWidget);
    final wallet = await _wallet(tester);
    expect(wallet.accounts.single.currencies.single.capacity, 500000);
    expect(wallet.accounts.single.cards.single.last4, '4321');
    final result = recommendCards(
      wallet: wallet,
      amount: 500001,
      currency: 'CNY',
      on: LocalDate(2026, 10, 18),
    );
    expect(result.eligible, isEmpty);
    expect(result.excluded.single.reason, '可用额度不足');
    expect(
      recommendCards(
        wallet: wallet,
        amount: 500000,
        currency: 'CNY',
        on: LocalDate(2026, 10, 18),
      ).eligible,
      hasLength(1),
    );
  });

  testWidgets('完整卡号不落库，末四位仍校验，关闭自动填充', (tester) async {
    await pumpCardFlowApp(tester);
    await _openNewCard(tester);
    await tester.enterText(_field('卡名'), '6222020200112233445');
    await tester.pump();
    expect(find.text(fullCardNumberMessage), findsOneWidget);
    await _save(tester);
    expect((await _wallet(tester)).accounts, isEmpty);
    await _scrollTo(tester, _field('卡名'), delta: -200);
    await tester.enterText(_field('卡名'), '生活卡');
    await tester.enterText(_field('末四位'), '123');
    await _save(tester);
    expect(find.text(last4Message), findsOneWidget);
    for (final label in ['卡名', '末四位', '当前可用额度']) {
      await _scrollTo(tester, _field(label), delta: -200);
      expect(tester.widget<TextField>(_field(label)).autofillHints, isNull);
    }
  });

  testWidgets('额度为空或账期未选不创建卡片', (tester) async {
    await pumpCardFlowApp(tester);
    await _openNewCard(tester);
    await tester.enterText(_field('卡名'), '生活卡');
    await tester.enterText(_field('末四位'), '4321');
    await _save(tester);
    expect((await _wallet(tester)).accounts, isEmpty);
    await _scrollTo(tester, _field('当前可用额度'), delta: -200);
    await tester.enterText(_field('当前可用额度'), '5000');
    await _save(tester);
    expect(find.text('请选择账单日和还款日'), findsOneWidget);
    expect((await _wallet(tester)).accounts, isEmpty);
  });

  testWidgets('卡片列表显示今日刷卡距还款天数、出账还款规则，并支持快速改额度', (tester) async {
    await pumpCardFlowApp(tester);
    await _openNewCard(tester);
    await fillSimpleCard(tester);
    await _save(tester);
    await goTo(tester, AppRoutes.cards);
    expect(find.textContaining('今天刷距预计还款'), findsOneWidget);
    expect(find.textContaining('每月 10 日出账'), findsOneWidget);

    final quickBtn = find.widgetWithText(TextButton, '快速改额度');
    await tester.ensureVisible(quickBtn);
    await tester.tap(quickBtn);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '当前可用额度'), '12000');
    await tester.tap(find.widgetWithText(FilledButton, '保存额度'));
    await tester.pumpAndSettle();
    expect(find.text('已更新可用额度'), findsOneWidget);
    expect(
      (await _wallet(tester)).accounts.single.currencies.single.capacity,
      1200000,
    );
  });
}
