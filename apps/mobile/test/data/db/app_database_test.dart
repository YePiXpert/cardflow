// 本机加密数据库的打开流程与 schema（真实 sqlite3mc + drift 后台 isolate）。
import 'dart:io';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/database_errors.dart';
import 'package:cardflow/data/db/database_key.dart';
import 'package:cardflow/data/db/database_location.dart';
import 'package:cardflow/data/db/database_platform.dart';
import 'package:cardflow/data/db/encryption.dart';
import 'package:cardflow/data/db/schema.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

import 'db_test_support.dart';

final DateTime _createdAt = DateTime.utc(2026, 10, 18, 6, 30);

/// 打开测试库（固定建库时间）。
Future<OpenedAppDatabase> _open(
  DatabaseLocation location,
  InMemoryDatabaseKeyStore store,
) => openAppDatabase(
  keys: DatabaseKeyManager(store),
  location: location,
  clock: () => _createdAt,
);

void main() {
  late DatabaseLocation location;
  late String path;

  setUp(() {
    location = createTempLocation();
    path = databasePathIn(location, appDatabaseFileName);
  });

  test('开关往返：首次新建（生成并保存密钥、建 meta 表），关闭后重开读到同样的内容', () async {
    final store = InMemoryDatabaseKeyStore();

    final first = await _open(location, store);
    expect(first.created, isTrue);
    expect(first.cipher.library, startsWith('SQLite3 Multiple Ciphers '));
    expect(first.cipher.cipher, pinnedCipher);
    expect(first.openDuration, greaterThan(Duration.zero));
    final meta = await first.database.readMeta();
    expect(meta.schemaVersion, LocalSchema.currentSchemaVersion);
    expect(meta.createdAt, _createdAt);
    await first.database.close();
    expect(store.writes, 1);

    final second = await _open(location, store);
    addTearDown(second.database.close);
    expect(second.created, isFalse);
    final again = await second.database.readMeta();
    expect(again.schemaVersion, meta.schemaVersion);
    expect(again.createdAt, meta.createdAt);
    expect(await second.database.readCipherInfo(), second.cipher);
    expect(store.writes, 1, reason: '密钥只在首次启动生成一次');
  });

  test('库文件是密文：文件头不是明文 SQLite 头，写入的文字在文件里找不到', () async {
    final store = InMemoryDatabaseKeyStore();
    final opened = await _open(location, store);
    await opened.database.customStatement(
      'CREATE TABLE probe (x TEXT NOT NULL) STRICT',
    );
    await opened.database.customStatement(
      "INSERT INTO probe (x) VALUES ('plaintext-marker-卡序-8000.00')",
    );
    await opened.database.close();

    final bytes = File(path).readAsBytesSync();
    expect(bytes.length, greaterThanOrEqualTo(4096));
    expect(isPlaintextSqliteHeader(bytes), isFalse);
    expect(databaseFileLooksPlaintext(path), isFalse);
    expect(String.fromCharCodes(bytes).contains('plaintext-marker'), isFalse);
    expect(String.fromCharCodes(bytes).contains('8000.00'), isFalse);
  });

  test('密钥错误 → wrong_key（SQLite 26），文件不被改动', () async {
    final store = InMemoryDatabaseKeyStore();
    await (await _open(location, store)).database.close();
    final before = File(path).readAsBytesSync();

    store.value = otherKeyHex;
    final error = await expectOpenError(
      () => _open(location, store),
      DatabaseErrorCode.wrongKey,
    );
    expect(error.sqliteResultCode, sqliteNotADatabase);
    expect(listEquals(File(path).readAsBytesSync(), before), isTrue);
  });

  test('数据库已有数据而钥匙串没有密钥 → key_missing：不新建密钥，不覆盖旧库', () async {
    await (await _open(location, InMemoryDatabaseKeyStore())).database.close();
    final before = File(path).readAsBytesSync();

    final emptyStore = InMemoryDatabaseKeyStore();
    await expectOpenError(
      () => _open(location, emptyStore),
      DatabaseErrorCode.keyMissing,
    );
    expect(emptyStore.writes, 0);
    expect(emptyStore.value, isNull);
    expect(listEquals(File(path).readAsBytesSync(), before), isTrue);
  });

  test('已有的明文 SQLite 文件 → 拒绝打开（wrong_key），文件保持原样', () async {
    sqlite3.open(path)
      ..execute('CREATE TABLE t(x)')
      ..close();
    expect(databaseFileLooksPlaintext(path), isTrue);
    final before = File(path).readAsBytesSync();

    await expectOpenError(
      () => _open(location, InMemoryDatabaseKeyStore(value: testKeyHex)),
      DatabaseErrorCode.wrongKey,
    );
    expect(listEquals(File(path).readAsBytesSync(), before), isTrue);
  });

  test('空文件不算已有数据：照常首次新建', () async {
    File(path).createSync();
    final store = InMemoryDatabaseKeyStore();
    final opened = await _open(location, store);
    addTearDown(opened.database.close);
    expect(opened.created, isTrue);
    expect(store.writes, 1);
  });

  test('钥匙串不可用 → key_store_failed，不建库', () async {
    final store = InMemoryDatabaseKeyStore()..failAll = true;
    await expectOpenError(
      () => _open(location, store),
      DatabaseErrorCode.keyStoreFailed,
    );
    expect(File(path).existsSync(), isFalse);
  });

  group('外键检查（审查 §4 第 6 条）', () {
    test('打开后 PRAGMA foreign_keys 为 1', () async {
      final opened = await _open(location, InMemoryDatabaseKeyStore());
      addTearDown(opened.database.close);
      final row = await opened.database
          .customSelect('PRAGMA foreign_keys')
          .getSingle();
      expect(row.data.values.single, 1);
    });

    test(
      '读回不是 1 → foreign_keys_unavailable（事务里设置 foreign_keys 不生效，正好用来制造）',
      () async {
        final opened = await _open(location, InMemoryDatabaseKeyStore());
        addTearDown(opened.database.close);
        final db = opened.database;
        await db.customStatement('PRAGMA foreign_keys = OFF');
        await expectOpenError(
          () => db.transaction(() => ensureForeignKeys(db)),
          DatabaseErrorCode.foreignKeysUnavailable,
        );
        await ensureForeignKeys(db);
      },
    );
  });
}
