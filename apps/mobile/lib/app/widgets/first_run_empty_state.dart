import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'calm_panel.dart';

/// 首次空白态里的一个操作。`onPressed` 为 null 表示该功能尚未开放，[stage] 注明何时提供。
@immutable
class EmptyStateAction {
  const EmptyStateAction({required this.label, this.onPressed, this.stage});

  final String label;
  final VoidCallback? onPressed;

  /// 未开放时的说明，如"后续版本提供"（界面上不写内部阶段代号）。
  final String? stage;
}

/// 未开放、又没有注明阶段的操作旁边的统一说明。
const String notYetAvailableNote = '尚未开放：功能将在后续版本提供。';

/// ui-spec §2"首次空白"：图标 + 页面文案 + 一句用途 + 主操作。
///
/// 第一个操作是主操作（实心按钮），其余为次要操作（描边按钮）。
/// 有任何操作尚未开放时，在按钮下方给出 [notYetAvailableNote]，不让按钮"点了没反应"。
/// 内容可滚动、不设固定高度，200% 字号下换行而不截断（ui-spec §3.3）。
class FirstRunEmptyState extends StatelessWidget {
  const FirstRunEmptyState({
    super.key,
    required this.icon,
    required this.message,
    required this.purpose,
    this.actions = const <EmptyStateAction>[],
    this.scrollable = true,
    this.largePrimary = false,
  });

  /// 主操作用大号按钮（卡账首页"添加第一张卡"）。
  final bool largePrimary;

  /// false：放在已有的滚动列表里时不再自带滚动。
  final bool scrollable;

  /// 主图标（装饰性，读屏跳过；含义由文字承载）。
  final IconData icon;

  /// 该页"首次空白"文案，如"还没有信用账户"。
  final String message;

  /// 一句用途，取自 ui-spec 该页的"目的"。
  final String purpose;

  /// 主操作与次要操作。
  final List<EmptyStateAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final hasUnavailable = actions.any(
      (a) => a.onPressed == null && a.stage == null,
    );
    final content = Padding(
      padding: const EdgeInsets.all(CfSpace.md),
      child: CalmPanel(
        padding: const EdgeInsets.all(CfSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: ExcludeSemantics(
                child: Container(
                  width: CfTouch.minTarget,
                  height: CfTouch.minTarget,
                  decoration: BoxDecoration(
                    color: colors.actionTint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: CfIconSize.lg, color: colors.action),
                ),
              ),
            ),
            const SizedBox(height: CfSpace.md),
            Text(
              message,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: CfSpace.xs),
            Text(
              purpose,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (actions.isNotEmpty) const SizedBox(height: CfSpace.lg),
            for (var i = 0; i < actions.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: CfTouch.minGap),
              if (i == 0)
                FilledButton(
                  style: largePrimary
                      ? FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(
                            CfTouch.minTarget + CfSpace.xs,
                          ),
                          textStyle: theme.textTheme.titleMedium,
                        )
                      : null,
                  onPressed: actions[i].onPressed,
                  child: Text(actions[i].label, textAlign: TextAlign.center),
                )
              else
                OutlinedButton(
                  onPressed: actions[i].onPressed,
                  child: Text(actions[i].label, textAlign: TextAlign.center),
                ),
              if (actions[i].onPressed == null && actions[i].stage != null)
                Padding(
                  padding: const EdgeInsets.only(top: CfSpace.xxs),
                  child: Text(
                    '${actions[i].label}：${actions[i].stage}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
            if (hasUnavailable) ...<Widget>[
              const SizedBox(height: CfSpace.sm),
              Text(
                notYetAvailableNote,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
    return scrollable ? SingleChildScrollView(child: content) : content;
  }
}
