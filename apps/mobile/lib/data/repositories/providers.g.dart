// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 工作空间仓库（全局）。

@ProviderFor(workspaceRepository)
final workspaceRepositoryProvider = WorkspaceRepositoryProvider._();

/// 工作空间仓库（全局）。

final class WorkspaceRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<WorkspaceRepository>,
          WorkspaceRepository,
          FutureOr<WorkspaceRepository>
        >
    with
        $FutureModifier<WorkspaceRepository>,
        $FutureProvider<WorkspaceRepository> {
  /// 工作空间仓库（全局）。
  WorkspaceRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'workspaceRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workspaceRepositoryHash();

  @$internal
  @override
  $FutureProviderElement<WorkspaceRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<WorkspaceRepository> create(Ref ref) {
    return workspaceRepository(ref);
  }
}

String _$workspaceRepositoryHash() =>
    r'6a93ec652d3f363da3f69697cf230c7913609383';

/// 当前工作空间；null = 还没有（首次启动或演示清除后没有真实空间）→ 路由先进 P-22。
///
/// 切换操作只记事件（`workspace/started`、`workspace/switched`、`workspace/demo_cleared`，
/// detail 只有 real/demo/none），不记任何内容。

@ProviderFor(CurrentWorkspace)
final currentWorkspaceProvider = CurrentWorkspaceProvider._();

/// 当前工作空间；null = 还没有（首次启动或演示清除后没有真实空间）→ 路由先进 P-22。
///
/// 切换操作只记事件（`workspace/started`、`workspace/switched`、`workspace/demo_cleared`，
/// detail 只有 real/demo/none），不记任何内容。
final class CurrentWorkspaceProvider
    extends $AsyncNotifierProvider<CurrentWorkspace, Workspace?> {
  /// 当前工作空间；null = 还没有（首次启动或演示清除后没有真实空间）→ 路由先进 P-22。
  ///
  /// 切换操作只记事件（`workspace/started`、`workspace/switched`、`workspace/demo_cleared`，
  /// detail 只有 real/demo/none），不记任何内容。
  CurrentWorkspaceProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'currentWorkspaceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentWorkspaceHash();

  @$internal
  @override
  CurrentWorkspace create() => CurrentWorkspace();
}

String _$currentWorkspaceHash() => r'a9ee0d06b3832a0b4b852cd43b36dd9e0e476552';

/// 当前工作空间；null = 还没有（首次启动或演示清除后没有真实空间）→ 路由先进 P-22。
///
/// 切换操作只记事件（`workspace/started`、`workspace/switched`、`workspace/demo_cleared`，
/// detail 只有 real/demo/none），不记任何内容。

