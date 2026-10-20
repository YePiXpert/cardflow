/// 卡序设计 token：颜色、字号、间距、圆角、图标与触控尺寸的唯一来源。
///
/// 0.0.2 起颜色与字号按简报 U-1 §5 与设计稿 `docs/50-ui/mockups/0.0.2/`：深色/浅色两套背景、表面、次级表面、
/// 分隔线与三级文字，强调色；注意、危险、银行确认、演示四类语义色沿用 ui-spec §3.1 的色相，背景用浅色调。
/// 间距仍按 ui-spec §3.2 的 4pt 网格；语义规则（§3.1 每个状态同时有图标、文字与颜色）不变。
///
/// 页面与组件只引用这里的常量或 [CardFlowColors]，不写字面量颜色、字号与尺寸。文字类颜色对它可能出现的
/// 每一种底色都不低于 4.5:1（`test/app/theme_test.dart` 用 WCAG 2.x 公式逐项核对；设计稿的第三级文字
/// #6B7480/#8A929C 不够，按偏离调成 #808996/#676F7A，见 apps/mobile/README.md"U-1 的偏离与约定"）。
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

  /// 页边距、卡片内边距（简报 U-1 §5：页面左右边距 16）。
  static const double md = 16;

  /// 区块之间。
  static const double lg = 24;

  /// 大区块之间。
  static const double xl = 32;
}

/// 圆角（ui-spec §3.2 的 4/8/12，加上简报 U-1 §5 的卡片圆角 18–22 取 20）。
abstract final class CfRadius {
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;

  /// 卡片内的小块（详情页的金额格、分段控件）。
  static const double tile = 16;

  /// 分组卡片、汇总卡、卡面（简报 U-1 §5：圆角 18–22）。
  static const double card = 20;
}

/// 图标尺寸（ui-spec §3.2）。
abstract final class CfIconSize {
  static const double sm = 16;
  static const double md = 20;
  static const double lg = 24;

  /// 首次空白态的主图标（ui-spec §2"图标+一句用途+主操作"），取 2 × lg。
  static const double emptyState = 48;
}

/// 固定尺寸的组件（简报 U-1 §5）。
abstract final class CfSize {
  /// 银行徽标：34pt 圆角方块（简报原值，不在 4pt 网格上，记入偏离）。
  static const double bankBadge = 34;

  /// 顶栏圆形图标按钮的可见直径（触控区域仍是 [CfTouch.minTarget]）。
  static const double iconCircle = 36;

  /// 底部导航的内容高度（不含 Home 指示条的安全区）。
  static const double tabBar = 60;

  /// 现金页余额曲线的绘图区高度（不含起止日期一行）。
  static const double chart = 160;
}

/// 描边粗细。
abstract final class CfStroke {
  /// 分隔线与控件边框。
  static const double hairline = 1;

  /// 进度条与额度条的粗细。
  static const double bar = 4;

  /// 余额曲线的线宽。
  static const double chartLine = 2;
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

/// 字号阶梯中的一级：字号、行高（pt）与字重。
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

/// 字号阶梯（简报 U-1 §5：大标题 32/粗、分组标题 17/粗、正文 15、说明 12；金额 38/30/24）。随系统动态字体
/// 缩放，不做钳制（ui-spec §3.3）。
abstract final class CfType {
  /// 各 Tab 根页的大标题（"卡账""现金"…）。
  static const largeTitle = CfTypeSpec(32, 38, FontWeight.w700);

  /// 推入页的顶栏标题（iOS 导航栏标题 17 半粗）。
  static const navTitle = CfTypeSpec(17, 22, FontWeight.w600);

  /// 分组标题（"按还款日""接下来"）。
  static const groupTitle = CfTypeSpec(17, 22, FontWeight.w700);

  /// 页内较大的标题（"关于"页的名称、卡面上的银行名）。
  static const headline = CfTypeSpec(22, 28, FontWeight.w700);

  /// 正文与列表主行。
  static const body = CfTypeSpec(15, 21, FontWeight.w400);

