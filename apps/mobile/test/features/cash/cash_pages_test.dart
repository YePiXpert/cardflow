// P-08 现金账户与收支计划（ui-spec P-08）：四态；演示数据的账户（可用性、受限资金不计入）、收支计划、
// 周期事项与调拨；添加账户（理财默认不可还款、初始余额缺实际时点不可存）；记录新快照时逐条询问"余额是否
// 已包含 {事件}"；新增收支须选层级（没有概率字段）；周期事项单期跳过/恢复；调拨两端不同；余额陈旧
// "{n} 天前"与「记录新快照」；没有快照"未计入规划"。
import 'dart:async';

import 'package:cardflow/app/routes.dart';
import 'package:cardflow/app/widgets/state_views.dart';
import 'package:cardflow/data/repositories/cash_account_repository.dart';
import 'package:cardflow/data/repositories/cash_models.dart';
import 'package:cardflow/data/repositories/cash_plan_reader.dart';
import 'package:cardflow/data/repositories/providers.dart';
import 'package:cardflow/data/repositories/recurring_item_repository.dart';
import 'package:cardflow/features/cash/cash_account_pages.dart';
import 'package:cardflow/features/cash/cash_entry_pages.dart';
import 'package:cardflow/features/cash/cash_form_fields.dart';
import 'package:cardflow/features/cash/cash_page.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../data/repositories/repository_test_support.dart';
import '../../test_helpers.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

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

