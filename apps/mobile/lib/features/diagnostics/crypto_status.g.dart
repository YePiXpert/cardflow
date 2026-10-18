// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'crypto_status.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 诊断页读取的加密库状态。
///
/// 下一任务（I0-5，加密 drift）把函数体换成真实检查：打开加密库 →
/// 执行 `PRAGMA cipher_version` → 非空返回 [CryptoLibraryReady]，否则返回
/// [CryptoLibraryUnavailable]。诊断页与报告无需改动。

@ProviderFor(cryptoLibraryStatus)
final cryptoLibraryStatusProvider = CryptoLibraryStatusProvider._();

/// 诊断页读取的加密库状态。
///
/// 下一任务（I0-5，加密 drift）把函数体换成真实检查：打开加密库 →
/// 执行 `PRAGMA cipher_version` → 非空返回 [CryptoLibraryReady]，否则返回
/// [CryptoLibraryUnavailable]。诊断页与报告无需改动。

final class CryptoLibraryStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<CryptoLibraryStatus>,
          CryptoLibraryStatus,
          FutureOr<CryptoLibraryStatus>
        >
    with
        $FutureModifier<CryptoLibraryStatus>,
        $FutureProvider<CryptoLibraryStatus> {
  /// 诊断页读取的加密库状态。
  ///
  /// 下一任务（I0-5，加密 drift）把函数体换成真实检查：打开加密库 →
  /// 执行 `PRAGMA cipher_version` → 非空返回 [CryptoLibraryReady]，否则返回
  /// [CryptoLibraryUnavailable]。诊断页与报告无需改动。
  CryptoLibraryStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cryptoLibraryStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cryptoLibraryStatusHash();

  @$internal
  @override
  $FutureProviderElement<CryptoLibraryStatus> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<CryptoLibraryStatus> create(Ref ref) {
    return cryptoLibraryStatus(ref);
  }
}

String _$cryptoLibraryStatusHash() =>
    r'a7be2cc82d782abbd34f7c22aa2ddfcfe35632ff';
