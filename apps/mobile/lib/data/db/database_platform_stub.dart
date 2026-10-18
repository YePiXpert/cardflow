import 'package:drift/drift.dart';

import 'database_errors.dart';
import 'database_location.dart';

// Web：没有加密本地库（Web 构建只作编译烟雾测试）。所有入口都报 unsupported_platform。

Future<DatabaseLocation> resolveDefaultDatabaseLocation() async =>
    throw const DatabaseOpenException(DatabaseErrorCode.unsupportedPlatform);

String joinDatabasePath(String directory, String fileName) =>
    '$directory/$fileName';

bool databaseFileHasData(String path) => false;

bool databaseFileLooksPlaintext(String path) => false;

int databaseFileSize(String path) => 0;

void deleteDatabaseFiles(String path) {}

QueryExecutor connectEncryptedDatabase({
  required String name,
  required String path,
  required String? tempDirectory,
  required String rawKeyLiteral,
}) => throw const DatabaseOpenException(DatabaseErrorCode.unsupportedPlatform);

Object unwrapRemoteError(Object error) => error;
