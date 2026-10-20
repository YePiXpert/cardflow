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

/// 现金账户与余额快照仓库（当前工作空间）。

@ProviderFor(cashAccountRepository)
final cashAccountRepositoryProvider = CashAccountRepositoryProvider._();

/// 现金账户与余额快照仓库（当前工作空间）。

final class CashAccountRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<CashAccountRepository>,
          CashAccountRepository,
          FutureOr<CashAccountRepository>
        >
    with
        $FutureModifier<CashAccountRepository>,
        $FutureProvider<CashAccountRepository> {
  /// 现金账户与余额快照仓库（当前工作空间）。
  CashAccountRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'cashAccountRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cashAccountRepositoryHash();

  @$internal
  @override
  $FutureProviderElement<CashAccountRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<CashAccountRepository> create(Ref ref) {
    return cashAccountRepository(ref);
  }
}

String _$cashAccountRepositoryHash() =>
    r'6e3fb4f1353a12c80e9e7dc38e80bd25c8df1e28';

/// 现金余额快照仓库（当前工作空间）。

@ProviderFor(cashSnapshotRepository)
final cashSnapshotRepositoryProvider = CashSnapshotRepositoryProvider._();

/// 现金余额快照仓库（当前工作空间）。

final class CashSnapshotRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<CashSnapshotRepository>,
          CashSnapshotRepository,
          FutureOr<CashSnapshotRepository>
        >
    with
        $FutureModifier<CashSnapshotRepository>,
        $FutureProvider<CashSnapshotRepository> {
  /// 现金余额快照仓库（当前工作空间）。
  CashSnapshotRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'cashSnapshotRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cashSnapshotRepositoryHash();

  @$internal
  @override
  $FutureProviderElement<CashSnapshotRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<CashSnapshotRepository> create(Ref ref) {
    return cashSnapshotRepository(ref);
  }
}

String _$cashSnapshotRepositoryHash() =>
    r'cc7e68d629915bf2d22bb1dbebca9c4331733fc2';

/// 现金事件仓库（收支计划、调拨、还款扣款；当前工作空间）。

@ProviderFor(cashEventRepository)
final cashEventRepositoryProvider = CashEventRepositoryProvider._();

/// 现金事件仓库（收支计划、调拨、还款扣款；当前工作空间）。

final class CashEventRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<CashEventRepository>,
          CashEventRepository,
          FutureOr<CashEventRepository>
        >
    with
        $FutureModifier<CashEventRepository>,
        $FutureProvider<CashEventRepository> {
  /// 现金事件仓库（收支计划、调拨、还款扣款；当前工作空间）。
  CashEventRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'cashEventRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cashEventRepositoryHash();

  @$internal
  @override
  $FutureProviderElement<CashEventRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<CashEventRepository> create(Ref ref) {
    return cashEventRepository(ref);
  }
}

String _$cashEventRepositoryHash() =>
    r'd9f073fa43b7b945d8566c1c157040fbe55c181d';

/// 周期事项仓库（当前工作空间）。

@ProviderFor(recurringItemRepository)
final recurringItemRepositoryProvider = RecurringItemRepositoryProvider._();

/// 周期事项仓库（当前工作空间）。

final class RecurringItemRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<RecurringItemRepository>,
          RecurringItemRepository,
          FutureOr<RecurringItemRepository>
        >
    with
        $FutureModifier<RecurringItemRepository>,
        $FutureProvider<RecurringItemRepository> {
  /// 周期事项仓库（当前工作空间）。
  RecurringItemRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'recurringItemRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recurringItemRepositoryHash();

  @$internal
  @override
  $FutureProviderElement<RecurringItemRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<RecurringItemRepository> create(Ref ref) {
    return recurringItemRepository(ref);
  }
}

String _$recurringItemRepositoryHash() =>
    r'48bb44546c7221cae02535c87345d3c3fe7b2c41';

