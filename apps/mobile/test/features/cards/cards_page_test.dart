// P-02 卡包与新建弹层（ui-spec P-02）：四态、层级列表（授信池 › 账户 › 卡片）、超限标注、
// 新建卡片（生成账户与 CNY 子账户、"已添加 › 设置账期"）、G2（粘贴完整卡号即拦下且不落库）、
// 末四位、同银行同末四位提示、附卡须指定主卡、关闭系统自动填充。
import 'dart:async';

import 'package:cardflow/app/routes.dart';
import 'package:cardflow/app/widgets/money_text.dart';
import 'package:cardflow/app/widgets/state_views.dart';
import 'package:cardflow/data/repositories/card_wallet_reader.dart';
import 'package:cardflow/data/repositories/providers.dart';
import 'package:cardflow/data/validation/text_rules.dart';
import 'package:cardflow/features/cards/cards_page.dart';
import 'package:cardflow/features/cards/new_card_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../data/repositories/repository_test_support.dart';
import '../../test_helpers.dart';

Finder _field(String label) => find.widgetWithText(TextField, label);

Future<void> _openNewCard(WidgetTester tester) async {
  await goTo(tester, AppRoutes.cards);
  await tester.tap(find.byTooltip('添加卡片'));
  await tester.pumpAndSettle();
  expect(appBarTitle(NewCardPage.title), findsOneWidget);
}

Future<void> _chooseBank(WidgetTester tester, String bank) async {
  await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, '银行'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(bank).last);
  await tester.pumpAndSettle();
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
    final file = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '从账单文件开始'),
    );
    expect(file.onPressed, isNull);
    expect(find.text('从账单文件开始：后续版本提供'), findsOneWidget);
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

  testWidgets('成功（演示数据）：授信池 › 账户 › 卡片；超限账户标"超限"、容量 0', (tester) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
    await goTo(tester, AppRoutes.cards);
    expect(find.text('授信池 · 乙行共享额度'), findsOneWidget);
    expect(find.text('池上限'), findsOneWidget);
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

  testWidgets('新建卡片：生成账户与 CNY 子账户，回到卡包并提示"已添加 › 设置账期"', (tester) async {
    await pumpCardFlowApp(tester);
    await _openNewCard(tester);
    await _chooseBank(tester, '招商银行');
    await tester.enterText(_field('别名（可选）'), '工资卡');
    await tester.enterText(_field('末四位'), '4321');
    await _save(tester);

    expect(appBarTitle(CardsPage.title), findsOneWidget);
    expect(find.text(NewCardPage.savedMessage), findsOneWidget);
    expect(find.text('设置账期'), findsOneWidget);
    expect(find.text('工资卡'), findsOneWidget);
    final wallet = await _wallet(tester);
    expect(wallet.accounts.single.currencies.single.currency, 'CNY');
    expect(wallet.accounts.single.cards.single.last4, '4321');
  });

  testWidgets('G2：粘贴完整卡号当场提示，保存被拦下且不落库；系统自动填充关闭', (tester) async {
    await pumpCardFlowApp(tester);
    await _openNewCard(tester);
    await _chooseBank(tester, '招商银行');
    await tester.enterText(_field('别名（可选）'), '卡号 6222020200112233445');
    await tester.pump();
    expect(find.text(fullCardNumberMessage), findsOneWidget);
    await tester.enterText(_field('末四位'), '６２２２０２０２００１１２２３３４４５');
    await tester.pump();
    expect(find.text(fullCardNumberMessage), findsNWidgets(2));
    await _save(tester);
    expect(appBarTitle(NewCardPage.title), findsOneWidget);
    expect((await _wallet(tester)).accounts, isEmpty);
    for (final label in <String>['别名（可选）', '末四位', '持卡人', '产品名（可选）']) {
      final field = tester.widget<TextField>(_field(label));
      expect(field.autofillHints, isNull, reason: label);
    }
  });

  testWidgets('末四位须恰好 4 位数字；附卡须指定主卡', (tester) async {
    await pumpCardFlowApp(tester);
    await _openNewCard(tester);
    await _chooseBank(tester, '招商银行');
    await tester.enterText(_field('末四位'), '123');
    await _save(tester);
    expect(find.text(last4Message), findsOneWidget);

    await _scrollTo(tester, find.text('附属卡'), delta: -200);
    await tester.tap(find.text('附属卡'));
    await tester.pumpAndSettle();
    expect(find.textContaining('还没有主卡'), findsOneWidget);
    await tester.enterText(_field('末四位'), '1234');
    await _save(tester);
    expect(appBarTitle(NewCardPage.title), findsOneWidget);
    expect((await _wallet(tester)).accounts, isEmpty);
  });

  testWidgets('同银行同末四位：提示"可能是同一信用账户的另一张卡"，加入既有账户后只有一个账户', (tester) async {
    await pumpCardFlowApp(
      tester,
      seed: (scope) async {
        await createTestCard(scope, bank: '招商银行', last4: '1234', alias: '主卡');
      },
    );
    await _openNewCard(tester);
    await _chooseBank(tester, '招商银行');
    await tester.enterText(_field('末四位'), '1234');
    await _save(tester);
    expect(find.text(NewCardPage.sameAccountTitle), findsOneWidget);
    await tester.tap(find.text('加入既有账户'));
    await tester.pumpAndSettle();
    final wallet = await _wallet(tester);
    expect(wallet.accounts, hasLength(1));
    expect(wallet.accounts.single.cards, hasLength(2));
  });
}
