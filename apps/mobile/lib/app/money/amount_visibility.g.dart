// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'amount_visibility.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 全局"金额隐藏"开关（ui-spec §3.6，R-SYS-03；简报 U-1 §9 R-09）：开启后 [MoneyText] 一律显示固定 4 个"•"，
/// 读屏读"金额已隐藏"。"我的"页有开关；状态存在 `app_settings`（键 [amountsHiddenSettingKey]，两个空间共用），
/// 本机数据库打开后由外壳调用 [restore] 读回。

@ProviderFor(AmountsHidden)
final amountsHiddenProvider = AmountsHiddenProvider._();

/// 全局"金额隐藏"开关（ui-spec §3.6，R-SYS-03；简报 U-1 §9 R-09）：开启后 [MoneyText] 一律显示固定 4 个"•"，
/// 读屏读"金额已隐藏"。"我的"页有开关；状态存在 `app_settings`（键 [amountsHiddenSettingKey]，两个空间共用），
/// 本机数据库打开后由外壳调用 [restore] 读回。
final class AmountsHiddenProvider
    extends $NotifierProvider<AmountsHidden, bool> {
  /// 全局"金额隐藏"开关（ui-spec §3.6，R-SYS-03；简报 U-1 §9 R-09）：开启后 [MoneyText] 一律显示固定 4 个"•"，
  /// 读屏读"金额已隐藏"。"我的"页有开关；状态存在 `app_settings`（键 [amountsHiddenSettingKey]，两个空间共用），
  /// 本机数据库打开后由外壳调用 [restore] 读回。
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

String _$amountsHiddenHash() => r'ba9ef4531ca8c6e9c855a60058132283112158be';

/// 全局"金额隐藏"开关（ui-spec §3.6，R-SYS-03；简报 U-1 §9 R-09）：开启后 [MoneyText] 一律显示固定 4 个"•"，
/// 读屏读"金额已隐藏"。"我的"页有开关；状态存在 `app_settings`（键 [amountsHiddenSettingKey]，两个空间共用），
/// 本机数据库打开后由外壳调用 [restore] 读回。

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
