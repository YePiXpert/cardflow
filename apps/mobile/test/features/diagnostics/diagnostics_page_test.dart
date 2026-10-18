import 'package:cardflow/app/diagnostics/diagnostic_log.dart';
import 'package:cardflow/app/routes.dart';
import 'package:cardflow/data/db/database_benchmark.dart';
import 'package:cardflow/data/db/database_providers.dart';
import 'package:cardflow/data/db/encryption.dart';
import 'package:cardflow/features/diagnostics/app_diagnostics.dart';
import 'package:cardflow/features/diagnostics/crypto_status.dart';
import 'package:cardflow/features/diagnostics/database_benchmark_controller.dart';
import 'package:cardflow/features/diagnostics/diagnostics_page.dart';
import 'package:cardflow/features/diagnostics/diagnostics_report.dart';
import 'package:cardflow/features/diagnostics/platform_description.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../data/db/db_test_support.dart';
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

/// 固定结果的基准控制器：记录点击次数，不做真实 I/O。
class _FakeBenchmark extends DatabaseBenchmark {
  int runs = 0;

  static const DatabaseBenchmarkResult result = DatabaseBenchmarkResult(
    rows: 100000,
    write: Duration(milliseconds: 812),
    open: Duration(milliseconds: 41),
    count: Duration(milliseconds: 29),
    fileSizeBytes: 9875456,
    cipher: CipherInfo(
      library: 'SQLite3 Multiple Ciphers 2.6.1',
      cipher: 'chacha20',
      cipherVersionPragma: '',
    ),
  );

  @override
  DatabaseBenchmarkState build() => const DatabaseBenchmarkIdle();

  @override
  Future<void> run() async {
    runs++;
    state = const DatabaseBenchmarkSucceeded(result);
  }
}

