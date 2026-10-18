// P-03 信用账户详情与 P-04 信用账户设置（ui-spec P-03/P-04）：四态、预测账期（未设置/非法/
// 预测）、额度区（超限）、换卡/冻结/销卡、账期规则编辑与 3 期预览（与 F-12/F-16 一致、到期不晚于
// 账单日阻止保存、工作日与顺延禁用）、版本历史（F-14）、额度快照表单、币种子账户、授信池。
import 'dart:async';

import 'package:cardflow/app/routes.dart';
import 'package:cardflow/app/widgets/state_views.dart';
import 'package:cardflow/data/repositories/card_wallet_reader.dart';
import 'package:cardflow/data/repositories/providers.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow/features/cards/account_detail_page.dart';
import 'package:cardflow/features/cards/account_settings_page.dart';
import 'package:cardflow/features/cards/currency_pool_sections.dart';
import 'package:cardflow/features/cards/limit_snapshot_section.dart';
import 'package:cardflow/features/cards/rule_editor_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../data/repositories/repository_test_support.dart';
import '../../test_helpers.dart';

/// 演示空间里某个账户的 id。
Future<String> _demoAccount(WidgetTester tester, String name) async =>
    (await readWallet(tester)).accounts
        .firstWhere((a) => a.displayName == name)
        .id;

/// 种子：一张没有规则、没有快照的卡（真实空间）。
Future<void> _bareCard(WorkspaceScope scope) async {
  await createTestCard(scope, bank: '招商银行', last4: '1234', alias: '新卡');
}

Future<String> _onlyAccount(WidgetTester tester) async =>
    (await readWallet(tester)).accounts.single.id;

/// [page] 里的滚动列表（P-04 用分段的类型：RuleEditorSection 等，避开顶部可滚动的 TabBar）。
Finder _scrollable(Type page) => find
    .descendant(of: find.byType(page), matching: find.byType(Scrollable))
    .first;

/// 滚到 [finder] 并让它完整出现在可视区域（只露出一部分时点击会落空）。
Future<void> _scrollTo(
  WidgetTester tester,
  Finder finder, {
  Type page = AccountDetailPage,
  double delta = 200,
}) async {
  await tester.scrollUntilVisible(finder, delta, scrollable: _scrollable(page));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _pickDropdown(
  WidgetTester tester,
  String label,
  String item,
) async {
  await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, label));
  await tester.pumpAndSettle();
  final menu = find.byType(Scrollable).last;
  final menuItem = find.descendant(of: menu, matching: find.text(item));
  await tester.scrollUntilVisible(menuItem, 60, scrollable: menu);
  await tester.ensureVisible(menuItem.last);
  await tester.pumpAndSettle();
  await tester.tap(menuItem.last);
  await tester.pumpAndSettle();
}

/// 当前测试所在的 P-04 分段（_scrollTo 用）。
Type _section = RuleEditorSection;

