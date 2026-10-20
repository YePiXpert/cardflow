// 我的（简报 U-1 §1、§9 R-09/R-10）：纯本地说明（从页顶标签挪到这里）、空间切换、隐藏金额（开关会记住，金额一律
// 4 个点）、关于/诊断/欢迎、重置本地数据（确认页写明两个空间的数据量、须输入"删除"）、公测说明。
import 'package:cardflow/app/money/amount_visibility.dart';
import 'package:cardflow/app/routes.dart';
import 'package:cardflow/app/startup/reset_local_data_page.dart';
import 'package:cardflow/data/db/database_providers.dart';
import 'package:cardflow/data/repositories/workspace_repository.dart';
import 'package:cardflow/features/home/ledger_home_page.dart';
import 'package:cardflow/features/settings/public_beta.dart';
import 'package:cardflow/features/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../data/repositories/repository_test_support.dart';
import '../../test_helpers.dart';

/// 记录调用的重置（真实的重置在 test/data/db/database_providers_test.dart 测）。
class _FakeRecovery extends DatabaseRecovery {
  int resets = 0;

  @override
  DatabaseRecoveryState build() => const DatabaseRecoveryIdle();

  @override
  Future<void> reset() async => resets++;
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

void main() {
  testWidgets('各节：纯本地、空间、隐私、关于与帮助、数据、公测说明', (tester) async {
    await pumpCardFlowApp(tester);
    await goTo(tester, AppRoutes.settings);
    expect(appBarTitle(SettingsPage.title), findsOneWidget);
    expect(find.text('纯本地'), findsOneWidget);
    expect(find.text(SettingsPage.firstRunMessage), findsOneWidget);
    expect(find.text(SettingsPage.localOnlyNote), findsOneWidget);
    expect(find.text('当前：真实空间'), findsOneWidget);
    expect(find.text('体验演示'), findsOneWidget);
    expect(find.text('隐藏金额'), findsOneWidget);
    for (final text in <String>['关于卡序', '诊断信息', '欢迎与开始方式', '重置本地数据']) {
      await _scrollTo(tester, find.text(text));
      expect(find.text(text), findsOneWidget, reason: text);
    }
    await _scrollTo(tester, find.text(PublicBeta.note));
    expect(find.text(PublicBeta.note), findsOneWidget);
  });

  testWidgets('隐藏金额：打开后卡账的金额一律 4 个点；开关记在本机，重新读回', (tester) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
    expect(find.text('¥2,393.33'), findsWidgets);
    await goTo(tester, AppRoutes.settings);
    await tester.tap(find.widgetWithText(SwitchListTile, '隐藏金额'));
    await tester.pumpAndSettle();
    expect(appContainer(tester).read(amountsHiddenProvider), isTrue);
    await goTo(tester, AppRoutes.home);
    expect(appBarTitle(LedgerHomePage.title), findsOneWidget);
    expect(find.text('¥2,393.33'), findsNothing);
    expect(find.text('••••'), findsWidgets);
    final stored = await withCurrentScope(
      tester,
      (scope) => WorkspaceRepository(scope.db).setting(amountsHiddenSettingKey),
    );
    expect(stored, '1');
    // 读回：先在本次运行里关掉，再按库里的值恢复。
    appContainer(tester).read(amountsHiddenProvider.notifier).state = false;
    await tester.pump();
    await tester.runAsync(
      () => appContainer(tester).read(amountsHiddenProvider.notifier).restore(),
    );
    await tester.pumpAndSettle();
    expect(appContainer(tester).read(amountsHiddenProvider), isTrue);
  });

  testWidgets('演示空间：当前是演示空间，可「退出演示」与「清除演示数据」', (tester) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
    await goTo(tester, AppRoutes.settings);
    expect(find.text('当前：演示空间'), findsOneWidget);
    expect(find.text('退出演示'), findsWidgets);
    expect(find.text('清除演示数据'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, '退出演示'));
    await tester.pumpAndSettle();
    expect(find.text('退出演示？'), findsOneWidget);
  });

  testWidgets('重置本地数据：确认页写明真实空间的数据量与不可恢复，输入"删除"才可执行', (tester) async {
    final recovery = _FakeRecovery();
    await pumpCardFlowApp(
      tester,
      seed: (scope) async {
        await createTestCard(scope, bank: '招商银行', last4: '1234');
      },
      overrides: <Override>[
        databaseRecoveryProvider.overrideWith(() => recovery),
      ],
    );
    await goTo(tester, AppRoutes.settings);
    await _scrollTo(tester, find.text('重置本地数据'));
    await tester.tap(find.text('重置本地数据'));
    await tester.pumpAndSettle();
    expect(appBarTitle(ResetLocalDataPage.title), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.textContaining('真实空间里 1 个信用账户、1 张卡片'), findsOneWidget);
    expect(
      find.textContaining(ResetLocalDataPage.irreversible),
      findsOneWidget,
    );
    final button = find.widgetWithText(FilledButton, ResetLocalDataPage.title);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '删除');
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pump();
    expect(recovery.resets, 1);
  });

  testWidgets('重置确认页返回"我的"', (tester) async {
    await pumpCardFlowApp(tester);
    await goTo(tester, AppRoutes.settings);
    await _scrollTo(tester, find.text('重置本地数据'));
    await tester.tap(find.text('重置本地数据'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(appBarTitle(SettingsPage.title), findsOneWidget);
  });
}