/// 情景仓库（当前工作空间）。

@ProviderFor(scenarioRepository)
final scenarioRepositoryProvider = ScenarioRepositoryProvider._();

/// 情景仓库（当前工作空间）。

final class ScenarioRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<ScenarioRepository>,
          ScenarioRepository,
          FutureOr<ScenarioRepository>
        >
    with
        $FutureModifier<ScenarioRepository>,
        $FutureProvider<ScenarioRepository> {
  /// 情景仓库（当前工作空间）。
  ScenarioRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'scenarioRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$scenarioRepositoryHash();

  @$internal
  @override
  $FutureProviderElement<ScenarioRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ScenarioRepository> create(Ref ref) {
    return scenarioRepository(ref);
  }
}

String _$scenarioRepositoryHash() =>
    r'17e37983014941eae559565315a6ab7203f1dc49';

/// 现金与收支计划（P-08）读模型：数据变化时自动重算。

@ProviderFor(cashPlan)
final cashPlanProvider = CashPlanProvider._();

/// 现金与收支计划（P-08）读模型：数据变化时自动重算。

final class CashPlanProvider
    extends
        $FunctionalProvider<
          AsyncValue<CashPlanView>,
          CashPlanView,
          FutureOr<CashPlanView>
        >
    with $FutureModifier<CashPlanView>, $FutureProvider<CashPlanView> {
  /// 现金与收支计划（P-08）读模型：数据变化时自动重算。
  CashPlanProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'cashPlanProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cashPlanHash();

  @$internal
  @override
  $FutureProviderElement<CashPlanView> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<CashPlanView> create(Ref ref) {
    return cashPlan(ref);
  }
}

String _$cashPlanHash() => r'201cac61b08bcf7ed52211c819efcc41e104eed0';

/// 现金账户详情（P-08）；账户不在当前空间时失败（NotFoundException）。

@ProviderFor(cashAccountDetail)
final cashAccountDetailProvider = CashAccountDetailFamily._();

/// 现金账户详情（P-08）；账户不在当前空间时失败（NotFoundException）。

