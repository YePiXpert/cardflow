// 撤销入口（审查 R-16、R-07、Q-3）：账单中心"不在已录账单里的交易"与账单详情的交易行有「删除」「补入账日」，
// 已转分期的交易先提示作废分期；分期卡片「作废（录错了）」；入账日未知、可能账期跨过本期账单日的交易标"可能
// 已出账，请补入账日"；删除退款后它的"退款待核对"由系统标为已处理并写明原因。都调用已有的仓库方法。
import 'package:cardflow/app/routes.dart';
import 'package:cardflow/data/repositories/installment_repository.dart';
import 'package:cardflow/data/repositories/ledger_models.dart';
import 'package:cardflow/data/repositories/ledger_reader.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow/features/statements/statement_pages.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../data/repositories/repository_test_support.dart';
import '../../support/forbidden_ui.dart';
import '../../test_helpers.dart';

Future<LedgerData> _ledger(WidgetTester tester) =>
    withCurrentScope(tester, (scope) => LedgerReader(scope).load());

/// 一个真实空间：卡 A（10 日出账、28 日到期，入账延迟 0–3 天）；10-10 账单 500；10-09 晚上一笔入账日未知的
/// 机票（可能在 10-10 或 11-10 出账）；10-12 一笔入账日未知的"咖啡"；10-13 的"家电"转 3 期（首期 11-10，
/// 各期都还没出账）；10-14 的"手机"转 6 期；10-15 一笔退款（退款待核对）。
Future<void> _seed(WorkspaceScope scope) async {
  final card = await createTestCard(scope, alias: '卡 A');
  await declareTestRule(scope, card.creditAccountId, postingDelayMax: 3);
  final sub = (await primaryCurrencyAccount(scope, card.creditAccountId)).id;
  await recordTestStatement(scope, sub, newBalance: 50000, minDue: 5000);
  await addTestTransaction(
    scope,
    sub,
    amount: 120000,
    txnAt: '2026-10-09T20:00:00+08:00',
    merchant: '机票',
    unposted: true,
  );
  await addTestTransaction(
    scope,
    sub,
    amount: 3500,
    txnAt: '2026-10-12T09:00:00+08:00',
    merchant: '咖啡',
    unposted: true,
  );
  for (final (merchant, day, periods) in <(String, int, int)>[
    ('家电', 13, 3),
    ('手机', 14, 6),
  ]) {
    final txn = await addTestTransaction(
      scope,
      sub,
      amount: 300000,
      txnAt: '2026-10-${day}T10:00:00+08:00',
      merchant: merchant,
    );
    await InstallmentRepository(scope).create(
      InstallmentDraft(
        transactionId: txn.id,
        periods: periods,
        perPeriodRate: Rational.parseDecimal('0.006'),
      ),
    );
  }
  await addTestTransaction(
    scope,
    sub,
    type: TxnType.refund,
    amount: -2000,
    txnAt: '2026-10-15T10:00:00+08:00',
    merchant: '退货',
  );
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

/// 某笔交易那一行里的按钮。
Finder _rowButton(String title, String label) => find.descendant(
  of: find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
  matching: find.widgetWithText(TextButton, label),
);

void main() {
  testWidgets('账单中心列出不在已录账单里的交易；「补入账日」写入入账日；「删除」已转分期的先提示作废分期，确认后'
      '计划作废、交易删除；删除退款后"退款待核对"由系统标为已处理（写明原因）；整页没有"还款成功"与绿色', (tester) async {
    await pumpCardFlowApp(tester, seed: _seed);
    await goTo(tester, AppRoutes.statements());
    await _scrollTo(tester, find.text('${StatementCenterPage.looseTitle}（4）'));
    await expectNoForbiddenRepaymentUi(tester, page: '账单中心（含交易）');

    // 补入账日：咖啡（入账日未知）→ 选默认的交易日。
    await _scrollTo(tester, _rowButton('消费 · 咖啡', '补入账日'));
    await tester.tap(_rowButton('消费 · 咖啡', '补入账日'));
    await tester.pumpAndSettle();
    expect(find.text('补入账日'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('已补入账日（你已确认）'), findsOneWidget);
    var data = await _ledger(tester);
    final coffee = data.transactions.firstWhere((t) => t.merchant == '咖啡');
    expect((coffee.postedOn, coffee.status), ('2026-10-12', 'posted'));

    // 删除已转分期的"家电"：先提示作废分期。
    await _scrollTo(tester, _rowButton('消费 · 家电', '删除'));
    await tester.tap(_rowButton('消费 · 家电', '删除'));
    await tester.pumpAndSettle();
    expect(find.text('这笔已转分期：先作废分期再删除？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '作废分期并删除'));
    await tester.pumpAndSettle();
    expect(find.text('已作废分期并删除这笔交易'), findsOneWidget);
    data = await _ledger(tester);
    expect(data.transactions.where((t) => t.merchant == '家电'), isEmpty);
    expect(
      data.plans.map((p) => p.status).toList(),
      containsAll(<String>['cancelled', 'active']),
    );

    // 删除退款：它的差异项由系统处理。
    await _scrollTo(tester, _rowButton('退款 · 退货', '删除'));
    await tester.tap(_rowButton('退款 · 退货', '删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除这笔交易？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(find.text('已删除这笔交易'), findsOneWidget);
    data = await _ledger(tester);
    expect(data.openItems, isEmpty);
    await goTo(tester, AppRoutes.repayments());
    await _scrollTo(tester, find.textContaining('结果：系统处理（引用的交易已删除） · 处理者：系统'));
  });

  testWidgets('账单详情：入账日未知、可能账期跨过本期账单日的机票标"可能已出账，请补入账日"；分期卡片「作废（录错了）」'
      '确认后计划作废，原消费回到未出账', (tester) async {
    await pumpCardFlowApp(tester, seed: _seed);
    final data = await _ledger(tester);
    final statement = data.statements.single;
    final ticket = data.transactions.firstWhere((t) => t.merchant == '机票');
    expect(data.mayBeBilled(ticket), isTrue);
    await goTo(tester, AppRoutes.statement(statement.id));
    await _scrollTo(tester, find.text(TransactionTile.mayBeBilledText));
    await _scrollTo(tester, _rowButton('消费 · 机票', '补入账日'));

    final phone = data.plans.firstWhere(
      (p) => data.transaction(p.transactionId)?.merchant == '手机',
    );
    await _scrollTo(tester, find.text('手机 · 6 期 · 进行中'));
    final cancel = find.descendant(
      of: find.ancestor(
        of: find.text('手机 · 6 期 · 进行中'),
        matching: find.byType(Card),
      ),
      matching: find.widgetWithText(
        TextButton,
        InstallmentPlanCard.cancelLabel,
      ),
    );
    await _scrollTo(tester, cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(find.text('作废这个分期计划？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '作废'));
    await tester.pumpAndSettle();
    expect(find.text('已作废分期计划'), findsOneWidget);
    final after = await _ledger(tester);
    final plan = after.plans.firstWhere((p) => p.id == phone.id);
    expect(plan.status, 'cancelled');
    expect(
      after.liabilities.values.single.unbilled,
      greaterThanOrEqualTo(300000),
      reason: '原消费回到未出账',
    );
  });
}
