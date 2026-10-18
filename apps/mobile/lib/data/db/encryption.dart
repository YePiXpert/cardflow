import 'package:flutter/foundation.dart';
import 'package:sqlite3/common.dart';

import 'database_errors.dart';

/// 固定使用的加密算法：sqlite3mc 的 ChaCha20-Poly1305（`chacha20`，也是它的默认算法）。
/// 显式写死，避免将来库的默认算法变化后已有的库打不开。
const String pinnedCipher = 'chacha20';

/// SQLite 主结果码 SQLITE_NOTADB：密钥错误（或文件损坏）时第一次读库返回它。
const int sqliteNotADatabase = 26;

/// 明文 SQLite 数据库文件的前 16 字节（"SQLite format 3\0"）。
const List<int> plaintextSqliteHeader = <int>[
  0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66, //
  0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00,
];

/// 执行一条语句，返回第一行第一列的文本（没有结果时为空串）；语句出错时抛
/// [SqliteException]。把检查逻辑与真实连接解耦，便于测试"不是加密构建"的分支。
typedef FirstValueQuery = String Function(String sql);

/// 加密库的识别信息（诊断页显示）。不含任何密钥材料。
@immutable
final class CipherInfo {
  const CipherInfo({
    required this.library,
    required this.cipher,
    required this.cipherVersionPragma,
  });

  /// `SELECT sqlite3mc_version()`，如 `SQLite3 Multiple Ciphers 2.6.1`。
  final String library;

  /// `PRAGMA cipher`：当前连接的加密算法，如 `chacha20`。
  final String cipher;

  /// `PRAGMA cipher_version` 的原始结果。这是 SQLCipher 的 PRAGMA，sqlite3mc 不实现，
  /// 实测为空串；保留下来只为在诊断报告里如实显示。
  final String cipherVersionPragma;

  @override
  bool operator ==(Object other) =>
      other is CipherInfo &&
      other.library == library &&
      other.cipher == cipher &&
      other.cipherVersionPragma == cipherVersionPragma;

  @override
  int get hashCode => Object.hash(library, cipher, cipherVersionPragma);

  @override
  String toString() => 'CipherInfo($library, $cipher)';
}

/// 读取加密库信息；加载的不是加密构建时抛 [DatabaseErrorCode.cipherUnavailable]。
///
/// 规划文档写的是"`PRAGMA cipher_version` 为空即拒绝"，但这是 SQLCipher 的 PRAGMA，
/// SQLite3MultipleCiphers 2.6.1 对它总是返回空（见 test/data/db/encryption_test.dart 与
/// evidence/i0/I0-b/）。这里改用 sqlite3mc 自己的两项检查，且两项都必须非空：
/// - `PRAGMA cipher`（drift 文档 Encryption 页推荐的运行时检查）；
/// - `SELECT sqlite3mc_version()`（普通 SQLite 没有这个函数）。
/// 普通 SQLite 对未知 PRAGMA 返回空、对未知函数报错，所以检查失败即止。
///
/// 注意 `SELECT sqlite3mc_version()` 需要读 schema：对已加密的库，必须在设置密钥之后
/// 调用（打开流程见 [applyEncryptionWith]）。
CipherInfo requireCipher(FirstValueQuery query) => cipherInfoFromValues(
  cipher: _valueOrEmpty(query, 'PRAGMA cipher'),
  library: _valueOrEmpty(query, 'SELECT sqlite3mc_version()'),
  cipherVersionPragma: _valueOrEmpty(query, 'PRAGMA cipher_version'),
);

/// 由三项查询结果得出 [CipherInfo]；`PRAGMA cipher` 或 `sqlite3mc_version()` 为空时抛
/// [DatabaseErrorCode.cipherUnavailable]（判定规则见 [requireCipher]）。
CipherInfo cipherInfoFromValues({
  required String cipher,
  required String library,
  required String cipherVersionPragma,
}) {
  if (cipher.isEmpty || library.isEmpty) {
    throw const DatabaseOpenException(DatabaseErrorCode.cipherUnavailable);
  }
  return CipherInfo(
    library: library,
    cipher: cipher,
    cipherVersionPragma: cipherVersionPragma,
  );
}

