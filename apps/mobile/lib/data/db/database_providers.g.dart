// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 设备数据库密钥的存放处：iOS 钥匙串。测试里换成内存实现。

@ProviderFor(databaseKeyStore)
final databaseKeyStoreProvider = DatabaseKeyStoreProvider._();

/// 设备数据库密钥的存放处：iOS 钥匙串。测试里换成内存实现。

final class DatabaseKeyStoreProvider
    extends
        $FunctionalProvider<
          DatabaseKeyStore,
          DatabaseKeyStore,
          DatabaseKeyStore
        >
    with $Provider<DatabaseKeyStore> {
  /// 设备数据库密钥的存放处：iOS 钥匙串。测试里换成内存实现。
  DatabaseKeyStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'databaseKeyStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$databaseKeyStoreHash();

  @$internal
  @override
  $ProviderElement<DatabaseKeyStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DatabaseKeyStore create(Ref ref) {
    return databaseKeyStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DatabaseKeyStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DatabaseKeyStore>(value),
    );
  }
}

String _$databaseKeyStoreHash() => r'd98451c49a236c9f9abf5e03fe0a7a85e655d807';

/// 密钥管理：同一进程内最多生成一次密钥。

@ProviderFor(databaseKeyManager)
final databaseKeyManagerProvider = DatabaseKeyManagerProvider._();

/// 密钥管理：同一进程内最多生成一次密钥。

final class DatabaseKeyManagerProvider
    extends
        $FunctionalProvider<
          DatabaseKeyManager,
          DatabaseKeyManager,
          DatabaseKeyManager
        >
    with $Provider<DatabaseKeyManager> {
  /// 密钥管理：同一进程内最多生成一次密钥。
  DatabaseKeyManagerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'databaseKeyManagerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$databaseKeyManagerHash();

  @$internal
  @override
  $ProviderElement<DatabaseKeyManager> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DatabaseKeyManager create(Ref ref) {
    return databaseKeyManager(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DatabaseKeyManager value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DatabaseKeyManager>(value),
    );
  }
}

String _$databaseKeyManagerHash() =>
    r'6ec2ab840eec4e9d1a65a27f5bff40b014e2b289';

/// 数据库文件位置（Application Support / Caches）。测试里换成临时目录。

@ProviderFor(databaseLocation)
final databaseLocationProvider = DatabaseLocationProvider._();

/// 数据库文件位置（Application Support / Caches）。测试里换成临时目录。

final class DatabaseLocationProvider
    extends
        $FunctionalProvider<
          AsyncValue<DatabaseLocation>,
          DatabaseLocation,
          FutureOr<DatabaseLocation>
        >
    with $FutureModifier<DatabaseLocation>, $FutureProvider<DatabaseLocation> {
  /// 数据库文件位置（Application Support / Caches）。测试里换成临时目录。
  DatabaseLocationProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'databaseLocationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$databaseLocationHash();

  @$internal
  @override
  $FutureProviderElement<DatabaseLocation> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<DatabaseLocation> create(Ref ref) {
    return databaseLocation(ref);
  }
}

String _$databaseLocationHash() => r'904b226e046be6f1666d951d76603d1067014037';

/// 已打开并通过加密检查的本机数据库，附带打开信息（加密库、是否新建、耗时）。
///
/// 失败时是 [DatabaseOpenException]（只含错误码）。诊断日志记 `db/opened`
/// （detail：created/existing）或 `db/open_failed`（detail：错误码）。

@ProviderFor(openedDatabase)
final openedDatabaseProvider = OpenedDatabaseProvider._();

/// 已打开并通过加密检查的本机数据库，附带打开信息（加密库、是否新建、耗时）。
///
/// 失败时是 [DatabaseOpenException]（只含错误码）。诊断日志记 `db/opened`
/// （detail：created/existing）或 `db/open_failed`（detail：错误码）。

final class OpenedDatabaseProvider
    extends
        $FunctionalProvider<
          AsyncValue<OpenedAppDatabase>,
          OpenedAppDatabase,
          FutureOr<OpenedAppDatabase>
        >
    with
        $FutureModifier<OpenedAppDatabase>,
        $FutureProvider<OpenedAppDatabase> {
  /// 已打开并通过加密检查的本机数据库，附带打开信息（加密库、是否新建、耗时）。
  ///
  /// 失败时是 [DatabaseOpenException]（只含错误码）。诊断日志记 `db/opened`
  /// （detail：created/existing）或 `db/open_failed`（detail：错误码）。
  OpenedDatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'openedDatabaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$openedDatabaseHash();

  @$internal
  @override
  $FutureProviderElement<OpenedAppDatabase> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<OpenedAppDatabase> create(Ref ref) {
    return openedDatabase(ref);
  }
}

