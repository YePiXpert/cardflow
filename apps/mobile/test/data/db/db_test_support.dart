// 本机加密数据库测试的公共辅助。
//
// 这些测试使用真实的 SQLite3MultipleCiphers：flutter test 会运行 sqlite3 包的构建钩子
// （pubspec.yaml 的 hooks.user_defines.sqlite3.source: sqlite3mc），钩子从 sqlite3.dart 的
// GitHub release 下载预编译库并校验 sha256。没有网络或钩子失败时测试会失败并给出钩子的
// 错误信息，不会跳过（见 encryption_test.dart 的第一个测试）。
import 'dart:io';

import 'package:cardflow/data/db/database_errors.dart';
import 'package:cardflow/data/db/database_key.dart';
import 'package:cardflow/data/db/database_location.dart';
import 'package:flutter_test/flutter_test.dart';

export '../../support/sensitive_text.dart' show containsKeyMaterial;

/// 一把固定的测试密钥（64 个十六进制字符）。只用于测试。
const String testKeyHex =
    '00112233445566778899aabbccddeeff102132435465768798a9bacbdcedfe0f';

/// 另一把固定的测试密钥，用来制造"密钥错误"。
const String otherKeyHex =
    'f0e1d2c3b4a5968778695a4b3c2d1e0fffeeddccbbaa99887766554433221100';

/// 内存中的密钥存放处：记录读写次数，可以模拟钥匙串失败或写入后读回不一致。
class InMemoryDatabaseKeyStore implements DatabaseKeyStore {
  InMemoryDatabaseKeyStore({this.value});

  String? value;
  int reads = 0;
  int writes = 0;

  /// 为 true 时所有操作都抛出（模拟钥匙串不可用）。
  bool failAll = false;

  /// 为 true 时写入"成功"但不保存（模拟写入后读回不一致）。
  bool dropWrites = false;

  @override
  Future<String?> read() async {
    reads++;
    _maybeFail();
    return value;
  }

  @override
  Future<void> write(String newValue) async {
    writes++;
    _maybeFail();
    if (!dropWrites) {
      value = newValue;
    }
  }

  @override
  Future<bool> exists() async {
    _maybeFail();
    return value != null;
  }

  int deletes = 0;

  @override
  Future<void> delete() async {
    deletes++;
    _maybeFail();
    value = null;
  }

  void _maybeFail() {
    if (failAll) {
      throw StateError('keychain unavailable: secret detail');
    }
  }
}

/// 建一个临时目录作为数据库位置，测试结束时删除。
DatabaseLocation createTempLocation() {
  final directory = Directory.systemTemp.createTempSync('cardflow_db_test_');
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  // tempDirectory 为 null：不改 sqlite3 的全局临时目录（测试进程里会有多个临时目录）。
  return DatabaseLocation(directory: directory.path);
}

/// 数据库文件的完整路径。
String databasePathIn(DatabaseLocation location, String fileName) =>
    '${location.directory}${Platform.pathSeparator}$fileName';

/// 断言 [action] 以指定错误码失败。
Future<DatabaseOpenException> expectOpenError(
  Future<Object?> Function() action,
  DatabaseErrorCode code,
) async {
  try {
    await action();
  } on DatabaseOpenException catch (error) {
    expect(error.code, code, reason: '$error');
    return error;
  }
  fail('expected DatabaseOpenException(${code.code})');
}
