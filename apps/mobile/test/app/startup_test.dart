// 启动分流（BL-04、ui-spec §1.1）与数据库打不开时的启动页（BL-07、审查 §4 第 7 条）：
// 没有工作空间 → 任何路由先进 P-22；打开中 → 启动页；打不开 → 错误码、「重试」（可重试的错误）、
// 「重置本地数据」（key_missing / wrong_key，确认页须输入"删除"）、诊断页仍可到达。
import 'dart:async';

import 'package:cardflow/app/routes.dart';
import 'package:cardflow/app/startup/reset_local_data_page.dart';
import 'package:cardflow/app/startup/startup_page.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/database_errors.dart';
import 'package:cardflow/data/db/database_providers.dart';
import 'package:cardflow/features/diagnostics/diagnostics_page.dart';
import 'package:cardflow/features/onboarding/welcome_page.dart';
import 'package:cardflow/features/overview/overview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

/// 记录调用的恢复操作（真实的重试与重置在 test/data/db/database_providers_test.dart 测）。
class _FakeRecovery extends DatabaseRecovery {
  int retries = 0;
  int resets = 0;

  @override
  DatabaseRecoveryState build() => const DatabaseRecoveryIdle();

  @override
  void retry() => retries++;

  @override
  Future<void> reset() async => resets++;
}

/// 本机数据库以 [code] 打不开时启动 App。
Future<_FakeRecovery> _pumpWithDatabaseError(
  WidgetTester tester,
  DatabaseErrorCode code,
) async {
  final recovery = _FakeRecovery();
  await pumpCardFlowApp(
    tester,
    useMemoryDatabase: false,
    overrides: <Override>[
      databaseProvider.overrideWith(
        (ref) => Future<AppDatabase>.error(DatabaseOpenException(code)),
      ),
      databaseRecoveryProvider.overrideWith(() => recovery),
    ],
  );
  return recovery;
}

void main() {
  testWidgets('没有工作空间：启动进 P-22（没有返回），任何路由都先回到 P-22；诊断页仍可到达', (tester) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.none);

    expect(appBarTitle(WelcomePage.title), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    for (final path in <String>[
      AppRoutes.overview,
      AppRoutes.cards,
      AppRoutes.settings,
      AppRoutes.welcome,
      AppRoutes.startup,
    ]) {
      await goTo(tester, path);
      expect(appBarTitle(WelcomePage.title), findsOneWidget, reason: path);
    }
    await goTo(tester, AppRoutes.diagnostics);
    expect(appBarTitle(DiagnosticsPage.title), findsOneWidget);
  });

  testWidgets('有工作空间：启动停在总览，启动页与首次使用页都不停留', (tester) async {
    await pumpCardFlowApp(tester);
    expect(appBarTitle(OverviewPage.title), findsOneWidget);
    await goTo(tester, AppRoutes.startup);
    expect(appBarTitle(OverviewPage.title), findsOneWidget);
  });

  testWidgets('打开中：启动页显示"正在打开本机加密数据…"（加载态，无动画）', (tester) async {
    final pending = Completer<AppDatabase>();
    await pumpCardFlowApp(
      tester,
      useMemoryDatabase: false,
      overrides: <Override>[
        databaseProvider.overrideWith((ref) => pending.future),
      ],
    );
    expect(find.text(StartupPage.loadingMessage), findsOneWidget);
    await goTo(tester, AppRoutes.cards);
    expect(find.text(StartupPage.loadingMessage), findsOneWidget);
  });

  testWidgets('key_store_failed：显示错误码与说明，原页面「重试」（不要求重启），没有重置入口', (
    tester,
  ) async {
    final recovery = await _pumpWithDatabaseError(
      tester,
      DatabaseErrorCode.keyStoreFailed,
    );
    expect(find.text(StartupPage.errorTitle), findsOneWidget);
    expect(find.text('错误码：key_store_failed'), findsOneWidget);
    expect(find.textContaining('解锁后点「重试」'), findsOneWidget);
    expect(find.text('重置本地数据'), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(recovery.retries, 1);
  });

  for (final code in <DatabaseErrorCode>[
    DatabaseErrorCode.keyMissing,
    DatabaseErrorCode.wrongKey,
  ]) {
    testWidgets('${code.code}：「重置本地数据」→ 确认页写明影响，输入"删除"才可执行', (tester) async {
      final recovery = await _pumpWithDatabaseError(tester, code);
      expect(find.text('错误码：${code.code}'), findsOneWidget);
      expect(find.text('重试'), findsNothing);

      await tester.tap(find.text('重置本地数据'));
      await tester.pumpAndSettle();
      expect(appBarTitle(ResetLocalDataPage.title), findsOneWidget);
      expect(find.text(ResetLocalDataPage.impact), findsOneWidget);
      final button = find.widgetWithText(
        FilledButton,
        ResetLocalDataPage.title,
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '删');
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.enterText(find.byType(TextField), '删除');
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      await tester.tap(button);
      await tester.pump();
      expect(recovery.resets, 1);
    });
  }

  testWidgets('不可恢复也不可重试的错误（cipher_unavailable）：只有说明与诊断信息', (tester) async {
    await _pumpWithDatabaseError(tester, DatabaseErrorCode.cipherUnavailable);
    expect(find.text('错误码：cipher_unavailable'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    expect(find.text('重置本地数据'), findsNothing);
    await tester.tap(find.text('诊断信息'));
    await tester.pumpAndSettle();
    expect(appBarTitle(DiagnosticsPage.title), findsOneWidget);
  });
}
