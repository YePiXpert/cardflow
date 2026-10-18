import 'dart:math' as math;

import 'package:cardflow/app/theme/app_theme.dart';
import 'package:cardflow/app/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.x 对比度。
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// ui-spec §3.1 的口径：前景对自身底色、surface、canvas 的最小值，浅色深色取小，
/// 再向下取一位小数。
double specMinimum(
  Color Function(CardFlowColors c) fg, [
  Color Function(CardFlowColors c)? ownBg,
]) {
  double worst(CardFlowColors c) {
    final ratios = <double>[
      contrast(fg(c), c.surface),
      contrast(fg(c), c.canvas),
      if (ownBg != null) contrast(fg(c), ownBg(c)),
    ];
    return ratios.reduce(math.min);
  }

  final value = math.min(
    worst(CardFlowColors.light),
    worst(CardFlowColors.dark),
  );
  return (value * 10).floor() / 10;
}

void main() {
  group('语义色与 ui-spec §3.1 对比度表一致（逐项核对 token 抄录）', () {
    final expected =
        <
          String,
          (
            double,
            Color Function(CardFlowColors),
            Color Function(CardFlowColors)?,
          )
        >{
          'text.primary': (13.6, (c) => c.textPrimary, null),
          'text.secondary': (6.2, (c) => c.textSecondary, null),
          'action': (5.9, (c) => c.action, null),
          'risk.robust': (5.6, (c) => c.robust.fg, (c) => c.robust.bg),
          'risk.attention': (6.5, (c) => c.attention.fg, (c) => c.attention.bg),
          'risk.danger': (5.5, (c) => c.danger.fg, (c) => c.danger.bg),
          'risk.unknown': (6.9, (c) => c.unknown.fg, (c) => c.unknown.bg),
          'risk.defect': (6.7, (c) => c.defect.fg, (c) => c.defect.bg),
          'confirm.bank': (6.7, (c) => c.bank.fg, (c) => c.bank.bg),
          'border.input': (3.5, (c) => c.borderInput, null),
        };
    for (final MapEntry(key: name, value: (ratio, fg, bg))
        in expected.entries) {
      test(name, () => expect(specMinimum(fg, bg), ratio));
    }

    test('demo（横幅文字对横幅底色）', () {
      final value = math.min(
        contrast(CardFlowColors.light.demo.fg, CardFlowColors.light.demo.bg),
        contrast(CardFlowColors.dark.demo.fg, CardFlowColors.dark.demo.bg),
      );
      expect((value * 10).floor() / 10, 9.8);
    });

    test('文字类 token 不低于 4.5:1，非文本控件边不低于 3:1', () {
      for (final c in <CardFlowColors>[
        CardFlowColors.light,
        CardFlowColors.dark,
      ]) {
        expect(contrast(c.onAction, c.action), greaterThanOrEqualTo(4.5));
        for (final text in <Color>[c.textPrimary, c.textSecondary, c.action]) {
          expect(contrast(text, c.surface), greaterThanOrEqualTo(4.5));
          expect(contrast(text, c.canvas), greaterThanOrEqualTo(4.5));
        }
        expect(contrast(c.borderInput, c.surface), greaterThanOrEqualTo(3));
      }
    });
  });

  group('ThemeData', () {
    for (final brightness in Brightness.values) {
      final c = brightness == Brightness.dark
          ? CardFlowColors.dark
          : CardFlowColors.light;

      test('$brightness：颜色全部来自 token', () {
        final theme = buildCardFlowTheme(brightness);
        expect(theme.brightness, brightness);
        expect(theme.extension<CardFlowColors>(), same(c));
        expect(theme.colorScheme.primary, c.action);
        expect(theme.colorScheme.onPrimary, c.onAction);
        expect(theme.colorScheme.surface, c.surface);
        expect(theme.colorScheme.onSurface, c.textPrimary);
        expect(theme.colorScheme.onSurfaceVariant, c.textSecondary);
        expect(theme.colorScheme.error, c.danger.fg);
        expect(theme.scaffoldBackgroundColor, c.canvas);
      });

      test('$brightness：字号阶梯来自 token，所有文字样式使用等宽数字', () {
        final textTheme = buildCardFlowTheme(brightness).textTheme;
        expect(textTheme.displaySmall?.fontSize, CfType.numDisplay.size);
        expect(textTheme.titleLarge?.fontSize, CfType.titleL.size);
        expect(textTheme.titleMedium?.fontSize, CfType.titleM.size);
        expect(textTheme.bodyLarge?.fontSize, CfType.bodyL.size);
        expect(textTheme.bodyMedium?.fontSize, CfType.bodyM.size);
        expect(textTheme.labelMedium?.fontSize, CfType.label.size);
        expect(textTheme.bodySmall?.fontSize, CfType.caption.size);
        final styles = <TextStyle?>[
          textTheme.displayLarge,
          textTheme.displayMedium,
          textTheme.displaySmall,
          textTheme.headlineLarge,
          textTheme.headlineMedium,
          textTheme.headlineSmall,
          textTheme.titleLarge,
          textTheme.titleMedium,
          textTheme.titleSmall,
          textTheme.bodyLarge,
          textTheme.bodyMedium,
          textTheme.bodySmall,
          textTheme.labelLarge,
          textTheme.labelMedium,
          textTheme.labelSmall,
        ];
        for (final style in styles) {
          expect(
            style?.fontFeatures,
            contains(const FontFeature.tabularFigures()),
          );
          expect(style?.color, c.textPrimary);
        }
      });

      test('$brightness：触控目标不小于 48', () {
        final theme = buildCardFlowTheme(brightness);
        expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
        expect(theme.visualDensity, VisualDensity.standard);
        for (final style in <ButtonStyle?>[
          theme.filledButtonTheme.style,
          theme.outlinedButtonTheme.style,
          theme.textButtonTheme.style,
        ]) {
          final size = style?.minimumSize?.resolve(<WidgetState>{});
          expect(size?.height, greaterThanOrEqualTo(CfTouch.minTarget));
        }
        expect(theme.listTileTheme.minTileHeight, CfTouch.listRowMinHeight);
      });
    }
  });

  test('间距取 4pt 网格', () {
    for (final value in <double>[
      CfSpace.xxs,
      CfSpace.xs,
      CfSpace.sm,
      CfSpace.md,
      CfSpace.lg,
      CfSpace.xl,
      CfRadius.sm,
      CfRadius.md,
      CfRadius.lg,
      CfIconSize.sm,
      CfIconSize.md,
      CfIconSize.lg,
      CfTouch.minTarget,
      CfTouch.listRowMinHeight,
    ]) {
      expect(value % 4, 0, reason: '$value');
    }
  });
}
