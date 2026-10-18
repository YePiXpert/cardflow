import 'package:drift/drift.dart';

import 'database_errors.dart';

/// 本地库 schema 的定义与迁移（drift 迁移策略的骨架）。
///
/// 约定（I-1 起加业务表时照此办理）：
/// 1. 把 [currentSchemaVersion] 加 1；
/// 2. 在 [schemaMigrations] 里登记"旧版本 → 旧版本 + 1"的一步（只做 expand：加表、加列、
///    建索引；不改写金额原值，data-model §7）；
/// 3. 新库走 [createSchema]：建出最新版本的完整结构；
/// 4. 测试：新建库与"上一版本的库升级上来"两条路径得到相同结构（见 test/data/db/）。
///
/// 迁移在一个事务里执行，任何一步失败都整体回滚，并以
/// [DatabaseErrorCode.migrationFailed] 拒绝打开。
///
/// 幂等（审查 §4 第 5 条）：drift 在迁移回调返回**之后**才写 `PRAGMA user_version`，若 App 恰好
/// 在两者之间退出，下次启动会重跑同一步。因此 [createSchema] 与 [migrateSchema] 在自己的事务里
/// 同时写 `user_version`（与结构变更一起提交或一起回滚），各迁移步骤里的建表、建索引、建触发器
/// 也一律写 `IF NOT EXISTS`，重跑不报错。
abstract final class LocalSchema {
  /// 当前 schema 版本（drift 的 `PRAGMA user_version` 与 meta 表同时记录）。
  static const int currentSchemaVersion = 1;

  /// v1：meta 表（单行）——schema 版本与建库时间（UTC，ISO-8601）。
  static const String createMetaTable = '''
CREATE TABLE meta (
  id INTEGER NOT NULL PRIMARY KEY CHECK (id = 1),
  schema_version INTEGER NOT NULL,
  created_at TEXT NOT NULL
) STRICT''';
}

/// 一步迁移：把库从版本 v 升到 v + 1。
typedef SchemaMigrationStep = Future<void> Function(GeneratedDatabase db);

/// 已登记的迁移步骤：键为旧版本 v，值把库从 v 升到 v + 1。v1 是第一个版本，暂无步骤。
const Map<int, SchemaMigrationStep> schemaMigrations =
    <int, SchemaMigrationStep>{};

/// 新库：在一个事务里建出最新版本的完整结构、写入 meta，并写 `PRAGMA user_version`。
Future<void> createSchema(
  GeneratedDatabase db, {
  required DateTime createdAt,
  int version = LocalSchema.currentSchemaVersion,
}) {
  return db.transaction(() async {
    await db.customStatement(LocalSchema.createMetaTable);
    await db.customStatement(
      'INSERT INTO meta (id, schema_version, created_at) VALUES (1, ?, ?)',
      <Object>[version, createdAt.toUtc().toIso8601String()],
    );
    await writeUserVersion(db, version);
  });
}

/// 写 `PRAGMA user_version`（drift 用它判断库的版本）。在事务里执行时随事务提交或回滚。
Future<void> writeUserVersion(GeneratedDatabase db, int version) {
  // PRAGMA 不能绑定参数；version 是 int，直接拼接没有注入问题。
  return db.customStatement('PRAGMA user_version = $version');
}

/// 旧库：按 [steps] 从 [from] 逐步升到 [to]，并在同一事务里更新 meta 与 `user_version`。
///
/// [from] 大于 [to]（库由更新版本的 App 创建）时抛 [DatabaseErrorCode.schemaTooNew]，
/// 不做任何改动；缺少某一步或某一步出错时抛 [DatabaseErrorCode.migrationFailed]。
Future<void> migrateSchema(
  GeneratedDatabase db, {
  required int from,
  required int to,
  Map<int, SchemaMigrationStep> steps = schemaMigrations,
}) async {
  if (from > to) {
    throw const DatabaseOpenException(DatabaseErrorCode.schemaTooNew);
  }
  for (var version = from; version < to; version++) {
    if (!steps.containsKey(version)) {
      throw const DatabaseOpenException(DatabaseErrorCode.migrationFailed);
    }
  }
  try {
    await db.transaction(() async {
      for (var version = from; version < to; version++) {
        await steps[version]!(db);
      }
      await db.customStatement(
        'UPDATE meta SET schema_version = ? WHERE id = 1',
        <Object>[to],
      );
      await writeUserVersion(db, to);
    });
  } on DatabaseOpenException {
    rethrow;
  } on Object {
    throw const DatabaseOpenException(DatabaseErrorCode.migrationFailed);
  }
}
