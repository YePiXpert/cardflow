/// 现金页的余额曲线（简报 U-1 §4；设计稿 `cash-dark.png`）：所选账户逐日最低余额的折线与面积，0 线、储备虚线，
/// 低于储备的一段标危险色并有 ▲ 与日期，起止日期标注；`CustomPaint` 自绘，不加依赖。带 `Semantics` 文字摘要
/// （"30 天内最低 −¥3,200，11-15，工资卡；缺口 1 处"），表格视图是资金日历（P-07）。
///
/// 语义不变：逐账户计算、账户之间从不相加；没有缺口不用绿色。数据来自 [CashAccountForecast]（领域包的时间线），
/// 这里只把时间线整理成逐日的点（[balanceSeriesOf]）。
library;

import 'dart:math' as math;

import 'package:cardflow_domain/cardflow_domain.dart'
    show LocalDate, PointPhase;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/money/amount_visibility.dart';
import '../../app/money/money_format.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/money_text.dart';
import '../../data/repositories/cash_forecast_reader.dart';
import '../cards/card_formatting.dart';

/// 一个账户的逐日最低余额（曲线的数据）。
@immutable
final class BalanceSeries {
  const BalanceSeries({
    required this.start,
    required this.lows,
    required this.reserve,
    required this.breachDays,
    required this.minIndex,
  });

  /// 第一天（快照日与今天中较早的那天）。
  final LocalDate start;

  /// 每天的最低余额（有收支的日子取当日最低点，没有的取前一天的日终）。
  final List<int> lows;

  /// 储备（低于它就是缺口）。
  final int reserve;

  /// 领域包记下缺口点的日子（下标）。
  final Set<int> breachDays;

  /// 全窗口最低点的下标（领域包的 `minOn`）。
  final int minIndex;

  int get length => lows.length;

  LocalDate dayAt(int index) => start.addDays(index);

  int get minBalance => lows[minIndex];

  /// 这一天低于储备。
  bool below(int index) => lows[index] < reserve;
}

/// 把领域包的时间线整理成逐日的最低余额：从快照日（或今天，取较早的）到窗口最后一天。时间线的点是"快照、
/// 然后每个有收支的日子一个当日最低点与一个日终"；没有收支的日子沿用前一天的日终。
BalanceSeries balanceSeriesOf(
  CashAccountForecast account,
  LocalDate today,
  LocalDate horizonEnd,
) {
  final points = account.report.timeline.points;
  final snapshot = points.first;
  final start = snapshot.on < today ? snapshot.on : today;
  final days = horizonEnd.differenceInDays(start) + 1;
  final lows = <int>[];
  var running = snapshot.balance;
  var index = 1;
  // 快照日之前（快照日晚于今天时不会发生；这里只为稳妥）沿用快照余额。
  for (var i = 0; i < days; i++) {
    final day = start.addDays(i);
    var low = running;
    if (day == snapshot.on) {
      low = snapshot.balance;
    }
    while (index + 1 < points.length && points[index].on == day) {
      final dayLow = points[index].balance;
      low = math.min(low, dayLow);
      running = points[index + 1].balance;
      index += 2;
    }
    lows.add(low);
  }
  final breaches = <int>{
    for (final b in account.report.breaches)
      if (b.phase == PointPhase.low || b.phase == PointPhase.snapshot)
        b.on.differenceInDays(start),
  }..removeWhere((i) => i < 0 || i >= days);
  final minOn = account.report.minOn.differenceInDays(start);
  var minIndex = minOn >= 0 && minOn < days ? minOn : 0;
  for (var i = 0; i < lows.length; i++) {
    if (lows[i] < lows[minIndex]) {
      minIndex = i;
    }
  }
  return BalanceSeries(
    start: start,
    lows: lows,
    reserve: account.account.reserveFloor,
    breachDays: breaches,
    minIndex: minIndex,
  );
}

/// 曲线的读屏摘要："30 天内最低 −¥3,200，11-15，工资卡；缺口 1 处"（金额隐藏时读"金额已隐藏"）。
String balanceChartSummary({
  required int windowDays,
  required CashAccountForecast account,
  required LocalDate today,
  required bool hidden,
}) {
  final report = account.report;
  final money = describeMoney(
    minor: report.minBalance,
    currency: account.account.currency,
    hidden: hidden,
    negativeLabel: '缺口',
    compact: true,
  );
  final gaps = report.breaches.length;
  return '$windowDays 天内最低 ${money.text}，${formatShortDate(report.minOn, today)}，'
      '${account.row.name}；${gaps == 0 ? '没有缺口' : '缺口 $gaps 处'}';
}

