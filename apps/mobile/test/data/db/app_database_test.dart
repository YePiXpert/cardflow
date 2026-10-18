// 本机加密数据库的打开流程与 schema（真实 sqlite3mc + drift 后台 isolate）。
import 'dart:io';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/database_errors.dart';
import 'package:cardflow/data/db/database_key.dart';
import 'package:cardflow/data/db/database_location.dart';
import 'package:cardflow/data/db/database_opener.dart';
import 'package:cardflow/data/db/database_platform.dart';
import 'package:cardflow/data/db/encryption.dart';
import 'package:cardflow/data/db/schema.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
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

/// 以 v2 schema 打开（多一张表）的数据库，用来走一遍 drift 的升级路径。
class _AppDatabaseV2 extends AppDatabase {
  _AppDatabaseV2(super.executor);

  static final Map<int, SchemaMigrationStep> steps = <int, SchemaMigrationStep>{
    1: (db) => db.customStatement('CREATE TABLE extra (x INTEGER) STRICT'),
  };

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => fail('v2 测试库只用于升级已有的 v1 库，不应走 onCreate'),
    onUpgrade: (m, from, to) =>
        migrateSchema(this, from: from, to: to, steps: steps),
  );
}

QueryExecutor _connect(DatabaseLocation location, String keyHex) =>
    connectEncryptedDatabase(
      name: 'cardflow_test',
      path: databasePathIn(location, appDatabaseFileName),
      tempDirectory: null,
      rawKeyLiteral: DatabaseKey.decode(keyHex).rawKeyLiteral(),
    );

Future<bool> _tableExists(GeneratedDatabase db, String name) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        variables: <Variable<Object>>[Variable<String>(name)],
      )
      .get();
  return rows.isNotEmpty;
}

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

  group('迁移骨架', () {
    test('drift 升级路径：v1 库用 v2 打开时按步骤升级，meta 记录新版本', () async {
      final store = InMemoryDatabaseKeyStore();
      await (await _open(location, store)).database.close();

      final v2 = _AppDatabaseV2(_connect(location, store.value!));
      expect((await v2.readMeta()).schemaVersion, 2);
      expect(await _tableExists(v2, 'extra'), isTrue);
      await v2.close();

      // 再用 v1 的 App 打开 v2 的库：拒绝降级。
      await expectOpenError(
        () => _open(location, store),
        DatabaseErrorCode.schemaTooNew,
      );
    });

    test('缺少某一步 → migration_failed，不做任何改动', () async {
      final opened = await _open(location, InMemoryDatabaseKeyStore());
      addTearDown(opened.database.close);
      await expectOpenError(
        () => migrateSchema(
          opened.database,
          from: 1,
          to: 3,
          steps: _AppDatabaseV2.steps,
        ),
        DatabaseErrorCode.migrationFailed,
      );
      expect((await opened.database.readMeta()).schemaVersion, 1);
      expect(await _tableExists(opened.database, 'extra'), isFalse);
    });

    test('某一步出错 → migration_failed，整个迁移回滚', () async {
      final opened = await _open(location, InMemoryDatabaseKeyStore());
      addTearDown(opened.database.close);
      await expectOpenError(
        () => migrateSchema(
          opened.database,
          from: 1,
          to: 3,
          steps: <int, SchemaMigrationStep>{
            1: (db) => db.customStatement('CREATE TABLE extra (x INTEGER)'),
            2: (db) => db.customStatement('THIS IS NOT SQL'),
          },
        ),
        DatabaseErrorCode.migrationFailed,
      );
      expect((await opened.database.readMeta()).schemaVersion, 1);
      expect(await _tableExists(opened.database, 'extra'), isFalse);
    });

    test('from > to（库来自更新的 App）→ schema_too_new', () async {
      final opened = await _open(location, InMemoryDatabaseKeyStore());
      addTearDown(opened.database.close);
      await expectOpenError(
        () => migrateSchema(opened.database, from: 2, to: 1),
        DatabaseErrorCode.schemaTooNew,
      );
    });

    test('v1 没有登记任何迁移步骤；当前版本为 1', () {
      expect(LocalSchema.currentSchemaVersion, 1);
      expect(schemaMigrations, isEmpty);
    });
  });
}