/// 打开加密库的连接设置（drift `NativeDatabase` 的 `setup`，在读写数据库之前运行）。
///
/// 顺序（任何一步失败都抛只含错误码的 [DatabaseOpenException]，drift 随即关闭连接，
/// 不会以明文方式继续使用）：
/// 1. `PRAGMA cipher` 非空——只有加密构建认识它；它由 sqlite3mc 的 VFS 处理、不读库，
///    所以能在设置密钥之前执行。普通 SQLite 在这里就被拒绝，`PRAGMA key` 根本不会执行；
/// 2. 固定算法 [pinnedCipher]；
/// 3. 设置原始密钥（结果必须是 `ok`）；
/// 4. 读一次 `sqlite_master` 验证密钥：SQLITE_NOTADB → `wrong_key`；
/// 5. `sqlite3mc_version()` 非空（这条 SELECT 要读 schema，所以放在验证密钥之后；
///    此时仍未写入任何数据）。
///
/// [rawKeyLiteral] 来自 `DatabaseKey.rawKeyLiteral()`。底层异常一律不向外传：
/// `SqliteException.toString()` 会带上出错的语句，而设置密钥的语句里就有密钥。
CipherInfo applyEncryptionWith(FirstValueQuery query, String rawKeyLiteral) {
  if (_valueOrEmpty(query, 'PRAGMA cipher').isEmpty) {
    throw const DatabaseOpenException(DatabaseErrorCode.cipherUnavailable);
  }

  final pinned = _valueOrEmpty(query, "PRAGMA cipher = '$pinnedCipher'");
  if (pinned != pinnedCipher) {
    throw const DatabaseOpenException(DatabaseErrorCode.cipherUnavailable);
  }

  String keyResult;
  try {
    keyResult = query('PRAGMA key = "$rawKeyLiteral"');
  } on Object {
    throw const DatabaseOpenException(DatabaseErrorCode.keyApplyFailed);
  }
  if (keyResult != 'ok') {
    throw const DatabaseOpenException(DatabaseErrorCode.keyApplyFailed);
  }

  try {
    query('SELECT count(*) FROM sqlite_master');
  } on SqliteException catch (e) {
    throw DatabaseOpenException(
      e.resultCode == sqliteNotADatabase
          ? DatabaseErrorCode.wrongKey
          : DatabaseErrorCode.openFailed,
      sqliteResultCode: e.extendedResultCode,
    );
  } on Object {
    throw const DatabaseOpenException(DatabaseErrorCode.openFailed);
  }

  return requireCipher(query);
}

/// [applyEncryptionWith] 作用于真实的 sqlite3 连接。
CipherInfo applyEncryption(CommonDatabase db, String rawKeyLiteral) =>
    applyEncryptionWith(firstValueQueryOf(db), rawKeyLiteral);

/// drift 连接的 `setup` 函数。它会被发送到 drift 的后台 isolate，所以只捕获密钥文本，
/// 不捕获任何其他对象。
void Function(CommonDatabase db) encryptionSetup(String rawKeyLiteral) =>
    (db) => applyEncryption(db, rawKeyLiteral);

/// 真实连接上的 [FirstValueQuery]。
FirstValueQuery firstValueQueryOf(CommonDatabase db) =>
    (sql) => firstValueOf(db.select(sql));

/// 结果集第一行第一列的文本；没有结果时为空串。
String firstValueOf(ResultSet result) {
  if (result.rows.isEmpty || result.rows.first.isEmpty) {
    return '';
  }
  final value = result.rows.first.first;
  return value == null ? '' : '$value'.trim();
}

/// 文件开头是否为明文 SQLite 文件头。sqlite3mc 加密后，文件开头是随机盐值。
bool isPlaintextSqliteHeader(List<int> firstBytes) {
  if (firstBytes.length < plaintextSqliteHeader.length) {
    return false;
  }
  for (var i = 0; i < plaintextSqliteHeader.length; i++) {
    if (firstBytes[i] != plaintextSqliteHeader[i]) {
      return false;
    }
  }
  return true;
}

/// 查询出错（普通 SQLite 上 `sqlite3mc_version()` 报 no such function）时当作空。
String _valueOrEmpty(FirstValueQuery query, String sql) {
  try {
    return query(sql);
  } on SqliteException {
    return '';
  }
}