  /// 列表次行与辅助说明。
  static const bodySecondary = CfTypeSpec(14, 20, FontWeight.w400);

  /// 说明与时间（不承载唯一关键信息）。
  static const caption = CfTypeSpec(12, 16, FontWeight.w400);

  /// 状态标签（胶囊）的文字。
  static const label = CfTypeSpec(12, 16, FontWeight.w600);

  /// 按钮文字。
  static const button = CfTypeSpec(15, 20, FontWeight.w600);

  /// 旧的总览主数字（保留给仍在用 displaySmall 的页面）。
  static const numDisplay = CfTypeSpec(32, 40, FontWeight.w600);

  /// 金额：汇总卡的主数字。
  static const amountHero = CfTypeSpec(38, 44, FontWeight.w700);

  /// 金额：详情页的主数字。
  static const amountDetail = CfTypeSpec(30, 36, FontWeight.w700);

  /// 金额：详情页的金额格。
  static const amountTile = CfTypeSpec(22, 28, FontWeight.w700);

  /// 金额与天数：列表行的大字（待还、"17 天后出账"的 17）。
  static const amountRow = CfTypeSpec(24, 30, FontWeight.w700);

  /// 列表行里随数字一起的小字（"天后出账"）与行内金额。
  static const amountInline = CfTypeSpec(15, 20, FontWeight.w600);

  /// 等宽数字（tabular figures）。
  static const List<FontFeature> tabularFigures = <FontFeature>[
    FontFeature.tabularFigures(),
  ];
}

/// 银行徽标的颜色（简报 U-1 §5：常见银行固定品牌色，其余按名称哈希取调色板）。都是近似色相，不是商标；
/// 白字（[mark]）对每一色都不低于 4.5:1（`test/app/bank_badge_test.dart`）。调色板不用绿色，避免与"稳妥"混淆。
abstract final class CfBankColors {
  /// 徽标上的字。
  static const Color mark = Color(0xFFFFFFFF);

  static const Color icbc = Color(0xFFC8102E);
  static const Color ccb = Color(0xFF0A4EA2);
  static const Color abc = Color(0xFF00796B);
  static const Color bocom = Color(0xFF1E3F8A);
  static const Color cmb = Color(0xFFD7000F);
  static const Color spdb = Color(0xFF00418D);
  static const Color cmbc = Color(0xFF0B766F);
  static const Color cib = Color(0xFF004B9C);
  static const Color ceb = Color(0xFF5C2D91);
  static const Color citic = Color(0xFFB81C22);
  static const Color pingan = Color(0xFFC2410C);
  static const Color cgb = Color(0xFFB4232A);
  static const Color hxb = Color(0xFFC41E24);
  static const Color psbc = Color(0xFF00703C);
  static const Color czb = Color(0xFF8C6A1F);
  static const Color boc = Color(0xFFB5121B);

