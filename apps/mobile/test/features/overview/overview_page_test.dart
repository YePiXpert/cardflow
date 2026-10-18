// P-01 总览（最小版，ui-spec P-01）：四态、顶部空间标识与"纯本地"、每个账户一行预测账期与到期日、
// 没有现金账户时"数据不全"、建卡入口。
import 'dart:async';

import 'package:cardflow/app/widgets/state_views.dart';
import 'package:cardflow/app/widgets/workspace_badges.dart';
import 'package:cardflow/data/repositories/card_wallet_reader.dart';
import 'package:cardflow/data/repositories/providers.dart';
import 'package:cardflow/features/cards/new_card_page.dart';
import 'package:cardflow/features/overview/overview_page.dart';
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

  testWidgets('成功（演示）：空间标识"演示"；每个账户一行预测账期（与回归样本一致）；数据不全：还没有现金账户', (
    tester,
  ) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
    expect(find.text('演示'), findsOneWidget);
    expect(find.textContaining(OverviewPage.noCashAccounts), findsOneWidget);
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
  });

  testWidgets('账户没有规则：显示"账期规则未设置"', (tester) async {
    await pumpCardFlowApp(
      tester,
      seed: (scope) async {
        await createTestCard(scope, alias: '新卡');
      },
    );
    expect(find.text('新卡'), findsOneWidget);
    expect(find.text('账期规则未设置'), findsOneWidget);
  });
}
