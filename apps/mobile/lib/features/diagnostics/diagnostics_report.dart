import 'package:flutter/foundation.dart';

import 'app_diagnostics.dart';
import 'diagnostic_log.dart';

/// 打开诊断页时的显示环境（便于定位大字号、深色模式下的界面问题）。
@immutable
class DisplayEnvironment {
  const DisplayEnvironment({
    required this.textScalePercent,
    required this.darkMode,
  });

  /// 系统文字缩放，百分比。
  final int textScalePercent;

  /// 是否处于深色模式。
  final bool darkMode;
}

/// 生成"复制诊断信息"的文本：版本、系统、构建、加密本地库状态、数据库基准与脱敏日志。
///
/// 不含金额与正文：日志条目在写入时已脱敏（见 [DiagnosticLog]），其余字段都是
/// 构建、系统与加密库元数据；数据库密钥只报告"已生成/未生成"，不含任何密钥内容。
/// 数据库基准是由 SQLite 生成的合成数据的耗时（毫秒），可以含数字。
String buildDiagnosticsReport({
  required AppDiagnostics app,
  required String cryptoStatus,
  required String databaseKeyStatus,
  required String databaseBenchmark,
  required DisplayEnvironment display,
  required List<DiagnosticEntry> entries,
  required int droppedCount,
  required int capacity,
  required DateTime generatedAt,
}) {
  final buffer = StringBuffer()
    ..writeln('卡序 CardFlow 诊断信息')
    ..writeln('生成时间：${generatedAt.toUtc().toIso8601String()}')
    ..writeln('应用：${app.appName} ${app.version}（构建 ${app.buildNumber}）')
    ..writeln('Bundle ID：${app.bundleId}')
    ..writeln('构建类型：${app.buildMode}')
    ..writeln('源码版本：${app.sourceRevision}')
    ..writeln('系统：${app.platform.osName} ${app.platform.osVersion}')
    ..writeln('Dart：${app.platform.dartVersion}')
    ..writeln('语言区域：${app.platform.localeName}')
    ..writeln('文字缩放：${display.textScalePercent}%')
    ..writeln('外观：${display.darkMode ? '深色' : '浅色'}')
    ..writeln('加密库状态：$cryptoStatus')
    ..writeln('数据库密钥：$databaseKeyStatus')
    ..writeln('数据库基准：$databaseBenchmark')
    ..writeln(
      '日志：${entries.length} 条（上限 $capacity 条，'
      '已丢弃 $droppedCount 条较早记录；时间为 UTC）',
    );
  for (final entry in entries) {
    buffer.writeln(entry.toReportText());
  }
  return buffer.toString();
}
