// 本机加密数据库测试的公共辅助。
//
// 这些测试使用真实的 SQLite3MultipleCiphers：flutter test 会运行 sqlite3 包的构建钩子
// （pubspec.yaml 的 hooks.user_defines.sqlite3.source: sqlite3mc），钩子从 sqlite3.dart 的
// GitHub release 下载预编译库并校验 sha256。没有网络或钩子失败时测试会失败并给出钩子的
// 错误信息，不会跳过（见 encryption_test.dart 的第一个测试）。
import 'dart:io';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/database_errors.dart';
import 'package:cardflow/data/db/database_key.dart';
import 'package:cardflow/data/db/database_location.dart';
import 'package:cardflow/data/db/database_platform.dart';
import 'package:cardflow/data/db/schema.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
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

/// 固定的建库时间（测试用）。
final DateTime testCreatedAt = DateTime.utc(2026, 10, 18, 6, 30);

/// 用 [store] 里的密钥（没有则生成）在 [location] 打开（必要时新建）本机加密数据库。
Future<OpenedAppDatabase> openTestDatabase(
  DatabaseLocation location,
  InMemoryDatabaseKeyStore store, {
  String fileName = appDatabaseFileName,
}) => openAppDatabase(
  keys: DatabaseKeyManager(store),
  location: location,
  fileName: fileName,
  clock: () => testCreatedAt,
);

/// I-0b（schema v1）的 App 建出的库：只有 meta 表，`user_version = 1`。
class LegacyV1Database extends GeneratedDatabase {
  LegacyV1Database(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      const <TableInfo<Table, Object?>>[];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await customStatement(LocalSchema.createMetaTable);
      await customStatement(
        'INSERT INTO meta (id, schema_version, created_at) VALUES (1, 1, ?)',
        <Object>[testCreatedAt.toIso8601String()],
      );
    },
  );
}

/// 在 [location] 用密钥 [keyHex] 建一个 v1 的加密库文件并关闭（模拟 I-0b 版本 App 留下的库）。
Future<void> createV1DatabaseFile(
  DatabaseLocation location,
  String keyHex, {
  String fileName = appDatabaseFileName,
}) async {
  final legacy = LegacyV1Database(
    encryptedConnection(location, keyHex, fileName: fileName),
  );
  await legacy.customSelect('SELECT 1').get();
  await legacy.close();
}

/// I-1a（schema v2）的 App 建出的库：meta + 冻结的 v2 结构（`SchemaV2`，与当时 drift 生成的一字不差），
/// `user_version = 2`。[seed] 在建好结构后写入 v2 的数据（升级后应原样保留）。
class LegacyV2Database extends GeneratedDatabase {
  LegacyV2Database(super.executor, {this.seed = const <String>[]});

  final List<String> seed;

  @override
  int get schemaVersion => 2;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      const <TableInfo<Table, Object?>>[];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await customStatement(LocalSchema.createMetaTable);
      await customStatement(
        'INSERT INTO meta (id, schema_version, created_at) VALUES (1, 2, ?)',
        <Object>[testCreatedAt.toIso8601String()],
      );
      for (final statement in <String>[...SchemaV2.migration, ...seed]) {
        await customStatement(statement);
      }
    },
  );
}

/// 在 [location] 用密钥 [keyHex] 建一个 v2 的加密库文件并关闭（模拟 I-1a 版本 App 留下的库）。
Future<void> createV2DatabaseFile(
  DatabaseLocation location,
  String keyHex, {
  String fileName = appDatabaseFileName,
  List<String> seed = const <String>[],
}) async {
  final legacy = LegacyV2Database(
    encryptedConnection(location, keyHex, fileName: fileName),
    seed: seed,
  );
  await legacy.customSelect('SELECT 1').get();
  await legacy.close();
}

/// I-1b（schema v3）的 App 建出的库：meta + 冻结的 v2、v3 结构（`SchemaV2`、`SchemaV3`），
/// `user_version = 3`。[seed] 在建好结构后写入 v3 的数据（升级后应原样保留）。
class LegacyV3Database extends GeneratedDatabase {
  LegacyV3Database(super.executor, {this.seed = const <String>[]});

  final List<String> seed;

  @override
  int get schemaVersion => 3;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      const <TableInfo<Table, Object?>>[];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await customStatement(LocalSchema.createMetaTable);
      await customStatement(
        'INSERT INTO meta (id, schema_version, created_at) VALUES (1, 3, ?)',
        <Object>[testCreatedAt.toIso8601String()],
      );
      for (final statement in <String>[
        ...SchemaV2.migration,
        ...SchemaV3.migration,
        ...seed,
      ]) {
        await customStatement(statement);
      }
    },
  );
}

/// 在 [location] 用密钥 [keyHex] 建一个 v3 的加密库文件并关闭（模拟 I-1b 版本 App 留下的库）。
Future<void> createV3DatabaseFile(
  DatabaseLocation location,
  String keyHex, {
  String fileName = appDatabaseFileName,
  List<String> seed = const <String>[],
}) async {
  final legacy = LegacyV3Database(
    encryptedConnection(location, keyHex, fileName: fileName),
    seed: seed,
  );
  await legacy.customSelect('SELECT 1').get();
  await legacy.close();
}

/// 直接建一个加密连接（不经 openAppDatabase 的检查与迁移），供测试用各种 schema 版本打开。
QueryExecutor encryptedConnection(
  DatabaseLocation location,
  String keyHex, {
  String fileName = appDatabaseFileName,
}) => connectEncryptedDatabase(
  name: 'cardflow_test',
  path: databasePathIn(location, fileName),
  tempDirectory: null,
  rawKeyLiteral: DatabaseKey.decode(keyHex).rawKeyLiteral(),
);

/// 数据库结构的完整文本描述：`PRAGMA user_version`、sqlite_master 的每一行（类型、名称、所属表、
/// SQL 原文），以及每张表的列（`table_xinfo`）、外键（`foreign_key_list`）、索引
/// （`index_list` + `index_xinfo`）。用于比较"新建"与"升级"两条路径。
Future<String> schemaDump(GeneratedDatabase db) async {
  final buffer = StringBuffer();
  Future<List<Map<String, Object?>>> rows(String sql) async =>
      (await db.customSelect(sql).get()).map((r) => r.data).toList();
  String line(Map<String, Object?> row) =>
      row.entries.map((e) => '${e.key}=${e.value}').join(' | ');

  final version = await rows('PRAGMA user_version');
  buffer.writeln('-- user_version: ${version.single.values.single}');
  final master = await rows(
    'SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY type, name',
  );
  for (final row in master) {
    buffer
      ..writeln('-- ${row['type']} ${row['name']} (table ${row['tbl_name']})')
      ..writeln(row['sql'] ?? '(no sql: internal)');
  }
  final tables = master
      .where((r) => r['type'] == 'table')
      .map((r) => r['name']! as String)
      .toList();
  for (final table in tables) {
    buffer.writeln('-- columns of $table');
    for (final column in await rows("PRAGMA table_xinfo('$table')")) {
      buffer.writeln(line(column));
    }
    buffer.writeln('-- foreign keys of $table');
    for (final fk in await rows("PRAGMA foreign_key_list('$table')")) {
      buffer.writeln(line(fk));
    }
    buffer.writeln('-- indexes of $table');
    for (final index in await rows("PRAGMA index_list('$table')")) {
      buffer.writeln(line(index));
      for (final column in await rows(
        "PRAGMA index_xinfo('${index['name']}')",
      )) {
        buffer.writeln('    ${line(column)}');
      }
    }
  }
  return buffer.toString();
}
