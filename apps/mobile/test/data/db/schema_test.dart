// 本地库 v4 的结构与迁移（真实 sqlite3mc + drift 后台 isolate）：
// 新建 vs 从 v1、v2、v3 升级的结构完全一致（v2、v3 的数据原样保留）、迁移失败整体回滚、重跑 1→4、
// 2→4、3→4 不报错、旧版 App 打开新库报 schema_too_new。
//
// 设了环境变量 CARDFLOW_SCHEMA_DUMP_DIR 时，第一个测试把四条路径的结构描述写进该目录
// （fresh-v4.txt、upgraded-from-v1.txt、upgraded-from-v2.txt、upgraded-from-v3.txt），供证据里用 diff 对比。
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

/// 旧版 App：schema 版本仍是 [version]，迁移逻辑与现在相同（from > to 时拒绝降级）。
class _OldAppDatabase extends AppDatabase {
  _OldAppDatabase(super.executor, this.version) : super.forTesting();

  final int version;

  @override
  int get schemaVersion => version;
}

/// v4 的全部表（v1 的 meta、v2 的 9 张、v3 的 8 张、v4 的 8 张）。
const List<String> _v4Tables = <String>[
  'app_settings',
  'banks',
  'billing_rule_versions',
  'cards',
  'cash_accounts',
  'cash_balance_snapshots',
  'cash_events',
  'credit_accounts',
  'credit_pools',
  'currency_accounts',
  'installment_plans',
  'installment_schedule',
  'limit_snapshots',
  'meta',
  'reconciliation_items',
  'recurring_items',
  'recurring_overrides',
  'repayment_allocations',
  'repayments',
  'scenario_runs',
  'scenarios',
  'snapshot_included_events',
  'statement_versions',
  'statements',
  'transactions',
  'workspaces',
];

/// I-1a 的 App 写下的 v2 数据（升级后必须原样保留）。
const String _ts = '2026-10-18T08:00:00+08:00';
const List<String> _v2Seed = <String>[
  "INSERT INTO workspaces (id, kind, name, created_at) VALUES ('w1', 'real', '我的数据', '$_ts')",
  "INSERT INTO app_settings (key, value) VALUES ('current_workspace_id', 'w1')",
  "INSERT INTO banks (id, workspace_id, name, created_at) VALUES ('b1', 'w1', '招商银行', '$_ts')",
  'INSERT INTO credit_accounts (id, workspace_id, bank_id, holder_alias, created_at, updated_at) '
      "VALUES ('a1', 'w1', 'b1', '本人', '$_ts', '$_ts')",
  'INSERT INTO currency_accounts (id, workspace_id, credit_account_id, currency, is_primary, created_at) '
      "VALUES ('c1', 'w1', 'a1', 'CNY', 1, '$_ts')",
  'INSERT INTO cards (id, workspace_id, credit_account_id, last4, holder_kind, status, created_at, updated_at) '
      "VALUES ('k1', 'w1', 'a1', '1234', 'primary', 'active', '$_ts', '$_ts')",
  'INSERT INTO limit_snapshots (id, workspace_id, currency_account_id, fixed_minor, used_minor, '
      'available_raw_minor, includes_holds, source_kind, balance_as_of, observed_at, recorded_at, '
      "confirmation_level) VALUES ('s1', 'w1', 'c1', 1000000, 1030000, -30000, 1, 'bank_app', "
      "'$_ts', '$_ts', '$_ts', 'user_confirmed')",
];

/// I-1b 的 App 写下的 v3 数据（现金账户、事件、快照与包含关系、情景；升级后必须原样保留）。
const List<String> _v3Seed = <String>[
  ..._v2Seed,
  'INSERT INTO cash_accounts (id, workspace_id, name, currency, kind, reserve_floor_minor, '
      "created_at, updated_at) VALUES ('ca1', 'w1', '工资卡', 'CNY', 'bank', 200000, '$_ts', '$_ts')",
  'INSERT INTO cash_events (id, workspace_id, cash_account_id, event_on, amount_minor, cls, '
      "category, label, created_at, updated_at) VALUES ('e1', 'w1', 'ca1', '2026-10-18', -3000, "
      "'confirmed', 'living', '早餐', '$_ts', '$_ts')",
  'INSERT INTO cash_balance_snapshots (id, workspace_id, cash_account_id, balance_minor, '
      'balance_as_of, observed_at, source_kind, confirmation_level, recorded_at) VALUES '
      "('cs1', 'w1', 'ca1', 500000, '2026-10-18', '$_ts', 'bank_app', 'user_confirmed', '$_ts')",
  'INSERT INTO snapshot_included_events (workspace_id, cash_account_id, snapshot_id, cash_event_id) '
      "VALUES ('w1', 'ca1', 'cs1', 'e1')",
  'INSERT INTO scenarios (id, workspace_id, name, kind, include_expected, created_at, updated_at) '
      "VALUES ('sc1', 'w1', '收入推迟', 'user_stress', 1, '$_ts', '$_ts')",
];

