import 'package:flutter/foundation.dart';

import 'diagnostic_log.dart';

/// 把未捕获的错误记入诊断日志，原有处理（控制台输出等）保持不变。
///
/// 只记录异常类型、代码位置，以及开发者可控的摘要：框架错误（[FlutterError]）
/// 与断言（[AssertionError]）的首行说明，且经过 [sanitizeDetail] 脱敏。
/// 其他异常的正文可能含有用户输入，一律不记。
void installErrorHooks(DiagnosticLog log, {PlatformDispatcher? dispatcher}) {
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
    previousFlutterOnError?.call(details);
  };

  final platformDispatcher = dispatcher ?? PlatformDispatcher.instance;
  final previousPlatformOnError = platformDispatcher.onError;
  platformDispatcher.onError = (Object error, StackTrace stack) {
    safeRecord('platform', error, stack);
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
