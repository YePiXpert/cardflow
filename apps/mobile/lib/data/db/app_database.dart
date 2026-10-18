import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'encryption.dart';
import 'schema.dart';

/// meta 表的内容。
@immutable
final class DatabaseMeta {
  const DatabaseMeta({required this.schemaVersion, required this.createdAt});

  final int schemaVersion;

  /// 建库时间（UTC）。
  final DateTime createdAt;
}

/// 卡序本地数据库（drift）。
///
/// 加密在连接层完成（`encryption.dart` 的 `applyEncryption` 作为 drift 的 `setup`），
/// 本类只负责 schema 与查询。请通过 `databaseProvider`（或测试里的 `openAppDatabase`）
/// 取得实例，不要直接构造：直接构造会绕过密钥与加密检查。
///
/// 目前没有 drift 代码生成：meta 表用 SQL 定义（schema.dart），查询用 `customSelect`。
/// I-1 起业务表改用 drift 的表 DSL，需要代码生成器 drift_dev（不在 architecture §11
/// 版本表内，引入前须评审登记）。
class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.executor, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  @override
  int get schemaVersion => LocalSchema.currentSchemaVersion;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      const <TableInfo<Table, Object?>>[];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => transaction(() => createSchema(this, createdAt: _clock())),
    onUpgrade: (m, from, to) => migrateSchema(this, from: from, to: to),
    beforeOpen: (details) => customStatement('PRAGMA foreign_keys = ON'),
  );

  /// 读 meta 表。
  Future<DatabaseMeta> readMeta() async {
    final row = await customSelect(
      'SELECT schema_version, created_at FROM meta WHERE id = 1',
    ).getSingle();
    return DatabaseMeta(
      schemaVersion: row.read<int>('schema_version'),
      createdAt: DateTime.parse(row.read<String>('created_at')).toUtc(),
    );
  }

  /// 读当前连接的加密库信息（与打开时的检查规则相同，见 `requireCipher`）。
  Future<CipherInfo> readCipherInfo() => readCipherInfoOf(this);
}

/// 在任意 drift 数据库上读加密库信息；不是加密构建时抛 `cipher_unavailable`。
///
/// 如果连接尚未打开，第一条查询会触发打开（含加密设置与迁移），打开失败的异常原样抛出。
Future<CipherInfo> readCipherInfoOf(GeneratedDatabase db) async {
  Future<String> firstValue(String sql) async {
    final rows = await db.customSelect(sql).get();
    if (rows.isEmpty || rows.first.data.isEmpty) {
      return '';
    }
    final value = rows.first.data.values.first;
    return value == null ? '' : '$value'.trim();
  }

  // 未知 PRAGMA 在普通 SQLite 上返回空而不报错，所以这两条的异常只可能来自打开失败。
  final cipher = await firstValue('PRAGMA cipher');
  final cipherVersion = await firstValue('PRAGMA cipher_version');
  String library;
  try {
    library = await firstValue('SELECT sqlite3mc_version()');
  } on Object {
    // 普通 SQLite 没有 sqlite3mc_version()：当作空，由下面的规则拒绝。
    library = '';
  }
  return cipherInfoFromValues(
    cipher: cipher,
    library: library,
    cipherVersionPragma: cipherVersion,
  );
}