Future<void> _enter(WidgetTester tester, String label, String text) async {
  await _scrollTo(tester, _field(label));
  await tester.enterText(_field(label), text);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('首次空白："添加还款用现金账户"，「添加账户」进入添加页；分段标签在顶部', (tester) async {
    await pumpCardFlowApp(tester);
    await goTo(tester, AppRoutes.cash);
    expect(appBarTitle(CashPage.title), findsOneWidget);
    expect(find.text(CashPage.firstRunMessage), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '资金日历'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '添加账户'));
    await tester.pumpAndSettle();
    expect(appBarTitle(NewCashAccountPage.title), findsOneWidget);
  });

  testWidgets('加载：骨架；错误：错误码与「重试」', (tester) async {
    final pending = Completer<CashPlanView>();
    await pumpCardFlowApp(
      tester,
      overrides: <Override>[
        cashPlanProvider.overrideWith((ref) => pending.future),
      ],
    );
    await goTo(tester, AppRoutes.cash);
    expect(find.byType(LoadingSkeleton), findsOneWidget);
  });

  testWidgets('错误：显示错误码与「重试」', (tester) async {
    await pumpCardFlowApp(
      tester,
      overrides: <Override>[
        cashPlanProvider.overrideWith(
          (ref) => Future<CashPlanView>.error(StateError('x')),
        ),
      ],
    );
    await goTo(tester, AppRoutes.cash);
    expect(find.text('现金与收支读取失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('成功（演示）：账户、可用性（受限资金不计入）、收支计划、周期事项（单期例外）、调拨', (tester) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
    await goTo(tester, AppRoutes.cash);
    expect(find.text('工资卡'), findsOneWidget);
    expect(find.text('可用于还款'), findsOneWidget);
    expect(find.text('定期存款'), findsOneWidget);
    expect(find.text('不计入可用现金（受限资金，未设可用日期）'), findsOneWidget);
    for (final text in <String>['工资', '已出账单', '贷款月供']) {
      await _scrollTo(tester, find.text(text).first);
      expect(find.text(text), findsWidgets, reason: text);
    }
    await _scrollTo(tester, find.textContaining('单期例外 1 项'));
    expect(find.text('房租'), findsOneWidget);
    await _scrollTo(tester, find.text('工资卡 → 定期存款'));
    expect(find.textContaining('转出 2026-11-01'), findsOneWidget);
  });

  testWidgets('添加账户：理财默认不可当日还款；填了余额却没填实际时点不能保存；保存后建账户与快照', (tester) async {
    await pumpCardFlowApp(tester);
    await goTo(tester, AppRoutes.newCashAccount);
    await _enter(tester, '账户名称（≤20 字）', '余额宝');
    await _tap(tester, find.widgetWithText(ChoiceChip, '理财'));
    final usable = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, '可用于还款'),
    );
    expect(usable.value, isFalse);
    await _enter(tester, '余额（可为负：透支）', '5,000');
    await _enter(tester, '实际时点（HH:MM，中国大陆（Asia/Shanghai，UTC+08:00））', '');
    await _tap(tester, find.widgetWithText(FilledButton, '保存'));
    expect(find.text('请填写时刻（HH:MM）'), findsOneWidget);
    await _enter(tester, '实际时点（HH:MM，中国大陆（Asia/Shanghai，UTC+08:00））', '09:30');
    await _tap(tester, find.widgetWithText(FilledButton, '保存'));
    expect(appBarTitle(CashPage.title), findsOneWidget);
    final plan = await readCashPlan(tester);
    final account = plan.accounts.single;
    expect(account.row.name, '余额宝');
    expect(account.availability.counted, isFalse);
    expect(account.latestSnapshot!.balanceMinor, 500000);
    expect(account.latestSnapshot!.observedAt, '2026-10-18T09:30:00+08:00');
  });

  testWidgets('记录新快照：当天已有收支时逐条询问"余额是否已包含"，答完才能保存；答"已包含"的写进包含关系', (
    tester,
  ) async {
    late String accountId;
    late String breakfastId;
    await pumpCardFlowApp(
      tester,
      seed: (scope) async {
        final acc = await createTestCashAccount(scope);
        accountId = acc.id;
        breakfastId = (await addTestCashEvent(
          scope,
          acc.id,
          d(2026, 10, 18),
          -3000,
          label: '早餐',
        )).id;
        await addTestCashEvent(
          scope,
          acc.id,
          d(2026, 10, 18),
          100000,
          label: '报销',
        );
      },
    );
    await goTo(tester, AppRoutes.recordCashSnapshot(accountId));
    expect(appBarTitle(RecordCashSnapshotPage.title), findsOneWidget);
    await _enter(tester, '余额（可为负：透支）', '1,000');
    await _enter(
      tester,
      '实际时点（HH:MM，必填，中国大陆（Asia/Shanghai，UTC+08:00））',
      '11:00',
    );
    expect(find.textContaining('余额是否已包含「早餐」'), findsOneWidget);
    expect(find.textContaining('余额是否已包含「报销」'), findsOneWidget);
    await _tap(tester, find.widgetWithText(FilledButton, '保存快照'));
    expect(find.text('请逐条回答：余额是否已包含当天的这些收支'), findsOneWidget);
    await _tap(tester, find.widgetWithText(ChoiceChip, '已包含').first);
    await _tap(tester, find.widgetWithText(ChoiceChip, '未包含').last);
    await _tap(tester, find.widgetWithText(FilledButton, '保存快照'));
    final included = await withCurrentScope(tester, (scope) async {
      final snapshots = CashSnapshotRepository(scope);
      final latest = (await snapshots.latestByAccount())[accountId]!;
      return snapshots.includedIn(latest.id);
    });
    expect(included, {breakfastId});
  });

  testWidgets('新增收支：必须选层级（确定/预计），没有概率字段；保存后正负由类型决定', (tester) async {
    await pumpCardFlowApp(
      tester,
      seed: (scope) async {
        await createTestCashAccount(scope);
      },
    );
    await goTo(tester, AppRoutes.newCashEvent('income'));
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration?.labelText?.contains('概率') ?? false),
      ),
      findsNothing,
      reason: '没有任何概率输入（只有"不设概率"的说明）',
    );
    expect(find.text('层级（必选；不设概率）'), findsOneWidget);
    await _enter(tester, '金额（收入，填正数）', '8500');
    await _enter(tester, '名称（可选，≤20 字）', '工资');
    await _tap(tester, find.widgetWithText(FilledButton, '保存'));
    expect(find.text(CashClassField.missing), findsOneWidget);
    await _tap(tester, find.widgetWithText(ChoiceChip, '预计（可能变动）'));
    await _tap(tester, find.widgetWithText(FilledButton, '保存'));
    final plan = await readCashPlan(tester);
    final event = plan.plan.single;
    expect(
      (event.amountMinor, event.cls, event.category, event.label),
      (850000, 'expected', 'income', '工资'),
    );
  });

  testWidgets('周期事项详情：跳过一期不影响其他各期，可以恢复', (tester) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
    final itemId = (await readCashPlan(tester)).recurring.single.row.id;
    await goTo(tester, AppRoutes.recurring(itemId));
    await _scrollTo(tester, find.textContaining('11-27 · 按周期'));
    final row = find.ancestor(
      of: find.textContaining('11-27 · 按周期'),
      matching: find.byType(ListTile),
    );
    await _tap(
      tester,
      find.descendant(of: row, matching: find.widgetWithText(TextButton, '跳过')),
    );
    expect(find.textContaining('11-27 · 已跳过'), findsOneWidget);
    expect(
      find.textContaining('12-27 · 已覆盖'),
      findsOneWidget,
      reason: '其他各期不变',
    );
    final occurrences = await withCurrentScope(
      tester,
      (scope) => RecurringItemRepository(scope).occurrences(itemId),
    );
    expect(
      occurrences.firstWhere((o) => o.key == d(2026, 11, 27)).skipped,
      isTrue,
    );
    expect(occurrences.where((o) => o.skipped), hasLength(1));
    final skipped = find.ancestor(
      of: find.textContaining('11-27 · 已跳过'),
      matching: find.byType(ListTile),
    );
    await _tap(
      tester,
      find.descendant(
        of: skipped,
        matching: find.widgetWithText(TextButton, '恢复'),
      ),
    );
    expect(find.textContaining('11-27 · 按周期'), findsOneWidget);
  });

  testWidgets('新增调拨：两端须是不同账户（仓库校验的文案显示在页面上）', (tester) async {
    await pumpCardFlowApp(
      tester,
      seed: (scope) async {
        await createTestCashAccount(scope);
        await createTestCashAccount(scope, name: '零钱');
      },
    );
    await goTo(tester, AppRoutes.newTransfer);
    expect(appBarTitle(TransferFormPage.title), findsOneWidget);
    for (final label in <String>['转出账户', '转入账户（与转出不同、币种相同）']) {
      final field = find.byKey(ValueKey<String>('account-field-$label'));
      await _tap(
        tester,
        find.descendant(
          of: field,
          matching: find.widgetWithText(ChoiceChip, '工资卡（CNY）'),
        ),
      );
    }
    await _enter(tester, '金额（填正数）', '100');
    await _tap(tester, find.widgetWithText(ChoiceChip, '确定（合同、已约定）'));
    await _tap(tester, find.widgetWithText(FilledButton, '保存调拨'));
    expect(find.text('转出与转入须是两个不同的账户'), findsWidgets);
    expect((await readCashPlan(tester)).transfers, isEmpty);
  });

  testWidgets('余额陈旧："{n} 天前"徽标与「记录新快照」；没有快照"未计入规划"', (tester) async {
    late String staleId;
    await pumpCardFlowApp(
      tester,
      realClock: StaleAwareClock(DateTime.utc(2026, 10, 18, 4)),
      seed: (scope) async {
        final acc = await createTestCashAccount(scope);
        staleId = acc.id;
        await recordTestCashSnapshot(scope, acc.id, d(2026, 10, 8), 100000);
        await createTestCashAccount(scope, name: '新账户');
      },
    );
    await goTo(tester, AppRoutes.cash);
    expect(find.text('10 天前'), findsOneWidget);
    expect(find.text('未计入规划（缺快照）'), findsOneWidget);
    expect(
      find.widgetWithText(TextButton, '记录新快照'),
      findsNWidgets(2),
      reason: '陈旧与缺快照的账户行都有「记录新快照」',
    );
    await goTo(tester, AppRoutes.cashAccount(staleId));
    expect(find.textContaining('余额快照已是 10 天前'), findsOneWidget);
    await _tap(tester, find.widgetWithText(OutlinedButton, '记录新快照'));
    expect(appBarTitle(RecordCashSnapshotPage.title), findsOneWidget);
  });

  testWidgets('不在当前空间的账户："已不存在"，可回到现金与收支', (tester) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
    await goTo(tester, AppRoutes.cashAccount('no-such-account'));
    expect(find.text('已不存在'), findsOneWidget);
    await tester.tap(find.text('回到现金与收支'));
    await tester.pumpAndSettle();
    expect(appBarTitle(CashPage.title), findsOneWidget);
  });

  testWidgets('受限资金的"可用于还款"开关禁用并说明（只能设可用日期）', (tester) async {
    await pumpCardFlowApp(tester);
    await goTo(tester, AppRoutes.newCashAccount);
    await _tap(
      tester,
      find.widgetWithText(ChoiceChip, CashAccountKind.restricted.label),
    );
    final usable = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, '可用于还款'),
    );
    expect(usable.value, isFalse);
    expect(usable.onChanged, isNull);
    expect(find.text('受限资金不能直接用于还款；可以设置可用日期'), findsOneWidget);
  });
}
