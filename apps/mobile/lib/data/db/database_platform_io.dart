import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'database_errors.dart';
import 'database_location.dart';
import 'encryption.dart';

/// 默认位置：数据库在 Application Support，临时文件在 Caches（都在 App 沙盒内）。
Future<DatabaseLocation> resolveDefaultDatabaseLocation() async {
  try {
    final support = await getApplicationSupportDirectory();
    final temp = await getTemporaryDirectory();
    return DatabaseLocation(directory: support.path, tempDirectory: temp.path);
  } on Object {
    throw const DatabaseOpenException(DatabaseErrorCode.locationUnavailable);
  }
}

/// 目录 + 文件名。
String joinDatabasePath(String directory, String fileName) =>
    '$directory${Platform.pathSeparator}$fileName';

/// 文件存在且非空。SQLite 打开时可能先建一个空文件，空文件不算"已有数据"。
bool databaseFileHasData(String path) {
  final file = File(path);
  return file.existsSync() && file.lengthSync() > 0;
}

/// 文件开头是不是明文 SQLite 文件头（加密库开头是随机盐值）。
bool databaseFileLooksPlaintext(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return false;
  }
  final handle = file.openSync();
  try {
    return isPlaintextSqliteHeader(
      handle.readSync(plaintextSqliteHeader.length),
    );
  } finally {
    handle.closeSync();
  }
}

/// 数据库文件大小（字节）；不存在时为 0。
int databaseFileSize(String path) {
  final file = File(path);
  return file.existsSync() ? file.lengthSync() : 0;
}

/// 删除数据库文件及其日志文件（-journal、-wal、-shm）。
void deleteDatabaseFiles(String path) {
  for (final suffix in const <String>['', '-journal', '-wal', '-shm']) {
    final file = File('$path$suffix');
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}

/// 打开加密连接：drift_flutter 在后台 isolate 中打开 SQLite，并在任何读写之前运行
/// [encryptionSetup]（确认 sqlite3mc → 固定算法 → 原始密钥 → 验证）。
///
/// 连接是惰性的：第一条查询才真正打开；打开失败的异常从那条查询抛出。
QueryExecutor connectEncryptedDatabase({
  required String name,
  required String path,
  required String? tempDirectory,
  required String rawKeyLiteral,
}) {
  return driftDatabase(
    name: name,
    native: DriftNativeOptions(
      databasePath: () async => path,
      tempDirectoryPath: () async => tempDirectory,
      setup: encryptionSetup(rawKeyLiteral),
    ),
  );
}

/// drift 后台 isolate 里抛出的异常在调用方会被包成 [DriftRemoteException]（可能多层）；
/// 逐层取出最初的异常。
Object unwrapRemoteError(Object error) {
  var cause = error;
  while (cause is DriftRemoteException) {
    cause = cause.remoteCause;
  }
  return cause;
}
