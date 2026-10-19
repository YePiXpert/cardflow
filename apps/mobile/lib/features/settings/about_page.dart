import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/feedback.dart';
import '../../app/widgets/state_views.dart';
import '../diagnostics/app_diagnostics.dart';
import 'public_beta.dart';

/// 「关于」（我的 › 关于卡序）：App 名称、版本与构建号（与诊断页同一来源：package_info_plus）、
/// "公测版"标识、公测说明、源码地址（纯文本，可选中复制，不打开浏览器）、反馈方式。
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  /// 页名，同时是"我的"页里的入口文字。
  static const String title = '关于卡序';

  /// 复制源码地址后的轻提示。
  static const String copiedMessage = '已复制源码地址';

  /// 版本的显示文字（与诊断页"版本"一行相同）。
  static String versionText(AsyncValue<AppDiagnostics> app) => switch (app) {
    AsyncData(:final value) => '${value.version}（构建 ${value.buildNumber}）',
    AsyncError(:final error) => '读取失败（${error.runtimeType}）',
    _ => '读取中…',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appDiagnosticsProvider);
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: CardFlowColors.of(context).textSecondary,
    );
    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: CfSpace.xl),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CfSpace.md,
              CfSpace.md,
              CfSpace.md,
              CfSpace.xs,
            ),
            child: Wrap(
              spacing: CfSpace.sm,
              runSpacing: CfSpace.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Semantics(
                  header: true,
                  child: Text(
                    PublicBeta.appName,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                const StatusBadge(
                  label: PublicBeta.badge,
                  icon: Icons.new_releases_outlined,
                  tone: NoticeTone.attention,
                ),
              ],
            ),
          ),
          LabeledValue(label: '版本', value: Text(versionText(app))),
          const SectionTitle(PublicBeta.noteTitle),
          const PublicBetaNotice(),
          const SectionTitle('源码'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
            // 可长按选中（读屏可操作），所以按触控目标给足最小高度。
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: CfTouch.minTarget),
              child: SelectableText(
                PublicBeta.sourceAddress,
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: Text('App 内不打开浏览器：可长按选中，或复制后在浏览器里打开。', style: secondary),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CfSpace.md,
              vertical: CfSpace.xs,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () => unawaited(_copySource(context)),
                icon: const Icon(Icons.copy_outlined),
                label: const Text('复制源码地址'),
              ),
            ),
          ),
          const SectionTitle('反馈'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: Text(PublicBeta.feedback, style: theme.textTheme.bodyLarge),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CfSpace.md,
              vertical: CfSpace.xs,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () => context.go(AppRoutes.diagnostics),
                icon: const Icon(Icons.monitor_heart_outlined),
                label: const Text('打开诊断信息'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _copySource(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(
      const ClipboardData(text: PublicBeta.sourceAddress),
    );
    showFeedback(messenger, copiedMessage);
  }
}
