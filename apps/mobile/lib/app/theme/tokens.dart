/// 卡序设计 token：颜色、字号、间距、圆角、图标与触控尺寸的唯一来源。
///
/// 取值来自 docs/50-ui/ui-spec.md §3（3.1 语义色、3.2 间距、3.3 字号、
/// 3.4 数字与金额、3.5 可访问性）。页面与组件只引用这里的常量或
/// [CardFlowColors]，不写字面量颜色、字号与尺寸。新增颜色须先通过
/// test/app/theme_test.dart 中的对比度检查（与 ui-spec §3.1 同一公式）。
library;

import 'package:flutter/material.dart';

/// 间距，4pt 网格（ui-spec §3.2）。
abstract final class CfSpace {
  /// 图标与文字之间。
  static const double xxs = 4;

  /// 相邻可点元素的最小间隔。
  static const double xs = 8;

  /// 行内分组。
  static const double sm = 12;

  /// 页边距、卡片内边距。
  static const double md = 16;

  /// 区块之间。
  static const double lg = 24;

  /// 大区块之间。
  static const double xl = 32;
}

/// 圆角（ui-spec §3.2）。
abstract final class CfRadius {
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;
}

/// 图标尺寸（ui-spec §3.2）。
abstract final class CfIconSize {
  static const double sm = 16;
  static const double md = 20;
  static const double lg = 24;

  /// 首次空白态的主图标（ui-spec §2"图标+一句用途+主操作"），取 2 × lg。
  static const double emptyState = 48;
}

/// 描边粗细。
abstract final class CfStroke {
  /// 分隔线与控件边框。
  static const double hairline = 1;
}

/// 触控与列表尺寸（ui-spec §3.2、§3.5）。
abstract final class CfTouch {
  /// 最小触控目标边长：iOS 要求 ≥44pt、Android ≥48dp，统一取 48 同时满足两者。
  static const double minTarget = 48;

  /// 相邻可点元素的最小间隔。
  static const double minGap = CfSpace.xs;

  /// 列表行最小高度。
  static const double listRowMinHeight = 48;
}

/// 字号阶梯中的一级：字号、行高（pt）与字重（ui-spec §3.3）。
@immutable
class CfTypeSpec {
  const CfTypeSpec(this.size, this.lineHeight, this.weight);

  final double size;
  final double lineHeight;
  final FontWeight weight;

  /// 转成 [TextStyle]。数字一律等宽（ui-spec §3.4，tnum）。
  TextStyle toTextStyle() => TextStyle(
    fontSize: size,
    height: lineHeight / size,
    fontWeight: weight,
    fontFeatures: CfType.tabularFigures,
  );
}

/// 字号阶梯（ui-spec §3.3）。随系统动态字体缩放，不做钳制。
abstract final class CfType {
  /// num.display：总览主数字。
  static const numDisplay = CfTypeSpec(32, 40, FontWeight.w600);

  /// title.l：页面标题。
  static const titleL = CfTypeSpec(24, 32, FontWeight.w600);

  /// title.m：区块标题。
  static const titleM = CfTypeSpec(20, 28, FontWeight.w600);

  /// body.l：正文与表单。
  static const bodyL = CfTypeSpec(17, 24, FontWeight.w400);

  /// body.m：列表次行。
  static const bodyM = CfTypeSpec(15, 20, FontWeight.w400);

  /// label：徽标。
  static const label = CfTypeSpec(13, 16, FontWeight.w500);

  /// caption：时间与来源（不承载唯一关键信息）。
  static const caption = CfTypeSpec(12, 16, FontWeight.w400);

  /// 按钮文字：body.l 的 Semibold 变体（iOS 按钮惯用 17pt）。
  static const button = CfTypeSpec(17, 24, FontWeight.w600);

  /// 等宽数字（tabular figures）。
  static const List<FontFeature> tabularFigures = <FontFeature>[
    FontFeature.tabularFigures(),
  ];
}

/// 一组前景/底色（ui-spec §3.1 中"前景/底色"成对出现的语义色）。
@immutable
class CfTone {
  const CfTone({required this.fg, required this.bg});

  final Color fg;
  final Color bg;

  static CfTone lerp(CfTone a, CfTone b, double t) =>
      CfTone(fg: Color.lerp(a.fg, b.fg, t)!, bg: Color.lerp(a.bg, b.bg, t)!);
}

/// 语义色 token（ui-spec §3.1），浅色与深色两套。
///
/// 每个状态同时要有图标、文字与颜色（R-UI-03、R-UI-05），颜色不能单独承载含义。
@immutable
class CardFlowColors extends ThemeExtension<CardFlowColors> {
  const CardFlowColors({
    required this.textPrimary,
    required this.textSecondary,
    required this.surface,
    required this.canvas,
    required this.action,
    required this.onAction,
    required this.borderInput,
    required this.robust,
    required this.attention,
    required this.danger,
    required this.unknown,
    required this.defect,
    required this.bank,
    required this.demo,
  });

  /// text.primary：正文与金额。
  final Color textPrimary;

  /// text.secondary：辅助文字。
  final Color textSecondary;

