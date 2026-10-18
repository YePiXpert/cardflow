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

/// P-04 的附加数据；账户不在当前空间时失败（NotFoundException）。

@ProviderFor(accountSettingsData)
final accountSettingsDataProvider = AccountSettingsDataFamily._();

/// P-04 的附加数据；账户不在当前空间时失败（NotFoundException）。

final class AccountSettingsDataProvider
    extends
        $FunctionalProvider<
          AsyncValue<AccountSettingsData>,
          AccountSettingsData,
          FutureOr<AccountSettingsData>
        >
    with
        $FutureModifier<AccountSettingsData>,
        $FutureProvider<AccountSettingsData> {
  /// P-04 的附加数据；账户不在当前空间时失败（NotFoundException）。
  AccountSettingsDataProvider._({
    required AccountSettingsDataFamily super.from,
    required String super.argument,
  }) : super(
         retry: noDatabaseRetry,
         name: r'accountSettingsDataProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$accountSettingsDataHash();

  @override
  String toString() {
    return r'accountSettingsDataProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<AccountSettingsData> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AccountSettingsData> create(Ref ref) {
    final argument = this.argument as String;
    return accountSettingsData(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AccountSettingsDataProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$accountSettingsDataHash() =>
    r'f0a26190a5e350588a3a1c0ac45bd1aec5553881';

/// P-04 的附加数据；账户不在当前空间时失败（NotFoundException）。

final class AccountSettingsDataFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<AccountSettingsData>, String> {
  AccountSettingsDataFamily._()
    : super(
        retry: noDatabaseRetry,
        name: r'accountSettingsDataProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// P-04 的附加数据；账户不在当前空间时失败（NotFoundException）。

  AccountSettingsDataProvider call(String accountId) =>
      AccountSettingsDataProvider._(argument: accountId, from: this);

  @override
  String toString() => r'accountSettingsDataProvider';
}
