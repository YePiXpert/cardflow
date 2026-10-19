// P-06 还款登记与核对（ui-spec P-06）：四态（首次空白、加载、错误、成功）；登记表单：多期分配实时合计，
// 合计 ≠ 还款额时禁止保存（F-33）、超应还提示、受限账户警告；保存后"已登记（待银行确认）"；时间线与动作
// （确认扣款、我已还款）；核对区处理疑似重复；全程不出现"还款成功"与绿色（robust）色。
import 'dart:async';

import 'package:cardflow/app/routes.dart';
import 'package:cardflow/app/theme/tokens.dart';
import 'package:cardflow/app/widgets/state_views.dart';
import 'package:cardflow/data/repositories/cash_models.dart';
import 'package:cardflow/data/repositories/ledger_reader.dart';
import 'package:cardflow/data/repositories/providers.dart';
import 'package:cardflow/features/repayments/repayment_form_page.dart';
import 'package:cardflow/features/repayments/repayment_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../data/repositories/repository_test_support.dart';
import '../../test_helpers.dart';
import '../statements/statement_pages_test.dart' show readLedger, seedLedger;

Finder _field(String label) => find.widgetWithText(TextField, label);

Future<void> _scrollTo(
  WidgetTester tester,
  Finder finder, {
  double delta = 200,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
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

/// 页面上没有任何 robust（绿色，只属于 FEASIBLE_ROBUST）的颜色。
void _expectNoRobustColor(WidgetTester tester) {
  final robust = <Color>{
    CardFlowColors.light.robust.fg,
    CardFlowColors.light.robust.bg,
  };
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    expect(robust.contains(text.style?.color), isFalse, reason: text.data);
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
  testWidgets('首次空白："本期还没有还款记录"「登记还款」进入表单', (tester) async {
    await pumpCardFlowApp(
      tester,
      seed: (scope) async {
        await createTestCard(scope, alias: '卡 A');
      },
    );
    await goTo(tester, AppRoutes.repayments());
    expect(appBarTitle(RepaymentCenterPage.title), findsOneWidget);
    expect(find.text(RepaymentCenterPage.firstRunMessage), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '登记还款'));
    await tester.pumpAndSettle();
    expect(appBarTitle(RepaymentFormPage.title), findsOneWidget);
  });

  testWidgets('加载：骨架；错误：错误码与「重新加载」', (tester) async {
    final pending = Completer<LedgerData>();
    await pumpCardFlowApp(
      tester,
      overrides: <Override>[
        ledgerProvider.overrideWith((ref) => pending.future),
      ],
    );
    await goTo(tester, AppRoutes.repayments());
    expect(find.byType(LoadingSkeleton), findsOneWidget);
  });

  testWidgets('错误：错误码与「重新加载」', (tester) async {
    await pumpCardFlowApp(
      tester,
      overrides: <Override>[
        ledgerProvider.overrideWith(
          (ref) => Future<LedgerData>.error(StateError('x')),
        ),
      ],
    );
    await goTo(tester, AppRoutes.repayments());
    expect(find.text('还款读取失败'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
  });

  testWidgets('登记还款：从账单进入预填剩余应还；分配合计 ≠ 还款额时禁止保存（F-33）；超应还提示；须选现金账户；'
      '保存 → "已登记（待银行确认）"，没有"还款成功"、没有绿色', (tester) async {
    await pumpCardFlowApp(tester, seed: seedLedger);
    final statement = (await readLedger(tester)).statements.single;
    await goTo(tester, AppRoutes.statement(statement.id));
    await _tap(tester, find.widgetWithText(FilledButton, '登记还款'));
    expect(appBarTitle(RepaymentFormPage.title), findsOneWidget);
    // 剩余应还 1,572 预填到还款额与这一期的分配。
    expect(tester.widget<TextField>(_field('还款额')).controller!.text, '1572.00');
    await tester.enterText(_field('还款额'), '2000');
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text(RepaymentFormPage.allocationMismatch));
    final save = find.widgetWithText(FilledButton, '登记');
    await _scrollTo(tester, save);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    // 分到这期 2,000（超过剩余应还）：合计相等，可以保存，并提示溢缴。
    await _scrollTo(tester, _field('分到这期（2026-10-10）'), delta: -200);
    await tester.enterText(_field('分到这期（2026-10-10）'), '2000');
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.textContaining('多出的部分会成为溢缴款'));
    await _scrollTo(tester, save);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('请选择扣款的现金账户'), findsOneWidget);
    await _tap(tester, find.widgetWithText(ChoiceChip, '工资卡（CNY）'));
    await _tap(tester, save);
    expect(find.text(RepaymentFormPage.savedMessage), findsWidgets);
    expect(appBarTitle(RepaymentDetailPage.title), findsOneWidget);
    expect(find.text('已登记（待银行确认）'), findsWidgets);
    expect(find.textContaining('还款成功'), findsNothing);
    _expectNoRobustColor(tester);
  });

  testWidgets('受限账户警告（R-CASH-01）', (tester) async {
    await pumpCardFlowApp(
      tester,
      seed: (scope) async {
        await seedLedger(scope);
        await createTestCashAccount(
          scope,
          name: '定期',
          kind: CashAccountKind.restricted,
        );
      },
    );
    await goTo(tester, AppRoutes.newRepayment());
    await _tap(tester, find.widgetWithText(ChoiceChip, '定期（CNY）'));
    await _scrollTo(tester, find.textContaining('这是受限资金或不可用于还款的账户'));
  });

  testWidgets('时间线与动作：「确认扣款」记录扣款时点；「我已还款」只到用户已标记（不是银行确认）', (tester) async {
    await pumpCardFlowApp(tester, seed: seedLedger);
    final data = await readLedger(tester);
    final manual = data.repayments.firstWhere((r) => r.method == 'manual');
    final auto = data.repayments.firstWhere((r) => r.method == 'auto_debit');

    await goTo(tester, AppRoutes.repayment(manual.id));
    expect(find.text('时间线'), findsOneWidget);
    await _tap(tester, find.widgetWithText(OutlinedButton, '我已还款'));
    expect(find.textContaining('这只是你的确认，不是银行确认'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '我已还款'));
    await tester.pumpAndSettle();
    expect(find.text('已记录：你已确认（待银行确认）'), findsOneWidget);
    await _scrollTo(tester, find.textContaining('"我已还款"只是你的确认'), delta: -200);
    expect(
      (await readLedger(tester)).repayment(manual.id)!.status,
      'user_marked_paid',
    );

    await goTo(tester, AppRoutes.repayment(auto.id));
    await _tap(tester, find.widgetWithText(FilledButton, '确认扣款'));
    await tester.enterText(_field('扣款时刻（HH:MM，不晚于现在）'), '09:00');
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();
    expect(find.text('已记录现金扣款（待银行入账）'), findsOneWidget);

    final after = await readLedger(tester);
    expect(
      after.repayment(auto.id)!.cashDebitedAt,
      '2026-10-18T09:00:00+08:00',
    );
    expect(after.repaymentEvents[auto.id]!.postingStatus, 'posted');
    expect(find.textContaining('还款成功'), findsNothing);
  });

  testWidgets('核对区：疑似重复还款「确为两笔」→ 已处理的差异显示结果与处理者', (tester) async {
    await pumpCardFlowApp(tester, seed: seedLedger);
    await goTo(tester, AppRoutes.repayments());
    await _scrollTo(tester, find.text('疑似重复还款'));
    expect(find.textContaining('同一天、同一账户、同金额'), findsOneWidget);
    await _tap(tester, find.widgetWithText(FilledButton, '确为两笔'));
    expect(find.text('已标记：确为两笔还款'), findsOneWidget);
    await _scrollTo(tester, find.textContaining('结果：确为两笔还款 · 处理者：本机用户'));
    final data = await readLedger(tester);
    expect(
      data.items.where((i) => i.kind == 'duplicate_repayment').single.status,
      'resolved',
    );
  });
}
