import 'package:cardflow/app/routes.dart';
import 'package:cardflow/features/diagnostics/app_diagnostics.dart';
import 'package:cardflow/features/diagnostics/crypto_status.dart';
import 'package:cardflow/features/diagnostics/diagnostic_log.dart';
import 'package:cardflow/features/diagnostics/diagnostics_page.dart';
import 'package:cardflow/features/diagnostics/diagnostics_report.dart';
import 'package:cardflow/features/diagnostics/platform_description.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers.dart';

/// 截获写入剪贴板的文字。
List<String> captureClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        final arguments = call.arguments as Map<Object?, Object?>;
        copied.add(arguments['text']! as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

void main() {
  testWidgets('显示版本、构建号、Bundle ID、构建类型、系统与加密库占位', (tester) async {
    await pumpCardFlowApp(tester);
    await goTo(tester, AppRoutes.diagnostics);

    expect(appBarTitle(DiagnosticsPage.title), findsOneWidget);
    expect(find.text('卡序'), findsOneWidget);
    expect(find.text('0.0.1（构建 7）'), findsOneWidget);
    expect(find.text('li.yep.cardflow'), findsOneWidget);
    expect(find.text('debug'), findsOneWidget);
    expect(find.text('本机构建'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('待下一阶段'), 200);
    expect(find.text('待下一阶段'), findsOneWidget);
    final routeRow = find.text('route/changed /settings/diagnostics');
    await tester.scrollUntilVisible(routeRow, 200);
    expect(routeRow, findsOneWidget);
  });

  testWidgets('「复制诊断信息」把报告放进剪贴板，并给出轻提示', (tester) async {
    await pumpCardFlowApp(tester);
    await goTo(tester, AppRoutes.diagnostics);
    final copied = captureClipboard(tester);

    await tester.tap(find.text('复制诊断信息'));
    await tester.pump();

    expect(copied, hasLength(1));
    final report = copied.single;
    expect(report, contains('卡序 CardFlow 诊断信息'));
    expect(report, contains('应用：卡序 0.0.1（构建 7）'));
    expect(report, contains('Bundle ID：li.yep.cardflow'));
    expect(report, contains('构建类型：debug'));
    expect(report, contains('加密库状态：待下一阶段'));
    expect(report, contains('route/changed /settings/diagnostics'));
    expect(find.text(DiagnosticsPage.copiedMessage), findsOneWidget);

    await tester.pump();
    final log = appContainer(tester).read(diagnosticLogProvider);
    expect(log.entries.last.event, 'copied');
  });

  testWidgets('下一阶段登记加密库状态后，诊断页直接显示', (tester) async {
    await pumpCardFlowApp(
      tester,
      overrides: <Override>[
        cryptoLibraryStatusProvider.overrideWith(
          (ref) async => const CryptoLibraryReady(cipherVersion: '4.9.0'),
        ),
      ],
    );
    await goTo(tester, AppRoutes.diagnostics);

    await tester.scrollUntilVisible(find.textContaining('cipher_version'), 200);
    expect(find.text('已启用（cipher_version 4.9.0）'), findsOneWidget);
  });

  test('报告只含元数据与脱敏日志', () {
    final log = DiagnosticLog(clock: () => DateTime.utc(2026, 10, 18, 9));
    addTearDown(log.dispose);
    log
      ..info('app', 'launch', detail: 'release')
      ..warning('import', 'parsed', detail: '应还 8000.00 卡号尾号 1234');

    final report = buildDiagnosticsReport(
      app: const AppDiagnostics(
        appName: '卡序',
        version: '0.0.1',
        buildNumber: '42',
        bundleId: 'li.yep.cardflow',
        buildMode: 'release',
        sourceRevision: 'abcdef123456',
        platform: PlatformDescription(
          osName: 'ios',
          osVersion: 'Version 18.1 (Build 22B83)',
          dartVersion: '3.13.5',
          localeName: 'zh_CN',
        ),
      ),
      cryptoStatus: const CryptoLibraryPending().displayText,
      display: const DisplayEnvironment(textScalePercent: 200, darkMode: true),
      entries: log.entries,
      droppedCount: log.droppedCount,
      capacity: log.capacity,
      generatedAt: DateTime.utc(2026, 10, 18, 10),
    );

    expect(report, contains('生成时间：2026-10-18T10:00:00.000Z'));
    expect(report, contains('系统：ios Version 18.1 (Build 22B83)'));
    expect(report, contains('文字缩放：200%'));
    expect(report, contains('外观：深色'));
    expect(report, contains('日志：2 条（上限 500 条，已丢弃 0 条较早记录；时间为 UTC）'));
    expect(report, contains('2026-10-18T09:00:00.000Z I app/launch release'));
    expect(report, contains('W import/parsed 应还 ####.## 卡号尾号 ####'));
    expect(report, isNot(contains('8000')));
  });

  test('源码版本：CI 注入提交号时显示前 12 位，本机构建显示"本机构建"', () {
    expect(describeSourceRevision(''), '本机构建');
    expect(describeSourceRevision('  '), '本机构建');
    expect(
      describeSourceRevision('0123456789abcdef0123456789abcdef01234567'),
      '0123456789ab',
    );
  });

  testWidgets('应用信息读取失败时显示错误而不是空白', (tester) async {
    await pumpCardFlowApp(
      tester,
      overrides: <Override>[
        appDiagnosticsProvider.overrideWith(
          (ref) => Future<AppDiagnostics>.error(StateError('x')),
        ),
      ],
    );
    await goTo(tester, AppRoutes.diagnostics);

    expect(find.text('读取失败（StateError）'), findsOneWidget);
    final button = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('复制诊断信息'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    expect(button.onPressed, isNull);
  });
}
