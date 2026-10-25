import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/money/amount_visibility.dart';
import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/cf_layout.dart';
import '../../app/widgets/confirm_dialog.dart';
import '../../app/widgets/state_views.dart';
import '../../data/repositories/models.dart';
import '../../data/repositories/providers.dart';
import '../onboarding/workspace_actions.dart';
import 'about_page.dart';
import 'public_beta.dart';

/// 我的（P-19，简报 U-1 §1、§9）：纯本地说明（"纯本地"从页顶标签挪到这里）、当前空间与演示/真实空间切换、
/// 隐藏金额（ui-spec §3.6）、关于卡序、诊断信息、欢迎与开始方式、重置本地数据（确认页按 ui-spec §4.5，须输入
/// "删除"；设备认证在后续版本）、公测说明。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  /// 页名，同时是底部导航的标签。
  static const String title = '我的';

  /// ui-spec P-19 九态表"首次空白"（纯本地）。
  static const String firstRunMessage = '仅在本机使用';

  /// 纯本地的说明。
  static const String localOnlyNote = '数据只保存在这台 iPhone 上，加密存储，卡序不会上传到任何服务器。';

  /// 隐藏金额开关的说明。
  static const String hideAmountsNote = '开启后所有金额显示为 ••••，保护屏幕隐私';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final workspace = ref.watch(currentWorkspaceProvider).value;
    final demoRows = ref.watch(demoWorkspaceRowsProvider).value;
    final hidden = ref.watch(amountsHiddenProvider);
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: colors.textSecondary,
    );
    final demo = workspace?.kind == WorkspaceKind.demo;
    return Scaffold(
      appBar: largeTitleAppBar(context, title: title),
      body: ListView(
        padding: const EdgeInsets.only(bottom: CfSpace.xl),
        children: <Widget>[
          GroupCard(
            children: <Widget>[
              MergeSemantics(
                child: Padding(
                  padding: const EdgeInsets.all(CfSpace.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      ExcludeSemantics(
                        child: Icon(
                          Icons.cloud_off_outlined,
                          size: CfIconSize.lg,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: CfSpace.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('纯本地', style: theme.textTheme.titleMedium),
                            const SizedBox(height: CfSpace.xxs),
                            Text(
                              firstRunMessage,
                              style: theme.textTheme.bodyLarge,
                            ),
                            const SizedBox(height: CfSpace.xxs),
                            Text(localOnlyNote, style: secondary),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SectionTitle('空间'),
          GroupCard(
            children: <Widget>[
              ListTile(
                leading: Icon(
                  demo ? Icons.science_outlined : Icons.person_outline,
                ),
                title: Text(
                  workspace == null ? '没有当前空间' : '当前：${workspace.kind.label}空间',
                ),
                subtitle: Text(demo ? '当前使用预置示例卡片，与真实数据独立' : '本机加密保存的真实卡片数据'),
              ),
              if (demo)
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('退出演示'),
                  subtitle: const Text('切换回真实卡片列表'),
                  onTap: () => unawaited(_exitDemo(context, ref)),
                )
              else
                ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('体验演示'),
                  subtitle: const Text('查看预置的多卡比较与拆分示例'),
                  onTap: () => unawaited(enterDemoWorkspace(context, ref)),
                ),
              if (demoRows != null)
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('清除演示数据'),
                  subtitle: const Text('删除演示空间的全部数据，真实数据不受影响'),
                  onTap: () =>
                      unawaited(clearDemoWorkspace(context, ref, demoRows)),
                ),
            ],
          ),
          const SectionTitle('隐私'),
          GroupCard(
            children: <Widget>[
              SwitchListTile(
                secondary: const Icon(Icons.visibility_off_outlined),
                title: const Text('隐藏金额'),
                subtitle: const Text(hideAmountsNote),
                value: hidden,
                onChanged: (v) =>
                    ref.read(amountsHiddenProvider.notifier).setHidden(v),
              ),
            ],
          ),
          const SectionTitle('关于与帮助'),
          GroupCard(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text(AboutPage.title),
                subtitle: const Text('版本、公测说明、源码与反馈'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(AppRoutes.about),
              ),
              ListTile(
                leading: const Icon(Icons.monitor_heart_outlined),
                title: const Text('诊断信息'),
                subtitle: const Text('版本、系统与本机日志，用于问题反馈'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(AppRoutes.diagnostics),
              ),
              ListTile(
                leading: const Icon(Icons.waving_hand_outlined),
                title: const Text('欢迎与开始方式'),
                subtitle: const Text('查看功能介绍与演示模式'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(AppRoutes.welcome),
              ),
            ],
          ),
          const SectionTitle('数据'),
          GroupCard(
            children: <Widget>[
              ListTile(
                leading: Icon(
                  Icons.delete_forever_outlined,
                  color: colors.danger.fg,
                ),
                title: Text(
                  '重置本地数据',
                  style: TextStyle(color: colors.danger.fg),
                ),
                subtitle: const Text('删除这台 iPhone 上的全部卡序数据，不可恢复'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(AppRoutes.settingsReset),
              ),
            ],
          ),
          const SectionTitle(PublicBeta.noteTitle),
          const PublicBetaNotice(),
        ],
      ),
    );
  }

  static Future<void> _exitDemo(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmAction(
      context,
      title: '退出演示？',
      message: '退出后将回到你的卡片列表；演示数据保留，可随时在这里「清除演示数据」。',
      confirmLabel: '退出演示',
    );
    if (confirmed) {
      await ref.read(currentWorkspaceProvider.notifier).exitDemo();
    }
  }
}