/// 曲线卡（设计稿 .chart）：标题行（N 天内最低、日期与账户、缺口数）与曲线。
class BalanceChartCard extends ConsumerWidget {
  const BalanceChartCard({
    super.key,
    required this.forecast,
    required this.account,
    required this.windowDays,
  });

  final CashForecast forecast;
  final CashAccountForecast account;
  final int windowDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final hidden = ref.watch(amountsHiddenProvider);
    final today = forecast.today;
    final series = balanceSeriesOf(account, today, forecast.horizonEnd);
    final report = account.report;
    final gaps = report.breaches.length;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: colors.textSecondary,
    );
    final summary = balanceChartSummary(
      windowDays: windowDays,
      account: account,
      today: today,
      hidden: hidden,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(
        CfSpace.md,
        CfSpace.sm,
        CfSpace.md,
        CfSpace.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(CfRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: CfSpace.sm,
            runSpacing: CfSpace.xxs,
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('$windowDays 天内最低', style: small),
                  MoneyText(
                    minor: report.minBalance,
                    currency: account.account.currency,
                    compact: true,
                    negativeLabel: '缺口',
                    semanticsPrefix: '$windowDays 天内最低',
                    textAlign: TextAlign.start,
                    style: CfType.amountDetail.toTextStyle().copyWith(
                      color: gaps > 0 ? colors.danger.fg : colors.textPrimary,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    '${formatShortDate(report.minOn, today)} · ${account.row.name}',
                    style: small,
                  ),
                  Text(
                    gaps == 0 ? '没有缺口' : '▲ 缺口 $gaps 处',
                    style: small?.copyWith(
                      color: gaps == 0
                          ? colors.textSecondary
                          : colors.danger.fg,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: CfSpace.sm),
          Semantics(
            container: true,
            label: summary,
            image: true,
            excludeSemantics: true,
            child: SizedBox(
              height: CfSize.chart,
              child: CustomPaint(
                size: Size.infinite,
                painter: BalanceChartPainter(
                  series: series,
                  today: today,
                  lineColor: colors.action,
                  dangerColor: colors.danger.fg,
                  reserveColor: colors.attention.fg,
                  axisColor: colors.divider,
                  labelColor: colors.textTertiary,
                  labelStyle: theme.textTheme.labelSmall ?? const TextStyle(),
                  reserveLabel: series.reserve > 0
                      ? '储备 ${hidden ? hiddenAmountText : formatMinorCompact(series.reserve, account.account.currency)}'
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 余额曲线的画法。
class BalanceChartPainter extends CustomPainter {
  BalanceChartPainter({
    required this.series,
    required this.today,
    required this.lineColor,
    required this.dangerColor,
    required this.reserveColor,
    required this.axisColor,
    required this.labelColor,
    required this.labelStyle,
    required this.reserveLabel,
  });

  final BalanceSeries series;
  final LocalDate today;
  final Color lineColor;
  final Color dangerColor;
  final Color reserveColor;
  final Color axisColor;
  final Color labelColor;
  final TextStyle labelStyle;
  final String? reserveLabel;

  /// 底部日期一行的高度。
  static const double footer = CfSpace.md + CfSpace.xxs;

  TextPainter _text(String text, Color color) => TextPainter(
    text: TextSpan(
      text: text,
      style: labelStyle.copyWith(color: color),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final n = series.length;
    if (n == 0) {
      return;
    }
    final plot = Rect.fromLTWH(
      0,
      CfSpace.xs,
      size.width,
      size.height - footer - CfSpace.xs,
    );
    var lo = math.min(0, series.reserve);
    var hi = math.max(0, series.reserve);
    for (final v in series.lows) {
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    if (hi == lo) {
      hi = lo + 1;
    }
    final pad = (hi - lo) * 0.12;
    final top = hi + pad;
    final bottom = lo - pad;
    double y(num value) =>
        plot.top + (top - value) / (top - bottom) * plot.height;
    double x(int index) =>
        n == 1 ? plot.left : plot.left + plot.width * index / (n - 1);

    // 低于储备的日子：浅色危险底。
    final gapFill = Paint()..color = dangerColor.withValues(alpha: 0.18);
    for (var i = 0; i < n; i++) {
      if (series.below(i)) {
        final half = n == 1 ? plot.width / 2 : plot.width / (n - 1) / 2;
        canvas.drawRect(
          Rect.fromLTRB(
            math.max(plot.left, x(i) - half),
            y(series.reserve),
            math.min(plot.right, x(i) + half),
            y(series.lows[i]),
          ),
          gapFill,
        );
      }
    }

    // 面积（渐变）与折线。
    final line = Path()..moveTo(x(0), y(series.lows[0]));
    for (var i = 1; i < n; i++) {
      line.lineTo(x(i), y(series.lows[i]));
    }
    final area = Path.from(line)
      ..lineTo(x(n - 1), plot.bottom)
      ..lineTo(x(0), plot.bottom)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            lineColor.withValues(alpha: 0.32),
            lineColor.withValues(alpha: 0),
          ],
        ).createShader(plot),
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = CfStroke.chartLine
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < n; i++) {
      stroke.color = series.below(i) || series.below(i - 1)
          ? dangerColor
          : lineColor;
      canvas.drawLine(
        Offset(x(i - 1), y(series.lows[i - 1])),
        Offset(x(i), y(series.lows[i])),
        stroke,
      );
    }
    if (n == 1) {
      canvas.drawCircle(
        Offset(x(0), y(series.lows[0])),
        CfStroke.chartLine,
        Paint()..color = lineColor,
      );
    }

    // 0 线与储备虚线。
    final zero = y(0);
    canvas.drawLine(
      Offset(plot.left, zero),
      Offset(plot.right, zero),
      Paint()
        ..color = axisColor
        ..strokeWidth = CfStroke.hairline,
    );
    final zeroLabel = _text('0', labelColor);
    zeroLabel.paint(canvas, Offset(plot.left + 2, zero - zeroLabel.height - 1));
    if (series.reserve > 0) {
      final reserveY = y(series.reserve);
      final dash = Paint()
        ..color = reserveColor.withValues(alpha: 0.85)
        ..strokeWidth = CfStroke.hairline;
      for (var dx = plot.left; dx < plot.right; dx += CfSpace.xs) {
        canvas.drawLine(
          Offset(dx, reserveY),
          Offset(math.min(dx + CfSpace.xxs, plot.right), reserveY),
          dash,
        );
      }
      if (reserveLabel case final text?) {
        final label = _text(text, reserveColor);
        label.paint(
          canvas,
          Offset(plot.right - label.width, reserveY - label.height - 1),
        );
      }
    }

    // 最低点与缺口的 ▲ 日期。
    final minX = x(series.minIndex);
    final minY = y(series.minBalance);
    final hasGap = series.breachDays.isNotEmpty;
    canvas.drawCircle(
      Offset(minX, minY),
      CfSpace.xxs,
      Paint()..color = hasGap ? dangerColor : lineColor,
    );
    final marker = hasGap
        ? series.breachDays.reduce(math.min)
        : series.minIndex;
    final markLabel = _text(
      '${hasGap ? '▲ ' : ''}${formatShortDate(series.dayAt(marker), today)}',
      hasGap ? dangerColor : labelColor,
    );
    final markX = (x(marker) - markLabel.width / 2)
        .clamp(0.0, math.max(0.0, size.width - markLabel.width))
        .toDouble();
    final first = _text(formatShortDate(series.start, today), labelColor);
    final last = _text(formatShortDate(series.dayAt(n - 1), today), labelColor);
    final footerY = size.height - footer + CfSpace.xxs;
    first.paint(canvas, Offset(0, footerY));
    last.paint(canvas, Offset(size.width - last.width, footerY));
    // 标记与起止日期重叠时只画标记（它更重要）。
    if (markX > first.width + CfSpace.xs &&
        markX + markLabel.width < size.width - last.width - CfSpace.xs) {
      markLabel.paint(canvas, Offset(markX, footerY));
    } else {
      markLabel.paint(
        canvas,
        Offset(markX, math.max(plot.top, minY + CfSpace.xs)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant BalanceChartPainter old) =>
      old.series != series ||
      old.lineColor != lineColor ||
      old.reserveLabel != reserveLabel ||
      old.labelStyle != labelStyle;
}
