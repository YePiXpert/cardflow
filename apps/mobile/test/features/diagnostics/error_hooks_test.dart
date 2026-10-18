import 'dart:ui' show ErrorCallback, PlatformDispatcher;

import 'package:cardflow/features/diagnostics/diagnostic_log.dart';
import 'package:cardflow/features/diagnostics/error_hooks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FlutterExceptionHandler? savedFlutterOnError;
  late ErrorCallback? savedPlatformOnError;

  setUp(() {
    savedFlutterOnError = FlutterError.onError;
    savedPlatformOnError = PlatformDispatcher.instance.onError;
  });

  tearDown(() {
    FlutterError.onError = savedFlutterOnError;
    PlatformDispatcher.instance.onError = savedPlatformOnError;
  });

  DiagnosticLog newLog() {
    final log = DiagnosticLog();
    addTearDown(log.dispose);
    return log;
  }

  test('框架错误：记类型与脱敏后的首行摘要，并继续交给原处理器', () {
    final forwarded = <FlutterErrorDetails>[];
    FlutterError.onError = forwarded.add;
    final log = newLog();
    installErrorHooks(log);

    FlutterError.onError!(
      FlutterErrorDetails(
        exception: FlutterError(
          'A RenderFlex overflowed by 42 pixels on the right.\n'
          'The relevant error-causing widget was: Text("¥8,000.00")',
        ),
        stack: StackTrace.current,
      ),
    );

    expect(forwarded, hasLength(1));
    final entry = log.entries.single;
    expect(entry.category, 'flutter');
    expect(entry.level, LogLevel.error);
    expect(
      entry.detail,
      'FlutterError: A RenderFlex overflowed by ## pixels on the right.',
    );
    expect(entry.toReportText(), isNot(contains('8,000')));
  });

  test('断言错误：记断言说明（脱敏）', () {
    FlutterError.onError = (_) {};
    final log = newLog();
    installErrorHooks(log);

    FlutterError.onError!(
      FlutterErrorDetails(exception: AssertionError('负数金额必须带语义词，见 §3.1')),
    );

    expect(log.entries.single.detail, 'AssertionError: 负数金额必须带语义词，见 §#.#');
  });

  test('其他异常只记类型；返回原处理器的结果', () {
    PlatformDispatcher.instance.onError = (error, stack) => true;
    final log = newLog();
    installErrorHooks(log);

    final handled = PlatformDispatcher.instance.onError!(
      StateError('用户输入：张三 6222020200112233445'),
      StackTrace.current,
    );

    expect(handled, isTrue);
    final entry = log.entries.single;
    expect(entry.category, 'platform');
    expect(entry.detail, 'StateError');
    expect(entry.toReportText(), isNot(contains('张三')));
  });

  test('没有原处理器时返回 false，保持默认处理', () {
    PlatformDispatcher.instance.onError = null;
    final log = newLog();
    installErrorHooks(log);

    expect(
      PlatformDispatcher.instance.onError!(Exception('x'), StackTrace.empty),
      isFalse,
    );
    expect(log.entries.single.detail, '_Exception');
  });
}
