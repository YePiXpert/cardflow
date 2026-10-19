// P-05 账单中心（ui-spec P-05）：四态（首次空白、加载、错误、成功；列表与详情）；列表行（剩余应还、到期、状态、
// 确认层级、版本数、差异数）与筛选；详情：版本切换（原值可查）、要素带来源与版本、来源未含的项显示"来源未含此项"
// 而不是 0、负债四分法、交易（退款待核对、可能账期）、分期（每期本金/费用、尾差、名义与实际年化并列）、还款分配、
// 差异清单；列表与详情整页没有"还款成功"、没有绿色（robust 色 token）；贷方余额（F-38）；人工修正生成新版本；
// 记一笔；录入正式账单的校验；已不存在。
import 'dart:async';

import 'package:cardflow/app/routes.dart';
import 'package:cardflow/app/widgets/state_views.dart';
import 'package:cardflow/data/repositories/installment_repository.dart';
import 'package:cardflow/data/repositories/ledger_models.dart';
import 'package:cardflow/data/repositories/ledger_reader.dart';
import 'package:cardflow/data/repositories/providers.dart';
import 'package:cardflow/data/repositories/statement_repository.dart';
import 'package:cardflow/data/repositories/transaction_repository.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow/features/statements/ledger_formatting.dart';
import 'package:cardflow/features/statements/statement_forms.dart';
import 'package:cardflow/features/statements/statement_pages.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../data/repositories/repository_test_support.dart';
import '../../support/forbidden_ui.dart';
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

/// 一个有账单的真实空间：卡 A（10 日出账、28 日到期）；9-21 的 12,000 消费转 12 期（0.6%），第 1 期在 10-10
/// 账单；10-10 账单 v1 → v2 修正（最低还款额抄错）；10-14 一笔退款（待核对）；10-15 一笔自动扣款与一笔
/// 手工还款同额（疑似重复）。
Future<void> seedLedger(WorkspaceScope scope) async {
  final card = await createTestCard(scope, last4: '1001', alias: '卡 A');
  await declareTestRule(scope, card.creditAccountId);
  final sub = (await primaryCurrencyAccount(scope, card.creditAccountId)).id;
  final cash = await createTestCashAccount(scope);
  await recordTestCashSnapshot(
    scope,
    cash.id,
    LocalDate(2026, 10, 15),
    1000000,
  );
  final big = await addTestTransaction(
    scope,
    sub,
    amount: 1200000,
    txnAt: '2026-09-21T10:00:00+08:00',
    merchant: '家电城',
    cardId: card.cardId,
  );
  await InstallmentRepository(scope).create(
    InstallmentDraft(
      transactionId: big.id,
      periods: 12,
      perPeriodRate: Rational.parseDecimal('0.006'),
      firstStatementOn: LocalDate(2026, 10, 10),
    ),
  );
  final statement = await recordTestStatement(
    scope,
    sub,
    newBalance: 157200,
    minDue: 15700,
    installmentDue: 107200,
  );
  await StatementRepository(scope).correct(
    statement.id,
    figures: const StatementFigures(
      newBalanceMinor: 157200,
      minDueMinor: 15720,
      installmentDueMinor: 107200,
    ),
    reason: '最低还款额抄错，按账单更正',
  );
  await addTestTransaction(
    scope,
    sub,
    type: TxnType.refund,
    amount: -15000,
    txnAt: '2026-10-14T10:00:00+08:00',
    merchant: '超市退货',
  );
  await addTestTransaction(scope, sub, amount: 26800, merchant: '超市');
  // 10-15 同额的一笔自动扣款与一笔手工还款：疑似重复（F-32）。
  for (final method in <RepaymentMethod>[
    RepaymentMethod.autoDebit,
    RepaymentMethod.manual,
  ]) {
    await registerTestRepayment(
      scope,
      currencyAccountId: sub,
      cashAccountId: cash.id,
      amount: 50000,
      statementId: statement.id,
      method: method,
      expectedDebitOn: LocalDate(2026, 10, 15),
    );
  }
}

Future<LedgerData> readLedger(WidgetTester tester) =>
    withCurrentScope(tester, (scope) => LedgerReader(scope).load());

