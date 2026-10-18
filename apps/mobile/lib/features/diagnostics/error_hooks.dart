import 'package:flutter/foundation.dart';

import '../../app/diagnostics/diagnostic_log.dart';

/// 把未捕获的错误记入诊断日志。
///
/// 只记录异常类型、代码位置，以及开发者可控的摘要：框架错误（[FlutterError]）
/// 与断言（[AssertionError]）的首行说明，且经过 [sanitizeDetail] 脱敏。
/// 其他异常的正文可能含有用户输入，一律不记。
///
/// [releaseMode]（默认 [kReleaseMode]）为 true 时，错误**只**进内存环形日志（已脱敏）：
/// 不再交给原来的处理器（`FlutterError.onError` 的默认实现会把异常正文打印到系统日志），
/// `PlatformDispatcher.onError` 返回 true（告诉引擎已处理，引擎就不会再打印一次）。
/// security-privacy §3 CODE："调试日志在 Release 关闭"；审查 R-08。
/// debug/profile 下保持原有行为（控制台输出），便于开发。
void installErrorHooks(
  DiagnosticLog log, {
  PlatformDispatcher? dispatcher,
  bool releaseMode = kReleaseMode,
}) {
  var recording = false;
  void safeRecord(String category, Object error, StackTrace? stack) {
    if (recording) {
      return;
    }
    recording = true;
    try {
      log.recordError(category, error, stack, summary: _summaryOf(error));
    } on Object {
      // 记录诊断日志本身失败时只能放弃，不能再抛出，否则会形成错误循环。
    } finally {
      recording = false;
    }
  }

  final previousFlutterOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    safeRecord('flutter', details.exception, details.stack);
    if (!releaseMode) {
      previousFlutterOnError?.call(details);
    }
  };

  final platformDispatcher = dispatcher ?? PlatformDispatcher.instance;
  final previousPlatformOnError = platformDispatcher.onError;
  platformDispatcher.onError = (Object error, StackTrace stack) {
    safeRecord('platform', error, stack);
    if (releaseMode) {
      return true;
    }
    return previousPlatformOnError?.call(error, stack) ?? false;
  };
}

String? _summaryOf(Object error) {
  if (error is FlutterError) {
    return error.message;
  }
  if (error is AssertionError) {
    return error.message?.toString();
  }
  return null;
}
