import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/diagnostics/diagnostic_log.dart';
import 'app_database.dart';
import 'database_errors.dart';
import 'database_key.dart';
import 'database_location.dart';
import 'database_opener.dart';
import 'database_platform.dart';

part 'database_providers.g.dart';

/// 数据库相关 provider 失败时不自动重试。
///
/// Riverpod 3 默认对抛出 Exception 的 provider 以指数退避重试最多 10 次（约 38 秒），
/// 期间状态一直是"读取中"。打开加密库的失败（wrong_key、key_missing、cipher_unavailable
/// 等）都是确定性的，重试只会把错误码推迟半分钟才显示；重新打开交给重启 App。
Duration? noDatabaseRetry(int retryCount, Object error) => null;

/// 设备数据库密钥的存放处：iOS 钥匙串。测试里换成内存实现。
@Riverpod(keepAlive: true)
DatabaseKeyStore databaseKeyStore(Ref ref) =>
    const SecureStorageDatabaseKeyStore();

/// 密钥管理：同一进程内最多生成一次密钥。
@Riverpod(keepAlive: true)
DatabaseKeyManager databaseKeyManager(Ref ref) =>
    DatabaseKeyManager(ref.watch(databaseKeyStoreProvider));

/// 数据库文件位置（Application Support / Caches）。测试里换成临时目录。
@Riverpod(keepAlive: true, retry: noDatabaseRetry)
Future<DatabaseLocation> databaseLocation(Ref ref) =>
    resolveDefaultDatabaseLocation();

/// 已打开并通过加密检查的本机数据库，附带打开信息（加密库、是否新建、耗时）。
///
/// 失败时是 [DatabaseOpenException]（只含错误码）。诊断日志记 `db/opened`
/// （detail：created/existing）或 `db/open_failed`（detail：错误码）。
@Riverpod(keepAlive: true, retry: noDatabaseRetry)
Future<OpenedAppDatabase> openedDatabase(Ref ref) async {
  final log = ref.watch(diagnosticLogProvider);
  final keys = ref.watch(databaseKeyManagerProvider);
  final locationFuture = ref.watch(databaseLocationProvider.future);
  try {
    final opened = await openAppDatabase(
      keys: keys,
      location: await locationFuture,
    );
    if (!ref.mounted) {
      await opened.database.close();
      throw StateError('database provider disposed while opening');
    }
    ref.onDispose(() => unawaited(opened.database.close()));
    log.info('db', 'opened', detail: opened.created ? 'created' : 'existing');
    return opened;
  } on StateError {
    rethrow;
  } on Object catch (error) {
    final failure = databaseOpenExceptionFrom(error);
    log.error('db', 'open_failed', detail: failure.code.code);
    throw failure;
  }
}

/// 本机加密数据库（drift）。仓库与用例从这里取：
/// `final db = await ref.watch(databaseProvider.future);`
@Riverpod(keepAlive: true, retry: noDatabaseRetry)
Future<AppDatabase> database(Ref ref) async =>
    (await ref.watch(openedDatabaseProvider.future)).database;

/// 钥匙串里是否已有数据库密钥（诊断页只显示"已生成/未生成"）。
///
/// 首次启动时密钥在打开数据库的过程中生成，所以先等打开结束（无论成败）再查。
@Riverpod(retry: noDatabaseRetry)
Future<bool> databaseKeyExists(Ref ref) async {
  if (kIsWeb) {
    throw const DatabaseOpenException(DatabaseErrorCode.unsupportedPlatform);
  }
  try {
    await ref.watch(openedDatabaseProvider.future);
  } on Object {
    // 打开失败也要显示密钥是否存在（例如 wrong_key 时密钥是存在的）。
  }
  return ref.read(databaseKeyManagerProvider).hasKey();
}
