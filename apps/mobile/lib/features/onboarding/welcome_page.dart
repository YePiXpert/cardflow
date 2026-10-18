import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../app/widgets/first_run_empty_state.dart';

/// P-22 首次使用/欢迎（ui-spec §6）。
///
/// 本阶段只展示使用边界与五种开始方式（均未开放）。"无工作空间时先进 P-22"
/// 的启动分流要等本地库与工作空间就绪（I-1）后再接入。
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  /// 页名。
  static const String title = '欢迎使用卡序';

  /// ui-spec P-22 布局"欢迎"区的四条边界。
  static const List<String> boundaries = <String>[
    '无需注册',
    '不发起支付',
    '结果可解释',
    '不实时同步银行',
  ];

  /// ui-spec P-22 的五种开始方式。
  static const List<String> startOptions = <String>[
    '手工建卡',
    '从账单开始',
    '从备份恢复',
    '体验演示',
    '连接服务器',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(CfSpace.md),
        children: <Widget>[
          Text('使用边界', style: theme.textTheme.titleMedium),
          const SizedBox(height: CfSpace.xs),
          for (final item in boundaries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: CfSpace.xxs),
              child: Row(
                children: <Widget>[
                  ExcludeSemantics(
                    child: Icon(
                      Icons.check_circle_outline,
                      size: CfIconSize.md,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: CfSpace.xs),
                  Expanded(child: Text(item, style: theme.textTheme.bodyLarge)),
                ],
              ),
            ),
          const SizedBox(height: CfSpace.lg),
          Text('开始方式', style: theme.textTheme.titleMedium),
          const SizedBox(height: CfSpace.xs),
          for (final option in startOptions)
            Padding(
              padding: const EdgeInsets.only(bottom: CfTouch.minGap),
              child: OutlinedButton(onPressed: null, child: Text(option)),
            ),
          const SizedBox(height: CfSpace.xxs),
          Text(
            notYetAvailableNote,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
