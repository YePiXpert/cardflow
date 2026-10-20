import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../money/amount_visibility.dart';
import '../money/money_format.dart';
import '../theme/tokens.dart';

/// 负数金额的语义色调（ui-spec §3.1）。颜色只是辅助，语义词才是主要信息。
enum MoneyTone {
  /// risk.danger：缺口、超限、逾期。
  danger,

  /// risk.attention：需要留意，但不是缺口（例如待核对的差额）。
  attention,

  /// 不着色：例如"贷方余额"（银行欠你的钱）。
  neutral,
}

/// 金额组件：输入整数最小单位 + 币种，等宽数字、右对齐。
///
/// - `minor` 为 null 时显示"—"（首次空白，不显示 0）；
/// - 负数显示为"语义词 −¥2,000.00"并着语义色，`negativeLabel` 必填；
/// - 金额隐藏（默认跟随 [amountsHiddenProvider]，也可用 `hidden` 单独指定）
///   时固定显示"••••"，读屏读"金额已隐藏"；
/// - 读屏朗读完整语义，如"本期应还 人民币 8,000.00 元"。
///
/// 用法：
/// ```dart
/// MoneyText(minor: 800000, currency: 'CNY', semanticsPrefix: '本期应还')
/// MoneyText(minor: -200000, currency: 'CNY', negativeLabel: '缺口')
/// MoneyText(minor: null, currency: 'CNY') // 显示"—"
/// ```
class MoneyText extends ConsumerWidget {
  const MoneyText({
    super.key,
    required this.minor,
    required this.currency,
    this.negativeLabel,
    this.negativeTone = MoneyTone.danger,
    this.semanticsPrefix,
    this.hidden,
    this.style,
    this.textAlign = TextAlign.end,
    this.compact = false,
  });

  /// 整数最小单位（CNY 为分、JPY 为元、KWD 为 1/1000）。null 表示没有金额。
  final int? minor;

  /// ISO 4217 币种代码；必须在 [minorDigits] 表中登记。
  final String currency;

  /// 负数时显示在金额前的语义词，如"缺口""超限""贷方余额"。
  final String? negativeLabel;

  /// 负数的语义色调。
  final MoneyTone negativeTone;

  /// 读屏前缀，如"本期应还"。
  final String? semanticsPrefix;

  /// 是否隐藏金额；null 表示跟随全局开关。
  final bool? hidden;

  /// 基础文字样式；无论传入什么，数字都强制等宽。
  final TextStyle? style;

  /// 对齐方式，金额默认右对齐。
  final TextAlign textAlign;

  /// 整元时省略小数部分（"¥12,300"；有角分时照常显示，"¥12,300.50"）。读屏照常读完整金额。
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHidden = hidden ?? ref.watch<bool>(amountsHiddenProvider);
    final display = describeMoney(
      minor: minor,
      currency: currency,
      hidden: isHidden,
      negativeLabel: negativeLabel,
      semanticsPrefix: semanticsPrefix,
      compact: compact,
    );
    final colors = CardFlowColors.of(context);
    final toneColor = !display.isNegative
        ? null
        : switch (negativeTone) {
            MoneyTone.danger => colors.danger.fg,
            MoneyTone.attention => colors.attention.fg,
            MoneyTone.neutral => null,
          };
    final baseStyle = DefaultTextStyle.of(context).style.merge(style);
    final effectiveStyle = baseStyle.copyWith(
      fontFeatures: CfType.tabularFigures,
      color: toneColor,
    );
    return Semantics(
      label: display.semanticsLabel,
      excludeSemantics: true,
      child: Text(display.text, style: effectiveStyle, textAlign: textAlign),
    );
  }
}
