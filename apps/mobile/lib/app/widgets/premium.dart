/// 精致化组件：顶部看板、银行卡面、多栏指标、选卡时间轴、提示条与序号圆点。
///
/// 只引用 [CardFlowColors] 与设计 token，不写字面量颜色（卡面颜色来自 [bankColor]）。卡面与看板上的文字一律用
/// 不透明的白色或看板文字色（对每一个渐变色标都不低于 4.5:1，见 `test/app/theme_test.dart` 与
/// `test/app/bank_badge_test.dart`）；装饰性的额度条不承载唯一信息，读屏跳过。
library;

import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/card_wallet_reader.dart';
import '../theme/tokens.dart';
import 'bank_badge.dart';

/// 文字放大到这个倍数以上时，横排的多栏改为纵向堆叠（ui-spec §3.3：≥130% 双列改单列）。
const double _stackScale = 1.3;

/// 当前文字缩放是否需要把多栏改为纵向。
bool useStackedLayout(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) > 10 * _stackScale;

/// 两位数的月-日（"11-28"）。
String monthDay(LocalDate d) =>
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 可用额度占总额度（固定 + 临时）的比例；缺快照、缺容量或总额度为 0 时为 null。
double? capacityFraction(CurrencyAccountView? sub) {
  final snapshot = sub?.latestSnapshot;
  final capacity = sub?.capacity;
  if (snapshot == null || capacity == null) return null;
  final total = snapshot.fixedMinor + snapshot.tempMinor;
  if (total <= 0) return null;
  return (capacity / total).clamp(0, 1).toDouble();
}

/// 顶部深色看板：克制的深岩灰/深蓝底色，无花哨光斑。子组件的文字用 [CardFlowColors.heroText] /
/// [CardFlowColors.heroTextSecondary]。
class HeroPanel extends StatelessWidget {
  const HeroPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = CardFlowColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CfRadius.card),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: c.hero,
        ),
        boxShadow: CfShadow.soft,
      ),
      child: Padding(
        padding: const EdgeInsets.all(CfSpace.md),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: c.heroText),
          child: IconTheme.merge(
            data: IconThemeData(color: c.heroText),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 看板上的胶囊（半透明白底 + 看板主文字）。
class HeroPill extends StatelessWidget {
  const HeroPill({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = CardFlowColors.of(context);
    final t = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.heroText.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(CfRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CfSpace.sm,
          vertical: CfSpace.xxs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: CfIconSize.sm, color: c.heroText),
              const SizedBox(width: CfSpace.xxs),
            ],
            Flexible(
              child: Text(
                label,
                style: t.labelMedium?.copyWith(color: c.heroText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 详情页顶部银行卡头：哑光品牌底色、尾号与可用额度条。
///
/// 卡面上的文字都是不透明白色（[CfBankColors.mark]）：品牌色对白字不低于 4.5:1，渐变只会往更暗的方向走。
class BankCardFace extends StatelessWidget {
  const BankCardFace({
    super.key,
    required this.bankName,
    required this.subtitle,
    required this.last4s,
    this.badge,
    this.badgeIcon,
    this.fraction,
    this.footer,
    this.compact = false,
  });

  /// 银行全名（决定颜色，显示在左上）。
  final String bankName;

  /// 卡名或账户名（"卡 A"）。
  final String subtitle;

  /// 有效卡片的末四位（主卡在前）。
  final List<String> last4s;

  /// 右上角徽章（"共享额度"）。
  final String? badge;

  /// 徽章图标（可选）。
  final IconData? badgeIcon;

  /// 可用额度占比（0–1）；null 时不画额度条。
  final double? fraction;

  /// 卡面底部（额度条上方）的内容，例如可用额度大字。
  final Widget? footer;

  /// 紧凑模式。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final base = bankColor(bankName);
    final shade = Color.lerp(base, CfBankColors.faceShade, .32)!;
    const white = CfBankColors.mark;
    final tailText = last4s.isEmpty
        ? '未记录尾号'
        : last4s.length > 1
        ? '尾号 ${last4s.first} · 共 ${last4s.length} 张'
        : '尾号 ${last4s.first}';
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CfRadius.card),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[base, shade],
        ),
        boxShadow: CfShadow.soft,
      ),
      child: Padding(
        padding: const EdgeInsets.all(CfSpace.md),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: white),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '$bankName · $subtitle',
                          style: t.titleMedium?.copyWith(color: white),
                        ),
                        const SizedBox(height: CfSpace.xxs),
                        Text(
                          tailText,
                          style: t.bodySmall?.copyWith(color: white),
                        ),
                      ],
                    ),
                  ),
                  if (badge != null) ...<Widget>[
                    const SizedBox(width: CfSpace.xs),
                    _FaceBadge(label: badge!, icon: badgeIcon),
                  ],
                ],
              ),
              if (footer != null) ...<Widget>[
                const SizedBox(height: CfSpace.md),
                footer!,
              ],
              if (fraction != null) ...<Widget>[
                const SizedBox(height: CfSpace.sm),
                LimitBar(fraction: fraction!, onCard: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FaceBadge extends StatelessWidget {
  const _FaceBadge({required this.label, this.icon});
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: CfBankColors.faceShade.withValues(alpha: .26),
      borderRadius: BorderRadius.circular(CfRadius.pill),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CfSpace.sm,
        vertical: CfSpace.xxs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: CfIconSize.sm, color: CfBankColors.mark),
            const SizedBox(width: CfSpace.xxs),
          ],
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: CfBankColors.mark),
            ),
          ),
        ],
      ),
    ),
  );
}