abstract class _$CurrentWorkspace extends $AsyncNotifier<Workspace?> {
  FutureOr<Workspace?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<Workspace?>, Workspace?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<Workspace?>, Workspace?>,
              AsyncValue<Workspace?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 演示空间的概况：是否存在，以及各表行数（P-22 的「清除演示数据」写明影响数量）。

@ProviderFor(demoWorkspaceRows)
final demoWorkspaceRowsProvider = DemoWorkspaceRowsProvider._();

/// 演示空间的概况：是否存在，以及各表行数（P-22 的「清除演示数据」写明影响数量）。

final class DemoWorkspaceRowsProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, int>?>,
          Map<String, int>?,
          FutureOr<Map<String, int>?>
        >
    with
        $FutureModifier<Map<String, int>?>,
        $FutureProvider<Map<String, int>?> {
  /// 演示空间的概况：是否存在，以及各表行数（P-22 的「清除演示数据」写明影响数量）。
  DemoWorkspaceRowsProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'demoWorkspaceRowsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$demoWorkspaceRowsHash();

  @$internal
  @override
  $FutureProviderElement<Map<String, int>?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Map<String, int>?> create(Ref ref) {
    return demoWorkspaceRows(ref);
  }
}

String _$demoWorkspaceRowsHash() => r'708da86f4dbc0a400f4ada27805c5391173a97da';

/// "现在"：演示空间固定为 2026-10-16（陈旧判定不触发），真实空间用系统时间。测试里替换。

@ProviderFor(clock)
final clockProvider = ClockProvider._();

/// "现在"：演示空间固定为 2026-10-16（陈旧判定不触发），真实空间用系统时间。测试里替换。

final class ClockProvider
    extends $FunctionalProvider<AppClock, AppClock, AppClock>
    with $Provider<AppClock> {
  /// "现在"：演示空间固定为 2026-10-16（陈旧判定不触发），真实空间用系统时间。测试里替换。
  ClockProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'clockProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$clockHash();

  @$internal
  @override
  $ProviderElement<AppClock> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppClock create(Ref ref) {
    return clock(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppClock value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppClock>(value),
    );
  }
}

String _$clockHash() => r'60dd1a28aeb173eb4e27f8b8fabe05981361b6ee';

/// 当前工作空间的作用域（数据库 + 工作空间 id + 时钟）；没有当前工作空间时失败
/// （[NoCurrentWorkspaceException]）。

@ProviderFor(workspaceScope)
final workspaceScopeProvider = WorkspaceScopeProvider._();

/// 当前工作空间的作用域（数据库 + 工作空间 id + 时钟）；没有当前工作空间时失败
/// （[NoCurrentWorkspaceException]）。

final class WorkspaceScopeProvider
    extends
        $FunctionalProvider<
          AsyncValue<WorkspaceScope>,
          WorkspaceScope,
          FutureOr<WorkspaceScope>
        >
    with $FutureModifier<WorkspaceScope>, $FutureProvider<WorkspaceScope> {
  /// 当前工作空间的作用域（数据库 + 工作空间 id + 时钟）；没有当前工作空间时失败
  /// （[NoCurrentWorkspaceException]）。
  WorkspaceScopeProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'workspaceScopeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workspaceScopeHash();

  @$internal
  @override
  $FutureProviderElement<WorkspaceScope> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<WorkspaceScope> create(Ref ref) {
    return workspaceScope(ref);
  }
}

String _$workspaceScopeHash() => r'7f38dae0a9f202e5afcc10352f9e11a4108f3a16';

/// 本地数据的变更计数：经 drift 的任何写入提交后加 1。读 provider watch 它以自动重算。

@ProviderFor(localDataRevision)
final localDataRevisionProvider = LocalDataRevisionProvider._();

/// 本地数据的变更计数：经 drift 的任何写入提交后加 1。读 provider watch 它以自动重算。

final class LocalDataRevisionProvider
    extends $FunctionalProvider<AsyncValue<int>, int, Stream<int>>
    with $FutureModifier<int>, $StreamProvider<int> {
  /// 本地数据的变更计数：经 drift 的任何写入提交后加 1。读 provider watch 它以自动重算。
  LocalDataRevisionProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'localDataRevisionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$localDataRevisionHash();

  @$internal
  @override
  $StreamProviderElement<int> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<int> create(Ref ref) {
    return localDataRevision(ref);
  }
}

String _$localDataRevisionHash() => r'7cc52c2325c4c1934ed3f90e0a6c8987555a5f80';

/// 银行仓库（当前工作空间）。

@ProviderFor(bankRepository)
final bankRepositoryProvider = BankRepositoryProvider._();

/// 银行仓库（当前工作空间）。

final class BankRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<BankRepository>,
          BankRepository,
          FutureOr<BankRepository>
        >
    with $FutureModifier<BankRepository>, $FutureProvider<BankRepository> {
  /// 银行仓库（当前工作空间）。
  BankRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'bankRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bankRepositoryHash();

  @$internal
  @override
  $FutureProviderElement<BankRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<BankRepository> create(Ref ref) {
    return bankRepository(ref);
  }
}

String _$bankRepositoryHash() => r'4579640b21830ceb4d79e5441440af4b63dbd6f5';

/// 信用账户与币种子账户仓库（当前工作空间）。

@ProviderFor(creditAccountRepository)
final creditAccountRepositoryProvider = CreditAccountRepositoryProvider._();

/// 信用账户与币种子账户仓库（当前工作空间）。

final class CreditAccountRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<CreditAccountRepository>,
          CreditAccountRepository,
          FutureOr<CreditAccountRepository>
        >
    with
        $FutureModifier<CreditAccountRepository>,
        $FutureProvider<CreditAccountRepository> {
  /// 信用账户与币种子账户仓库（当前工作空间）。
  CreditAccountRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'creditAccountRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$creditAccountRepositoryHash();

  @$internal
  @override
  $FutureProviderElement<CreditAccountRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<CreditAccountRepository> create(Ref ref) {
    return creditAccountRepository(ref);
  }
}

String _$creditAccountRepositoryHash() =>
    r'd1e4c3320db19a7c7646fe31ced6e9fcc9163c42';

/// 卡片仓库（当前工作空间）。

@ProviderFor(cardRepository)
final cardRepositoryProvider = CardRepositoryProvider._();

/// 卡片仓库（当前工作空间）。

final class CardRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<CardRepository>,
          CardRepository,
          FutureOr<CardRepository>
        >
    with $FutureModifier<CardRepository>, $FutureProvider<CardRepository> {
  /// 卡片仓库（当前工作空间）。
  CardRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'cardRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cardRepositoryHash();

  @$internal
  @override
  $FutureProviderElement<CardRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<CardRepository> create(Ref ref) {
    return cardRepository(ref);
  }
}

String _$cardRepositoryHash() => r'78741eb6125413d63b80b3e0f2b2ca68f596d5dd';

/// 授信池仓库（当前工作空间）。

@ProviderFor(creditPoolRepository)
final creditPoolRepositoryProvider = CreditPoolRepositoryProvider._();

/// 授信池仓库（当前工作空间）。

final class CreditPoolRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<CreditPoolRepository>,
          CreditPoolRepository,
          FutureOr<CreditPoolRepository>
        >
    with
        $FutureModifier<CreditPoolRepository>,
        $FutureProvider<CreditPoolRepository> {
  /// 授信池仓库（当前工作空间）。
  CreditPoolRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'creditPoolRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$creditPoolRepositoryHash();

  @$internal
  @override
  $FutureProviderElement<CreditPoolRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<CreditPoolRepository> create(Ref ref) {
    return creditPoolRepository(ref);
  }
}

String _$creditPoolRepositoryHash() =>
    r'27dc3fed029a116b69f670df34f566c401c15fbd';

/// 账期规则版本仓库（当前工作空间）。

@ProviderFor(billingRuleRepository)
final billingRuleRepositoryProvider = BillingRuleRepositoryProvider._();

/// 账期规则版本仓库（当前工作空间）。

final class BillingRuleRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<BillingRuleRepository>,
          BillingRuleRepository,
          FutureOr<BillingRuleRepository>
        >
    with
        $FutureModifier<BillingRuleRepository>,
        $FutureProvider<BillingRuleRepository> {
  /// 账期规则版本仓库（当前工作空间）。
  BillingRuleRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'billingRuleRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$billingRuleRepositoryHash();

  @$internal
  @override
  $FutureProviderElement<BillingRuleRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<BillingRuleRepository> create(Ref ref) {
    return billingRuleRepository(ref);
  }
}

String _$billingRuleRepositoryHash() =>
    r'6e37cd6fddbb4886cc6dc835323cf2d3072af394';

/// 额度快照仓库（当前工作空间）。

@ProviderFor(limitSnapshotRepository)
final limitSnapshotRepositoryProvider = LimitSnapshotRepositoryProvider._();

/// 额度快照仓库（当前工作空间）。

final class LimitSnapshotRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<LimitSnapshotRepository>,
          LimitSnapshotRepository,
          FutureOr<LimitSnapshotRepository>
        >
    with
        $FutureModifier<LimitSnapshotRepository>,
        $FutureProvider<LimitSnapshotRepository> {
  /// 额度快照仓库（当前工作空间）。
  LimitSnapshotRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'limitSnapshotRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$limitSnapshotRepositoryHash();

  @$internal
  @override
  $FutureProviderElement<LimitSnapshotRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<LimitSnapshotRepository> create(Ref ref) {
    return limitSnapshotRepository(ref);
  }
}

String _$limitSnapshotRepositoryHash() =>
    r'934ff46b32c23fd18f89d3ec93f49e1dc2329efc';

/// 卡包读模型（P-01/P-02/P-03）：数据变化时自动重算。

@ProviderFor(wallet)
final walletProvider = WalletProvider._();

/// 卡包读模型（P-01/P-02/P-03）：数据变化时自动重算。

final class WalletProvider
    extends
        $FunctionalProvider<
          AsyncValue<WalletView>,
          WalletView,
          FutureOr<WalletView>
        >
    with $FutureModifier<WalletView>, $FutureProvider<WalletView> {
  /// 卡包读模型（P-01/P-02/P-03）：数据变化时自动重算。
  WalletProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'walletProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$walletHash();

  @$internal
  @override
  $FutureProviderElement<WalletView> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<WalletView> create(Ref ref) {
    return wallet(ref);
  }
}

String _$walletHash() => r'313b21f2b6dccc226f89c6595c9d7543b64bff69';