  /// surface：卡片。
  final Color surface;

  /// canvas：页底。
  final Color canvas;

  /// action：主按钮、链接。
  final Color action;

  /// action 按钮上的文字颜色。
  final Color onAction;

  /// border.input：输入框与控件边（非文本，≥3:1）。
  final Color borderInput;

  /// risk.robust：**仅** FEASIBLE_ROBUST（盾牌勾"稳妥"）。
  final CfTone robust;

  /// risk.attention：有条件可行、需要数据、陈旧、数据不全、待核对。
  final CfTone attention;

  /// risk.danger：基线缺口、无解、缺口、逾期、失败。
  final CfTone danger;

  /// risk.unknown：未判定、资格待确认。
  final CfTone unknown;

  /// risk.defect：模型异常、系统缺陷。
  final CfTone defect;

  /// confirm.bank：银行确认。
  final CfTone bank;

  /// demo：演示横幅（fg 为横幅文字，bg 为横幅底色）。
  final CfTone demo;

  static const CardFlowColors light = CardFlowColors(
    textPrimary: Color(0xFF1A1C1E),
    textSecondary: Color(0xFF575C63),
    surface: Color(0xFFFFFFFF),
    canvas: Color(0xFFF5F6F8),
    action: Color(0xFF1F5BB8),
    onAction: Color(0xFFFFFFFF),
    borderInput: Color(0xFF7C828A),
    robust: CfTone(fg: Color(0xFF146C36), bg: Color(0xFFE5F3EA)),
    attention: CfTone(fg: Color(0xFF7A4D00), bg: Color(0xFFFFF2D1)),
    danger: CfTone(fg: Color(0xFFB3261E), bg: Color(0xFFFCE8E6)),
    unknown: CfTone(fg: Color(0xFF4B5059), bg: Color(0xFFECEEF1)),
    defect: CfTone(fg: Color(0xFF7B2D8F), bg: Color(0xFFF4E8F7)),
    bank: CfTone(fg: Color(0xFF1C4FA0), bg: Color(0xFFE6EEFA)),
    demo: CfTone(fg: Color(0xFFFFFFFF), bg: Color(0xFF4A2E8C)),
  );

  static const CardFlowColors dark = CardFlowColors(
    textPrimary: Color(0xFFE6E8EB),
    textSecondary: Color(0xFFA8AEB6),
    surface: Color(0xFF1B1E22),
    canvas: Color(0xFF101214),
    action: Color(0xFF8AB4F8),
    onAction: Color(0xFF0B1D3A),
    borderInput: Color(0xFF7D848D),
    robust: CfTone(fg: Color(0xFF6FD394), bg: Color(0xFF12301E)),
    attention: CfTone(fg: Color(0xFFF2C14E), bg: Color(0xFF3A2B07)),
    danger: CfTone(fg: Color(0xFFFF8F85), bg: Color(0xFF3D1512)),
    unknown: CfTone(fg: Color(0xFFC2C7CF), bg: Color(0xFF2A2E34)),
    defect: CfTone(fg: Color(0xFFE2A8F0), bg: Color(0xFF36183F)),
    bank: CfTone(fg: Color(0xFF9DBEFF), bg: Color(0xFF14284A)),
    demo: CfTone(fg: Color(0xFF1D1238), bg: Color(0xFFCBB7FF)),
  );

  /// 当前主题的语义色；主题里没有登记时按亮度回退到内置的两套。
  static CardFlowColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<CardFlowColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  CardFlowColors copyWith({
    Color? textPrimary,
    Color? textSecondary,
    Color? surface,
    Color? canvas,
    Color? action,
    Color? onAction,
    Color? borderInput,
    CfTone? robust,
    CfTone? attention,
    CfTone? danger,
    CfTone? unknown,
    CfTone? defect,
    CfTone? bank,
    CfTone? demo,
  }) => CardFlowColors(
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    surface: surface ?? this.surface,
    canvas: canvas ?? this.canvas,
    action: action ?? this.action,
    onAction: onAction ?? this.onAction,
    borderInput: borderInput ?? this.borderInput,
    robust: robust ?? this.robust,
    attention: attention ?? this.attention,
    danger: danger ?? this.danger,
    unknown: unknown ?? this.unknown,
    defect: defect ?? this.defect,
    bank: bank ?? this.bank,
    demo: demo ?? this.demo,
  );

  @override
  CardFlowColors lerp(covariant CardFlowColors? other, double t) {
    if (other == null) {
      return this;
    }
    return CardFlowColors(
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      action: Color.lerp(action, other.action, t)!,
      onAction: Color.lerp(onAction, other.onAction, t)!,
      borderInput: Color.lerp(borderInput, other.borderInput, t)!,
      robust: CfTone.lerp(robust, other.robust, t),
      attention: CfTone.lerp(attention, other.attention, t),
      danger: CfTone.lerp(danger, other.danger, t),
      unknown: CfTone.lerp(unknown, other.unknown, t),
      defect: CfTone.lerp(defect, other.defect, t),
      bank: CfTone.lerp(bank, other.bank, t),
      demo: CfTone.lerp(demo, other.demo, t),
    );
  }
}