void main() {
  group('P-03 信用账户详情', () {
    testWidgets('加载与错误', (tester) async {
      final pending = Completer<WalletView>();
      await pumpCardFlowApp(
        tester,
        overrides: <Override>[
          walletProvider.overrideWith((ref) => pending.future),
        ],
      );
      await goTo(tester, AppRoutes.account('x'));
      expect(find.byType(LoadingSkeleton), findsOneWidget);
    });

    testWidgets('错误：显示错误码与「重试」', (tester) async {
      await pumpCardFlowApp(
        tester,
        overrides: <Override>[
          walletProvider.overrideWith(
            (ref) => Future<WalletView>.error(StateError('x')),
          ),
        ],
      );
      await goTo(tester, AppRoutes.account('x'));
      expect(find.text('读取失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('不在当前空间的账户："已不存在"，可回到卡包', (tester) async {
      await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
      await goTo(tester, AppRoutes.account('no-such-account'));
      expect(find.text('已不存在'), findsOneWidget);
      await tester.tap(find.text('回到卡包'));
      await tester.pumpAndSettle();
      expect(appBarTitle('卡包'), findsOneWidget);
    });

    testWidgets('成功（卡 A）：预测账期（未出账）、系统估计、尚无账单、留位、额度、两张卡', (tester) async {
      await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
      await goTo(tester, AppRoutes.account(await _demoAccount(tester, '卡 A')));
      expect(appBarTitle('卡 A'), findsOneWidget);
      expect(find.text('预测账期（未出账）'), findsOneWidget);
      expect(find.text('系统估计'), findsOneWidget);
      expect(find.text('2026-11-10'), findsOneWidget);
      expect(find.text('2026-11-28'), findsOneWidget);
      expect(find.text(AccountDetailPage.noStatementsNote), findsOneWidget);
      expect(find.textContaining('I-1c 提供'), findsOneWidget);
      expect(find.text('仅示例'), findsOneWidget);
      await _scrollTo(tester, find.text('银行可用（原值）'));
      expect(find.text('银行可用（原值）'), findsOneWidget);
      await _scrollTo(tester, find.textContaining('•••• 1001'));
      expect(find.textContaining('•••• 1001'), findsOneWidget);
      await _scrollTo(tester, find.textContaining('•••• 1002'));
      expect(find.textContaining('附属卡'), findsWidgets);
      await _scrollTo(tester, find.text('当天归属'));
      expect(find.text('账单日当天入账计入本期'), findsOneWidget);
    });

    testWidgets('卡 D 超限：银行可用原值为负、标"超限"、容量 0', (tester) async {
      await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
      await goTo(tester, AppRoutes.account(await _demoAccount(tester, '卡 D')));
      await _scrollTo(tester, find.textContaining('超限：银行可用额为负'));
      expect(find.textContaining('超限：银行可用额为负'), findsOneWidget);
      expect(find.textContaining('共享授信池「乙行共享额度」'), findsOneWidget);
    });

    testWidgets('没有规则："账期规则：未设置" ›「去设置」到 P-04', (tester) async {
      await pumpCardFlowApp(tester, seed: _bareCard);
      await goTo(tester, AppRoutes.account(await _onlyAccount(tester)));
      expect(find.text('账期规则：未设置'), findsOneWidget);
      expect(find.textContaining('还没有额度快照'), findsOneWidget);
      await tester.tap(find.text('去设置'));
      await tester.pumpAndSettle();
      expect(
        find.text(RuleEditorSection.noRuleMessage, findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining(RuleEditorSection.noRuleMessage),
        findsOneWidget,
      );
    });

    testWidgets('规则非法：显示"规则非法，无法计算账期"', (tester) async {
      await pumpCardFlowApp(
        tester,
        seed: (scope) async {
          final card = await createTestCard(scope);
          // 绕过仓库校验，直接写一条到期早于账单日的规则（例如来自旧版本或手工改库）。
          await scope.db.customStatement(
            'INSERT INTO billing_rule_versions (id, workspace_id, subject_kind, subject_id, '
            'statement_day, due_kind, due_day, source, version, review_status, created_at) '
            "VALUES ('bad-rule', '${scope.workspaceId}', 'credit_account', "
            "'${card.creditAccountId}', 28, 'fixed_day', 25, 'user_declared', 1, "
            "'user_declared', '2026-10-18T12:00:00+08:00')",
          );
        },
      );
      await goTo(tester, AppRoutes.account(await _onlyAccount(tester)));
      expect(find.text(AccountDetailPage.invalidRuleText), findsOneWidget);
      expect(find.text('去修改'), findsOneWidget);
    });

    testWidgets('换卡/补卡、冻结/解冻、销卡（历史不变，已停用的卡折叠）', (tester) async {
      await pumpCardFlowApp(tester, seed: _bareCard);
      await goTo(tester, AppRoutes.account(await _onlyAccount(tester)));
      await _scrollTo(tester, find.text('冻结'));
      await tester.tap(find.text('冻结'));
      await tester.pumpAndSettle();
      expect(find.text('已冻结'), findsWidgets);
      await tester.tap(find.text('解冻'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('换卡/补卡'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '新卡末四位'), '9876');
      await tester.tap(find.text('确认换卡'));
      await tester.pumpAndSettle();
      expect(find.text('已换卡，历史不变'), findsOneWidget);
      await _scrollTo(tester, find.textContaining('•••• 9876'));
      expect(find.textContaining('•••• 9876'), findsOneWidget);
      await _scrollTo(tester, find.text('已停用的卡（1）'));
      expect(find.text('已停用的卡（1）'), findsOneWidget);

      await _scrollTo(tester, find.text('销卡'), delta: -200);
      await tester.tap(find.text('销卡'));
      await tester.pumpAndSettle();
      expect(find.textContaining('欠款仍显示'), findsOneWidget);
      await tester.tap(find.text('确认销卡'));
      await tester.pumpAndSettle();
      expect(find.text('已销卡'), findsOneWidget);
    });
  });

  group('P-04 信用账户设置', () {
    setUp(() => _section = RuleEditorSection);

    Future<void> openSettings(WidgetTester tester, {String? section}) async {
      final id = await _onlyAccount(tester);
      await goTo(tester, AppRoutes.accountSettings(id, section: section));
      expect(find.byType(AccountSettingsPage), findsOneWidget);
    }

    testWidgets('首次空白与 3 期预览：账单日 31、账单后 20 天（F-16 月末截断）', (tester) async {
      await pumpCardFlowApp(tester, seed: _bareCard);
      await openSettings(tester);
      expect(
        find.textContaining(RuleEditorSection.noRuleMessage),
        findsOneWidget,
      );
      await _pickDropdown(tester, '每月账单日', '31 日');
      expect(find.textContaining('月末截断'), findsOneWidget);
      await _scrollTo(tester, find.text('账单后 N 天'), page: _section);
      await tester.tap(find.text('账单后 N 天'));
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.text('第 2 期'), page: _section);
      // 测试时钟：2026-10-18。
      expect(find.text('账单日 2026-10-31 → 到期 2026-11-20'), findsOneWidget);
      expect(find.text('账单日 2026-11-30 → 到期 2026-12-20'), findsOneWidget);
      expect(find.text('账单日 2026-12-31 → 到期 2027-01-20'), findsOneWidget);
    });

    testWidgets('F-12：账单日当天入账的归属开关改变第一期', (tester) async {
      await pumpCardFlowApp(tester, seed: _bareCard);
      await openSettings(tester);
      await _pickDropdown(tester, '每月账单日', '18 日');
      await _scrollTo(tester, find.text('第 1 期'), page: _section);
      expect(find.text('账单日 2026-10-18 → 到期 2026-10-28'), findsOneWidget);
      final inclusive = find.widgetWithText(SwitchListTile, '账单日当天入账计入本期');
      await _scrollTo(tester, inclusive, page: _section, delta: -200);
      await tester.tap(inclusive);
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.text('第 1 期'), page: _section);
      expect(find.text('账单日 2026-11-18 → 到期 2026-11-28'), findsOneWidget);
    });

    testWidgets('到期不晚于账单日：提示且不能保存；工作日与顺延开关禁用', (tester) async {
      await pumpCardFlowApp(tester, seed: _bareCard);
      await openSettings(tester);
      await _pickDropdown(tester, '每月账单日', '28 日');
      await _scrollTo(
        tester,
        find.widgetWithText(DropdownButtonFormField<int>, '到期日'),
        page: _section,
      );
      await _pickDropdown(tester, '到期日', '25 日');
      await _scrollTo(tester, find.text('到期日须晚于账单日（不能保存）'), page: _section);
      expect(find.text('到期日须晚于账单日（不能保存）'), findsOneWidget);
      final save = find.widgetWithText(FilledButton, '保存为用户声明');
      await _scrollTo(tester, save, page: _section);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await _scrollTo(
        tester,
        find.text('到期日遇节假日顺延'),
        page: _section,
        delta: -200,
      );
      final rollover = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '到期日遇节假日顺延'),
      );
      expect(rollover.onChanged, isNull);
    });

    testWidgets('保存 → 第 1 版（全部历史）；再从某日起保存 → 第 2 版，旧版已失效（F-14）', (tester) async {
      await pumpCardFlowApp(tester, seed: _bareCard);
      await openSettings(tester);
      final save = find.widgetWithText(FilledButton, '保存为用户声明');
      await _scrollTo(tester, save, page: _section);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text(RuleEditorSection.savedMessage), findsOneWidget);
      await _scrollTo(tester, find.textContaining('第 1 版'), page: _section);
      expect(find.textContaining('全部历史'), findsWidgets);

      await _scrollTo(
        tester,
        find.text('从某日起按新规则'),
        page: _section,
        delta: -200,
      );
      await tester.tap(find.text('从某日起按新规则'));
      await tester.pumpAndSettle();
      await _scrollTo(tester, save, page: _section);
      await tester.tap(save);
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.textContaining('第 2 版'), page: _section);
      expect(find.textContaining('第 2 版 · 用户声明'), findsOneWidget);
      expect(find.textContaining('2026-10-18 起'), findsOneWidget);
      await _scrollTo(
        tester,
        find.textContaining('第 1 版 · 已失效'),
        page: _section,
      );
      expect(find.textContaining('全部历史，至 2026-10-18 前'), findsOneWidget);
    });

    testWidgets('额度快照：临时额度须到期日、专项须用途；可负的银行可用；记录后进入历史', (tester) async {
      _section = LimitSnapshotSection;
      await pumpCardFlowApp(tester, seed: _bareCard);
      await openSettings(tester, section: 'limits');
      await tester.enterText(find.widgetWithText(TextField, '固定额度'), '10,000');
      await tester.enterText(find.widgetWithText(TextField, '临时额度（可选）'), '500');
      await _scrollTo(
        tester,
        find.widgetWithText(TextField, '已用'),
        page: _section,
      );
      await tester.enterText(find.widgetWithText(TextField, '已用'), '10,300');
      await tester.enterText(
        find.widgetWithText(TextField, '银行可用（银行显示的数，可为负）'),
        '-300',
      );
      final record = find.widgetWithText(FilledButton, '记录新快照');
      await _scrollTo(tester, record, page: _section);
      await tester.tap(record);
      await tester.pumpAndSettle();
      await _scrollTo(
        tester,
        find.text('临时额度须填写到期日'),
        page: _section,
        delta: -200,
      );
      expect(find.text('临时额度须填写到期日'), findsOneWidget);

      final tempField = find.widgetWithText(TextField, '临时额度（可选）');
      await _scrollTo(tester, tempField, page: _section, delta: -200);
      await tester.enterText(tempField, '');
      await _scrollTo(tester, record, page: _section);
      await tester.tap(record);
      await tester.pumpAndSettle();
      expect(find.text(LimitSnapshotSection.savedMessage), findsOneWidget);
      await _scrollTo(
        tester,
        find.textContaining('银行 App · 你已确认'),
        page: _section,
      );
      expect(find.textContaining('银行 App · 你已确认'), findsOneWidget);
    });

    testWidgets('币种子账户：增加美元、删除美元（须确认）；主子账户不可删', (tester) async {
      await pumpCardFlowApp(tester, seed: _bareCard);
      await openSettings(tester, section: 'currencies');
      expect(find.text('主子账户（不可删除）'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, '币种（只支持这 13 种）'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('美元（USD）').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '增加'));
      await tester.pumpAndSettle();
      expect(find.text('外币子账户'), findsOneWidget);
      await tester.tap(find.byTooltip('删除美元（USD）子账户'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(find.text('外币子账户'), findsNothing);
    });

    testWidgets('授信池：新建并加入、显示池上限与池内合计、移出', (tester) async {
      _section = PoolSection;
      await pumpCardFlowApp(
        tester,
        seed: (scope) async {
          final card = await createTestCard(scope, bank: '建设银行', last4: '1234');
          final primary = await primaryCurrencyAccount(
            scope,
            card.creditAccountId,
          );
          await recordTestSnapshot(
            scope,
            primary.id,
            fixed: 1500000,
            used: 300000,
          );
        },
      );
      await openSettings(tester, section: 'pool');
      expect(find.textContaining('还没有授信池'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, '池名称'), '建行共享额度');
      await tester.enterText(find.widgetWithText(TextField, '池上限'), '10000');
      await _scrollTo(tester, find.text('新建并加入'), page: _section);
      await tester.tap(find.text('新建并加入'));
      await tester.pumpAndSettle();
      expect(find.text('已新建并加入授信池'), findsOneWidget);
      expect(find.text('当前授信池 · 建行共享额度'), findsOneWidget);
      expect(find.text('池内账户可用合计'), findsOneWidget);
      await _scrollTo(tester, find.text('移出授信池'), page: _section);
      await tester.tap(find.text('移出授信池'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '移出'));
      await tester.pumpAndSettle();
      expect(find.text('已移出授信池'), findsOneWidget);
      expect(find.text('加入同银行的授信池'), findsOneWidget);
    });
  });
}
