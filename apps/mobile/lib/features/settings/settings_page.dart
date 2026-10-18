import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';

/// P-19 我的（设置）根页（ui-spec §6）。
///
/// 本阶段只有：纯本地模式说明（"首次空白"态）、诊断信息入口、欢迎页入口。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  /// 页名，同时是底部导航的标签。
  static const String title = '我的';

  /// ui-spec P-19 九态表"首次空白"（纯本地）。
  static const String firstRunMessage = '未连接服务器（可选）';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: CfSpace.xs),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(CfSpace.md),
            child: MergeSemantics(
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
                        Text(firstRunMessage, style: theme.textTheme.bodyLarge),
                        const SizedBox(height: CfSpace.xxs),
                        Text(
                          '外观、隐私安全、授权与帮助。',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
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
            subtitle: const Text('卡序的使用边界与开始方式'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(AppRoutes.welcome),
          ),
        ],
      ),
    );
  }
}
