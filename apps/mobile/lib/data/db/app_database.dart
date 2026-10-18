import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'database_errors.dart';
import 'database_failures.dart';
import 'database_key.dart';
import 'database_location.dart';
import 'database_platform.dart';
import 'encryption.dart';
import 'schema.dart';
import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

/// 本机数据库文件名。
const String appDatabaseFileName = 'cardflow.sqlite';

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
/// 本类只负责 schema 与查询。业务表用 drift 表 DSL 定义（`tables.dart`），代码生成产物
/// `app_database.g.dart` 随源码提交；索引、触发器与迁移步骤在 `schema.dart`。
///
/// **只能经 [openAppDatabase] 取得实例**（App 代码里通常是 `databaseProvider`）：构造函数是
/// 私有的，[openAppDatabase] 在同一个库里，先取密钥、建加密连接，再做全部检查。这样仓库代码
/// 无法拿一个未加密的执行器直接 new 出数据库而绕过检查（审查 §4 第 9 条）。测试用
/// [AppDatabase.forTesting]（`@visibleForTesting`，在 lib/ 里使用会被静态分析拦下）。
@DriftDatabase(
  tables: <Type>[
    Workspaces,
    AppSettings,
    Banks,
    CreditPools,
    CreditAccounts,
    CurrencyAccounts,
    Cards,
    BillingRuleVersions,
    LimitSnapshots,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase._(super.executor, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// 测试入口：在任意执行器上构造（例如组件测试里的 `NativeDatabase.memory()`），
  /// 不经过密钥与加密检查。只允许测试使用。
  @visibleForTesting
  AppDatabase.forTesting(super.executor, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  @override
  int get schemaVersion => LocalSchema.currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => createSchema(this, m, createdAt: _clock()),
    onUpgrade: (m, from, to) => migrateSchema(this, from: from, to: to),
    beforeOpen: (details) => ensureForeignKeys(this),
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

/// 打开外键检查并读回确认；读回不是 1 时抛 [DatabaseErrorCode.foreignKeysUnavailable]
/// （失败即止，审查 §4 第 6 条）。
///
/// `PRAGMA foreign_keys` 在事务里执行不生效（SQLite 文档："This pragma is a no-op within a
/// transaction"），所以它放在 drift 的 `beforeOpen`：迁移事务已经提交之后、任何业务读写之前。
Future<void> ensureForeignKeys(GeneratedDatabase db) async {
  await db.customStatement('PRAGMA foreign_keys = ON');
  final rows = await db.customSelect('PRAGMA foreign_keys').get();
  final value = rows.isEmpty || rows.first.data.isEmpty
      ? null
      : rows.first.data.values.first;
  if (value != 1) {
    throw const DatabaseOpenException(DatabaseErrorCode.foreignKeysUnavailable);
  }
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

/// 已打开并通过检查的本机数据库。
@immutable
final class OpenedAppDatabase {
  const OpenedAppDatabase({
    required this.database,
    required this.cipher,
    required this.created,
    required this.openDuration,
  });

  final AppDatabase database;

  /// 打开时读到的加密库信息。
  final CipherInfo cipher;

  /// 本次打开是否新建了数据库（首次启动）。
  final bool created;

  /// 从开始连接到第一条查询返回（含后台 isolate、设密钥、验证与迁移）的耗时。
  final Duration openDuration;
}

/// 打开（必要时新建）本机加密数据库。这是取得 [AppDatabase] 的唯一途径。
///
/// 1. 看数据库文件是否已有数据；
/// 2. 取密钥：钥匙串已有则用；没有且文件也没有数据（首次启动）才生成并保存；文件已有
///    数据而密钥丢失时拒绝（`key_missing`），不会新建密钥覆盖旧库；
/// 3. drift 后台连接，`setup` 中确认 sqlite3mc → 固定算法 → 原始密钥 → 读一次库验证；
/// 4. 第一条查询触发迁移（新库建出完整结构），随后打开外键检查并读回确认；
/// 5. 检查文件开头不是明文 SQLite 文件头（`plaintext_database`）。
///
/// 任一步失败：关闭连接，抛 [DatabaseOpenException]（只含错误码，不含密钥与路径）。
Future<OpenedAppDatabase> openAppDatabase({
  required DatabaseKeyManager keys,
  required DatabaseLocation location,
  String fileName = appDatabaseFileName,
  DateTime Function()? clock,
}) async {
  final String path;
  final bool hadData;
  try {
    path = joinDatabasePath(location.directory, fileName);
    hadData = databaseFileHasData(path);
  } on Object catch (error) {
    throw databaseOpenExceptionFrom(error);
  }

  final key = await keys.obtain(databaseHasData: hadData);

  final stopwatch = Stopwatch()..start();
  AppDatabase? database;
  try {
    database = AppDatabase._(
      connectEncryptedDatabase(
        name: 'cardflow',
        path: path,
        tempDirectory: location.tempDirectory,
        rawKeyLiteral: key.rawKeyLiteral(),
      ),
      clock: clock,
    );
    final cipher = await database.readCipherInfo();
    stopwatch.stop();
    if (databaseFileLooksPlaintext(path)) {
      throw const DatabaseOpenException(DatabaseErrorCode.plaintextDatabase);
    }
    return OpenedAppDatabase(
      database: database,
      cipher: cipher,
      created: !hadData,
      openDuration: stopwatch.elapsed,
    );
  } on Object catch (error) {
    await closeQuietly(database);
    throw databaseOpenExceptionFrom(error);
  }
}
