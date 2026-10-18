import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/common.dart' show SqliteException;

import 'app_database.dart';
import 'database_errors.dart';
import 'database_key.dart';
import 'database_location.dart';
import 'database_platform.dart';
import 'encryption.dart';

/// 本机数据库文件名。
const String appDatabaseFileName = 'cardflow.sqlite';

/// 已打开并通过检查的本机数据库。
@immutable
final class OpenedAppDatabase {
  const OpenedAppDatabase({
    required this.database,
    required this.cipher,
    required this.created,
    required this.openDuration,
  });

  final AppDatabase database;

  /// 打开时读到的加密库信息。
  final CipherInfo cipher;

  /// 本次打开是否新建了数据库（首次启动）。
  final bool created;

  /// 从开始连接到第一条查询返回（含后台 isolate、设密钥、验证与迁移）的耗时。
  final Duration openDuration;
}

/// 打开（必要时新建）本机加密数据库。
///
/// 1. 看数据库文件是否已有数据；
/// 2. 取密钥：钥匙串已有则用；没有且文件也没有数据（首次启动）才生成并保存；文件已有
///    数据而密钥丢失时拒绝（`key_missing`），不会新建密钥覆盖旧库；
/// 3. drift 后台连接，`setup` 中确认 sqlite3mc → 固定算法 → 原始密钥 → 读一次库验证；
/// 4. 第一条查询触发迁移（新库建 meta 表）；
/// 5. 检查文件开头不是明文 SQLite 文件头（`plaintext_database`）。
///
/// 任一步失败：关闭连接，抛 [DatabaseOpenException]（只含错误码，不含密钥与路径）。
Future<OpenedAppDatabase> openAppDatabase({
  required DatabaseKeyManager keys,
  required DatabaseLocation location,
  String fileName = appDatabaseFileName,
  DateTime Function()? clock,
}) async {
  final String path;
  final bool hadData;
  try {
    path = joinDatabasePath(location.directory, fileName);
    hadData = databaseFileHasData(path);
  } on Object catch (error) {
    throw databaseOpenExceptionFrom(error);
  }

  final key = await keys.obtain(databaseHasData: hadData);

  final stopwatch = Stopwatch()..start();
  AppDatabase? database;
  try {
    database = AppDatabase(
      connectEncryptedDatabase(
        name: 'cardflow',
        path: path,
        tempDirectory: location.tempDirectory,
        rawKeyLiteral: key.rawKeyLiteral(),
      ),
      clock: clock,
    );
    final cipher = await database.readCipherInfo();
    stopwatch.stop();
    if (databaseFileLooksPlaintext(path)) {
      throw const DatabaseOpenException(DatabaseErrorCode.plaintextDatabase);
    }
    return OpenedAppDatabase(
      database: database,
      cipher: cipher,
      created: !hadData,
      openDuration: stopwatch.elapsed,
    );
  } on Object catch (error) {
    await closeQuietly(database);
    throw databaseOpenExceptionFrom(error);
  }
}

/// 把打开过程中的任何异常换成只含错误码的 [DatabaseOpenException]。
///
/// drift 后台 isolate 里抛出的异常会被包成 `DriftRemoteException`，先逐层取出原因
/// （`unwrapRemoteError`）。底层异常（[SqliteException] 等）的正文与语句一律丢弃。
DatabaseOpenException databaseOpenExceptionFrom(Object error) {
  final cause = unwrapRemoteError(error);
  if (cause is DatabaseOpenException) {
    return cause;
  }
  if (cause is SqliteException) {
    return DatabaseOpenException(
      cause.resultCode == sqliteNotADatabase
          ? DatabaseErrorCode.wrongKey
          : DatabaseErrorCode.openFailed,
      sqliteResultCode: cause.extendedResultCode,
    );
  }
  return const DatabaseOpenException(DatabaseErrorCode.openFailed);
}

/// 关闭数据库，忽略关闭本身的错误（用在失败路径上，原始错误更重要）。
Future<void> closeQuietly(GeneratedDatabase? database) async {
  if (database == null) {
    return;
  }
  try {
    await database.close();
  } on Object {
    // 连接可能根本没打开成功；关闭失败不影响已经要抛出的错误码。
  }
}