  /// 其余银行的调色板。
  static const List<Color> palette = <Color>[
    Color(0xFF3B5BA9),
    Color(0xFF7B3FA0),
    Color(0xFFA8323E),
    Color(0xFF2E6E80),
    Color(0xFF8A5A00),
    Color(0xFF5B4BB5),
    Color(0xFF9C3B72),
    Color(0xFF4E6A85),
    Color(0xFF2F5D8A),
    Color(0xFF7A4E2D),
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

/// 颜色 token，浅色与深色两套（简报 U-1 §5）。
///
/// 每个状态同时要有图标、文字与颜色（R-UI-03、R-UI-05），颜色不能单独承载含义。语义色的底色在深色模式下是
/// 前景色以 14% 叠在表面色上的结果（预先算成不透明色，便于核对对比度），浅色模式沿用 ui-spec 的浅底。
@immutable
class CardFlowColors extends ThemeExtension<CardFlowColors> {
  const CardFlowColors({
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceLow,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.action,
    required this.onAction,
    required this.actionTint,
    required this.borderInput,
    required this.robust,
    required this.attention,
    required this.danger,
    required this.unknown,
    required this.defect,
    required this.bank,
    required this.demo,
    required this.hero,
    required this.heroText,
    required this.heroTextSecondary,
  });

  /// 页底（背景）。
  final Color canvas;

  /// 表面：分组卡片、列表。
  final Color surface;

  /// 次级表面：卡片里的小块、顶栏圆形按钮、选中的分段。
  final Color surfaceRaised;

  /// 介于页底与表面之间（底部弹层下的遮挡层次、ColorScheme 的 surfaceContainerLow）。
  final Color surfaceLow;

  /// 分隔线（装饰性，不承载信息）。
  final Color divider;

  /// 主文字：正文与金额。
  final Color textPrimary;

  /// 次要文字：辅助说明。
  final Color textSecondary;

  /// 第三级文字：产品名、坐标轴、未选中的底部导航。
  final Color textTertiary;

  /// 强调色：主按钮、链接、选中的底部导航。
  final Color action;

  /// 主按钮上的文字颜色（深色模式下白字对强调色不足 4.5:1，用深蓝）。
  final Color onAction;

  /// 强调色的浅底（次要按钮、选中的标签）。
  final Color actionTint;

  /// border.input：输入框与控件边（非文本，≥3:1）。
  final Color borderInput;

  /// risk.robust：**仅** FEASIBLE_ROBUST（盾牌勾"稳妥"）。
  final CfTone robust;

  /// risk.attention：有条件可行、需要数据、陈旧、数据不全、待核对、已还一部分、今天还款。
  final CfTone attention;

  /// risk.danger：基线缺口、无解、缺口、逾期、失败。
  final CfTone danger;

  /// risk.unknown：未判定、资格待确认、中性的状态。
  final CfTone unknown;

  /// risk.defect：模型异常、系统缺陷。
  final CfTone defect;

  /// confirm.bank：银行确认。
  final CfTone bank;

  /// demo：演示横幅（fg 为横幅文字，bg 为横幅底色）。
  final CfTone demo;

  /// 汇总卡的渐变（左上 → 右下）。
  final List<Color> hero;

  /// 汇总卡上的主文字。
  final Color heroText;

  /// 汇总卡上的说明文字（对渐变最亮的一端不低于 4.5:1）。
  final Color heroTextSecondary;

  static const CardFlowColors light = CardFlowColors(
    canvas: Color(0xFFF2F3F6),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF6F7F9),
    surfaceLow: Color(0xFFF6F7F9),
    divider: Color(0xFFE8EAEE),
    textPrimary: Color(0xFF15181C),
    textSecondary: Color(0xFF5F6874),
    textTertiary: Color(0xFF676F7A),
    action: Color(0xFF1F5BB8),
    onAction: Color(0xFFFFFFFF),
    actionTint: Color(0xFFE8F0FD),
    borderInput: Color(0xFF7C828A),
    robust: CfTone(fg: Color(0xFF146C36), bg: Color(0xFFE5F3EA)),
    attention: CfTone(fg: Color(0xFF7A4D00), bg: Color(0xFFFFF2D1)),
    danger: CfTone(fg: Color(0xFFB3261E), bg: Color(0xFFFCE8E6)),
    unknown: CfTone(fg: Color(0xFF4B5059), bg: Color(0xFFECEEF1)),
    defect: CfTone(fg: Color(0xFF7B2D8F), bg: Color(0xFFF4E8F7)),
    bank: CfTone(fg: Color(0xFF1C4FA0), bg: Color(0xFFE6EEFA)),
    demo: CfTone(fg: Color(0xFFFFFFFF), bg: Color(0xFF4A2E8C)),
    hero: <Color>[Color(0xFF2560C0), Color(0xFF2156B0), Color(0xFF1B4691)],
    heroText: Color(0xFFFFFFFF),
    heroTextSecondary: Color(0xFFE1EAFA),
  );

  static const CardFlowColors dark = CardFlowColors(
    canvas: Color(0xFF0B0D10),
    surface: Color(0xFF16191E),
    surfaceRaised: Color(0xFF1E2228),
    surfaceLow: Color(0xFF101317),
    divider: Color(0xFF262B33),
    textPrimary: Color(0xFFF2F4F7),
    textSecondary: Color(0xFF9AA3AE),
    textTertiary: Color(0xFF808996),
    action: Color(0xFF5B9BFF),
    onAction: Color(0xFF0B1D3A),
    actionTint: Color(0xFF212E42),
    borderInput: Color(0xFF7D848D),
    robust: CfTone(fg: Color(0xFF6FD394), bg: Color(0xFF12301E)),
    attention: CfTone(fg: Color(0xFFF2C14E), bg: Color(0xFF353125)),
    danger: CfTone(fg: Color(0xFFFF8F85), bg: Color(0xFF372A2C)),
    unknown: CfTone(fg: Color(0xFFC2C7CF), bg: Color(0xFF2E3137)),
    defect: CfTone(fg: Color(0xFFE2A8F0), bg: Color(0xFF332D3B)),
    bank: CfTone(fg: Color(0xFF9DBEFF), bg: Color(0xFF29303E)),
    demo: CfTone(fg: Color(0xFF1D1238), bg: Color(0xFFCBB7FF)),
    hero: <Color>[Color(0xFF21407A), Color(0xFF172C55), Color(0xFF121F3D)],
    heroText: Color(0xFFFFFFFF),
    heroTextSecondary: Color(0xFFC3D0EA),
  );

  /// 当前主题的语义色；主题里没有登记时按亮度回退到内置的两套。
  static CardFlowColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<CardFlowColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  CardFlowColors copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceLow,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? action,
    Color? onAction,
    Color? actionTint,
    Color? borderInput,
    CfTone? robust,
    CfTone? attention,
    CfTone? danger,
    CfTone? unknown,
    CfTone? defect,
    CfTone? bank,
    CfTone? demo,
    List<Color>? hero,
    Color? heroText,
    Color? heroTextSecondary,
  }) => CardFlowColors(
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    surfaceLow: surfaceLow ?? this.surfaceLow,
    divider: divider ?? this.divider,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textTertiary: textTertiary ?? this.textTertiary,
    action: action ?? this.action,
    onAction: onAction ?? this.onAction,
    actionTint: actionTint ?? this.actionTint,
    borderInput: borderInput ?? this.borderInput,
    robust: robust ?? this.robust,
    attention: attention ?? this.attention,
    danger: danger ?? this.danger,
    unknown: unknown ?? this.unknown,
    defect: defect ?? this.defect,
    bank: bank ?? this.bank,
    demo: demo ?? this.demo,
    hero: hero ?? this.hero,
    heroText: heroText ?? this.heroText,
    heroTextSecondary: heroTextSecondary ?? this.heroTextSecondary,
  );

