// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'calendar_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 当前工作空间的压力情景（P-07 控制条"情景选择"）。

@ProviderFor(scenarioChoices)
final scenarioChoicesProvider = ScenarioChoicesProvider._();

/// 当前工作空间的压力情景（P-07 控制条"情景选择"）。

final class ScenarioChoicesProvider
    extends
        $FunctionalProvider<
          AsyncValue<ScenarioChoices>,
          ScenarioChoices,
          FutureOr<ScenarioChoices>
        >
    with $FutureModifier<ScenarioChoices>, $FutureProvider<ScenarioChoices> {
  /// 当前工作空间的压力情景（P-07 控制条"情景选择"）。
  ScenarioChoicesProvider._()
    : super(
        from: null,
        argument: null,
        retry: noDatabaseRetry,
        name: r'scenarioChoicesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$scenarioChoicesHash();

  @$internal
  @override
  $FutureProviderElement<ScenarioChoices> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ScenarioChoices> create(Ref ref) {
    return scenarioChoices(ref);
  }
}

String _$scenarioChoicesHash() => r'cf874e346e43b805480e2f0c92ed4e91561edbac';
