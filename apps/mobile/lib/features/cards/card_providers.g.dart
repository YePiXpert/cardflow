// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'card_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 新建卡片时的银行选择（内置常用银行 + 用户添加的）。

@ProviderFor(bankChoices)
final bankChoicesProvider = BankChoicesProvider._();

/// 新建卡片时的银行选择（内置常用银行 + 用户添加的）。

final class BankChoicesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<BankChoice>>,
          List<BankChoice>,
          FutureOr<List<BankChoice>>
        >
    with $FutureModifier<List<BankChoice>>, $FutureProvider<List<BankChoice>> {
  /// 新建卡片时的银行选择（内置常用银行 + 用户添加的）。
  BankChoicesProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'bankChoicesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bankChoicesHash();

  @$internal
  @override
  $FutureProviderElement<List<BankChoice>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<BankChoice>> create(Ref ref) {
    return bankChoices(ref);
  }
}

String _$bankChoicesHash() => r'6ba11c44d9ab238547c4415b7e1f24e7699921c5';
