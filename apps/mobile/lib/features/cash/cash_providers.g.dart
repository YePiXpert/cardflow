// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cash_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// [accountId] 在 [date]（`YYYY-MM-DD`）这一天的未删除收支。

@ProviderFor(sameDayCashEvents)
final sameDayCashEventsProvider = SameDayCashEventsFamily._();

/// [accountId] 在 [date]（`YYYY-MM-DD`）这一天的未删除收支。

final class SameDayCashEventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<SameDayEvents>,
          SameDayEvents,
          FutureOr<SameDayEvents>
        >
    with $FutureModifier<SameDayEvents>, $FutureProvider<SameDayEvents> {
  /// [accountId] 在 [date]（`YYYY-MM-DD`）这一天的未删除收支。
  SameDayCashEventsProvider._({
    required SameDayCashEventsFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: noDatabaseRetry,
         name: r'sameDayCashEventsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sameDayCashEventsHash();

  @override
  String toString() {
    return r'sameDayCashEventsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<SameDayEvents> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<SameDayEvents> create(Ref ref) {
    final argument = this.argument as (String, String);
    return sameDayCashEvents(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is SameDayCashEventsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sameDayCashEventsHash() => r'f39e8cdb68ca8ff9610063c544edff716b4a1ee2';

/// [accountId] 在 [date]（`YYYY-MM-DD`）这一天的未删除收支。

final class SameDayCashEventsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<SameDayEvents>, (String, String)> {
  SameDayCashEventsFamily._()
    : super(
        retry: noDatabaseRetry,
        name: r'sameDayCashEventsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// [accountId] 在 [date]（`YYYY-MM-DD`）这一天的未删除收支。

  SameDayCashEventsProvider call(String accountId, String date) =>
      SameDayCashEventsProvider._(argument: (accountId, date), from: this);

  @override
  String toString() => r'sameDayCashEventsProvider';
}

/// 按 id 取一笔未删除的收支；不在当前空间时失败（NotFoundException）。

@ProviderFor(cashEventEntry)
final cashEventEntryProvider = CashEventEntryFamily._();

/// 按 id 取一笔未删除的收支；不在当前空间时失败（NotFoundException）。

final class CashEventEntryProvider
    extends
        $FunctionalProvider<
          AsyncValue<CashEventEntry>,
          CashEventEntry,
          FutureOr<CashEventEntry>
        >
    with $FutureModifier<CashEventEntry>, $FutureProvider<CashEventEntry> {
  /// 按 id 取一笔未删除的收支；不在当前空间时失败（NotFoundException）。
  CashEventEntryProvider._({
    required CashEventEntryFamily super.from,
    required String super.argument,
  }) : super(
         retry: noDatabaseRetry,
         name: r'cashEventEntryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$cashEventEntryHash();

  @override
  String toString() {
    return r'cashEventEntryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<CashEventEntry> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<CashEventEntry> create(Ref ref) {
    final argument = this.argument as String;
    return cashEventEntry(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CashEventEntryProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$cashEventEntryHash() => r'391cfcca511654e10e66bd53b5191da142d2c76d';

/// 按 id 取一笔未删除的收支；不在当前空间时失败（NotFoundException）。

final class CashEventEntryFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<CashEventEntry>, String> {
  CashEventEntryFamily._()
    : super(
        retry: noDatabaseRetry,
        name: r'cashEventEntryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 按 id 取一笔未删除的收支；不在当前空间时失败（NotFoundException）。

  CashEventEntryProvider call(String eventId) =>
      CashEventEntryProvider._(argument: eventId, from: this);

  @override
  String toString() => r'cashEventEntryProvider';
}