String _$openedDatabaseHash() => r'b455d8a3fb2c1806f120ff5d561b7c2adf0b1afe';

/// 本机加密数据库（drift）。仓库与用例从这里取：
/// `final db = await ref.watch(databaseProvider.future);`

@ProviderFor(database)
final databaseProvider = DatabaseProvider._();

/// 本机加密数据库（drift）。仓库与用例从这里取：
/// `final db = await ref.watch(databaseProvider.future);`

final class DatabaseProvider
    extends
        $FunctionalProvider<
          AsyncValue<AppDatabase>,
          AppDatabase,
          FutureOr<AppDatabase>
        >
    with $FutureModifier<AppDatabase>, $FutureProvider<AppDatabase> {
  /// 本机加密数据库（drift）。仓库与用例从这里取：
  /// `final db = await ref.watch(databaseProvider.future);`
  DatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'databaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$databaseHash();

  @$internal
  @override
  $FutureProviderElement<AppDatabase> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AppDatabase> create(Ref ref) {
    return database(ref);
  }
}

String _$databaseHash() => r'95353766274673013bc8634734eb55124e4f102d';

/// 钥匙串里是否已有数据库密钥（诊断页只显示"已生成/未生成"）。
///
/// 首次启动时密钥在打开数据库的过程中生成，所以先等打开结束（无论成败）再查。

@ProviderFor(databaseKeyExists)
final databaseKeyExistsProvider = DatabaseKeyExistsProvider._();

/// 钥匙串里是否已有数据库密钥（诊断页只显示"已生成/未生成"）。
///
/// 首次启动时密钥在打开数据库的过程中生成，所以先等打开结束（无论成败）再查。

final class DatabaseKeyExistsProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// 钥匙串里是否已有数据库密钥（诊断页只显示"已生成/未生成"）。
  ///
  /// 首次启动时密钥在打开数据库的过程中生成，所以先等打开结束（无论成败）再查。
  DatabaseKeyExistsProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'databaseKeyExistsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$databaseKeyExistsHash();

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    return databaseKeyExists(ref);
  }
}

String _$databaseKeyExistsHash() => r'a256bc8b0a6f5fdb8340d1df46d505a0d45b538d';

/// 打开本机数据库失败后的恢复操作：「重试」与「重置本地数据」。
///
/// 诊断日志只记事件（`db/retry`、`db/reset`、`db/reset_failed` + 错误码），没有任何内容。

@ProviderFor(DatabaseRecovery)
final databaseRecoveryProvider = DatabaseRecoveryProvider._();

/// 打开本机数据库失败后的恢复操作：「重试」与「重置本地数据」。
///
/// 诊断日志只记事件（`db/retry`、`db/reset`、`db/reset_failed` + 错误码），没有任何内容。
final class DatabaseRecoveryProvider
    extends $NotifierProvider<DatabaseRecovery, DatabaseRecoveryState> {
  /// 打开本机数据库失败后的恢复操作：「重试」与「重置本地数据」。
  ///
  /// 诊断日志只记事件（`db/retry`、`db/reset`、`db/reset_failed` + 错误码），没有任何内容。
  DatabaseRecoveryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'databaseRecoveryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$databaseRecoveryHash();

  @$internal
  @override
  DatabaseRecovery create() => DatabaseRecovery();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DatabaseRecoveryState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DatabaseRecoveryState>(value),
    );
  }
}

String _$databaseRecoveryHash() => r'7170e3aa230b68af3a0581c2e6b5d2b4bfab5bec';

/// 打开本机数据库失败后的恢复操作：「重试」与「重置本地数据」。
///
/// 诊断日志只记事件（`db/retry`、`db/reset`、`db/reset_failed` + 错误码），没有任何内容。

abstract class _$DatabaseRecovery extends $Notifier<DatabaseRecoveryState> {
  DatabaseRecoveryState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<DatabaseRecoveryState, DatabaseRecoveryState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DatabaseRecoveryState, DatabaseRecoveryState>,
              DatabaseRecoveryState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
