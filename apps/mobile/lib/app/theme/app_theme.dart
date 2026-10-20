import 'package:flutter/material.dart';

import 'tokens.dart';

/// 由设计 token 构建浅色/深色 [ThemeData]。
///
/// 这里只做"token → Material 角色"的映射，不引入新的颜色、字号或尺寸。文字大小随系统动态字体缩放，不做钳制
/// （ui-spec §3.3）。ColorScheme 的 surfaceContainer 各级映射到不同的层次（简报 U-1 §5：不要全部等于 surface）：
/// 深色由暗到亮为 页底 → 介于两者 → 表面 → 次级表面 → 分隔线；浅色由亮到暗为 表面（白）→ 次级表面 → 页底 →
/// 分隔线。
///
/// [fontFamily]、[fontFamilyFallback] 只给截图工具用（`test/tool/screenshots_test.dart`）：测试环境里没有系统
/// 字体，要让每一种文字样式都解析到已加载的字体；App 本身用系统字体（iOS 上是苹方），不打包字体。
ThemeData buildCardFlowTheme(
  Brightness brightness, {
  String? fontFamily,
  List<String>? fontFamilyFallback,
}) {
  final isDark = brightness == Brightness.dark;
  final c = isDark ? CardFlowColors.dark : CardFlowColors.light;
  final opposite = isDark ? CardFlowColors.light : CardFlowColors.dark;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.action,
    onPrimary: c.onAction,
    primaryContainer: c.actionTint,
    onPrimaryContainer: c.action,
    secondary: c.action,
    onSecondary: c.onAction,
    secondaryContainer: c.actionTint,
    onSecondaryContainer: c.action,
    tertiary: c.action,
    onTertiary: c.onAction,
    tertiaryContainer: c.actionTint,
    onTertiaryContainer: c.action,
    error: c.danger.fg,
    onError: c.danger.bg,
    errorContainer: c.danger.bg,
    onErrorContainer: c.danger.fg,
    surface: c.surface,
    onSurface: c.textPrimary,
    onSurfaceVariant: c.textSecondary,
    surfaceDim: c.canvas,
    surfaceBright: isDark ? c.surfaceRaised : c.surface,
    surfaceContainerLowest: isDark ? c.canvas : c.surface,
    surfaceContainerLow: isDark ? c.surfaceLow : c.surfaceRaised,
    surfaceContainer: isDark ? c.surface : c.canvas,
    surfaceContainerHigh: isDark ? c.surfaceRaised : c.divider,
    surfaceContainerHighest: c.divider,
    outline: c.borderInput,
    outlineVariant: c.divider,
    inverseSurface: c.textPrimary,
    onInverseSurface: c.surface,
    inversePrimary: opposite.action,
    shadow: Colors.black,
    scrim: Colors.black,
    surfaceTint: Colors.transparent,
  );

  var textTheme = TextTheme(
    displayLarge: CfType.numDisplay.toTextStyle(),
    displayMedium: CfType.numDisplay.toTextStyle(),
    displaySmall: CfType.numDisplay.toTextStyle(),
    headlineLarge: CfType.largeTitle.toTextStyle(),
    headlineMedium: CfType.headline.toTextStyle(),
    headlineSmall: CfType.headline.toTextStyle(),
    titleLarge: CfType.navTitle.toTextStyle(),
    titleMedium: CfType.groupTitle.toTextStyle(),
    titleSmall: CfType.button.toTextStyle(),
    bodyLarge: CfType.body.toTextStyle(),
    bodyMedium: CfType.bodySecondary.toTextStyle(),
    bodySmall: CfType.caption.toTextStyle(),
    labelLarge: CfType.button.toTextStyle(),
    labelMedium: CfType.label.toTextStyle(),
    labelSmall: CfType.caption.toTextStyle(),
  ).apply(bodyColor: c.textPrimary, displayColor: c.textPrimary);
  if (fontFamily != null) {
    textTheme = textTheme.apply(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );
  }

  // 按钮文字取应用了字体族的 labelLarge（截图工具指定字体族时按钮文字也用它，不会成方块）。
  final button = textTheme.labelLarge!;
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(CfRadius.lg),
  );
  const buttonMinSize = Size(CfTouch.minTarget, CfTouch.minTarget);
  const buttonPadding = EdgeInsets.symmetric(horizontal: CfSpace.md);
  final cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(CfRadius.card),
  );
  final overlayTitle = textTheme.titleLarge;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    scaffoldBackgroundColor: c.canvas,
    canvasColor: c.canvas,
    textTheme: textTheme,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    splashFactory: InkRipple.splashFactory,
    extensions: <ThemeExtension<dynamic>>[c],
    appBarTheme: AppBarTheme(
      backgroundColor: c.canvas,
      foregroundColor: c.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: overlayTitle,
      iconTheme: IconThemeData(color: c.action, size: CfIconSize.lg),
      actionsIconTheme: IconThemeData(color: c.action, size: CfIconSize.lg),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: CfSize.tabBar,
      // 与页底同色（iOS 15 起滚动到底时标签栏透明），上沿一条分隔线在外壳里画。
      backgroundColor: c.canvas,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: Colors.transparent,
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelPadding: const EdgeInsets.only(top: CfSpace.xxs / 2),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => CfType.label.toTextStyle().copyWith(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
          color: states.contains(WidgetState.selected)
              ? c.action
              : c.textTertiary,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: CfIconSize.lg,
          color: states.contains(WidgetState.selected)
              ? c.action
              : c.textTertiary,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: buttonMinSize,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: button,
        backgroundColor: c.action,
        foregroundColor: c.onAction,
      ),
    ),
    // 次要按钮：强调色浅底 + 强调色文字（设计稿的"记一笔""更新额度"），不再用 0.0.1 的灰边框。
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: buttonMinSize,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: button,
        backgroundColor: c.actionTint,
        foregroundColor: c.action,
        side: BorderSide.none,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: buttonMinSize,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: button,
        foregroundColor: c.action,
      ),
    ),
    listTileTheme: ListTileThemeData(
      minTileHeight: CfTouch.listRowMinHeight,
      contentPadding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
      iconColor: c.textSecondary,
      textColor: c.textPrimary,
    ),
    dividerTheme: DividerThemeData(
      color: c.divider,
      thickness: CfStroke.hairline,
      space: CfStroke.hairline,
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: cardShape,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surfaceRaised,
      selectedColor: c.actionTint,
      disabledColor: c.surfaceRaised,
      checkmarkColor: c.action,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: CfType.bodySecondary.toTextStyle().copyWith(
        color: WidgetStateColor.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? c.action : c.textPrimary,
        ),
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
      ),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      shape: const Border(),
      collapsedShape: const Border(),
      iconColor: c.textSecondary,
      collapsedIconColor: c.textSecondary,
      textColor: c.textPrimary,
      collapsedTextColor: c.textPrimary,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: isDark ? c.surfaceRaised : c.surface,
      surfaceTintColor: Colors.transparent,
      shape: cardShape,
      titleTextStyle: textTheme.titleMedium,
      contentTextStyle: textTheme.bodyLarge,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isDark ? c.surfaceRaised : c.surface,
      modalBackgroundColor: isDark ? c.surfaceRaised : c.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: c.textTertiary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CfRadius.card),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: isDark ? c.surfaceRaised : c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CfRadius.tile),
      ),
      textStyle: textTheme.bodyLarge,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CfRadius.lg),
        borderSide: BorderSide(color: c.borderInput),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CfRadius.lg),
        borderSide: BorderSide(color: c.borderInput),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CfRadius.lg),
        borderSide: BorderSide(color: c.action, width: CfStroke.hairline * 2),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.transparent
            : c.borderInput,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.textPrimary,
      contentTextStyle: CfType.bodySecondary.toTextStyle().copyWith(
        color: c.surface,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CfRadius.lg),
      ),
    ),
  );
}
