import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme/tokens.dart';
import 'app_diagnostics.dart';
import 'crypto_status.dart';
import 'diagnostic_log.dart';
import 'diagnostics_report.dart';

/// 诊断信息页（"我的"Tab 内）：没有 Mac 时唯一的真机反馈渠道。
///
/// 显示 App 版本与构建号、Bundle ID、构建类型、源码版本、系统版本、加密库状态
/// 与内存环形日志；「复制诊断信息」把同样的内容（不含金额与正文）放进剪贴板。
class DiagnosticsPage extends ConsumerWidget {
  const DiagnosticsPage({super.key});

  /// 页名。
  static const String title = '诊断信息';

  /// 复制成功的轻提示。
  static const String copiedMessage = '已复制诊断信息';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appDiagnosticsProvider);
    final crypto = ref.watch(cryptoLibraryStatusProvider);
    final log = ref.watch(diagnosticLogProvider);
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final textScalePercent = MediaQuery.textScalerOf(context)
        .scale(100)
        .round();
    final darkMode = theme.brightness == Brightness.dark;
    final cryptoText = switch (crypto) {
      AsyncData(:final value) => value.displayText,
      AsyncError(:final error) => '读取失败（${error.runtimeType}）',
      _ => '读取中…',
    };

    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: ListenableBuilder(
        listenable: log,
        builder: (context, _) {
          final entries = log.entries;
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: CfSpace.xs),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CfSpace.md,
                  vertical: CfSpace.xs,
                ),
                child: Text(
                  '复制的内容只有版本、系统与本机日志，不含金额与正文，可直接发给开发者。'
                  '日志只保存在内存中，最多 ${log.capacity} 条，重启 App 后清空。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CfSpace.md,
                  vertical: CfSpace.xs,
                ),
                child: FilledButton.icon(
                  onPressed: app.hasValue
                      ? () => unawaited(
                          _copyReport(
                            context: context,
                            log: log,
                            app: app.requireValue,
                            cryptoText: cryptoText,
                            display: DisplayEnvironment(
                              textScalePercent: textScalePercent,
                              darkMode: darkMode,
                            ),
                          ),
                        )
                      : null,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('复制诊断信息'),
                ),
              ),
              const _SectionHeader('应用'),
              ..._appRows(app),
              const _SectionHeader('系统'),
              ..._systemRows(app),
              _InfoRow(label: '文字缩放', value: '$textScalePercent%'),
              _InfoRow(label: '外观', value: darkMode ? '深色' : '浅色'),
              const _SectionHeader('加密本地库'),
              _InfoRow(label: '加密库状态', value: cryptoText),
              _SectionHeader(
                '日志（${entries.length} 条，已丢弃 ${log.droppedCount} 条）',
              ),
              if (entries.isEmpty)
                const _InfoRow(label: '日志', value: '暂无记录')
              else
                for (final entry in entries.reversed) _LogRow(entry),
            ],
          );
        },
      ),
    );
  }

  static List<Widget> _appRows(AsyncValue<AppDiagnostics> app) {
    return switch (app) {
      AsyncData(:final value) => <Widget>[
        _InfoRow(label: '名称', value: value.appName),
        _InfoRow(
          label: '版本',
          value: '${value.version}（构建 ${value.buildNumber}）',
        ),
        _InfoRow(label: 'Bundle ID', value: value.bundleId),
        _InfoRow(label: '构建类型', value: value.buildMode),
        _InfoRow(label: '源码版本', value: value.sourceRevision),
      ],
      AsyncError(:final error) => <Widget>[
        _InfoRow(label: '应用信息', value: '读取失败（${error.runtimeType}）'),
      ],
      _ => const <Widget>[_InfoRow(label: '应用信息', value: '读取中…')],
    };
  }

  static List<Widget> _systemRows(AsyncValue<AppDiagnostics> app) {
    final platform = app.value?.platform;
    if (platform == null) {
      return const <Widget>[_InfoRow(label: '系统', value: '读取中…')];
    }
    return <Widget>[
      _InfoRow(label: '系统', value: '${platform.osName} ${platform.osVersion}'),
      _InfoRow(label: 'Dart', value: platform.dartVersion),
      _InfoRow(label: '语言区域', value: platform.localeName),
    ];
  }

  static Future<void> _copyReport({
    required BuildContext context,
    required DiagnosticLog log,
    required AppDiagnostics app,
    required String cryptoText,
    required DisplayEnvironment display,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final report = buildDiagnosticsReport(
      app: app,
      cryptoStatus: cryptoText,
      display: display,
      entries: log.entries,
      droppedCount: log.droppedCount,
      capacity: log.capacity,
      generatedAt: DateTime.now(),
    );
    await Clipboard.setData(ClipboardData(text: report));
    log.info('diagnostics', 'copied');
    messenger.showSnackBar(const SnackBar(content: Text(copiedMessage)));
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CfSpace.md,
        CfSpace.lg,
        CfSpace.md,
        CfSpace.xs,
      ),
      child: Semantics(
        header: true,
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: ListTile(title: Text(label), subtitle: Text(value)),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow(this.entry);

  final DiagnosticEntry entry;

  static final DateFormat _timeFormat = DateFormat('HH:mm:ss');

  @override
  Widget build(BuildContext context) {
    final colors = CardFlowColors.of(context);
    final levelColor = switch (entry.level) {
      LogLevel.info => colors.textSecondary,
      LogLevel.warning => colors.attention.fg,
      LogLevel.error => colors.danger.fg,
    };
    final detail = entry.detail == null ? '' : ' ${entry.detail}';
    final frames = entry.frames.isEmpty ? '' : '\n${entry.frames.join('\n')}';
    return MergeSemantics(
      child: ListTile(
        title: Text('${entry.category}/${entry.event}$detail$frames'),
        subtitle: Text(
          '${_timeFormat.format(entry.time.toLocal())} · ${entry.level.label}',
          style: TextStyle(color: levelColor),
        ),
      ),
    );
  }
}
