import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// ui-spec §2"加载"：静态骨架（没有闪烁动画，减少动效时也不需要特殊处理）。读屏读"读取中"。
class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({super.key, this.rows = 3});

  /// 骨架行数。
  final int rows;

  /// 读屏文字。
  static const String semanticsLabel = '读取中';

  @override
  Widget build(BuildContext context) {
    final colors = CardFlowColors.of(context);
    return Semantics(
      label: semanticsLabel,
      container: true,
      child: ExcludeSemantics(
        child: ListView(
          padding: const EdgeInsets.all(CfSpace.md),
          physics: const NeverScrollableScrollPhysics(),
          children: <Widget>[
            for (var i = 0; i < rows; i++) ...<Widget>[
              Container(
                height: CfTouch.listRowMinHeight * 2,
                decoration: BoxDecoration(
                  color: colors.unknown.bg,
                  borderRadius: BorderRadius.circular(CfRadius.lg),
                ),
              ),
              const SizedBox(height: CfSpace.sm),
            ],
          ],
        ),
      ),
    );
  }
}

/// ui-spec §2"错误"/"重试"：区块内显示错误（带错误码时一并显示），可选「重试」。
class ErrorBlock extends StatelessWidget {
  const ErrorBlock({
    super.key,
    required this.title,
    this.detail,
    this.code,
    this.onRetry,
    this.retryLabel = '重试',
  });

  final String title;

  /// 说明（已保留什么、怎么办）。
  final String? detail;

  /// 错误码或异常类型（只含标识，不含正文）。
  final String? code;

  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        ErrorBlockBody(title: title, code: code, detail: detail),
        if (onRetry != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: FilledButton(onPressed: onRetry, child: Text(retryLabel)),
          ),
      ],
    );
  }
}

/// [ErrorBlock] 的内容部分（不带外层滚动），用在已有滚动容器里。
class ErrorBlockBody extends StatelessWidget {
  const ErrorBlockBody({
    super.key,
    required this.title,
    this.code,
    this.detail,
  });

  final String title;
  final String? code;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(color: colors.danger.fg);
    return Container(
      margin: const EdgeInsets.all(CfSpace.md),
      padding: const EdgeInsets.all(CfSpace.md),
      decoration: BoxDecoration(
        color: colors.danger.bg,
        borderRadius: BorderRadius.circular(CfRadius.lg),
      ),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ExcludeSemantics(
              child: Icon(
                Icons.error_outline,
                size: CfIconSize.lg,
                color: colors.danger.fg,
              ),
            ),
            const SizedBox(width: CfSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.danger.fg,
                    ),
                  ),
                  if (code != null) ...<Widget>[
                    const SizedBox(height: CfSpace.xxs),
                    Text('错误码：$code', style: style),
                  ],
                  if (detail != null) ...<Widget>[
                    const SizedBox(height: CfSpace.xxs),
                    Text(detail!, style: style),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 页面里的区块标题（读屏标为标题）。
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 分组标题 17 粗，比卡片内容多缩进 4（设计稿 .sec）。
      padding: const EdgeInsets.fromLTRB(
        CfSpace.md + CfSpace.xxs,
        CfSpace.md + CfSpace.xxs,
        CfSpace.md,
        CfSpace.xs,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Semantics(
              header: true,
              child: Text(text, style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 语义色调的徽标或提示（图标 + 文字 + 颜色，颜色不单独承载含义，ui-spec §3.1）。
enum NoticeTone { attention, danger, unknown, bank, neutral }

/// 一条提示（数据不全、占位说明、陈旧等）：图标 + 文字，可带一个操作。
class NoticeCard extends StatelessWidget {
  const NoticeCard({
    super.key,
    required this.icon,
    required this.text,
    this.tone = NoticeTone.attention,
    this.action,
    this.margin = defaultMargin,
  });

  final IconData icon;
  final String text;
  final NoticeTone tone;
  final Widget? action;

  /// 外边距；放在本身已有内边距的列表里时可传 [EdgeInsets.zero]。
  final EdgeInsetsGeometry margin;

  /// 默认外边距（与页面内容左右对齐）。
  static const EdgeInsets defaultMargin = EdgeInsets.symmetric(
    horizontal: CfSpace.md,
    vertical: CfSpace.xs,
  );

  @override
  Widget build(BuildContext context) {
    final colors = CardFlowColors.of(context);
    final tones = toneColors(colors, tone);
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(CfSpace.sm),
      decoration: BoxDecoration(
        color: tones.bg,
        borderRadius: BorderRadius.circular(CfRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MergeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ExcludeSemantics(
                  child: Icon(icon, size: CfIconSize.md, color: tones.fg),
                ),
                const SizedBox(width: CfSpace.xs),
                Expanded(
                  child: Text(
                    text,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: tones.fg),
                  ),
                ),
              ],
            ),
          ),
          if (action != null) ...<Widget>[
            const SizedBox(height: CfSpace.xs),
            Align(alignment: AlignmentDirectional.centerStart, child: action),
          ],
        ],
      ),
    );
  }
}

/// 色调 → 前景/底色（只从 token 取）。
CfTone toneColors(CardFlowColors colors, NoticeTone tone) => switch (tone) {
  NoticeTone.attention => colors.attention,
  NoticeTone.danger => colors.danger,
  NoticeTone.unknown => colors.unknown,
  NoticeTone.bank => colors.bank,
  NoticeTone.neutral => CfTone(fg: colors.textSecondary, bg: colors.surface),
};

/// 小徽标：图标 + 文字（如"用户声明""系统估计""超限""已冻结"）。
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.icon,
    this.tone = NoticeTone.unknown,
  });

  final String label;
  final IconData icon;
  final NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = toneColors(CardFlowColors.of(context), tone);
    final style = Theme.of(context).textTheme.labelMedium;
    // 胶囊形状态标签（设计稿 .pill）：图标 + 文字 + 颜色，颜色不单独承载含义。
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CfSpace.xs,
        vertical: CfSpace.xxs / 2,
      ),
      decoration: ShapeDecoration(
        color: colors.bg,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ExcludeSemantics(
            child: Icon(
              icon,
              size: MediaQuery.textScalerOf(context)
                  .scale(style?.fontSize ?? CfIconSize.sm),
              color: colors.fg,
            ),
          ),
          const SizedBox(width: CfSpace.xxs),
          Flexible(
            child: Text(label, style: style?.copyWith(color: colors.fg)),
          ),
        ],
      ),
    );
  }
}

/// 一行"标签：值"（读屏合并朗读）。值可以是任意组件（例如 MoneyText）。
class LabeledValue extends StatelessWidget {
  const LabeledValue({super.key, required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CfSpace.md,
          vertical: CfSpace.xxs,
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: CfSpace.sm,
          children: <Widget>[
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            DefaultTextStyle.merge(
              style: theme.textTheme.bodyLarge,
              child: value,
            ),
          ],
        ),
      ),
    );
  }
}
