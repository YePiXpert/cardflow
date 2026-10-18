import 'package:flutter/material.dart';

import 'tokens.dart';

/// 由设计 token 构建浅色/深色 [ThemeData]。
///
/// 这里只做"token → Material 角色"的映射，不引入新的颜色、字号或尺寸。
/// 文字大小随系统动态字体缩放，不做钳制（ui-spec §3.3）。
ThemeData buildCardFlowTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final c = isDark ? CardFlowColors.dark : CardFlowColors.light;
  final opposite = isDark ? CardFlowColors.light : CardFlowColors.dark;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.action,
    onPrimary: c.onAction,
    primaryContainer: c.action,
    onPrimaryContainer: c.onAction,
    secondary: c.action,
    onSecondary: c.onAction,
    secondaryContainer: c.action,
    onSecondaryContainer: c.onAction,
    tertiary: c.action,
    onTertiary: c.onAction,
    tertiaryContainer: c.action,
    onTertiaryContainer: c.onAction,
    error: c.danger.fg,
    onError: c.danger.bg,
    errorContainer: c.danger.bg,
    onErrorContainer: c.danger.fg,
    surface: c.surface,
    onSurface: c.textPrimary,
    onSurfaceVariant: c.textSecondary,
    surfaceDim: c.surface,
    surfaceBright: c.surface,
    surfaceContainerLowest: c.surface,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.surface,
    surfaceContainerHighest: c.surface,
    outline: c.borderInput,
    outlineVariant: c.borderInput,
    inverseSurface: c.textPrimary,
    onInverseSurface: c.surface,
    inversePrimary: opposite.action,
    surfaceTint: Colors.transparent,
  );

  final numDisplay = CfType.numDisplay.toTextStyle();
  final titleL = CfType.titleL.toTextStyle();
  final button = CfType.button.toTextStyle();
  final textTheme = TextTheme(
    displayLarge: numDisplay,
    displayMedium: numDisplay,
    displaySmall: numDisplay,
    headlineLarge: titleL,
    headlineMedium: titleL,
    headlineSmall: titleL,
    titleLarge: titleL,
    titleMedium: CfType.titleM.toTextStyle(),
    titleSmall: button,
    bodyLarge: CfType.bodyL.toTextStyle(),
    bodyMedium: CfType.bodyM.toTextStyle(),
    bodySmall: CfType.caption.toTextStyle(),
    labelLarge: button,
    labelMedium: CfType.label.toTextStyle(),
    labelSmall: CfType.caption.toTextStyle(),
  ).apply(bodyColor: c.textPrimary, displayColor: c.textPrimary);

  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(CfRadius.md),
  );
  const buttonMinSize = Size(CfTouch.minTarget, CfTouch.minTarget);
  const buttonPadding = EdgeInsets.symmetric(horizontal: CfSpace.md);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.canvas,
    canvasColor: c.canvas,
    textTheme: textTheme,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    extensions: <ThemeExtension<dynamic>>[c],
    appBarTheme: AppBarTheme(
      backgroundColor: c.canvas,
      foregroundColor: c.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: textTheme.titleLarge,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.action,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => CfType.label.toTextStyle().copyWith(
          color: states.contains(WidgetState.selected)
              ? c.textPrimary
              : c.textSecondary,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: CfIconSize.lg,
          color: states.contains(WidgetState.selected)
              ? c.onAction
              : c.textSecondary,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: buttonMinSize,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: button,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: buttonMinSize,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: button,
        side: BorderSide(color: c.borderInput, width: CfStroke.hairline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: buttonMinSize,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: button,
      ),
    ),
    listTileTheme: ListTileThemeData(
      minTileHeight: CfTouch.listRowMinHeight,
      contentPadding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
      iconColor: c.textSecondary,
      textColor: c.textPrimary,
    ),
    dividerTheme: DividerThemeData(
      color: c.borderInput,
      thickness: CfStroke.hairline,
      space: CfStroke.hairline,
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CfRadius.lg),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.textPrimary,
      contentTextStyle: CfType.bodyM.toTextStyle().copyWith(color: c.surface),
    ),
  );
}
