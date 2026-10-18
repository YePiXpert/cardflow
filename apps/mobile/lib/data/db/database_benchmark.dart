import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'app_database.dart' show readCipherInfoOf;
import 'database_errors.dart';
import 'database_failures.dart' show closeQuietly, databaseOpenExceptionFrom;
import 'database_key.dart';
import 'database_location.dart';
import 'database_platform.dart';
import 'encryption.dart';

/// "数据库基准"的默认行数：ADR-001 PoC-1 的退出条件是"10 万行冷启动 <1 s"（真机）。
const int defaultBenchmarkRows = 100000;

/// 基准临时库的文件名（放在 `DatabaseLocation.scratchDirectory`，跑完即删）。
const String benchmarkFileName = 'cardflow-benchmark.sqlite';

/// 一次基准的结果。不含任何用户数据（数据全部由 SQLite 生成）。
@immutable
final class DatabaseBenchmarkResult {
  const DatabaseBenchmarkResult({
    required this.rows,
    required this.write,
    required this.open,
    required this.count,
    required this.fileSizeBytes,
    required this.cipher,
  });

  /// 写入并数到的行数。
  final int rows;

  /// 一个事务内写入 [rows] 行的耗时。
  final Duration write;

  /// 关闭后重新打开的耗时：新建后台 isolate、打开文件、确认 sqlite3mc、设置密钥、
  /// 读库验证、drift 版本检查，直到第一条查询返回。
  final Duration open;

  /// 重新打开后 `SELECT COUNT(*)` 的耗时（遍历并解密整张表）。
  final Duration count;

  /// 临时库文件大小（字节）。
  final int fileSizeBytes;

  /// 临时库的加密库信息。
  final CipherInfo cipher;

  /// 诊断报告中的一行。报告正文可以有数字（只有内存环形日志按规则脱敏）。
  String toReportText() =>
      'rows=$rows write_ms=${write.inMilliseconds} '
      'open_ms=${open.inMilliseconds} count_ms=${count.inMilliseconds} '
      'file_bytes=$fileSizeBytes cipher=${cipher.cipher} '
      'library=${cipher.library}';
}

/// 基准临时库：一张形如交易流水的表。
class _BenchmarkDatabase extends GeneratedDatabase {
  _BenchmarkDatabase(super.executor);

  static const String createTable = '''
CREATE TABLE bench_transactions (
  id INTEGER NOT NULL PRIMARY KEY,
  amount_minor INTEGER NOT NULL,
  currency TEXT NOT NULL,
  occurred_at INTEGER NOT NULL,
  merchant TEXT NOT NULL,
  note TEXT NOT NULL
) STRICT''';

  /// 由 SQLite 自己生成 [rows] 行合成数据（递归 CTE），不经过 Dart 内存。
  static const String insertRows = '''
WITH RECURSIVE seq(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < ?)
INSERT INTO bench_transactions (amount_minor, currency, occurred_at, merchant, note)
SELECT (i * 7919) % 1000000, 'CNY', 1760000000 + i * 60,
       'merchant_' || (i % 997), hex(randomblob(16))
FROM seq''';

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      const <TableInfo<Table, Object?>>[];

  @override
  MigrationStrategy get migration =>
      MigrationStrategy(onCreate: (m) => customStatement(createTable));

  Future<int> countRows() async {
    final row = await customSelect(
      'SELECT COUNT(*) AS n FROM bench_transactions',
    ).getSingle();
    return row.read<int>('n');
  }
}

/// 运行"数据库基准"：建临时加密库 → 一个事务内写入 [rows] 行 → 关闭 → 重新打开并
/// `COUNT(*)`，返回各段耗时。
///
/// - 临时库用一把只在内存中的随机密钥（[random]，默认系统安全随机数），不读写钥匙串，
///   不碰真正的本机数据库；
/// - 打开路径与正式库相同（drift_flutter 后台 isolate + 同样的加密设置与检查）；
/// - 跑完（无论成败）删除临时库文件。
///
/// 说明：刚写完的文件通常仍在系统文件缓存里，所以"重新打开"测的是新连接（SQLite 页缓存
/// 为空、需重新解密）而不是磁盘冷读；iOS App 无法清空系统文件缓存。
Future<DatabaseBenchmarkResult> runDatabaseBenchmark({
  required DatabaseLocation location,
  int rows = defaultBenchmarkRows,
  Random? random,
}) async {
  if (rows <= 0) {
    throw ArgumentError.value(rows, 'rows', 'must be positive');
  }
  final path = joinDatabasePath(location.scratchDirectory, benchmarkFileName);
  final rawKeyLiteral = DatabaseKey.generate(random).rawKeyLiteral();

  _BenchmarkDatabase connect() => _BenchmarkDatabase(
    connectEncryptedDatabase(
      name: 'cardflow_benchmark',
      path: path,
      tempDirectory: location.tempDirectory,
      rawKeyLiteral: rawKeyLiteral,
    ),
  );

  _BenchmarkDatabase? open;
  try {
    deleteDatabaseFiles(path);

    // 1. 新建并在一个事务内写入。
    final writer = open = connect();
    await readCipherInfoOf(writer);
    final writeWatch = Stopwatch()..start();
    await writer.transaction(
      () =>
          writer.customStatement(_BenchmarkDatabase.insertRows, <Object>[rows]),
    );
    writeWatch.stop();
    await writer.close();
    open = null;

    // 2. 重新打开（新的后台 isolate 与连接）并计数。
    final openWatch = Stopwatch()..start();
    final reader = open = connect();
    final cipher = await readCipherInfoOf(reader);
    openWatch.stop();
    final countWatch = Stopwatch()..start();
    final counted = await reader.countRows();
    countWatch.stop();
    await reader.close();
    open = null;

    if (counted != rows) {
      throw StateError('benchmark row count mismatch');
    }
    if (databaseFileLooksPlaintext(path)) {
      throw const DatabaseOpenException(DatabaseErrorCode.plaintextDatabase);
    }
    return DatabaseBenchmarkResult(
      rows: counted,
      write: writeWatch.elapsed,
      open: openWatch.elapsed,
      count: countWatch.elapsed,
      fileSizeBytes: databaseFileSize(path),
      cipher: cipher,
    );
  } on StateError {
    rethrow;
  } on Object catch (error) {
    throw databaseOpenExceptionFrom(error);
  } finally {
    await closeQuietly(open);
    try {
      deleteDatabaseFiles(path);
    } on Object {
      // 临时文件删不掉不影响结果；下次运行开始时会再删一次。
    }
  }
}
