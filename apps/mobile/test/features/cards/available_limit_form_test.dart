import 'package:cardflow/app/routes.dart';
import 'package:cardflow/data/repositories/card_recommendation.dart';
import 'package:cardflow/data/repositories/simple_card_setup.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers.dart';

void main() {
  testWidgets('只填当前可用额度，更新后影响推荐；零和负数不当成未知', (tester) async {
    await pumpCardFlowApp(
      tester,
      seed: (scope) => createSimpleCard(
        scope,
        cardId: 'simple',
        accountId: 'account',
        name: '生活卡',
        last4: '4321',
        available: 100000,
        statementDay: 10,
        dueDay: 28,
      ),
    );
    for (final value in ['2000.01', '0', '-10']) {
      await goTo(
        tester,
        AppRoutes.accountSettings('account', section: 'limits'),
      );
      expect(find.text('固定额度'), findsNothing);
      expect(find.text('已用'), findsNothing);
      await tester.enterText(find.widgetWithText(TextField, '当前可用额度'), value);
      await tester.tap(find.widgetWithText(FilledButton, '更新额度'));
      await tester.pumpAndSettle();
      expect(find.text('已更新可用额度'), findsWidgets);
      final wallet = await readWallet(tester);
      final result = recommendCards(
        wallet: wallet,
        amount: 200001,
        currency: 'CNY',
        on: LocalDate(2026, 10, 18),
      );
      expect(result.eligible.length, value == '2000.01' ? 1 : 0);
      if (value == '-10') {
        expect(
          wallet
              .accounts
              .single
              .primaryCurrency
              .latestSnapshot!
              .availableRawMinor,
          -1000,
        );
      }
    }
    await goTo(tester, AppRoutes.accountSettings('account'));
    expect(find.text('还款日'), findsWidgets);
    expect(find.text('当前可用额度'), findsNothing);
  });

  testWidgets('支持还款后按还款额增加可用额度及一键恢复满额', (tester) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
    final before = await readWallet(tester);
    final cardA = before.accounts.firstWhere((a) => a.displayName == '卡 A');
    expect(cardA.primaryCurrency.availableToday, 800000);

    await goTo(tester, AppRoutes.accountSettings(cardA.id, section: 'limits'));
    await tester.enterText(find.widgetWithText(TextField, '当前可用额度'), '2000');
    await tester.tap(find.text('按还款额增加'));
    await tester.pumpAndSettle();
    expect(find.text('已按还款额增加可用额度'), findsOneWidget);

    final afterRepay = await readWallet(tester);
    final cardAAfterRepay = afterRepay.accounts.firstWhere(
      (a) => a.id == cardA.id,
    );
    expect(cardAAfterRepay.primaryCurrency.availableToday, 1000000);

    // 刷新页面，点击「恢复满额」恢复到 12000（fixedMinor 1000000 + 有效 tempMinor 200000）
    await goTo(tester, AppRoutes.accountSettings(cardA.id, section: 'limits'));
    await tester.tap(find.text('恢复满额'));
    await tester.pumpAndSettle();
    expect(find.text('已恢复满额可用额度'), findsOneWidget);

    final afterFull = await readWallet(tester);
    final cardAAfterFull = afterFull.accounts.firstWhere(
      (a) => a.id == cardA.id,
    );
    expect(cardAAfterFull.primaryCurrency.availableToday, 2000000);
  });
}
