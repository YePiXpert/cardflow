import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/db/database_benchmark.dart';
import '../../data/db/database_opener.dart' show databaseOpenExceptionFrom;
import '../../data/db/database_providers.dart';
import 'diagnostic_log.dart';

part 'database_benchmark_controller.g.dart';

/// 诊断页"数据库基准"的状态。
sealed class DatabaseBenchmarkState {
  const DatabaseBenchmarkState();

  /// 诊断页上的文字。
  String get displayText;

  /// 诊断报告里的文字（含毫秒数，供用户回传）。
  String get reportText => displayText;
}

/// 还没有运行过。
final class DatabaseBenchmarkIdle extends DatabaseBenchmarkState {
  const DatabaseBenchmarkIdle();

  @override
  String get displayText => '未运行';
}

/// 正在运行。
final class DatabaseBenchmarkRunning extends DatabaseBenchmarkState {
  const DatabaseBenchmarkRunning();

  @override
  String get displayText => '运行中…';
}

/// 运行完成。
final class DatabaseBenchmarkSucceeded extends DatabaseBenchmarkState {
  const DatabaseBenchmarkSucceeded(this.result);

  final DatabaseBenchmarkResult result;

  @override
  String get displayText =>
      '${result.rows} 行：写入 ${result.write.inMilliseconds} ms · '
      '重新打开 ${result.open.inMilliseconds} ms · '
      'COUNT ${result.count.inMilliseconds} ms';

  @override
  String get reportText => result.toReportText();
}

/// 运行失败。[reasonCode] 只放错误码。
final class DatabaseBenchmarkFailed extends DatabaseBenchmarkState {
  const DatabaseBenchmarkFailed(this.reasonCode);

  final String reasonCode;

  @override
  String get displayText => '失败（$reasonCode）';
}

/// 基准行数（ADR-001 PoC-1：10 万行）。测试里改小。
@riverpod
int databaseBenchmarkRows(Ref ref) => defaultBenchmarkRows;

/// "数据库基准"按钮背后的状态。结果保留到 App 退出，以便离开页面后再复制报告。
@Riverpod(keepAlive: true)
class DatabaseBenchmark extends _$DatabaseBenchmark {
  @override
  DatabaseBenchmarkState build() => const DatabaseBenchmarkIdle();

  /// 运行一次基准；正在运行时忽略重复点击。
  Future<void> run() async {
    if (state is DatabaseBenchmarkRunning) {
      return;
    }
    state = const DatabaseBenchmarkRunning();
    final log = ref.read(diagnosticLogProvider)
      ..info('db', 'benchmark_started');
    final rows = ref.read(databaseBenchmarkRowsProvider);
    try {
      final location = await ref.read(databaseLocationProvider.future);
      final result = await runDatabaseBenchmark(location: location, rows: rows);
      if (!ref.mounted) {
        return;
      }
      state = DatabaseBenchmarkSucceeded(result);
      log.info('db', 'benchmark_done');
    } on Object catch (error) {
      final code = error is StateError
          ? 'benchmark_mismatch'
          : databaseOpenExceptionFrom(error).code.code;
      if (!ref.mounted) {
        return;
      }
      state = DatabaseBenchmarkFailed(code);
      log.error('db', 'benchmark_failed', detail: code);
    }
  }
}
