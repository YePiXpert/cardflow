import 'package:drift/drift.dart';
import 'package:sqlite3/common.dart' show SqliteException;

import 'database_errors.dart';
import 'database_platform.dart';
import 'encryption.dart';

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
