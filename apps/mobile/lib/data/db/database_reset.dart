import 'app_database.dart' show appDatabaseFileName;
import 'database_errors.dart';
import 'database_key.dart';
import 'database_location.dart';
import 'database_platform.dart';

/// "重置本地数据"（BL-07）：删除本机数据库文件（含 -journal/-wal/-shm）与钥匙串里的数据库密钥，
/// 并让密钥管理器忘掉缓存（审查 R-15）。
///
/// 只在打开失败且无法恢复（`key_missing`、`wrong_key`）时由用户确认后调用；调用前数据库连接
/// 必须已关闭。之后重新打开即按首次启动处理：生成新密钥、建新库。
///
/// 失败：数据库文件删不掉 → [DatabaseErrorCode.resetFailed]；钥匙串操作失败 →
/// [DatabaseErrorCode.keyStoreFailed]。两种情况下密钥缓存都已忘掉，可以重试。
Future<void> resetLocalDatabase({
  required DatabaseKeyManager keys,
  required DatabaseLocation location,
  String fileName = appDatabaseFileName,
}) async {
  keys.forget();
  try {
    deleteDatabaseFiles(joinDatabasePath(location.directory, fileName));
  } on Object {
    throw const DatabaseOpenException(DatabaseErrorCode.resetFailed);
  }
  await keys.deleteKey();
}
