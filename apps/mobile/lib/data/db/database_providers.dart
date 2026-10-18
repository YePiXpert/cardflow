import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/diagnostics/diagnostic_log.dart';
import 'app_database.dart';
import 'database_errors.dart';
import 'database_failures.dart';
import 'database_key.dart';
import 'database_location.dart';
import 'database_platform.dart';
import 'database_reset.dart';

part 'database_providers.g.dart';

/// 数据库相关 provider 失败时不自动重试。
///
/// Riverpod 3 默认对抛出 Exception 的 provider 以指数退避重试最多 10 次（约 38 秒），
/// 期间状态一直是"读取中"。打开加密库的失败（wrong_key、key_missing、cipher_unavailable
/// 等）大多是确定性的，自动重试只会把错误码推迟半分钟才显示。可重试的失败（钥匙串暂时
/// 不可用等）由启动错误页的「重试」手动触发（[DatabaseRecovery.retry]），不需要重启 App。
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

/// 启动错误页上的恢复操作的状态。
sealed class DatabaseRecoveryState {
  const DatabaseRecoveryState();
}

/// 没有进行中的恢复操作。
final class DatabaseRecoveryIdle extends DatabaseRecoveryState {
  const DatabaseRecoveryIdle();
}

/// 正在重置本地数据。
final class DatabaseRecoveryRunning extends DatabaseRecoveryState {
  const DatabaseRecoveryRunning();
}

/// 重置失败（只含错误码）。
final class DatabaseRecoveryFailed extends DatabaseRecoveryState {
  const DatabaseRecoveryFailed(this.code);

  final DatabaseErrorCode code;
}

/// 打开本机数据库失败后的恢复操作：「重试」与「重置本地数据」。
///
/// 诊断日志只记事件（`db/retry`、`db/reset`、`db/reset_failed` + 错误码），没有任何内容。
@Riverpod(keepAlive: true)
class DatabaseRecovery extends _$DatabaseRecovery {
  @override
  DatabaseRecoveryState build() => const DatabaseRecoveryIdle();

  /// 重新打开数据库（审查 §4 第 7 条：钥匙串暂时不可用等可重试的失败在原页面重试，
  /// 不要求重启 App）。密钥管理器在取密钥失败时已清掉失败的结果，重开会重新读钥匙串。
  void retry() {
    ref.read(diagnosticLogProvider).info('db', 'retry');
    state = const DatabaseRecoveryIdle();
    _reopen();
  }

  /// 重置本地数据（BL-07，只在 `key_missing`、`wrong_key` 时提供，用户确认后调用）：关闭
  /// 连接 → 删除数据库文件与钥匙串里的密钥 → 密钥管理器忘掉缓存（R-15）→ 重新打开（按首次
  /// 启动建新库、生成新密钥）。
  Future<void> reset() async {
    if (state is DatabaseRecoveryRunning) {
      return;
    }
    state = const DatabaseRecoveryRunning();
    final log = ref.read(diagnosticLogProvider);
    try {
      await closeQuietly(ref.read(openedDatabaseProvider).value?.database);
      final location = await ref.read(databaseLocationProvider.future);
      await resetLocalDatabase(
        keys: ref.read(databaseKeyManagerProvider),
        location: location,
      );
      log.info('db', 'reset');
      state = const DatabaseRecoveryIdle();
    } on Object catch (error) {
      final failure = databaseOpenExceptionFrom(error);
      log.error('db', 'reset_failed', detail: failure.code.code);
      state = DatabaseRecoveryFailed(failure.code);
      return;
    }
    _reopen();
  }

  void _reopen() {
    ref
      ..invalidate(databaseLocationProvider)
      ..invalidate(openedDatabaseProvider)
      ..invalidate(databaseKeyExistsProvider);
  }
}
