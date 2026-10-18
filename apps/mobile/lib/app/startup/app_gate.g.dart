// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_gate.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 当前的启动分流状态（由当前工作空间 provider 推出；它依赖本机数据库）。

@ProviderFor(appGate)
final appGateProvider = AppGateProvider._();

/// 当前的启动分流状态（由当前工作空间 provider 推出；它依赖本机数据库）。

final class AppGateProvider
    extends $FunctionalProvider<AppGate, AppGate, AppGate>
    with $Provider<AppGate> {
  /// 当前的启动分流状态（由当前工作空间 provider 推出；它依赖本机数据库）。
  AppGateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appGateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appGateHash();

  @$internal
  @override
  $ProviderElement<AppGate> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppGate create(Ref ref) {
    return appGate(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppGate value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppGate>(value),
    );
  }
}

String _$appGateHash() => r'17abf4db7135e3963b0dc6d6faceeb858cc3293d';
