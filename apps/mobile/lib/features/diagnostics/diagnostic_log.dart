import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'diagnostic_log.g.dart';

/// 诊断日志级别。界面上用文字区分，不只靠颜色。
enum LogLevel {
  info('I', '信息'),
  warning('W', '警告'),
  error('E', '错误');

  const LogLevel(this.code, this.label);

  /// 报告里的单字母代码。
  final String code;

  /// 界面上的中文标签。
  final String label;
}

/// 一条诊断日志。时间为 UTC。
@immutable
class DiagnosticEntry {
  const DiagnosticEntry({
    required this.time,
    required this.level,
    required this.category,
    required this.event,
    this.detail,
    this.frames = const <String>[],
  });

  final DateTime time;
  final LogLevel level;

  /// 模块标识，如 `app`、`route`、`flutter`。
  final String category;

  /// 事件标识，如 `launch`、`changed`、`uncaught`。
  final String event;

  /// 已脱敏的补充说明（数字已替换为 `#`）。
  final String? detail;

  /// 代码位置（`package:…/x.dart:行:列`），只在错误条目里出现。
  final List<String> frames;

  /// 报告中的文本形式。
  String toReportText() {
    final buffer = StringBuffer()
      ..write(time.toIso8601String())
      ..write(' ')
      ..write(level.code)
      ..write(' ')
      ..write(category)
      ..write('/')
      ..write(event);
    if (detail != null) {
      buffer
        ..write(' ')
        ..write(detail);
    }
    for (final frame in frames) {
      buffer
        ..write('\n    at ')
        ..write(frame);
    }
    return buffer.toString();
  }
}

/// 内存环形诊断日志：最多保留 [capacity]（默认 500）条，满了丢弃最早的一条。
///
/// 这是没有 Mac 时唯一的真机反馈渠道（诊断页"复制诊断信息"）。为保证报告里
/// 不出现金额与正文：
/// - `category`、`event` 只能是小写字母、下划线和点（不允许数字），应当是代码里的常量；
/// - `detail` 只保留首行，所有数字替换为 `#`，并截断到 [maxDetailLength] 个字符；
/// - 错误只记异常类型、框架给出的摘要（同样脱敏）与代码位置，不记异常正文。
///
/// 只保存在内存中，App 重启后清空，不写磁盘、不外发。
class DiagnosticLog extends ChangeNotifier {
  DiagnosticLog({this.capacity = defaultCapacity, DateTime Function()? clock})
    : assert(capacity > 0, 'capacity must be positive'),
      _clock = clock ?? DateTime.now;

  /// 默认容量。
  static const int defaultCapacity = 500;

  /// `detail` 的最大字符数。
  static const int maxDetailLength = 120;

  /// 每条错误最多保留的代码位置数。
  static const int maxFrames = 6;

  /// 合法的 `category` / `event`。
  static final RegExp identifierPattern = RegExp(r'^[a-z][a-z_.]*$');

  final int capacity;
  final DateTime Function() _clock;
  final ListQueue<DiagnosticEntry> _entries = ListQueue<DiagnosticEntry>();
  int _droppedCount = 0;
  bool _notifyScheduled = false;
  bool _disposed = false;

  /// 当前保留的日志，按时间从早到晚。
  List<DiagnosticEntry> get entries =>
      List<DiagnosticEntry>.unmodifiable(_entries);

  /// 当前保留的条数。
  int get length => _entries.length;

  /// 因超出容量而丢弃的条数。
  int get droppedCount => _droppedCount;

  void info(String category, String event, {String? detail}) =>
      record(LogLevel.info, category, event, detail: detail);

  void warning(String category, String event, {String? detail}) =>
      record(LogLevel.warning, category, event, detail: detail);

  void error(String category, String event, {String? detail}) =>
      record(LogLevel.error, category, event, detail: detail);

  /// 记录一条日志。`frames` 必须是 [codeLocations] 的结果。
  void record(
    LogLevel level,
    String category,
    String event, {
    String? detail,
    List<String> frames = const <String>[],
  }) {
    assert(
      identifierPattern.hasMatch(category),
      'category 只能含小写字母、下划线和点：$category',
    );
    assert(identifierPattern.hasMatch(event), 'event 只能含小写字母、下划线和点：$event');
    final entry = DiagnosticEntry(
      time: _clock().toUtc(),
      level: level,
      category: sanitizeIdentifier(category),
      event: sanitizeIdentifier(event),
      detail: detail == null ? null : sanitizeDetail(detail),
      frames: List<String>.unmodifiable(frames.take(maxFrames)),
    );
    if (_entries.length >= capacity) {
      _entries.removeFirst();
      _droppedCount++;
    }
    _entries.addLast(entry);
    _scheduleNotify();
  }

  /// 记录一个未捕获的错误：异常类型 + 脱敏摘要 + 代码位置。
  void recordError(
    String category,
    Object error,
    StackTrace? stack, {
    String? summary,
  }) {
    final type = error.runtimeType.toString();
    record(
      LogLevel.error,
      category,
      'uncaught',
      detail: summary == null ? type : '$type: $summary',
      frames: codeLocations(stack),
    );
  }

  // 日志可能在构建/布局阶段被写入（例如框架错误回调），此时不能同步通知界面重建，
  // 所以合并到一个微任务里通知。
  void _scheduleNotify() {
    if (_notifyScheduled || _disposed) {
      return;
    }
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 把标识符中不允许的字符替换为 `_`（debug 下已由断言拦截，这里是 release 兜底）。
String sanitizeIdentifier(String raw) {
  final cleaned = raw.toLowerCase().replaceAll(RegExp('[^a-z_.]'), '_');
  return cleaned.isEmpty ? 'unknown' : cleaned;
}

final RegExp _anyDigit = RegExp(r'[0-9０-９]');
final RegExp _controlChars = RegExp(r'[\u0000-\u001F\u007F]');

/// 详情脱敏：只取首行；所有数字（含全角）替换为 `#`；控制字符替换为空格；
/// 截断到 [DiagnosticLog.maxDetailLength] 个字符。
String sanitizeDetail(String raw) {
  final firstLine = raw.split(RegExp(r'[\r\n]')).first;
  final masked = firstLine
      .replaceAll(_anyDigit, '#')
      .replaceAll(_controlChars, ' ')
      .trim();
  final runes = masked.runes;
  if (runes.length <= DiagnosticLog.maxDetailLength) {
    return masked;
  }
  return '${String.fromCharCodes(runes.take(DiagnosticLog.maxDetailLength))}…';
}

final RegExp _vmFrameLocation = RegExp(
  r'\(((?:package|dart):[^\s()]+:\d+(?::\d+)?)\)',
);

/// 从调用栈中只提取代码位置（`package:`/`dart:` URI 与行列号），丢弃其余文字。
List<String> codeLocations(
  StackTrace? stack, {
  int max = DiagnosticLog.maxFrames,
}) {
  if (stack == null) {
    return const <String>[];
  }
  return _vmFrameLocation
      .allMatches(stack.toString())
      .map((m) => m.group(1)!)
      .take(max)
      .toList(growable: false);
}

/// 全局诊断日志（整个 App 生命周期内唯一）。
@Riverpod(keepAlive: true)
DiagnosticLog diagnosticLog(Ref ref) {
  final log = DiagnosticLog();
  ref.onDispose(log.dispose);
  return log;
}
