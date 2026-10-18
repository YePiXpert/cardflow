// databaseProvider / cryptoLibraryStatusProvider / 基准控制器 与诊断日志、诊断报告
// （真实 sqlite3mc；钥匙串与目录换成测试替身）。
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/database_errors.dart';
import 'package:cardflow/data/db/database_location.dart';
import 'package:cardflow/data/db/database_providers.dart';
import 'package:cardflow/features/diagnostics/app_diagnostics.dart';
import 'package:cardflow/features/diagnostics/crypto_status.dart';
import 'package:cardflow/features/diagnostics/database_benchmark_controller.dart';
import 'package:cardflow/features/diagnostics/diagnostic_log.dart';
import 'package:cardflow/features/diagnostics/diagnostics_report.dart';
import 'package:cardflow/features/diagnostics/platform_description.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'db_test_support.dart';

/// 一个"App 进程"：共享同一个钥匙串与目录，重建容器即模拟重启。
ProviderContainer _launch(
  InMemoryDatabaseKeyStore store,
  DatabaseLocation location, {
  int benchmarkRows = 500,
}) {
  final container = ProviderContainer.test(
    overrides: [
      databaseKeyStoreProvider.overrideWithValue(store),
      databaseLocationProvider.overrideWith((ref) async => location),
      databaseBenchmarkRowsProvider.overrideWithValue(benchmarkRows),
    ],
  );
  return container;
}

String _reportOf(ProviderContainer container, CryptoLibraryStatus status) {
  final log = container.read(diagnosticLogProvider);
  final benchmark = container.read(databaseBenchmarkProvider);
  return buildDiagnosticsReport(
    app: const AppDiagnostics(
      appName: '卡序',
      version: '0.0.1',
      buildNumber: '1',
      bundleId: 'li.yep.cardflow',
      buildMode: 'release',
      sourceRevision: 'abcdef123456',
      platform: PlatformDescription(
        osName: 'ios',
        osVersion: '26.0',
        dartVersion: '3.13.5',
        localeName: 'zh_CN',
      ),
    ),
    cryptoStatus: status.reportText,
    databaseKeyStatus: '已生成',
    databaseBenchmark: benchmark.reportText,
    display: const DisplayEnvironment(textScalePercent: 100, darkMode: false),
    entries: log.entries,
    droppedCount: log.droppedCount,
    capacity: log.capacity,
    generatedAt: DateTime.utc(2026, 10, 18),
  );
}

List<String> _logLines(ProviderContainer container) => container
    .read(diagnosticLogProvider)
    .entries
    .map((e) => e.toReportText())
    .toList();

/// 模拟退出 App：先等数据库关闭，再销毁容器（容器销毁时还会再调用一次 close，应无害）。
///
/// 每条打开过数据库的测试都以它结束：drift 的关闭是异步的，若只销毁容器，下一条测试
/// 打开数据库时上一个连接可能还没关完（drift 会警告"打开了多个实例"）。
Future<void> _quit(ProviderContainer container) async {
  try {
    final db = await container.read(databaseProvider.future);
    await db.close();
  } on DatabaseOpenException {
    // 没打开成功，无需关闭。
  }
  container.dispose();
}