  @override
  CardFlowColors lerp(covariant CardFlowColors? other, double t) {
    if (other == null) {
      return this;
    }
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return CardFlowColors(
      canvas: mix(canvas, other.canvas),
      surface: mix(surface, other.surface),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      surfaceLow: mix(surfaceLow, other.surfaceLow),
      divider: mix(divider, other.divider),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textTertiary: mix(textTertiary, other.textTertiary),
      action: mix(action, other.action),
      onAction: mix(onAction, other.onAction),
      actionTint: mix(actionTint, other.actionTint),
      borderInput: mix(borderInput, other.borderInput),
      robust: CfTone.lerp(robust, other.robust, t),
      attention: CfTone.lerp(attention, other.attention, t),
      danger: CfTone.lerp(danger, other.danger, t),
      unknown: CfTone.lerp(unknown, other.unknown, t),
      defect: CfTone.lerp(defect, other.defect, t),
      bank: CfTone.lerp(bank, other.bank, t),
      demo: CfTone.lerp(demo, other.demo, t),
      hero: <Color>[
        for (var i = 0; i < hero.length; i++) mix(hero[i], other.hero[i]),
      ],
      heroText: mix(heroText, other.heroText),
      heroTextSecondary: mix(heroTextSecondary, other.heroTextSecondary),
    );
  }
}
