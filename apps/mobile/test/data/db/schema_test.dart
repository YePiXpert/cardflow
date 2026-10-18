// 本地库 v2 的结构与迁移（真实 sqlite3mc + drift 后台 isolate）：
// 新建 vs 从 v1 升级的结构完全一致、迁移失败整体回滚、重跑 1→2 不报错、旧版 App 打开新库报
// schema_too_new。
//
// 设了环境变量 CARDFLOW_SCHEMA_DUMP_DIR 时，第一个测试把两条路径的结构描述写进该目录
// （fresh-v2.txt、upgraded-from-v1.txt），供证据里用 diff 对比。
import 'dart:io';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/database_errors.dart';
import 'package:cardflow/data/db/database_failures.dart';
import 'package:cardflow/data/db/database_key.dart';
import 'package:cardflow/data/db/database_location.dart';
import 'package:cardflow/data/db/encryption.dart';
import 'package:cardflow/data/db/schema.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

import 'db_test_support.dart';

/// 旧版 App：schema 版本仍是 1，迁移逻辑与现在相同（from > to 时拒绝降级）。
class _OldAppDatabase extends AppDatabase {
  _OldAppDatabase(super.executor) : super.forTesting();

  @override
  int get schemaVersion => 1;
}

/// v2 的全部业务表（加上 v1 的 meta）。
const List<String> _v2Tables = <String>[
  'app_settings',
  'banks',
  'billing_rule_versions',
  'cards',
  'credit_accounts',
  'credit_pools',
  'currency_accounts',
  'limit_snapshots',
  'meta',
  'workspaces',
];

Future<List<String>> _names(GeneratedDatabase db, String type) async =>
    (await db
            .customSelect(
              'SELECT name FROM sqlite_master WHERE type = ? '
              "AND name NOT LIKE 'sqlite_%' ORDER BY name",
              variables: <Variable<Object>>[Variable<String>(type)],
            )
            .get())
        .map((r) => r.read<String>('name'))
        .toList();

Future<int> _userVersion(GeneratedDatabase db) async =>
    (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
      'user_version',
    );

/// 不经 drift，直接用 sqlite3 打开加密库执行语句（模拟"迁移已提交、版本号还没写"）。
void _rawExecute(String path, String keyHex, List<String> statements) {
  final raw = sqlite3.open(path);
  try {
    applyEncryption(raw, DatabaseKey.decode(keyHex).rawKeyLiteral());
    statements.forEach(raw.execute);
  } finally {
    raw.close();
  }
}

