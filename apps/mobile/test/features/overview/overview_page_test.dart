// P-01 总览（最小版，ui-spec P-01）：四态、顶部空间标识与"纯本地"、每个账户一行预测账期与到期日、
// 没有现金账户时"数据不全"、建卡入口。
import 'dart:async';

import 'package:cardflow/app/routes.dart';
import 'package:cardflow/app/theme/tokens.dart';
import 'package:cardflow/app/widgets/state_views.dart';
import 'package:cardflow/app/widgets/workspace_badges.dart';
import 'package:cardflow/data/repositories/card_wallet_reader.dart';
import 'package:cardflow/data/repositories/providers.dart';
import 'package:cardflow/features/calendar/cash_calendar_page.dart';
import 'package:cardflow/features/cards/new_card_page.dart';
import 'package:cardflow/features/cash/cash_account_pages.dart';
import 'package:cardflow/features/overview/overview_page.dart';
import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../data/repositories/repository_test_support.dart';
import '../../test_helpers.dart';

void main() {
  testWidgets('首次空白："还没有信用账户"、空间标识"真实"与"纯本地"；建卡进入新建卡片', (tester) async {
    await pumpCardFlowApp(tester);
    expect(find.text(OverviewPage.firstRunMessage), findsOneWidget);
    expect(find.text('真实'), findsOneWidget);
    expect(find.text(LocalOnlyPill.label), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '建卡'));
    await tester.pumpAndSettle();
    expect(appBarTitle(NewCardPage.title), findsOneWidget);
  });

  testWidgets('加载：骨架；错误：错误码与「重试」', (tester) async {
    final pending = Completer<WalletView>();
    await pumpCardFlowApp(
      tester,
      overrides: <Override>[
        walletProvider.overrideWith((ref) => pending.future),
      ],
    );
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
    expect(find.text('总览读取失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets(
    '成功（演示）：空间标识"演示"；现金压力（基准 30 天最低点与首个缺口日，可切到已确认）；每个账户一行预测账期（与回归样本一致）',
    (tester) async {
      await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
      expect(find.text('演示'), findsOneWidget);
      final confirmed = find.widgetWithText(ChoiceChip, '已确认');
      await tester.scrollUntilVisible(confirmed, 200);
      await tester.ensureVisible(confirmed);
      await tester.pumpAndSettle();
      expect(find.text('现金压力'), findsOneWidget);
      expect(find.textContaining(OverviewPage.noCashAccounts), findsNothing);
      expect(find.text('未来 30 天 · 基准预期 · 人民币（CNY）'), findsOneWidget);
      expect(find.text('11-01 · 工资卡'), findsOneWidget);
      expect(find.text('▲ 首个缺口日 11-01（工资卡）· 共 1 个缺口点'), findsOneWidget);
      await tester.tap(confirmed);
      await tester.pumpAndSettle();
      expect(find.text('▲ 首个缺口日 11-01（工资卡）· 共 2 个缺口点'), findsOneWidget);
      await tester.ensureVisible(find.textContaining('查看资金日历'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('查看资金日历'));
      await tester.pumpAndSettle();
      expect(appBarTitle(CashCalendarPage.title), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '已确认'))
            .selected,
        isTrue,
        reason: '带着口径进入资金日历',
      );

      await goTo(tester, AppRoutes.overview);
      expect(find.text('预测账期（未出账）'), findsOneWidget);
      for (final (name, line) in <(String, String)>[
        ('卡 A', '账单日 11-10 · 到期 11-28（系统估计）'),
        ('卡 B', '账单日 10-20 · 到期 11-08（系统估计）'),
        ('卡 D', '账单日 11-15 · 到期 12-05（系统估计）'),
        ('卡 C', '账单日 11-05 · 到期 11-25（系统估计）'),
      ]) {
        await tester.scrollUntilVisible(find.text(line), 100);
        expect(find.text(name), findsOneWidget, reason: name);
        expect(find.text(line), findsOneWidget, reason: name);
      }
    },
  );

  testWidgets('有卡、没有现金账户：数据不全：还没有现金账户「添加现金账户」→ 添加页', (tester) async {
    await pumpCardFlowApp(
      tester,
      seed: (scope) async {
        await createTestCard(scope, alias: '新卡');
      },
    );
    expect(find.textContaining(OverviewPage.noCashAccounts), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '添加现金账户'));
    await tester.pumpAndSettle();
    expect(appBarTitle(NewCashAccountPage.title), findsOneWidget);
  });

  testWidgets('现金压力：缺快照的账户"数据不全：{账户}缺快照，未计入"；没有缺口用中性色（不用绿色）', (tester) async {
    await pumpCardFlowApp(
      tester,
      seed: (scope) async {
        await createTestCard(scope, alias: '新卡');
        final acc = await createTestCashAccount(scope);
        await recordTestCashSnapshot(
          scope,
          acc.id,
          LocalDate(2026, 10, 17),
          500000,
        );
        await createTestCashAccount(scope, name: '零钱');
      },
    );
    expect(find.text('数据不全：零钱缺快照，未计入'), findsOneWidget);
    expect(find.text('30 天内没有缺口'), findsOneWidget);
    final card = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('cash-pressure-CNY')),
            matching: find.byType(Container),
          )
          .first,
    );
    final colors = CardFlowColors.light;
    final decoration = card.decoration! as BoxDecoration;
    expect(decoration.color, isNot(colors.robust.bg));
    expect(decoration.color, colors.surface);
    expect(find.textContaining('安全'), findsNothing);
    expect(find.textContaining('稳妥'), findsNothing);
  });

  testWidgets('账户没有规则：显示"账期规则未设置"', (tester) async {
    await pumpCardFlowApp(
      tester,
      seed: (scope) async {
        await createTestCard(scope, alias: '新卡');
      },
    );
    await tester.scrollUntilVisible(find.text('账期规则未设置'), 200);
    expect(find.text('新卡'), findsOneWidget);
    expect(find.text('账期规则未设置'), findsOneWidget);
  });
}