/// 额度条：可用占比。卡面上用白色，普通表面上用强调色。
class LimitBar extends StatelessWidget {
  const LimitBar({super.key, required this.fraction, this.onCard = false});

  final double fraction;
  final bool onCard;

  @override
  Widget build(BuildContext context) {
    final c = CardFlowColors.of(context);
    final fill = onCard ? CfBankColors.mark : c.action;
    final track = onCard
        ? CfBankColors.mark.withValues(alpha: .25)
        : c.surfaceRaised;
    return Semantics(
      label: '可用额度占比 ${(fraction * 100).round()}%',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(CfRadius.pill),
        child: SizedBox(
          height: CfStroke.bar,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ColoredBox(color: track),
              FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: fraction,
                child: ColoredBox(color: fill),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一栏指标：标签、主值（大字）与说明。
class Metric {
  const Metric({
    required this.label,
    required this.value,
    this.caption,
    this.emphasized = false,
  });

  final String label;

  /// 主值：文字或 MoneyText。
  final Widget value;
  final String? caption;

  /// 用强调色突出（第一名的"距还款"）。
  final bool emphasized;
}

/// 多栏指标（竖线分隔）；文字放大时纵向堆叠，不溢出、不截断金额。
class MetricRow extends StatelessWidget {
  const MetricRow({super.key, required this.metrics});

  final List<Metric> metrics;

  @override
  Widget build(BuildContext context) {
    final c = CardFlowColors.of(context);
    if (useStackedLayout(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var i = 0; i < metrics.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: CfSpace.sm),
            _MetricCell(metric: metrics[i]),
          ],
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var i = 0; i < metrics.length; i++) ...<Widget>[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: CfSpace.sm),
                child: VerticalDivider(
                  width: CfStroke.hairline,
                  thickness: CfStroke.hairline,
                  color: c.divider,
                ),
              ),
            Expanded(
              flex: i == 0 ? 6 : 5,
              child: _MetricCell(metric: metrics[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.metric});
  final Metric metric;

  @override
  Widget build(BuildContext context) {
    final c = CardFlowColors.of(context);
    final t = Theme.of(context).textTheme;
    final valueStyle = CfType.amountInline.toTextStyle().copyWith(
      fontSize: CfType.groupTitle.size + 1,
      fontWeight: FontWeight.w700,
      color: metric.emphasized ? c.action : c.textPrimary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          metric.label,
          style: t.bodySmall?.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: CfSpace.xxs),
        DefaultTextStyle.merge(style: valueStyle, child: metric.value),
        if (metric.caption != null) ...<Widget>[
          const SizedBox(height: CfSpace.xxs / 2),
          Text(
            metric.caption!,
            style: t.bodySmall?.copyWith(color: c.textSecondary),
          ),
        ],
      ],
    );
  }
}

/// 选卡时间轴：今天刷 → 出账 → 还款，轨道按天数比例分段。
class SwipeTimeline extends StatelessWidget {
  const SwipeTimeline({
    super.key,
    required this.swipeOn,
    required this.statementDate,
    required this.dueDate,
    this.swipeLabel = '今天刷',
  });

  final LocalDate swipeOn;
  final LocalDate statementDate;
  final LocalDate dueDate;
  final String swipeLabel;

  @override
  Widget build(BuildContext context) {
    final c = CardFlowColors.of(context);
    final t = Theme.of(context).textTheme;
    final toStatement = statementDate.differenceInDays(swipeOn);
    final toDue = dueDate.differenceInDays(swipeOn);
    final first = toStatement.clamp(1, 1 << 20);
    final second = (toDue - toStatement).clamp(1, 1 << 20);
    final caption = t.bodySmall?.copyWith(color: c.textSecondary);
    final strong = t.labelLarge?.copyWith(color: c.textPrimary);
    Widget node(String title, String date, CrossAxisAlignment align) => Column(
      crossAxisAlignment: align,
      children: <Widget>[
        Text(title, style: caption),
        Text(date, style: strong),
      ],
    );
    final stacked = useStackedLayout(context);
    return Semantics(
      label:
          '$swipeLabel ${monthDay(swipeOn)}，${monthDay(statementDate)} 出账，'
          '${monthDay(dueDate)} 还款，距还款 $toDue 天',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: CfSpace.xs,
            child: Row(
              children: <Widget>[
                _Dot(color: c.action),
                Expanded(
                  flex: first,
                  child: Container(height: CfStroke.bar / 2, color: c.action),
                ),
                _Dot(color: c.action),
                Expanded(
                  flex: second,
                  child: Container(
                    height: CfStroke.bar / 2,
                    color: c.action.withValues(alpha: .35),
                  ),
                ),
                _Dot(color: c.action, hollow: true),
              ],
            ),
          ),
          const SizedBox(height: CfSpace.xxs),
          if (stacked)
            Wrap(
              spacing: CfSpace.md,
              runSpacing: CfSpace.xs,
              children: <Widget>[
                node(swipeLabel, monthDay(swipeOn), CrossAxisAlignment.start),
                node('出账', monthDay(statementDate), CrossAxisAlignment.start),
                node('还款', monthDay(dueDate), CrossAxisAlignment.start),
              ],
            )
          else
            Row(
              children: <Widget>[
                Expanded(
                  child: node(
                    swipeLabel,
                    monthDay(swipeOn),
                    CrossAxisAlignment.start,
                  ),
                ),
                Expanded(
                  child: node(
                    '出账',
                    monthDay(statementDate),
                    CrossAxisAlignment.center,
                  ),
                ),
                Expanded(
                  child: node('还款', monthDay(dueDate), CrossAxisAlignment.end),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.hollow = false});
  final Color color;
  final bool hollow;

  @override
  Widget build(BuildContext context) => Container(
    width: CfSpace.xs,
    height: CfSpace.xs,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: hollow ? CardFlowColors.of(context).surface : color,
      border: Border.all(color: color, width: CfStroke.hairline * 1.5),
    ),
  );
}

/// 提示条：注意色浅底 + 图标 + 文字（例如"再等 2 天刷，多压 30 天"）。
class HintStrip extends StatelessWidget {
  const HintStrip({
    super.key,
    required this.text,
    this.icon = Icons.schedule_rounded,
  });

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = CardFlowColors.of(context);
    final t = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.attention.bg,
        borderRadius: BorderRadius.circular(CfRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CfSpace.sm,
          vertical: CfSpace.xs,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: CfIconSize.sm, color: c.attention.fg),
            const SizedBox(width: CfSpace.xs),
            Expanded(
              child: Text(
                text,
                style: t.bodySmall?.copyWith(
                  color: c.attention.fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 排行序号圆点：第一名用强调色实心，其余为浅底。
class RankDot extends StatelessWidget {
  const RankDot({super.key, required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final c = CardFlowColors.of(context);
    final top = rank == 1;
    return ExcludeSemantics(
      child: MediaQuery.withNoTextScaling(
        child: Container(
          width: CfSize.rankDot,
          height: CfSize.rankDot,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CfRadius.md),
            color: top ? c.action : c.actionTint,
          ),
          child: Text(
            '$rank',
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: top ? c.onAction : c.action, height: 1),
          ),
        ),
      ),
    );
  }
}

/// 区块标题行：粗体标题 + 右侧附加内容（链接、合计）。
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CfSpace.xxs,
        CfSpace.md,
        CfSpace.xxs,
        CfSpace.xs,
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: CfSpace.md,
        runSpacing: CfSpace.xxs,
        children: <Widget>[
          Text(title, style: t.titleMedium),
          ?trailing,
        ],
      ),
    );
  }
}

/// 两个并排的操作按钮：常规字号时等宽并排，文字放大时上下排列。
class ActionPair extends StatelessWidget {
  const ActionPair({super.key, required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    if (useStackedLayout(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          first,
          const SizedBox(height: CfSpace.xs),
          second,
        ],
      );
    }
    return Row(
      children: <Widget>[
        Expanded(child: first),
        const SizedBox(width: CfSpace.sm),
        Expanded(child: second),
      ],
    );
  }
}