void main() {
  testWidgets('首次空白："还没有正式账单"「录入正式账单」「记一笔」，导入在后续版本提供', (tester) async {
    await pumpCardFlowApp(
      tester,
      seed: (scope) async {
        await createTestCard(scope, alias: '卡 A');
      },
    );
    await goTo(tester, AppRoutes.statements());
    expect(appBarTitle(StatementCenterPage.title), findsOneWidget);
    expect(find.text(StatementCenterPage.firstRunMessage), findsOneWidget);
    expect(find.text('导入：后续版本提供'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '录入正式账单'));
    await tester.pumpAndSettle();
    expect(appBarTitle(StatementEntryPage.title), findsOneWidget);
  });

  testWidgets('加载：骨架', (tester) async {
    final pending = Completer<LedgerData>();
    await pumpCardFlowApp(
      tester,
      overrides: <Override>[
        ledgerProvider.overrideWith((ref) => pending.future),
      ],
    );
    await goTo(tester, AppRoutes.statements());
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
    await goTo(tester, AppRoutes.statements());
    expect(find.text('账单读取失败'), findsOneWidget);
    expect(find.text('错误码：StateError'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
  });

  testWidgets('详情页：加载是骨架', (tester) async {
    final pending = Completer<LedgerData>();
    await pumpCardFlowApp(
      tester,
      overrides: <Override>[
        ledgerProvider.overrideWith((ref) => pending.future),
      ],
    );
    await goTo(tester, AppRoutes.statement('any'));
    expect(find.byType(LoadingSkeleton), findsOneWidget);
  });

  testWidgets('详情页：读取失败显示错误码与「重新加载」', (tester) async {
    await pumpCardFlowApp(
      tester,
      overrides: <Override>[
        ledgerProvider.overrideWith(
          (ref) => Future<LedgerData>.error(StateError('x')),
        ),
      ],
    );
    await goTo(tester, AppRoutes.statement('any'));
    expect(find.text('账单读取失败'), findsOneWidget);
    expect(find.text('错误码：StateError'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '重新加载'), findsOneWidget);
  });

  testWidgets('成功：列表行（剩余应还、到期、有效状态"待还"、确认层级、2 个版本、差异 1）→ 详情：版本切换与原值、来源与版本、'
      '"来源未含此项"、负债四分法、交易与退款待核对、分期成本并列；整页没有"还款成功"、没有绿色', (tester) async {
    await pumpCardFlowApp(tester, seed: seedLedger);
    await goTo(tester, AppRoutes.statements());
    expect(find.text('卡 A · 2026-10-10 账单'), findsOneWidget);
    expect(find.text('¥1,572.00'), findsOneWidget);
    expect(find.text('到期 10-28'), findsOneWidget);
    expect(find.text('待还'), findsNWidgets(2), reason: '状态筛选标签与行里的徽标（有效状态）');
    expect(find.text('已修正'), findsNothing, reason: '存储状态只是动作记录，界面用有效状态');
    expect(find.text('你已确认'), findsOneWidget);
    expect(find.text('2 个版本'), findsOneWidget);
    expect(find.text('差异 1'), findsOneWidget);
    // 筛选：状态"已逾期"没有账单 → 不出现这个筛选项；选"待还"仍有一行。
    expect(find.widgetWithText(ChoiceChip, '已逾期'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '待还'));
    await tester.pumpAndSettle();
    expect(find.text('卡 A · 2026-10-10 账单'), findsOneWidget);
    await expectNoForbiddenRepaymentUi(tester, page: '账单中心');

    await tester.tap(find.text('卡 A · 2026-10-10 账单'));
    await tester.pumpAndSettle();
    expect(appBarTitle('卡 A · 2026-10-10 账单'), findsOneWidget);
    await _scrollTo(tester, find.text('账单要素（v2）'));
    expect(find.text('v2 人工修正（当前）'), findsOneWidget);
    expect(find.text('¥157.20'), findsOneWidget, reason: 'v2 的最低还款额');
    expect(find.text('来源：人工修正 · v2（理由：最低还款额抄错，按账单更正）'), findsWidgets);
    // 来源未含的项（利息、费用……）显示"来源未含此项"，不当 0。
    expect(find.text(LedgerAmountRow.missingText), findsWidgets);
    // 切到 v1：原值可查。
    await tester.tap(find.widgetWithText(ChoiceChip, 'v1 手工录入'));
    await tester.pumpAndSettle();
    expect(find.text('账单要素（v1）'), findsOneWidget);
    expect(find.text('¥157.00'), findsOneWidget, reason: 'v1 的最低还款额原值');
    await _scrollTo(tester, find.text('负债四分法'));
    for (final label in <String>['总负债', '本期应还', '未出账', '未来分期本金']) {
      await _scrollTo(tester, find.text(label));
      expect(find.text(label), findsWidgets);
    }
    await _scrollTo(tester, find.textContaining('总负债 = 已出账未还 + 未出账 + 未来分期本金'));
    await _scrollTo(tester, find.text('分期（1）'));
    await _scrollTo(tester, find.text('名义年化（每期费率 × 12，不是实际成本）'));
    expect(find.text('7.2%'), findsOneWidget);
    await _scrollTo(tester, find.text('实际年化（复利，按各期现金流 IRR）'));
    await _scrollTo(tester, find.text('还款分配（2）'));
    await _scrollTo(tester, find.text('差异清单（1）'));
    await _scrollTo(tester, find.text('疑似重复还款'));
    await expectNoForbiddenRepaymentUi(tester, page: '账单详情');
  });

  testWidgets('交易：本期账期里的消费（已转分期）；10-14 的退款在下一期（可能账期之外），列在账单中心的交易里不出现在 10-10', (
    tester,
  ) async {
    await pumpCardFlowApp(tester, seed: seedLedger);
    final data = await readLedger(tester);
    final statement = data.statements.single;
    final inCycle = data.transactionsOf(statement.id).map((e) => e.$1.merchant);
    expect(inCycle, <String?>['家电城']);
    await goTo(tester, AppRoutes.statement(statement.id));
    await _scrollTo(tester, find.text('本期交易（1）'));
    await _scrollTo(tester, find.text('已转分期（本金按各期出账）'));
    expect(find.text('转分期'), findsNothing, reason: '已转分期的消费不能再转');
  });

  testWidgets('人工修正：理由必填；保存生成 v3、原值保留', (tester) async {
    await pumpCardFlowApp(tester, seed: seedLedger);
    final statement = (await readLedger(tester)).statements.single;
    await goTo(tester, AppRoutes.correctStatement(statement.id));
    expect(appBarTitle(StatementCorrectionPage.title), findsOneWidget);
    expect(find.textContaining('修正会生成 v3'), findsOneWidget);
    await _tap(tester, find.widgetWithText(FilledButton, '生成新版本'));
    expect(find.text('请填写修正理由'), findsOneWidget);
    await _scrollTo(tester, _field('修正理由（必填，≤200 字）'));
    await tester.enterText(_field('修正理由（必填，≤200 字）'), '按纸质账单更正');
    await _tap(tester, find.widgetWithText(FilledButton, '生成新版本'));
    expect(find.text('已生成 v3，原值保留'), findsOneWidget);
    final versions = (await readLedger(tester)).versions[statement.id]!;
    expect(versions.map((v) => v.versionNo), <int>[1, 2, 3]);
    expect(versions.first.minDueMinor, 15700);
  });

  testWidgets('录入正式账单：没选日期不能保存；F-38 贷方余额的账单在详情里显示"贷方余额"、本期应还为 0', (
    tester,
  ) async {
    await pumpCardFlowApp(
      tester,
      seed: (scope) async {
        final card = await createTestCard(scope, alias: '卡 A');
        await declareTestRule(scope, card.creditAccountId);
        final sub = (await primaryCurrencyAccount(
          scope,
          card.creditAccountId,
        )).id;
        await recordTestStatement(
          scope,
          sub,
          newBalance: -10000,
          minDue: 0,
          creditBalance: 10000,
        );
      },
    );
    await goTo(tester, AppRoutes.newStatement());
    await _tap(tester, find.widgetWithText(FilledButton, '保存为 v1'));
    expect(find.text('没有保存：请选择账单日'), findsNothing, reason: '本地校验不提交');
    await tester.scrollUntilVisible(
      find.text('请选择账单日'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('请选择账单日'), findsOneWidget);
    expect(find.text('请选择到期还款日'), findsOneWidget);
    await _scrollTo(tester, find.text('请填写金额'));

    final statement = (await readLedger(tester)).statements.single;
    await goTo(tester, AppRoutes.statement(statement.id));
    expect(find.text('这期有贷方余额（溢缴款），本期应还为 0。'), findsOneWidget);
    await _scrollTo(tester, find.text('贷方余额 −¥100.00'));
    await goTo(tester, AppRoutes.statements());
    expect(find.text('贷方余额'), findsOneWidget);
    expect(find.text('¥0.00'), findsOneWidget);
  });

  testWidgets('记一笔：选类型与金额保存；退款进入"退款待核对"并提示应还不变', (tester) async {
    await pumpCardFlowApp(tester, seed: seedLedger);
    await goTo(tester, AppRoutes.newTransaction());
    expect(appBarTitle(TransactionFormPage.title), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '退款'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('金额（填正数）'), '30');
    await _scrollTo(tester, _field('商户（可选，≤20 字）'));
    await tester.enterText(_field('商户（可选，≤20 字）'), '超市');
    await _tap(tester, find.widgetWithText(FilledButton, '保存'));
    expect(find.text('已记一笔：退款待核对（应还不变）'), findsOneWidget);
    final data = await readLedger(tester);
    final refunds = data.transactions.where((t) => t.txnType == 'refund');
    expect(
      refunds.map((t) => t.amountMinor),
      containsAll(<int>[-15000, -3000]),
    );
    expect(
      data.openItems.where((i) => i.kind == 'refund_pending'),
      hasLength(2),
    );
  });

  testWidgets('不在当前空间的账单："已不存在"，可回到账单中心', (tester) async {
    await pumpCardFlowApp(tester, seed: seedLedger);
    await goTo(tester, AppRoutes.statement('no-such-statement'));
    expect(find.text('已不存在'), findsOneWidget);
    await tester.tap(find.text('回到账单中心'));
    await tester.pumpAndSettle();
    expect(appBarTitle(StatementCenterPage.title), findsOneWidget);
  });

  testWidgets('从 P-03「全部账单」进入只看该账户，留在卡包栈里', (tester) async {
    await pumpCardFlowApp(tester, seed: seedLedger);
    final data = await readLedger(tester);
    final account = data.wallet.accounts.single.id;
    await goTo(tester, AppRoutes.account(account));
    await _tap(tester, find.text('全部账单'));
    expect(appBarTitle(StatementCenterPage.title), findsOneWidget);
    expect(
      appRouter(tester).routerDelegate.currentConfiguration.uri.path,
      '/cards/accounts/$account/statements',
    );
    expect(find.text('卡 A · 2026-10-10 账单'), findsOneWidget);
  });

  testWidgets('转分期：预览每期本金与费用、名义与实际年化；保存后计划进入分期区', (tester) async {
    await pumpCardFlowApp(tester, seed: seedLedger);
    final data = await readLedger(tester);
    final txn = data.transactions.firstWhere((t) => t.merchant == '超市');
    await goTo(tester, AppRoutes.newInstallment(txn.id));
    expect(appBarTitle(InstallmentFormPage.title), findsOneWidget);
    await tester.enterText(_field('期数（1–60）'), '3');
    await tester.enterText(_field('每期费率（%，如 0.6）'), '1.5');
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('名义年化（每期费率 × 12，不是实际成本）'));
    expect(find.text('18%'), findsOneWidget);
    await _tap(tester, find.widgetWithText(FilledButton, '转分期'));
    expect(find.text('已转分期（你已确认）'), findsOneWidget);
    final after = await readLedger(tester);
    expect(after.plans, hasLength(2));
    expect(
      await withCurrentScope(
        tester,
        (scope) async =>
            (await TransactionRepository(scope).byId(txn.id)) != null,
      ),
      isTrue,
    );
  });
}