/// 升级前后逐行比较的旧表。
const List<String> _seededTables = <String>[
  'workspaces',
  'app_settings',
  'banks',
  'credit_accounts',
  'currency_accounts',
  'cards',
  'limit_snapshots',
  'cash_accounts',
  'cash_events',
  'cash_balance_snapshots',
  'snapshot_included_events',
  'scenarios',
];

/// 每张旧表的全部行（按 rowid）：升级前后逐行比较。
Future<Map<String, List<Map<String, Object?>>>> _rows(
  GeneratedDatabase db,
  Iterable<String> tables,
) async => <String, List<Map<String, Object?>>>{
  for (final table in tables)
    table: (await db.customSelect('SELECT * FROM $table ORDER BY rowid').get())
        .map((r) => r.data)
        .toList(),
};

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

  // 第一个测试同时打开四个不同文件的库（新建与三种升级），drift 的"同一个数据库类建了多次"警告
  // 针对的是共用同一执行器的情形，这里不适用。
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  test('新建的 v4 与 v1、v2、v3 升级上来的 v4：sqlite_master（表、列、索引、触发器）完全一致；'
      'v2、v3 的数据原样保留', () async {
    final fresh = await openTestDatabase(location, InMemoryDatabaseKeyStore());
    addTearDown(fresh.database.close);
    expect(fresh.created, isTrue);
    final freshDump = await schemaDump(fresh.database);

    final fromV1Location = createTempLocation();
    await createV1DatabaseFile(fromV1Location, testKeyHex);
    final fromV1 = await openTestDatabase(
      fromV1Location,
      InMemoryDatabaseKeyStore(value: testKeyHex),
    );
    addTearDown(fromV1.database.close);
    expect(fromV1.created, isFalse);
    final fromV1Dump = await schemaDump(fromV1.database);

    final fromV2Location = createTempLocation();
    await createV2DatabaseFile(fromV2Location, testKeyHex, seed: _v2Seed);
    final legacyV2 = LegacyV2Database(
      encryptedConnection(fromV2Location, testKeyHex),
    );
    final beforeV2 = await _rows(legacyV2, _seededTables.take(7));
    await legacyV2.close();
    expect(beforeV2['limit_snapshots'], hasLength(1));
    final fromV2 = await openTestDatabase(
      fromV2Location,
      InMemoryDatabaseKeyStore(value: testKeyHex),
    );
    addTearDown(fromV2.database.close);
    expect(fromV2.created, isFalse);
    final fromV2Dump = await schemaDump(fromV2.database);

    final fromV3Location = createTempLocation();
    await createV3DatabaseFile(fromV3Location, testKeyHex, seed: _v3Seed);
    final legacyV3 = LegacyV3Database(
      encryptedConnection(fromV3Location, testKeyHex),
    );
    final beforeV3 = await _rows(legacyV3, _seededTables);
    await legacyV3.close();
    expect(beforeV3['snapshot_included_events'], hasLength(1));
    final fromV3 = await openTestDatabase(
      fromV3Location,
      InMemoryDatabaseKeyStore(value: testKeyHex),
    );
    addTearDown(fromV3.database.close);
    expect(fromV3.created, isFalse);
    final fromV3Dump = await schemaDump(fromV3.database);

    final dumpDir = Platform.environment['CARDFLOW_SCHEMA_DUMP_DIR'];
    if (dumpDir != null && dumpDir.isNotEmpty) {
      Directory(dumpDir).createSync(recursive: true);
      File('$dumpDir/fresh-v4.txt').writeAsStringSync(freshDump);
      File('$dumpDir/upgraded-from-v1.txt').writeAsStringSync(fromV1Dump);
      File('$dumpDir/upgraded-from-v2.txt').writeAsStringSync(fromV2Dump);
      File('$dumpDir/upgraded-from-v3.txt').writeAsStringSync(fromV3Dump);
    }

    expect(fromV1Dump, freshDump);
    expect(fromV2Dump, freshDump);
    expect(fromV3Dump, freshDump);
    expect(
      await _rows(fromV2.database, _seededTables.take(7)),
      beforeV2,
      reason: 'v2 → v4 只做 expand',
    );
    expect(
      await _rows(fromV3.database, _seededTables),
      beforeV3,
      reason: 'v3 → v4 只做 expand',
    );
    expect(LocalSchema.currentSchemaVersion, 4);
    for (final db in <AppDatabase>[
      fresh.database,
      fromV1.database,
      fromV2.database,
      fromV3.database,
    ]) {
      expect(await _userVersion(db), 4);
      expect((await db.readMeta()).schemaVersion, 4);
      expect(await _names(db, 'table'), _v4Tables);
      expect(
        await _names(db, 'index'),
        hasLength(
          SchemaV2.indexes.length +
              SchemaV3.indexes.length +
              SchemaV4.indexes.length,
        ),
      );
      expect(
        await _names(db, 'trigger'),
        hasLength(
          SchemaV2.triggers.length +
              SchemaV3.triggers.length +
              SchemaV4.triggers.length,
        ),
      );
    }
    // drift 生成的建表语句与冻结的 SQL 一一对应（表的个数也相同）。
    expect(
      SchemaV2.tables.length + SchemaV3.tables.length + SchemaV4.tables.length,
      fresh.database.allTables.length,
    );
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

  test('迁移（2→3）在事务中：某一步失败时整体回滚，库仍是完整的 v2，数据不变', () async {
    await createV2DatabaseFile(location, testKeyHex, seed: _v2Seed);
    final legacy = LegacyV2Database(encryptedConnection(location, testKeyHex));
    addTearDown(legacy.close);
    final rowsBefore = await _rows(legacy, _seededTables.take(7));
    final tablesBefore = await _names(legacy, 'table');
    final triggersBefore = await _names(legacy, 'trigger');

    await expectOpenError(
      () => migrateSchema(
        legacy,
        from: 2,
        to: 3,
        steps: <int, SchemaMigrationStep>{
          2: (db) async {
            for (final statement in SchemaV3.migration) {
              await db.customStatement(statement);
            }
            await db.customStatement('THIS IS NOT SQL');
          },
        },
      ),
      DatabaseErrorCode.migrationFailed,
    );

    expect(await _names(legacy, 'table'), tablesBefore);
    expect(tablesBefore, isNot(contains('cash_events')));
    expect(await _names(legacy, 'trigger'), triggersBefore);
    expect(await _userVersion(legacy), 2);
    expect(await _rows(legacy, _seededTables.take(7)), rowsBefore);
  });

  test('迁移（3→4）在事务中：某一步失败时整体回滚，库仍是完整的 v3，数据不变', () async {
    await createV3DatabaseFile(location, testKeyHex, seed: _v3Seed);
    final legacy = LegacyV3Database(encryptedConnection(location, testKeyHex));
    addTearDown(legacy.close);
    final rowsBefore = await _rows(legacy, _seededTables);
    final tablesBefore = await _names(legacy, 'table');
    final indexesBefore = await _names(legacy, 'index');
    final triggersBefore = await _names(legacy, 'trigger');

    await expectOpenError(
      () => migrateSchema(
        legacy,
        from: 3,
        to: 4,
        steps: <int, SchemaMigrationStep>{
          3: (db) async {
            for (final statement in SchemaV4.migration) {
              await db.customStatement(statement);
            }
            await db.customStatement('THIS IS NOT SQL');
          },
        },
      ),
      DatabaseErrorCode.migrationFailed,
    );

    expect(await _names(legacy, 'table'), tablesBefore);
    expect(tablesBefore, isNot(contains('statement_versions')));
    expect(await _names(legacy, 'index'), indexesBefore);
    expect(await _names(legacy, 'trigger'), triggersBefore);
    expect(await _userVersion(legacy), 3);
    expect(await _rows(legacy, _seededTables), rowsBefore);
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

  for (final from in <int>[1, 2, 3]) {
    test(
      '重跑 $from→4 不报错：迁移已提交而 drift 还没写 user_version 时退出，下次启动结构与数据都不变',
      () async {
        final store = InMemoryDatabaseKeyStore(value: testKeyHex);
        await createV1DatabaseFile(location, testKeyHex);
        final first = await openTestDatabase(location, store);
        await first.database.customStatement(
          'INSERT INTO workspaces (id, kind, name, created_at) VALUES '
          "('00000000-0000-4000-8000-000000000001', 'real', '我的数据', "
          "'2026-10-18T08:00:00+08:00')",
        );
        await first.database.customStatement(
          'INSERT INTO cash_accounts (id, workspace_id, name, currency, kind, created_at, '
          "updated_at) VALUES ('ca1', '00000000-0000-4000-8000-000000000001', '工资卡', "
          "'CNY', 'bank', '2026-10-18T08:00:00+08:00', '2026-10-18T08:00:00+08:00')",
        );
        await first.database.customStatement(
          'INSERT INTO reconciliation_items (id, workspace_id, kind, refs, created_at, '
          "updated_at) VALUES ('r1', '00000000-0000-4000-8000-000000000001', "
          "'unmatched_repayment', '{\"transaction_id\":\"t1\"}', "
          "'2026-10-18T08:00:00+08:00', '2026-10-18T08:00:00+08:00')",
        );
        final before = await schemaDump(first.database);
        await first.database.close();

        _rawExecute(path, testKeyHex, <String>[
          'PRAGMA user_version = $from',
          'UPDATE meta SET schema_version = $from',
        ]);

        final again = await openTestDatabase(location, store);
        addTearDown(again.database.close);
        expect(await schemaDump(again.database), before);
        final workspaces = await again.database
            .customSelect('SELECT name FROM workspaces')
            .get();
        expect(workspaces.map((r) => r.read<String>('name')), <String>['我的数据']);
        final cash = await again.database
            .customSelect('SELECT name FROM cash_accounts')
            .get();
        expect(cash.map((r) => r.read<String>('name')), <String>['工资卡']);
        final items = await again.database
            .customSelect('SELECT kind FROM reconciliation_items')
            .get();
        expect(items.map((r) => r.read<String>('kind')), <String>[
          'unmatched_repayment',
        ]);
      },
    );
  }

  for (final oldVersion in <int>[1, 2, 3]) {
    test(
      '旧版 App（schema v$oldVersion）打开 v4 的库 → schema_too_new，库文件不被改动',
      () async {
        final created = await openTestDatabase(
          location,
          InMemoryDatabaseKeyStore(value: testKeyHex),
        );
        await created.database.close();
        final before = File(path).readAsBytesSync();

        final old = _OldAppDatabase(
          encryptedConnection(location, testKeyHex),
          oldVersion,
        );
        try {
          await old.customSelect('SELECT 1').get();
          fail('旧版 App 不应能打开 v4 的库');
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
        expect((await current.database.readMeta()).schemaVersion, 4);
      },
    );
  }

  test('缺少某一步 → migration_failed；from > to → schema_too_new（不做任何改动）', () async {
    await createV1DatabaseFile(location, testKeyHex);
    final legacy = LegacyV1Database(encryptedConnection(location, testKeyHex));
    addTearDown(legacy.close);
    await expectOpenError(
      () => migrateSchema(legacy, from: 1, to: 5),
      DatabaseErrorCode.migrationFailed,
    );
    await expectOpenError(
      () => migrateSchema(legacy, from: 5, to: 4),
      DatabaseErrorCode.schemaTooNew,
    );
    expect(await _names(legacy, 'table'), <String>['meta']);
    expect(await _userVersion(legacy), 1);
  });

  test('登记的迁移步骤：1→2、2→3、3→4；冻结的语句全部带 IF NOT EXISTS', () {
    expect(schemaMigrations.keys, <int>[1, 2, 3]);
    for (final statement in <String>[
      ...SchemaV2.migration,
      ...SchemaV3.migration,
      ...SchemaV4.migration,
    ]) {
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
