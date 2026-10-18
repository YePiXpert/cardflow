// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database_benchmark_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 基准行数（ADR-001 PoC-1：10 万行）。测试里改小。

@ProviderFor(databaseBenchmarkRows)
final databaseBenchmarkRowsProvider = DatabaseBenchmarkRowsProvider._();

/// 基准行数（ADR-001 PoC-1：10 万行）。测试里改小。

final class DatabaseBenchmarkRowsProvider
    extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  /// 基准行数（ADR-001 PoC-1：10 万行）。测试里改小。
  DatabaseBenchmarkRowsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'databaseBenchmarkRowsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$databaseBenchmarkRowsHash();

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    return databaseBenchmarkRows(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$databaseBenchmarkRowsHash() =>
    r'a396da8ed614fc05eb2dc7a6d6e5697955ea19fa';

/// "数据库基准"按钮背后的状态。结果保留到 App 退出，以便离开页面后再复制报告。

@ProviderFor(DatabaseBenchmark)
final databaseBenchmarkProvider = DatabaseBenchmarkProvider._();

/// "数据库基准"按钮背后的状态。结果保留到 App 退出，以便离开页面后再复制报告。
final class DatabaseBenchmarkProvider
    extends $NotifierProvider<DatabaseBenchmark, DatabaseBenchmarkState> {
  /// "数据库基准"按钮背后的状态。结果保留到 App 退出，以便离开页面后再复制报告。
  DatabaseBenchmarkProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'databaseBenchmarkProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$databaseBenchmarkHash();

  @$internal
  @override
  DatabaseBenchmark create() => DatabaseBenchmark();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DatabaseBenchmarkState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DatabaseBenchmarkState>(value),
    );
  }
}

String _$databaseBenchmarkHash() => r'd4ac221c7dac618a229275d72e67cbe14f2df637';

/// "数据库基准"按钮背后的状态。结果保留到 App 退出，以便离开页面后再复制报告。

abstract class _$DatabaseBenchmark extends $Notifier<DatabaseBenchmarkState> {
  DatabaseBenchmarkState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<DatabaseBenchmarkState, DatabaseBenchmarkState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DatabaseBenchmarkState, DatabaseBenchmarkState>,
              DatabaseBenchmarkState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