void main() {
  testWidgets('显示版本、构建号、Bundle ID、构建类型、系统、加密库状态与密钥状态', (tester) async {
    await pumpCardFlowApp(tester);
    await goTo(tester, AppRoutes.diagnostics);

    expect(appBarTitle(DiagnosticsPage.title), findsOneWidget);
    expect(find.text('卡序'), findsOneWidget);
    expect(find.text('0.0.1（构建 7）'), findsOneWidget);
    expect(find.text('li.yep.cardflow'), findsOneWidget);
    expect(find.text('debug'), findsOneWidget);
    expect(find.text('本机构建'), findsOneWidget);

    for (final text in <String>[
      '已启用（SQLite3 Multiple Ciphers 2.6.1，算法 chacha20）',
      '已生成',
      '未运行',
      '运行数据库基准（10 万行）',
    ]) {
      await tester.scrollUntilVisible(find.text(text), 100);
      expect(find.text(text), findsOneWidget, reason: text);
    }
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
    expect(
      report,
      contains(
        '加密库状态：已启用（SQLite3 Multiple Ciphers 2.6.1，算法 chacha20）；'
        'PRAGMA cipher=chacha20；sqlite3mc_version()=SQLite3 Multiple Ciphers 2.6.1；'
        'PRAGMA cipher_version=（空，sqlite3mc 不提供此 PRAGMA）',
      ),
    );
    expect(report, contains('数据库密钥：已生成'));
    expect(report, contains('数据库基准：未运行'));
    expect(report, contains('route/changed /settings/diagnostics'));
    expect(find.text(DiagnosticsPage.copiedMessage), findsOneWidget);

    await tester.pump();
    final log = appContainer(tester).read(diagnosticLogProvider);
    expect(log.entries.last.event, 'copied');
  });

  testWidgets('加密库不可用时显示错误码，密钥显示"未生成"', (tester) async {
    await pumpCardFlowApp(
      tester,
      databaseOverrides: fakeDatabaseOverrides(
        status: const CryptoLibraryUnavailable(reasonCode: 'key_missing'),
        keyExists: false,
      ),
    );
    await goTo(tester, AppRoutes.diagnostics);

    for (final text in <String>['不可用（key_missing）', '未生成']) {
      await tester.scrollUntilVisible(find.text(text), 100);
      expect(find.text(text), findsOneWidget, reason: text);
    }
  });

  testWidgets('「运行数据库基准」：显示各段毫秒数，并进入复制的报告', (tester) async {
    final fake = _FakeBenchmark();
    await pumpCardFlowApp(
      tester,
      overrides: <Override>[databaseBenchmarkProvider.overrideWith(() => fake)],
    );
    await goTo(tester, AppRoutes.diagnostics);
    final copied = captureClipboard(tester);

    final button = find.text('运行数据库基准（10 万行）');
    await tester.scrollUntilVisible(button, 200);
    await tester.tap(button);
    await tester.pump();

    expect(fake.runs, 1);
    expect(
      find.text('100000 行：写入 812 ms · 重新打开 41 ms · COUNT 29 ms'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(find.text('复制诊断信息'), -200);
    await tester.tap(find.text('复制诊断信息'));
    await tester.pump();
    expect(
      copied.single,
      contains(
        '数据库基准：rows=100000 write_ms=812 open_ms=41 count_ms=29 '
        'file_bytes=9875456 cipher=chacha20 library=SQLite3 Multiple Ciphers 2.6.1',
      ),
    );
  });

  testWidgets('真实加密库：诊断页显示 sqlite3mc 与"已生成"，报告里没有密钥', (tester) async {
    final location = createTempLocation();
    final store = InMemoryDatabaseKeyStore(value: testKeyHex);
    await pumpCardFlowApp(
      tester,
      databaseOverrides: <Override>[
        databaseKeyStoreProvider.overrideWithValue(store),
        databaseLocationProvider.overrideWith((ref) async => location),
        databaseBenchmarkRowsProvider.overrideWithValue(300),
      ],
    );
    final container = appContainer(tester);
    // 真实 I/O（后台 isolate、文件）只能在 runAsync 的真实事件循环里完成；已在真实 zone 里
    // 完成的 future 若在组件测试的伪异步 zone 里 await，其回调排在真实事件循环上，伪时钟
    // pump 不会执行它。所以 provider 都在 runAsync 里先算好（自动释放的密钥状态用 listen
    // 保活），页面随后直接读到结果。
    await tester.runAsync(() async {
      final keySubscription = container.listen(
        databaseKeyExistsProvider,
        (_, _) {},
      );
      addTearDown(keySubscription.close);
      await container.read(cryptoLibraryStatusProvider.future);
      await container.read(databaseKeyExistsProvider.future);
    });
    await goTo(tester, AppRoutes.diagnostics);
    final copied = captureClipboard(tester);

    for (final finder in <Finder>[
      find.textContaining('已启用（SQLite3 Multiple Ciphers '),
      find.text('已生成'),
      find.text('运行数据库基准（300 行）'),
    ]) {
      await tester.scrollUntilVisible(finder, 100);
      expect(finder, findsOneWidget);
    }

    await tester.runAsync(
      () => container.read(databaseBenchmarkProvider.notifier).run(),
    );
    await tester.pump();
    expect(find.textContaining('300 行：写入 '), findsOneWidget);

    await tester.scrollUntilVisible(find.text('复制诊断信息'), -200);
    await tester.tap(find.text('复制诊断信息'));
    await tester.pump();
    final report = copied.single;
    expect(report, contains('加密库状态：已启用（SQLite3 Multiple Ciphers '));
    expect(report, contains('数据库密钥：已生成'));
    expect(report, contains('数据库基准：rows=300 '));
    expect(report, contains('I db/opened created'));
    expect(report, contains('I db/benchmark_done'));
    expect(containsKeyMaterial(report, testKeyHex), isFalse);
    expect(report, isNot(contains("x'")));

    // 页面的工作空间数据来自内存库（pumpCardFlowApp 默认）；这里关的是诊断页打开的真实加密库。
    await tester.runAsync(
      () async =>
          (await container.read(openedDatabaseProvider.future)).database
              .close(),
    );
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
      cryptoStatus: const CryptoLibraryUnavailable(reasonCode: 'wrong_key')
          .reportText,
      databaseKeyStatus: '已生成',
      databaseBenchmark: const DatabaseBenchmarkIdle().reportText,
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
    expect(report, contains('加密库状态：不可用（wrong_key）'));
    expect(report, contains('数据库密钥：已生成'));
    expect(report, contains('数据库基准：未运行'));
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

  test('基准按钮上的行数写法', () {
    expect(DiagnosticsPage.describeRowCount(100000), '10 万行');
    expect(DiagnosticsPage.describeRowCount(300), '300 行');
    expect(DiagnosticsPage.describeRowCount(15000), '15000 行');
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
