// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'amount_visibility.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 全局"金额隐藏"开关（ui-spec §3.6，R-SYS-03）。[MoneyText] 默认跟随它。
///
/// 本阶段只保存在内存中；"我的"页的开关与持久化随 I-4（应用锁、金额隐藏、遮罩）接入。

@ProviderFor(AmountsHidden)
final amountsHiddenProvider = AmountsHiddenProvider._();

/// 全局"金额隐藏"开关（ui-spec §3.6，R-SYS-03）。[MoneyText] 默认跟随它。
///
/// 本阶段只保存在内存中；"我的"页的开关与持久化随 I-4（应用锁、金额隐藏、遮罩）接入。
final class AmountsHiddenProvider
    extends $NotifierProvider<AmountsHidden, bool> {
  /// 全局"金额隐藏"开关（ui-spec §3.6，R-SYS-03）。[MoneyText] 默认跟随它。
  ///
  /// 本阶段只保存在内存中；"我的"页的开关与持久化随 I-4（应用锁、金额隐藏、遮罩）接入。
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

String _$amountsHiddenHash() => r'9705cad5b29dbc4e6a53a10148b537354dab816d';

/// 全局"金额隐藏"开关（ui-spec §3.6，R-SYS-03）。[MoneyText] 默认跟随它。
///
/// 本阶段只保存在内存中；"我的"页的开关与持久化随 I-4（应用锁、金额隐藏、遮罩）接入。

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
