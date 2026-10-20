import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 设计稿的分组卡片（.list）：表面色、圆角 20，子项之间一条分隔线（不跨到卡片边缘）。用在页面左右 16 的
/// 边距里。
class GroupCard extends StatelessWidget {
  const GroupCard({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.symmetric(horizontal: CfSpace.md),
    this.dividerIndent = CfSpace.md,
    this.color,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry margin;

  /// 分隔线左右缩进。
  final double dividerIndent;

  /// 底色；默认表面色。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = CardFlowColors.of(context);
    return Container(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color ?? colors.surface,
        borderRadius: BorderRadius.circular(CfRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0)
              Divider(
                height: CfStroke.hairline,
                indent: dividerIndent,
                endIndent: dividerIndent,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// 顶栏右侧的圆形图标按钮（设计稿 .ico）：可见直径 36、次级表面底、强调色图标；触控区域仍是 48。
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = CardFlowColors.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: CfIconSize.md),
      style: IconButton.styleFrom(
        backgroundColor: colors.surfaceRaised,
        foregroundColor: colors.action,
        fixedSize: const Size.square(CfSize.iconCircle),
        minimumSize: const Size.square(CfSize.iconCircle),
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: const CircleBorder(),
      ),
    );
  }
}

/// 各 Tab 根页的顶栏：左边大标题（32 粗），右边圆形图标按钮。顶栏高度随字号放大，标题不被裁掉。
PreferredSizeWidget largeTitleAppBar(
  BuildContext context, {
  required String title,
  List<Widget> actions = const <Widget>[],
}) {
  final scaled = MediaQuery.textScalerOf(context)
      .scale(CfType.largeTitle.lineHeight);
  return AppBar(
    toolbarHeight: math.max(kToolbarHeight, scaled + CfSpace.sm),
    centerTitle: false,
    titleSpacing: CfSpace.md + CfSpace.xxs,
    title: Text(title, style: Theme.of(context).textTheme.headlineLarge),
    actions: <Widget>[
      ...actions,
      const SizedBox(width: CfSpace.xs),
    ],
  );
}

/// 一列"标签 / 值"（设计稿汇总卡底部的 .kv、金额格）：小字标签在上，值在下。
class KeyValueColumn extends StatelessWidget {
  const KeyValueColumn({
    super.key,
    required this.label,
    required this.value,
    this.labelColor,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final String label;
  final Widget value;
  final Color? labelColor;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: labelColor ?? CardFlowColors.of(context).textSecondary,
            ),
          ),
          const SizedBox(height: CfSpace.xxs / 2),
          value,
        ],
      ),
    );
  }
}