final class CashAccountDetailProvider
    extends
        $FunctionalProvider<
          AsyncValue<CashAccountDetailView>,
          CashAccountDetailView,
          FutureOr<CashAccountDetailView>
        >
    with
        $FutureModifier<CashAccountDetailView>,
        $FutureProvider<CashAccountDetailView> {
  /// 现金账户详情（P-08）；账户不在当前空间时失败（NotFoundException）。
  CashAccountDetailProvider._({
    required CashAccountDetailFamily super.from,
    required String super.argument,
  }) : super(
         retry: noDatabaseRetry,
         name: r'cashAccountDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$cashAccountDetailHash();

  @override
  String toString() {
    return r'cashAccountDetailProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<CashAccountDetailView> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<CashAccountDetailView> create(Ref ref) {
    final argument = this.argument as String;
    return cashAccountDetail(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CashAccountDetailProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$cashAccountDetailHash() => r'0e2200981fb29aa04e0b4164db665bc0cc0d5474';

/// 现金账户详情（P-08）；账户不在当前空间时失败（NotFoundException）。

final class CashAccountDetailFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<CashAccountDetailView>, String> {
  CashAccountDetailFamily._()
    : super(
        retry: noDatabaseRetry,
        name: r'cashAccountDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 现金账户详情（P-08）；账户不在当前空间时失败（NotFoundException）。

  CashAccountDetailProvider call(String accountId) =>
      CashAccountDetailProvider._(argument: accountId, from: this);

  @override
  String toString() => r'cashAccountDetailProvider';
}

/// 周期事项详情（P-08）；不在当前空间时失败（NotFoundException）。

@ProviderFor(recurringDetail)
final recurringDetailProvider = RecurringDetailFamily._();

/// 周期事项详情（P-08）；不在当前空间时失败（NotFoundException）。

final class RecurringDetailProvider
    extends
        $FunctionalProvider<
          AsyncValue<RecurringDetailView>,
          RecurringDetailView,
          FutureOr<RecurringDetailView>
        >
    with
        $FutureModifier<RecurringDetailView>,
        $FutureProvider<RecurringDetailView> {
  /// 周期事项详情（P-08）；不在当前空间时失败（NotFoundException）。
  RecurringDetailProvider._({
    required RecurringDetailFamily super.from,
    required String super.argument,
  }) : super(
         retry: noDatabaseRetry,
         name: r'recurringDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$recurringDetailHash();

  @override
  String toString() {
    return r'recurringDetailProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<RecurringDetailView> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<RecurringDetailView> create(Ref ref) {
    final argument = this.argument as String;
    return recurringDetail(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is RecurringDetailProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$recurringDetailHash() => r'd04b6b1ad04f78ad6a243fdd34be00a4d330de35';

/// 周期事项详情（P-08）；不在当前空间时失败（NotFoundException）。

final class RecurringDetailFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<RecurringDetailView>, String> {
  RecurringDetailFamily._()
    : super(
        retry: noDatabaseRetry,
        name: r'recurringDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 周期事项详情（P-08）；不在当前空间时失败（NotFoundException）。

  RecurringDetailProvider call(String itemId) =>
      RecurringDetailProvider._(argument: itemId, from: this);

  @override
  String toString() => r'recurringDetailProvider';
}

/// 资金日历（P-07）与总览现金压力卡（P-01）：数据变化时自动重算（provider 依赖）。

@ProviderFor(cashForecast)
final cashForecastProvider = CashForecastFamily._();

/// 资金日历（P-07）与总览现金压力卡（P-01）：数据变化时自动重算（provider 依赖）。

final class CashForecastProvider
    extends
        $FunctionalProvider<
          AsyncValue<CashForecast>,
          CashForecast,
          FutureOr<CashForecast>
        >
    with $FutureModifier<CashForecast>, $FutureProvider<CashForecast> {
  /// 资金日历（P-07）与总览现金压力卡（P-01）：数据变化时自动重算（provider 依赖）。
  CashForecastProvider._({
    required CashForecastFamily super.from,
    required CashForecastQuery super.argument,
  }) : super(
         retry: noDatabaseRetry,
         name: r'cashForecastProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$cashForecastHash();

  @override
  String toString() {
    return r'cashForecastProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<CashForecast> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<CashForecast> create(Ref ref) {
    final argument = this.argument as CashForecastQuery;
    return cashForecast(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CashForecastProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$cashForecastHash() => r'c7d68b8de526cf490d11063ac0fa4bee2cfc83fd';

/// 资金日历（P-07）与总览现金压力卡（P-01）：数据变化时自动重算（provider 依赖）。

final class CashForecastFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<CashForecast>, CashForecastQuery> {
  CashForecastFamily._()
    : super(
        retry: noDatabaseRetry,
        name: r'cashForecastProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 资金日历（P-07）与总览现金压力卡（P-01）：数据变化时自动重算（provider 依赖）。

  CashForecastProvider call(CashForecastQuery query) =>
      CashForecastProvider._(argument: query, from: this);

  @override
  String toString() => r'cashForecastProvider';
}

/// 情景列表（P-09）：每个情景的计算版本（新的在前）与最新版本是否已过期。

@ProviderFor(scenarioBoard)
final scenarioBoardProvider = ScenarioBoardProvider._();

/// 情景列表（P-09）：每个情景的计算版本（新的在前）与最新版本是否已过期。

final class ScenarioBoardProvider
    extends
        $FunctionalProvider<
          AsyncValue<ScenarioBoard>,
          ScenarioBoard,
          FutureOr<ScenarioBoard>
        >
    with $FutureModifier<ScenarioBoard>, $FutureProvider<ScenarioBoard> {
  /// 情景列表（P-09）：每个情景的计算版本（新的在前）与最新版本是否已过期。
  ScenarioBoardProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'scenarioBoardProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$scenarioBoardHash();

  @$internal
  @override
  $FutureProviderElement<ScenarioBoard> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ScenarioBoard> create(Ref ref) {
    return scenarioBoard(ref);
  }
}

String _$scenarioBoardHash() => r'8676de6feed29d0dcc26d5a2f57d89536e8248ac';

/// 交易仓库（当前工作空间，I-1c）。

@ProviderFor(transactionRepository)
final transactionRepositoryProvider = TransactionRepositoryProvider._();

/// 交易仓库（当前工作空间，I-1c）。

final class TransactionRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<TransactionRepository>,
          TransactionRepository,
          FutureOr<TransactionRepository>
        >
    with
        $FutureModifier<TransactionRepository>,
        $FutureProvider<TransactionRepository> {
  /// 交易仓库（当前工作空间，I-1c）。
  TransactionRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'transactionRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$transactionRepositoryHash();

  @$internal
  @override
  $FutureProviderElement<TransactionRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<TransactionRepository> create(Ref ref) {
    return transactionRepository(ref);
  }
}

String _$transactionRepositoryHash() =>
    r'90fd2c69655b664a40fb0bc0f48a23f7f7c14748';

/// 账单与账单版本仓库（当前工作空间）。

@ProviderFor(statementRepository)
final statementRepositoryProvider = StatementRepositoryProvider._();

/// 账单与账单版本仓库（当前工作空间）。

final class StatementRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<StatementRepository>,
          StatementRepository,
          FutureOr<StatementRepository>
        >
    with
        $FutureModifier<StatementRepository>,
        $FutureProvider<StatementRepository> {
  /// 账单与账单版本仓库（当前工作空间）。
  StatementRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'statementRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$statementRepositoryHash();

  @$internal
  @override
  $FutureProviderElement<StatementRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<StatementRepository> create(Ref ref) {
    return statementRepository(ref);
  }
}

String _$statementRepositoryHash() =>
    r'89ddde5153ad75ac6c9d5e183176c94528e8275c';

/// 分期计划仓库（当前工作空间）。

@ProviderFor(installmentRepository)
final installmentRepositoryProvider = InstallmentRepositoryProvider._();

/// 分期计划仓库（当前工作空间）。

final class InstallmentRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<InstallmentRepository>,
          InstallmentRepository,
          FutureOr<InstallmentRepository>
        >
    with
        $FutureModifier<InstallmentRepository>,
        $FutureProvider<InstallmentRepository> {
  /// 分期计划仓库（当前工作空间）。
  InstallmentRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'installmentRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$installmentRepositoryHash();

  @$internal
  @override
  $FutureProviderElement<InstallmentRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<InstallmentRepository> create(Ref ref) {
    return installmentRepository(ref);
  }
}

String _$installmentRepositoryHash() =>
    r'e243b3d9e5ff33d30c772715be2f3fb61698fd3d';

/// 还款仓库（当前工作空间）。

@ProviderFor(repaymentRepository)
final repaymentRepositoryProvider = RepaymentRepositoryProvider._();

/// 还款仓库（当前工作空间）。

final class RepaymentRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<RepaymentRepository>,
          RepaymentRepository,
          FutureOr<RepaymentRepository>
        >
    with
        $FutureModifier<RepaymentRepository>,
        $FutureProvider<RepaymentRepository> {
  /// 还款仓库（当前工作空间）。
  RepaymentRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'repaymentRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$repaymentRepositoryHash();

  @$internal
  @override
  $FutureProviderElement<RepaymentRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<RepaymentRepository> create(Ref ref) {
    return repaymentRepository(ref);
  }
}

String _$repaymentRepositoryHash() =>
    r'1ad0abb4ce5665c9468b08a959030a72fd9625ad';

/// 差异项仓库（当前工作空间）。

@ProviderFor(reconciliationRepository)
final reconciliationRepositoryProvider = ReconciliationRepositoryProvider._();

/// 差异项仓库（当前工作空间）。

final class ReconciliationRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<ReconciliationRepository>,
          ReconciliationRepository,
          FutureOr<ReconciliationRepository>
        >
    with
        $FutureModifier<ReconciliationRepository>,
        $FutureProvider<ReconciliationRepository> {
  /// 差异项仓库（当前工作空间）。
  ReconciliationRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'reconciliationRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reconciliationRepositoryHash();

  @$internal
  @override
  $FutureProviderElement<ReconciliationRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ReconciliationRepository> create(Ref ref) {
    return reconciliationRepository(ref);
  }
}

String _$reconciliationRepositoryHash() =>
    r'c5b9423c34d0c60b5c082c65695169ad9db05d52';

/// 账单、交易、分期、还款与差异项的读模型（P-05/P-06/P-03/P-01）：数据变化时自动重算。

@ProviderFor(ledger)
final ledgerProvider = LedgerProvider._();

/// 账单、交易、分期、还款与差异项的读模型（P-05/P-06/P-03/P-01）：数据变化时自动重算。

final class LedgerProvider
    extends
        $FunctionalProvider<
          AsyncValue<LedgerData>,
          LedgerData,
          FutureOr<LedgerData>
        >
    with $FutureModifier<LedgerData>, $FutureProvider<LedgerData> {
  /// 账单、交易、分期、还款与差异项的读模型（P-05/P-06/P-03/P-01）：数据变化时自动重算。
  LedgerProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'ledgerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ledgerHash();

  @$internal
  @override
  $FutureProviderElement<LedgerData> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<LedgerData> create(Ref ref) {
    return ledger(ref);
  }
}

String _$ledgerHash() => r'17803145dfc1d93cd4518f81b5b252f2e91b36d7';

/// 卡账首页（简报 U-1 §2）的读模型：账单读模型变化时自动重算；[sort] 决定行的顺序。

@ProviderFor(ledgerHome)
final ledgerHomeProvider = LedgerHomeFamily._();

/// 卡账首页（简报 U-1 §2）的读模型：账单读模型变化时自动重算；[sort] 决定行的顺序。

final class LedgerHomeProvider
    extends
        $FunctionalProvider<
          AsyncValue<LedgerHome>,
          LedgerHome,
          FutureOr<LedgerHome>
        >
    with $FutureModifier<LedgerHome>, $FutureProvider<LedgerHome> {
  /// 卡账首页（简报 U-1 §2）的读模型：账单读模型变化时自动重算；[sort] 决定行的顺序。
  LedgerHomeProvider._({
    required LedgerHomeFamily super.from,
    required LedgerSort super.argument,
  }) : super(
         retry: noDatabaseRetry,
         name: r'ledgerHomeProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$ledgerHomeHash();

  @override
  String toString() {
    return r'ledgerHomeProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<LedgerHome> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<LedgerHome> create(Ref ref) {
    final argument = this.argument as LedgerSort;
    return ledgerHome(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is LedgerHomeProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$ledgerHomeHash() => r'eb7a467adc8d72a3e0f983f7fa5ef4073fdf03b3';

/// 卡账首页（简报 U-1 §2）的读模型：账单读模型变化时自动重算；[sort] 决定行的顺序。

final class LedgerHomeFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<LedgerHome>, LedgerSort> {
  LedgerHomeFamily._()
    : super(
        retry: noDatabaseRetry,
        name: r'ledgerHomeProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 卡账首页（简报 U-1 §2）的读模型：账单读模型变化时自动重算；[sort] 决定行的顺序。

  LedgerHomeProvider call(LedgerSort sort) =>
      LedgerHomeProvider._(argument: sort, from: this);

  @override
  String toString() => r'ledgerHomeProvider';
}
