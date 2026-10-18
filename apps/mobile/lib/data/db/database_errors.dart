import 'package:flutter/foundation.dart';

/// 加密本地库打开失败的错误码（ADR-001 / PoC-1："失败即止"，绝不退回明文库）。
///
/// [code] 只含小写字母与下划线，可以直接写进诊断日志与诊断页。
enum DatabaseErrorCode {
  /// 加载的 SQLite 不是加密构建（sqlite3mc 的 `PRAGMA cipher` 或
  /// `sqlite3mc_version()` 为空）。
  cipherUnavailable('cipher_unavailable'),

  /// 打开后检查数据库文件，发现是明文 SQLite 文件头。
  plaintextDatabase('plaintext_database'),

  /// 数据库文件已存在，但钥匙串里没有密钥（不会新建密钥覆盖旧库）。
  keyMissing('key_missing'),

  /// 钥匙串里的密钥格式不对（不是 32 字节）。
  keyInvalid('key_invalid'),

  /// 读写钥匙串失败，或新生成的密钥写入后读回不一致。
  keyStoreFailed('key_store_failed'),

  /// 设置密钥的语句执行失败。
  keyApplyFailed('key_apply_failed'),

  /// 密钥打不开该数据库（SQLITE_NOTADB）：密钥错误或文件损坏。
  wrongKey('wrong_key'),

  /// 数据库由更新版本的 App 创建（schema 版本高于本版本），拒绝降级打开。
  schemaTooNew('schema_too_new'),

  /// schema 迁移失败（缺少某一步，或迁移语句出错）；迁移在事务里，失败不会留下半截。
  migrationFailed('migration_failed'),

  /// 打开后 `PRAGMA foreign_keys` 读回不是 1：外键检查没有生效。业务表的工作空间隔离与
  /// 关联一致性依赖外键，因此拒绝使用（审查 §4 第 6 条）。
  foreignKeysUnavailable('foreign_keys_unavailable'),

  /// "重置本地数据"时删不掉数据库文件（钥匙串条目删不掉报 `key_store_failed`）。
  resetFailed('reset_failed'),

  /// 取不到数据库目录（path_provider 失败）。
  locationUnavailable('location_unavailable'),

  /// 其他 SQLite 打开错误。
  openFailed('open_failed'),

  /// 当前平台没有加密本地库（Web 只用于编译检查）。
  unsupportedPlatform('unsupported_platform');

  const DatabaseErrorCode(this.code);

  /// 诊断日志与诊断页使用的错误码。
  final String code;
}

/// 打开加密本地库失败。
///
/// 消息里只有错误码与 SQLite 结果码：不含密钥、路径、SQL 语句与底层异常正文
/// （底层 `SqliteException` 会带上出错的语句，设置密钥的语句里就有密钥）。
@immutable
final class DatabaseOpenException implements Exception {
  const DatabaseOpenException(this.code, {this.sqliteResultCode});

  final DatabaseErrorCode code;

  /// SQLite 的扩展结果码（如 26 = SQLITE_NOTADB），没有时为 null。
  final int? sqliteResultCode;

  @override
  String toString() {
    final sqlite = sqliteResultCode;
    return sqlite == null
        ? 'DatabaseOpenException(${code.code})'
        : 'DatabaseOpenException(${code.code}, sqlite $sqlite)';
  }

  @override
  bool operator ==(Object other) =>
      other is DatabaseOpenException &&
      other.code == code &&
      other.sqliteResultCode == sqliteResultCode;

  @override
  int get hashCode => Object.hash(code, sqliteResultCode);
}
