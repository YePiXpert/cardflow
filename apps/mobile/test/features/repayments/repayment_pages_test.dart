// P-06 还款登记与核对（ui-spec P-06）：四态（首次空白、加载、错误、成功；列表、详情与登记表单）；登记表单：
// 多期分配实时合计，合计 ≠ 还款额时禁止保存（F-33）、超应还提示、受限账户警告；保存后"已登记（待银行确认）"；
// 时间线与动作（确认扣款、我已还款）；核对区处理疑似重复；每种还款状态下 P-06、P-05、P-03、P-01 都不出现
// "还款成功"与绿色（robust 色 token，test/support/forbidden_ui.dart）。
import 'dart:async';

import 'package:cardflow/app/routes.dart';
import 'package:cardflow/app/widgets/state_views.dart';
import 'package:cardflow/data/repositories/cash_models.dart';
import 'package:cardflow/data/repositories/ledger_models.dart';
import 'package:cardflow/data/repositories/ledger_reader.dart';
import 'package:cardflow/data/repositories/providers.dart';
import 'package:cardflow/data/repositories/repayment_repository.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow/features/repayments/repayment_form_page.dart';
import 'package:cardflow/features/repayments/repayment_pages.dart';
import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate, Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../data/repositories/repository_test_support.dart';
import '../../support/forbidden_ui.dart';
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

  testWidgets('加载：列表、详情与登记表单都是骨架', (tester) async {
    final pending = Completer<LedgerData>();
    await pumpCardFlowApp(
      tester,
      overrides: <Override>[
        ledgerProvider.overrideWith((ref) => pending.future),
      ],
    );
    for (final page in <String>[
      AppRoutes.repayments(),
      AppRoutes.repayment('any'),
      AppRoutes.newRepayment(),
    ]) {
      await goTo(tester, page);
      expect(find.byType(LoadingSkeleton), findsOneWidget, reason: page);
    }
  });

  testWidgets('错误：列表、详情与登记表单显示错误码与「重新加载」/「重试」', (tester) async {
    await pumpCardFlowApp(
      tester,
      overrides: <Override>[
        ledgerProvider.overrideWith(
          (ref) => Future<LedgerData>.error(StateError('x')),
        ),
      ],
    );
    for (final (page, title, retry) in <(String, String, String)>[
      (AppRoutes.repayments(), '还款读取失败', '重新加载'),
      (AppRoutes.repayment('any'), '还款读取失败', '重新加载'),
      (AppRoutes.newRepayment(), '读取失败', '重试'),
    ]) {
      await goTo(tester, page);
      expect(find.text(title), findsOneWidget, reason: page);
      expect(find.text('错误码：StateError'), findsOneWidget, reason: page);
      expect(find.widgetWithText(FilledButton, retry), findsOneWidget);
    }
  });

  testWidgets('成功（列表）：待核对的还款、差异清单（退款待核对、疑似重复）与全部还款的行（账户、金额、状态、方式、分到的账单）；'
      '没有"还款成功"、没有绿色', (tester) async {
    await pumpCardFlowApp(tester, seed: seedLedger);
    await goTo(tester, AppRoutes.repayments());
    expect(appBarTitle(RepaymentCenterPage.title), findsOneWidget);
    expect(find.text('待核对的还款（0）'), findsOneWidget);
    expect(find.text('没有等待银行证据的还款。'), findsOneWidget);
    expect(find.text('差异清单（2）'), findsOneWidget, reason: '退款待核对与疑似重复');
    await _scrollTo(tester, find.text('全部还款（2）'));
    for (final method in <RepaymentMethod>[
      RepaymentMethod.autoDebit,
      RepaymentMethod.manual,
    ]) {
      await _scrollTo(tester, find.text(method.label).last);
    }
    expect(find.text(RepaymentStatus.recorded.label), findsWidgets);
    expect(find.text('分到 10-10 账单'), findsWidgets);
    expect(find.text('¥500.00'), findsWidgets);
    await expectNoForbiddenRepaymentUi(tester, page: '还款与核对');
  });

  testWidgets('多期分配实时合计：分到两期账单，合计 ≠ 还款额时「登记」不可点并提示（F-33），'
      '相等后可保存，两期的分配都写入', (tester) async {
    late String early;
    late String late_;
    await pumpCardFlowApp(
      tester,
      seed: (scope) async {
        final card = await createTestCard(scope, alias: '卡 A');
        await declareTestRule(scope, card.creditAccountId);
        final sub = (await primaryCurrencyAccount(
          scope,
          card.creditAccountId,
        )).id;
        await createTestCashAccount(scope);
        early = (await recordTestStatement(
          scope,
          sub,
          statementDate: LocalDate(2026, 9, 10),
          dueDate: LocalDate(2026, 9, 28),
          newBalance: 30000,
          minDue: 3000,
        )).id;
        late_ = (await recordTestStatement(
          scope,
          sub,
          newBalance: 50000,
          minDue: 5000,
        )).id;
      },
    );
    await goTo(tester, AppRoutes.newRepayment());
    final save = find.widgetWithText(FilledButton, '登记');
    Future<void> expectSaveEnabled({required bool enabled}) async {
      await _scrollTo(tester, save);
      expect(
        tester.widget<FilledButton>(save).onPressed != null,
        enabled,
        reason: enabled ? '合计等于还款额' : '合计不等于还款额',
      );
    }

    await tester.enterText(_field('还款额'), '800');
    await tester.pumpAndSettle();
    // 账单新的在前：先 10-10，再 09-10。
    await _scrollTo(tester, _field('分到这期（2026-10-10）'));
    await tester.enterText(_field('分到这期（2026-10-10）'), '400');
    await tester.pumpAndSettle();
    await _scrollTo(tester, _field('分到这期（2026-09-10）'));
    await tester.enterText(_field('分到这期（2026-09-10）'), '300');
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('分配合计'));
    expect(find.text('¥700.00'), findsOneWidget, reason: '分配合计');
    await _scrollTo(tester, find.text(RepaymentFormPage.allocationMismatch));
    await expectSaveEnabled(enabled: false);

    await _scrollTo(tester, _field('分到这期（2026-10-10）'), delta: -200);
    await tester.enterText(_field('分到这期（2026-10-10）'), '500');
    await tester.pumpAndSettle();
    expect(find.text(RepaymentFormPage.allocationMismatch), findsNothing);
    await expectSaveEnabled(enabled: true);
    await _tap(tester, find.widgetWithText(ChoiceChip, '工资卡（CNY）'));
    await _tap(tester, save);
    expect(find.text(RepaymentFormPage.savedMessage), findsWidgets);

    final data = await readLedger(tester);
    final repayment = data.repayments.single;
    expect(repayment.amountMinor, 80000);
    expect(
      <String, int>{
        for (final a in data.allocationsOf(repayment.id))
          a.statementId: a.amountMinor,
      },
      <String, int>{early: 30000, late_: 50000},
    );
  });

  testWidgets('每种还款状态（9 种）与已结清、已逾期的账单：还款详情、还款与核对、账单中心、账单详情、'
      '信用账户详情与总览都没有"还款成功"、没有绿色（robust 色 token）', (tester) async {
    late _AllStatuses seeded;
    await pumpCardFlowApp(
      tester,
      seed: (scope) async => seeded = await _seedAllStatuses(scope),
    );
    final data = await readLedger(tester);
    expect(
      <RepaymentStatus>{
        for (final r in data.repayments) RepaymentStatus.of(r.status),
      },
      RepaymentStatus.values.toSet(),
      reason: '9 种状态都有',
    );
    expect(
      <StatementStatus>{
        for (final s in data.statements) StatementStatus.of(s.status),
      },
      containsAll(<StatementStatus>[
        StatementStatus.partiallySettled,
        StatementStatus.settled,
        StatementStatus.overdue,
      ]),
    );
    final pages = <(String, String)>[
      for (final r in data.repayments)
        (
          AppRoutes.repayment(r.id),
          '还款详情（${RepaymentStatus.of(r.status).label}）',
        ),
      (AppRoutes.repayments(), '还款与核对'),
      (AppRoutes.statements(), '账单中心'),
      for (final s in data.statements)
        (
          AppRoutes.statement(s.id),
          '账单详情（${StatementStatus.of(s.status).label}）',
        ),
      (AppRoutes.account(seeded.accountA), '信用账户详情（卡 A）'),
      (AppRoutes.account(seeded.accountB), '信用账户详情（卡 B）'),
      (AppRoutes.overview, '总览'),
    ];
    for (final (route, page) in pages) {
      await goTo(tester, route);
      await expectNoForbiddenRepaymentUi(tester, page: page);
    }
    // 银行确认的还款：时间线走到"银行确认"，徽标是银行确认色（不是绿色）。
    await goTo(tester, AppRoutes.repayment(seeded.confirmed));
    expect(find.text(RepaymentStatus.bankConfirmed.label), findsWidgets);
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
    await expectNoForbiddenRepaymentUi(tester, page: '还款详情（刚登记）');
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

/// [_seedAllStatuses] 写入的账户与还款。
final class _AllStatuses {
  const _AllStatuses({
    required this.accountA,
    required this.accountB,
    required this.confirmed,
  });

  final String accountA;
  final String accountB;
  final String confirmed;
}

/// 卡 A：10-10 账单（应还 9,000）上有 9 种状态的还款各一笔（金额各不相同，不构成疑似重复；时点都在
/// 10-17，早于测试的"现在" 10-18 12:00）；卡 B：10-10 账单全额还款经银行确认 → 已结清，09-10 账单
/// 过了到期日仍未还 → 已逾期。
Future<_AllStatuses> _seedAllStatuses(WorkspaceScope scope) async {
  final cardA = await createTestCard(scope, last4: '1001', alias: '卡 A');
  await declareTestRule(scope, cardA.creditAccountId);
  final subA = (await primaryCurrencyAccount(scope, cardA.creditAccountId)).id;
  final cardB = await createTestCard(scope, last4: '2002', alias: '卡 B');
  await declareTestRule(scope, cardB.creditAccountId);
  final subB = (await primaryCurrencyAccount(scope, cardB.creditAccountId)).id;
  final cash = await createTestCashAccount(scope);
  final statementA = await recordTestStatement(
    scope,
    subA,
    newBalance: 900000,
    minDue: 90000,
  );
  final settled = await recordTestStatement(
    scope,
    subB,
    newBalance: 5000,
    minDue: 500,
  );
  await recordTestStatement(
    scope,
    subB,
    statementDate: LocalDate(2026, 9, 10),
    dueDate: LocalDate(2026, 9, 28),
    newBalance: 7000,
    minDue: 700,
  );
  final repo = RepaymentRepository(scope);
  Timestamp at(String hm) => Timestamp.parse('2026-10-17T$hm:00+08:00');
  Future<String> register(int amount, {String? sub, String? statement}) async =>
      (await registerTestRepayment(
        scope,
        currencyAccountId: sub ?? subA,
        cashAccountId: cash.id,
        amount: amount,
        statementId: statement ?? statementA.id,
        expectedDebitOn: LocalDate(2026, 10, 17),
      )).id;
  Future<String> confirmed(int amount, {String? sub, String? statement}) async {
    final id = await register(amount, sub: sub, statement: statement);
    await repo.confirmDebit(id, at('10:00'));
    await repo.markCreditPosted(id, at('11:00'));
    await repo.confirmByBank(id, at('12:00'));
    return id;
  }

  await register(10000); // 已登记
  final processing = await register(11000);
  await repo.markInitiated(processing, at('09:00'));
  final debited = await register(12000);
  await repo.confirmDebit(debited, at('10:00'));
  final posted = await register(13000);
  await repo.confirmDebit(posted, at('10:00'));
  await repo.markCreditPosted(posted, at('11:00'));
  final bankConfirmed = await confirmed(14000);
  final failed = await register(15000);
  await repo.markInitiated(failed, at('09:00'));
  await repo.markFailed(failed);
  final marked = await register(16000);
  await repo.markUserPaid(marked);
  final review = await register(17000);
  await repo.markUserPaid(review);
  await repo.markNeedsReview(review);
  final reversed = await confirmed(18000);
  await repo.reverse(reversed);
  await confirmed(5000, sub: subB, statement: settled.id);
  return _AllStatuses(
    accountA: cardA.creditAccountId,
    accountB: cardB.creditAccountId,
    confirmed: bankConfirmed,
  );
}
