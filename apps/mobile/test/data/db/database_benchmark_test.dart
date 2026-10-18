// "数据库基准"（lib/data/db/database_benchmark.dart）：小 N，真实 sqlite3mc。
import 'dart:io';

import 'package:cardflow/data/db/database_benchmark.dart';
import 'package:cardflow/data/db/database_location.dart';
import 'package:cardflow/data/db/encryption.dart';
import 'package:flutter_test/flutter_test.dart';

import 'db_test_support.dart';

void main() {
  late DatabaseLocation location;

  setUp(() => location = createTempLocation());

  test('建临时加密库 → 写入 N 行 → 关闭 → 重开 COUNT：行数一致，耗时非负，跑完删除临时库', () async {
    const rows = 2000;
    final result = await runDatabaseBenchmark(location: location, rows: rows);

    expect(result.rows, rows);
    expect(result.write, greaterThanOrEqualTo(Duration.zero));
    expect(result.open, greaterThan(Duration.zero));
    expect(result.count, greaterThanOrEqualTo(Duration.zero));
    expect(result.fileSizeBytes, greaterThan(rows * 32));
    expect(result.cipher.library, startsWith('SQLite3 Multiple Ciphers '));
    expect(result.cipher.cipher, pinnedCipher);

    final leftovers = Directory(location.directory).listSync();
    expect(leftovers, isEmpty, reason: '临时库及其日志文件应被删除');
  });

  test('报告行：毫秒数与文件大小，供用户回传', () async {
    final result = await runDatabaseBenchmark(location: location, rows: 300);
    final text = result.toReportText();
    expect(
      text,
      matches(
        RegExp(
          r'^rows=300 write_ms=\d+ open_ms=\d+ count_ms=\d+ file_bytes=\d+ '
          r'cipher=chacha20 library=SQLite3 Multiple Ciphers \S+$',
        ),
      ),
    );
  });

  test('上次没删掉的临时库会先被删除，不影响结果', () async {
    final stale = File(databasePathIn(location, benchmarkFileName))
      ..writeAsStringSync('stale data from an interrupted run');
    final result = await runDatabaseBenchmark(location: location, rows: 100);
    expect(result.rows, 100);
    expect(stale.existsSync(), isFalse);
  });

  test('行数必须为正', () {
    expect(
      () => runDatabaseBenchmark(location: location, rows: 0),
      throwsArgumentError,
    );
  });
}
