// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_diagnostics.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 读取 App 与系统信息（package_info_plus + dart:io Platform）。

@ProviderFor(appDiagnostics)
final appDiagnosticsProvider = AppDiagnosticsProvider._();

/// 读取 App 与系统信息（package_info_plus + dart:io Platform）。

final class AppDiagnosticsProvider
    extends
        $FunctionalProvider<
          AsyncValue<AppDiagnostics>,
          AppDiagnostics,
          FutureOr<AppDiagnostics>
        >
    with $FutureModifier<AppDiagnostics>, $FutureProvider<AppDiagnostics> {
  /// 读取 App 与系统信息（package_info_plus + dart:io Platform）。
  AppDiagnosticsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appDiagnosticsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appDiagnosticsHash();

  @$internal
  @override
  $FutureProviderElement<AppDiagnostics> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AppDiagnostics> create(Ref ref) {
    return appDiagnostics(ref);
  }
}

String _$appDiagnosticsHash() => r'ccd51c09c39a4bf77a9a685f618787306a36eea5';
