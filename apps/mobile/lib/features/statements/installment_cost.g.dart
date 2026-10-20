// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'installment_cost.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 默认放到后台 isolate（原生平台 `Isolate.run`）。组件测试在伪时钟里等不到 isolate，`pumpCardFlowApp`
/// 默认换成就地计算；R-04 的测试用真正的后台 isolate。

@ProviderFor(installmentCostRunner)
final installmentCostRunnerProvider = InstallmentCostRunnerProvider._();

/// 默认放到后台 isolate（原生平台 `Isolate.run`）。组件测试在伪时钟里等不到 isolate，`pumpCardFlowApp`
/// 默认换成就地计算；R-04 的测试用真正的后台 isolate。

final class InstallmentCostRunnerProvider
    extends
        $FunctionalProvider<
          InstallmentCostRunner,
          InstallmentCostRunner,
          InstallmentCostRunner
        >
    with $Provider<InstallmentCostRunner> {
  /// 默认放到后台 isolate（原生平台 `Isolate.run`）。组件测试在伪时钟里等不到 isolate，`pumpCardFlowApp`
  /// 默认换成就地计算；R-04 的测试用真正的后台 isolate。
  InstallmentCostRunnerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'installmentCostRunnerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$installmentCostRunnerHash();

  @$internal
  @override
  $ProviderElement<InstallmentCostRunner> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  InstallmentCostRunner create(Ref ref) {
    return installmentCostRunner(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(InstallmentCostRunner value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<InstallmentCostRunner>(value),
    );
  }
}

String _$installmentCostRunnerHash() =>
    r'0cb6d09413374d82a89010542c227df7b25d81e0';

/// 某分期计划的成本：按计划 id 记忆化（条款与各期金额都不可改），第一次用到时在后台 isolate 里算。

@ProviderFor(installmentCost)
final installmentCostProvider = InstallmentCostFamily._();

/// 某分期计划的成本：按计划 id 记忆化（条款与各期金额都不可改），第一次用到时在后台 isolate 里算。

final class InstallmentCostProvider
    extends
        $FunctionalProvider<
          AsyncValue<InstallmentCost>,
          InstallmentCost,
          FutureOr<InstallmentCost>
        >
    with $FutureModifier<InstallmentCost>, $FutureProvider<InstallmentCost> {
  /// 某分期计划的成本：按计划 id 记忆化（条款与各期金额都不可改），第一次用到时在后台 isolate 里算。
  InstallmentCostProvider._({
    required InstallmentCostFamily super.from,
    required String super.argument,
  }) : super(
         retry: noDatabaseRetry,
         name: r'installmentCostProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$installmentCostHash();

  @override
  String toString() {
    return r'installmentCostProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<InstallmentCost> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<InstallmentCost> create(Ref ref) {
    final argument = this.argument as String;
    return installmentCost(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is InstallmentCostProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$installmentCostHash() => r'f474daa4f2e3a14d56edf73b7e84ac7bafd5f7a4';

/// 某分期计划的成本：按计划 id 记忆化（条款与各期金额都不可改），第一次用到时在后台 isolate 里算。

final class InstallmentCostFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<InstallmentCost>, String> {
  InstallmentCostFamily._()
    : super(
        retry: noDatabaseRetry,
        name: r'installmentCostProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// 某分期计划的成本：按计划 id 记忆化（条款与各期金额都不可改），第一次用到时在后台 isolate 里算。

  InstallmentCostProvider call(String planId) =>
      InstallmentCostProvider._(argument: planId, from: this);

  @override
  String toString() => r'installmentCostProvider';
}
