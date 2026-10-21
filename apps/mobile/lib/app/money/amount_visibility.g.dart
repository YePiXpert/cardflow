// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'amount_visibility.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 全局"金额隐藏"开关（ui-spec §3.6，R-SYS-03；简报 U-1 §9 R-09）：开启后 [MoneyText] 一律显示固定 4 个"•"，
/// 读屏读"金额已隐藏"。"我的"页有开关；状态存在 `app_settings`（键 [amountsHiddenSettingKey]，两个空间共用），
/// 启动时由 [amountsHiddenRestoredProvider] 读回一次。

@ProviderFor(AmountsHidden)
final amountsHiddenProvider = AmountsHiddenProvider._();

/// 全局"金额隐藏"开关（ui-spec §3.6，R-SYS-03；简报 U-1 §9 R-09）：开启后 [MoneyText] 一律显示固定 4 个"•"，
/// 读屏读"金额已隐藏"。"我的"页有开关；状态存在 `app_settings`（键 [amountsHiddenSettingKey]，两个空间共用），
/// 启动时由 [amountsHiddenRestoredProvider] 读回一次。
final class AmountsHiddenProvider
    extends $NotifierProvider<AmountsHidden, bool> {
  /// 全局"金额隐藏"开关（ui-spec §3.6，R-SYS-03；简报 U-1 §9 R-09）：开启后 [MoneyText] 一律显示固定 4 个"•"，
  /// 读屏读"金额已隐藏"。"我的"页有开关；状态存在 `app_settings`（键 [amountsHiddenSettingKey]，两个空间共用），
  /// 启动时由 [amountsHiddenRestoredProvider] 读回一次。
  AmountsHiddenProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'amountsHiddenProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$amountsHiddenHash();

  @$internal
  @override
  AmountsHidden create() => AmountsHidden();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$amountsHiddenHash() => r'dd9ac44f54a95079abb8e7b3951dd17ee84d1c5c';

/// 全局"金额隐藏"开关（ui-spec §3.6，R-SYS-03；简报 U-1 §9 R-09）：开启后 [MoneyText] 一律显示固定 4 个"•"，
/// 读屏读"金额已隐藏"。"我的"页有开关；状态存在 `app_settings`（键 [amountsHiddenSettingKey]，两个空间共用），
/// 启动时由 [amountsHiddenRestoredProvider] 读回一次。

abstract class _$AmountsHidden extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 读回"隐藏金额"开关：启动时一次，本机数据库重新打开（重置本地数据、重试打开）之后再一次。启动分流
/// （`app_gate.dart`）等它完成才进入主导航：打开隐藏后冷启动，页面不会先露出金额。读不到时照常完成。

@ProviderFor(amountsHiddenRestored)
final amountsHiddenRestoredProvider = AmountsHiddenRestoredProvider._();

/// 读回"隐藏金额"开关：启动时一次，本机数据库重新打开（重置本地数据、重试打开）之后再一次。启动分流
/// （`app_gate.dart`）等它完成才进入主导航：打开隐藏后冷启动，页面不会先露出金额。读不到时照常完成。

final class AmountsHiddenRestoredProvider
    extends $FunctionalProvider<AsyncValue<void>, void, FutureOr<void>>
    with $FutureModifier<void>, $FutureProvider<void> {
  /// 读回"隐藏金额"开关：启动时一次，本机数据库重新打开（重置本地数据、重试打开）之后再一次。启动分流
  /// （`app_gate.dart`）等它完成才进入主导航：打开隐藏后冷启动，页面不会先露出金额。读不到时照常完成。
  AmountsHiddenRestoredProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'amountsHiddenRestoredProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$amountsHiddenRestoredHash();

  @$internal
  @override
  $FutureProviderElement<void> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<void> create(Ref ref) {
    return amountsHiddenRestored(ref);
  }
}

String _$amountsHiddenRestoredHash() =>
    r'685fdd2150956a055258ee4048362c4ba38b7c27';