void main() {
  late DatabaseLocation location;
  late String path;

  setUp(() {
    location = createTempLocation();
    path = databasePathIn(location, appDatabaseFileName);
  });

  // 第一个测试同时打开两个不同文件的库（新建与升级），drift 的"同一个数据库类建了两次"警告
  // 针对的是共用同一执行器的情形，这里不适用。
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  test('新建的 v2 与 v1 升级上来的 v2：sqlite_master（表、列、索引、触发器）完全一致', () async {
    final fresh = await openTestDatabase(location, InMemoryDatabaseKeyStore());
    addTearDown(fresh.database.close);
    expect(fresh.created, isTrue);
    final freshDump = await schemaDump(fresh.database);

    final upgradeLocation = createTempLocation();
    await createV1DatabaseFile(upgradeLocation, testKeyHex);
    final upgraded = await openTestDatabase(
      upgradeLocation,
      InMemoryDatabaseKeyStore(value: testKeyHex),
    );
    addTearDown(upgraded.database.close);
    expect(upgraded.created, isFalse);
    final upgradedDump = await schemaDump(upgraded.database);

    final dumpDir = Platform.environment['CARDFLOW_SCHEMA_DUMP_DIR'];
    if (dumpDir != null && dumpDir.isNotEmpty) {
      Directory(dumpDir).createSync(recursive: true);
      File('$dumpDir/fresh-v2.txt').writeAsStringSync(freshDump);
      File('$dumpDir/upgraded-from-v1.txt').writeAsStringSync(upgradedDump);
    }

    expect(upgradedDump, freshDump);
    expect(LocalSchema.currentSchemaVersion, 2);
    for (final db in <AppDatabase>[fresh.database, upgraded.database]) {
      expect(await _userVersion(db), 2);
      expect((await db.readMeta()).schemaVersion, 2);
      expect(await _names(db, 'table'), _v2Tables);
      expect(await _names(db, 'index'), hasLength(SchemaV2.indexes.length));
      expect(await _names(db, 'trigger'), hasLength(SchemaV2.triggers.length));
    }
    // drift 生成的建表语句与冻结的 SQL 一一对应（表的个数也相同）。
    expect(SchemaV2.tables, hasLength(fresh.database.allTables.length));
  });

  test('迁移（1→2）在事务中：某一步失败时整体回滚，库仍是完整的 v1', () async {
    await createV1DatabaseFile(location, testKeyHex);
    final legacy = LegacyV1Database(encryptedConnection(location, testKeyHex));
    addTearDown(legacy.close);

    await expectOpenError(
      () => migrateSchema(
        legacy,
        from: 1,
        to: 2,
        steps: <int, SchemaMigrationStep>{
          1: (db) async {
            for (final statement in SchemaV2.migration) {
              await db.customStatement(statement);
            }
            await db.customStatement('THIS IS NOT SQL');
          },
        },
      ),
      DatabaseErrorCode.migrationFailed,
    );

    expect(await _names(legacy, 'table'), <String>['meta']);
    expect(await _names(legacy, 'index'), isEmpty);
    expect(await _names(legacy, 'trigger'), isEmpty);
    expect(await _userVersion(legacy), 1);
    final meta = await legacy
        .customSelect('SELECT schema_version FROM meta')
        .getSingle();
    expect(meta.read<int>('schema_version'), 1);
  });

  test('经 openAppDatabase 的迁移失败 → migration_failed，文件仍是 v1，可再次打开重试', () async {
    // v1 库里恰好有一张同名但结构不同的表：建表因 IF NOT EXISTS 被跳过，随后建索引失败。
    final legacy = LegacyV1Database(encryptedConnection(location, testKeyHex));
    await legacy.customSelect('SELECT 1').get();
    await legacy.customStatement('CREATE TABLE cards (x TEXT)');
    await legacy.close();

    final store = InMemoryDatabaseKeyStore(value: testKeyHex);
    await expectOpenError(
      () => openTestDatabase(location, store),
      DatabaseErrorCode.migrationFailed,
    );

    final reopened = LegacyV1Database(
      encryptedConnection(location, testKeyHex),
    );
    addTearDown(reopened.close);
    expect(await _userVersion(reopened), 1);
    expect(await _names(reopened, 'table'), <String>['cards', 'meta']);
    expect(await _names(reopened, 'trigger'), isEmpty);
  });

  test('重跑 1→2 不报错：迁移已提交而 drift 还没写 user_version 时退出，下次启动结构与数据都不变', () async {
    final store = InMemoryDatabaseKeyStore(value: testKeyHex);
    await createV1DatabaseFile(location, testKeyHex);
    final first = await openTestDatabase(location, store);
    await first.database.customStatement(
      'INSERT INTO workspaces (id, kind, name, created_at) VALUES '
      "('00000000-0000-4000-8000-000000000001', 'real', '我的数据', "
      "'2026-10-18T08:00:00+08:00')",
    );
    final before = await schemaDump(first.database);
    await first.database.close();

    _rawExecute(path, testKeyHex, <String>[
      'PRAGMA user_version = 1',
      'UPDATE meta SET schema_version = 1',
    ]);

    final again = await openTestDatabase(location, store);
    addTearDown(again.database.close);
    expect(await schemaDump(again.database), before);
    final workspaces = await again.database
        .customSelect('SELECT name FROM workspaces')
        .get();
    expect(workspaces.map((r) => r.read<String>('name')), <String>['我的数据']);
  });

  test('旧版 App（schema v1）打开 v2 的库 → schema_too_new，库文件不被改动', () async {
    final created = await openTestDatabase(
      location,
      InMemoryDatabaseKeyStore(value: testKeyHex),
    );
    await created.database.close();
    final before = File(path).readAsBytesSync();

    final old = _OldAppDatabase(encryptedConnection(location, testKeyHex));
    try {
      await old.customSelect('SELECT 1').get();
      fail('旧版 App 不应能打开 v2 的库');
    } on Object catch (error) {
      expect(
        databaseOpenExceptionFrom(error).code,
        DatabaseErrorCode.schemaTooNew,
      );
    } finally {
      await closeQuietly(old);
    }
    expect(listEquals(File(path).readAsBytesSync(), before), isTrue);

    // 现版本仍能正常打开。
    final current = await openTestDatabase(
      location,
      InMemoryDatabaseKeyStore(value: testKeyHex),
    );
    addTearDown(current.database.close);
    expect((await current.database.readMeta()).schemaVersion, 2);
  });

  test('缺少某一步 → migration_failed；from > to → schema_too_new（不做任何改动）', () async {
    await createV1DatabaseFile(location, testKeyHex);
    final legacy = LegacyV1Database(encryptedConnection(location, testKeyHex));
    addTearDown(legacy.close);
    await expectOpenError(
      () => migrateSchema(legacy, from: 1, to: 3),
      DatabaseErrorCode.migrationFailed,
    );
    await expectOpenError(
      () => migrateSchema(legacy, from: 3, to: 2),
      DatabaseErrorCode.schemaTooNew,
    );
    expect(await _names(legacy, 'table'), <String>['meta']);
    expect(await _userVersion(legacy), 1);
  });

  test('登记的迁移步骤：只有 1→2；冻结的语句全部带 IF NOT EXISTS', () {
    expect(schemaMigrations.keys, <int>[1]);
    for (final statement in SchemaV2.migration) {
      expect(
        statement,
        matches(
          RegExp(r'^\s*CREATE (UNIQUE )?(TABLE|INDEX|TRIGGER) IF NOT EXISTS '),
        ),
        reason: statement,
      );
    }
  });
}
