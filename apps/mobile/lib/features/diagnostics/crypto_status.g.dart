// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'crypto_status.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 诊断页读取的加密库状态：打开本机加密数据库（`openedDatabaseProvider`）的结果。

@ProviderFor(cryptoLibraryStatus)
final cryptoLibraryStatusProvider = CryptoLibraryStatusProvider._();

/// 诊断页读取的加密库状态：打开本机加密数据库（`openedDatabaseProvider`）的结果。

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
  /// 诊断页读取的加密库状态：打开本机加密数据库（`openedDatabaseProvider`）的结果。
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
    r'fb0872bd552e9a1ec626b6bc88fd1793ba371d31';
