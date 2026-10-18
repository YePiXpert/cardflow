// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'diagnostic_log.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 全局诊断日志（整个 App 生命周期内唯一）。

@ProviderFor(diagnosticLog)
final diagnosticLogProvider = DiagnosticLogProvider._();

/// 全局诊断日志（整个 App 生命周期内唯一）。

final class DiagnosticLogProvider
    extends $FunctionalProvider<DiagnosticLog, DiagnosticLog, DiagnosticLog>
    with $Provider<DiagnosticLog> {
  /// 全局诊断日志（整个 App 生命周期内唯一）。
  DiagnosticLogProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'diagnosticLogProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$diagnosticLogHash();

  @$internal
  @override
  $ProviderElement<DiagnosticLog> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DiagnosticLog create(Ref ref) {
    return diagnosticLog(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DiagnosticLog value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DiagnosticLog>(value),
    );
  }
}

String _$diagnosticLogHash() => r'e8fa7ec44cfd51ba97b4a2eeb6bd4a3247b0dee7';