void main() {
  late DatabaseLocation location;

  setUp(() => location = createTempLocation());

  test('首次启动：建库、生成密钥，日志 db/opened created；状态显示加密库与算法', () async {
    final store = InMemoryDatabaseKeyStore();
    final container = _launch(store, location);

    final db = await container.read(databaseProvider.future);
    expect(db, isA<AppDatabase>());
    expect((await db.readMeta()).schemaVersion, 1);

    final status = await container.read(cryptoLibraryStatusProvider.future);
    expect(status, isA<CryptoLibraryReady>());
    final ready = status as CryptoLibraryReady;
    expect(ready.library, startsWith('SQLite3 Multiple Ciphers '));
    expect(ready.cipher, 'chacha20');
    expect(
      ready.displayText,
      matches(RegExp(r'^已启用（SQLite3 Multiple Ciphers \S+，算法 chacha20）$')),
    );
    expect(
      ready.reportText,
      contains('PRAGMA cipher_version=（空，sqlite3mc 不提供此 PRAGMA）'),
    );
    expect(await container.read(databaseKeyExistsProvider.future), isTrue);

    final entries = container.read(diagnosticLogProvider).entries;
    final opened = entries.singleWhere((e) => e.category == 'db');
    expect(opened.event, 'opened');
    expect(opened.detail, 'created');
    expect(store.writes, 1);
    await _quit(container);
  });

  test('第二次启动：沿用密钥，日志 db/opened existing', () async {
    final store = InMemoryDatabaseKeyStore();
    final first = _launch(store, location);
    await first.read(databaseProvider.future);
    await _quit(first);

    final second = _launch(store, location);
    await second.read(databaseProvider.future);
    final opened = second
        .read(diagnosticLogProvider)
        .entries
        .singleWhere((e) => e.category == 'db');
    expect(opened.detail, 'existing');
    expect(store.writes, 1);
    await _quit(second);
  });

  test('密钥错误：状态显示 wrong_key，日志 db/open_failed 只记错误码', () async {
    final store = InMemoryDatabaseKeyStore();
    final first = _launch(store, location);
    await first.read(databaseProvider.future);
    await _quit(first);

    store.value = otherKeyHex;
    final container = _launch(store, location);
    final status = await container.read(cryptoLibraryStatusProvider.future);
    expect(status, isA<CryptoLibraryUnavailable>());
    expect(status.displayText, '不可用（wrong_key）');
    await expectLater(
      container.read(databaseProvider.future),
      throwsA(
        isA<DatabaseOpenException>().having(
          (e) => e.code,
          'code',
          DatabaseErrorCode.wrongKey,
        ),
      ),
    );
    expect(await container.read(databaseKeyExistsProvider.future), isTrue);

    final failed = container
        .read(diagnosticLogProvider)
        .entries
        .singleWhere((e) => e.category == 'db');
    expect(failed.event, 'open_failed');
    expect(failed.detail, 'wrong_key');
  });

  test('无密钥而库已存在：状态 key_missing，密钥显示"未生成"，不新建密钥', () async {
    final first = _launch(InMemoryDatabaseKeyStore(), location);
    await first.read(databaseProvider.future);
    await _quit(first);

    final emptyStore = InMemoryDatabaseKeyStore();
    final container = _launch(emptyStore, location);
    final status = await container.read(cryptoLibraryStatusProvider.future);
    expect(status.displayText, '不可用（key_missing）');
    expect(await container.read(databaseKeyExistsProvider.future), isFalse);
    expect(emptyStore.writes, 0);
  });

  test('取不到目录（path_provider 失败）→ location_unavailable', () async {
    final container = ProviderContainer.test(
      overrides: [
        databaseKeyStoreProvider.overrideWithValue(InMemoryDatabaseKeyStore()),
        databaseLocationProvider.overrideWith(
          (ref) => Future<DatabaseLocation>.error(
            const DatabaseOpenException(DatabaseErrorCode.locationUnavailable),
          ),
        ),
      ],
    );
    final status = await container.read(cryptoLibraryStatusProvider.future);
    expect(status.displayText, '不可用（location_unavailable）');
  });

  group('数据库基准控制器', () {
    test('运行 → 成功：状态含毫秒数；日志只记事件（数字脱敏）', () async {
      final container = _launch(InMemoryDatabaseKeyStore(), location);
      final controller = container.read(databaseBenchmarkProvider.notifier);
      expect(
        container.read(databaseBenchmarkProvider),
        isA<DatabaseBenchmarkIdle>(),
      );

      final run = controller.run();
      expect(
        container.read(databaseBenchmarkProvider),
        isA<DatabaseBenchmarkRunning>(),
      );
      await controller.run(); // 运行中重复点击被忽略
      await run;

      final state = container.read(databaseBenchmarkProvider);
      expect(state, isA<DatabaseBenchmarkSucceeded>());
      expect(
        state.displayText,
        matches(RegExp(r'^500 行：写入 \d+ ms · 重新打开 \d+ ms · COUNT \d+ ms$')),
      );
      expect(state.reportText, startsWith('rows=500 write_ms='));
      final events = container
          .read(diagnosticLogProvider)
          .entries
          .where((e) => e.category == 'db')
          .map((e) => e.event);
      expect(events, <String>['benchmark_started', 'benchmark_done']);
    });

    test('失败：状态与日志只有错误码', () async {
      final container = ProviderContainer.test(
        overrides: [
          databaseLocationProvider.overrideWith(
            (ref) => Future<DatabaseLocation>.error(
              const DatabaseOpenException(
                DatabaseErrorCode.locationUnavailable,
              ),
            ),
          ),
        ],
      );
      await container.read(databaseBenchmarkProvider.notifier).run();
      final state = container.read(databaseBenchmarkProvider);
      expect(state, isA<DatabaseBenchmarkFailed>());
      expect(state.displayText, '失败（location_unavailable）');
      final failed = container.read(diagnosticLogProvider).entries.last;
      expect(failed.event, 'benchmark_failed');
      expect(failed.detail, 'location_unavailable');
    });
  });

  test('日志与诊断报告里没有密钥（建库、错误密钥、基准全部走一遍）', () async {
    final store = InMemoryDatabaseKeyStore(value: testKeyHex);
    final container = _launch(store, location);
    final status = await container.read(cryptoLibraryStatusProvider.future);
    expect(status, isA<CryptoLibraryReady>());
    await container.read(databaseBenchmarkProvider.notifier).run();
    final report = _reportOf(container, status);
    expect(report, contains('数据库基准：rows=500 '));
    expect(report, contains('加密库状态：已启用（SQLite3 Multiple Ciphers '));
    final firstLog = _logLines(container);
    await _quit(container);

    store.value = otherKeyHex;
    final failing = _launch(store, location);
    final failedStatus = await failing.read(cryptoLibraryStatusProvider.future);
    final failedReport = _reportOf(failing, failedStatus);
    try {
      await failing.read(databaseProvider.future);
    } on DatabaseOpenException catch (error) {
      expect(containsKeyMaterial(error.toString(), otherKeyHex), isFalse);
    }

    for (final text in <String>[
      report,
      failedReport,
      ...firstLog,
      ..._logLines(failing),
    ]) {
      expect(containsKeyMaterial(text, testKeyHex), isFalse, reason: text);
      expect(containsKeyMaterial(text, otherKeyHex), isFalse, reason: text);
      expect(text, isNot(contains("x'")), reason: text);
    }
  });
}
