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

/// 两种模式。
const Map<String, CardFlowColors> modes = <String, CardFlowColors>{
  '浅色': CardFlowColors.light,
  '深色': CardFlowColors.dark,
};

void main() {
  group('颜色 token 与简报 U-1 §5 一致（逐项核对抄录；第三级文字按偏离调色）', () {
    test('深色', () {
      const c = CardFlowColors.dark;
      expect(c.canvas, const Color(0xFF0B0D10));
      expect(c.surface, const Color(0xFF16191E));
      expect(c.surfaceRaised, const Color(0xFF1E2228));
      expect(c.divider, const Color(0xFF262B33));
      expect(c.textPrimary, const Color(0xFFF2F4F7));
      expect(c.textSecondary, const Color(0xFF9AA3AE));
      // 简报 #6B7480 对表面只有 3.7:1，调成 #808996（README"U-1 的偏离与约定"）。
      expect(c.textTertiary, const Color(0xFF808996));
      expect(c.action, const Color(0xFF5B9BFF));
    });

    test('浅色', () {
      const c = CardFlowColors.light;
      expect(c.canvas, const Color(0xFFF2F3F6));
      expect(c.surface, const Color(0xFFFFFFFF));
      expect(c.surfaceRaised, const Color(0xFFF6F7F9));
      expect(c.divider, const Color(0xFFE8EAEE));
      expect(c.textPrimary, const Color(0xFF15181C));
      expect(c.textSecondary, const Color(0xFF5F6874));
      // 简报 #8A929C 对白底只有 3.2:1，调成 #676F7A。
      expect(c.textTertiary, const Color(0xFF676F7A));
      expect(c.action, const Color(0xFF1F5BB8));
    });

    test('注意、危险、银行确认、演示沿用 ui-spec §3.1 的前景色', () {
      expect(CardFlowColors.light.attention.fg, const Color(0xFF7A4D00));
      expect(CardFlowColors.dark.attention.fg, const Color(0xFFF2C14E));
      expect(CardFlowColors.light.danger.fg, const Color(0xFFB3261E));
      expect(CardFlowColors.dark.danger.fg, const Color(0xFFFF8F85));
      expect(CardFlowColors.light.bank.fg, const Color(0xFF1C4FA0));
      expect(CardFlowColors.dark.bank.fg, const Color(0xFF9DBEFF));
      expect(CardFlowColors.light.demo.bg, const Color(0xFF4A2E8C));
      expect(CardFlowColors.dark.demo.bg, const Color(0xFFCBB7FF));
    });
  });

  group('对比度（WCAG 2.x）：文字 ≥ 4.5:1，两种模式都核对', () {
    for (final MapEntry(key: mode, value: c) in modes.entries) {
      final backgrounds = <String, Color>{
        '页底': c.canvas,
        '表面': c.surface,
        '次级表面': c.surfaceRaised,
      };

      test('$mode：三级文字与强调色对页底、表面、次级表面', () {
        for (final MapEntry(key: name, value: fg) in <String, Color>{
          '主文字': c.textPrimary,
          '次要文字': c.textSecondary,
          '第三级文字': c.textTertiary,
          '强调色': c.action,
        }.entries) {
          for (final MapEntry(key: where, value: bg) in backgrounds.entries) {
            expect(
              contrast(fg, bg),
              greaterThanOrEqualTo(4.5),
              reason: '$mode $name 对 $where',
            );
          }
        }
      });

      test('$mode：语义色的前景对自身底色、页底、表面、次级表面', () {
        for (final MapEntry(key: name, value: tone) in <String, CfTone>{
          '注意': c.attention,
          '危险': c.danger,
          '银行确认': c.bank,
          '中性': c.unknown,
          '缺陷': c.defect,
          '稳妥（仅 FEASIBLE_ROBUST）': c.robust,
        }.entries) {
          for (final MapEntry(key: where, value: bg) in <String, Color>{
            '自身底色': tone.bg,
            ...backgrounds,
          }.entries) {
            expect(
              contrast(tone.fg, bg),
              greaterThanOrEqualTo(4.5),
              reason: '$mode $name 对 $where',
            );
          }
          // 正文与次要文字也会出现在语义色的底色上（提示块里的说明）。
          expect(
            contrast(c.textPrimary, tone.bg),
            greaterThanOrEqualTo(4.5),
            reason: '$mode 主文字对 $name 底色',
          );
        }
      });

      test('$mode：按钮、演示横幅、汇总卡', () {
        expect(contrast(c.onAction, c.action), greaterThanOrEqualTo(4.5));
        expect(contrast(c.action, c.actionTint), greaterThanOrEqualTo(4.5));
        expect(
          contrast(c.textPrimary, c.actionTint),
          greaterThanOrEqualTo(4.5),
        );
        expect(contrast(c.demo.fg, c.demo.bg), greaterThanOrEqualTo(4.5));
        for (final stop in c.hero) {
          expect(contrast(c.heroText, stop), greaterThanOrEqualTo(4.5));
          expect(
            contrast(c.heroTextSecondary, stop),
            greaterThanOrEqualTo(4.5),
          );
        }
      });

      test('$mode：输入框边对表面与页底不低于 3:1（非文本）', () {
        expect(contrast(c.borderInput, c.surface), greaterThanOrEqualTo(3));
        expect(contrast(c.borderInput, c.canvas), greaterThanOrEqualTo(3));
        expect(
          contrast(c.borderInput, c.surfaceRaised),
          greaterThanOrEqualTo(3),
        );
      });
    }
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
        expect(theme.dividerTheme.color, c.divider);
        expect(theme.cardTheme.color, c.surface);
      });

      test('$brightness：surfaceContainer 各级是不同的层次，不全等于 surface', () {
        final s = buildCardFlowTheme(brightness).colorScheme;
        final levels = <Color>[
          s.surfaceContainerLowest,
          s.surfaceContainerLow,
          s.surfaceContainer,
          s.surfaceContainerHigh,
          s.surfaceContainerHighest,
        ];
        expect(levels.toSet().length, greaterThanOrEqualTo(4));
        expect(levels.where((l) => l == s.surface), hasLength(lessThan(2)));
        // 由低到高单调：深色越来越亮，浅色越来越暗。
        final luminance = levels.map((l) => l.computeLuminance()).toList();
        for (var i = 1; i < luminance.length; i++) {
          if (brightness == Brightness.dark) {
            expect(luminance[i], greaterThanOrEqualTo(luminance[i - 1]));
          } else {
            expect(luminance[i], lessThanOrEqualTo(luminance[i - 1]));
          }
        }
      });

      test('$brightness：字号阶梯来自 token（简报 U-1 §5），所有文字样式使用等宽数字', () {
        final textTheme = buildCardFlowTheme(brightness).textTheme;
        expect(textTheme.headlineLarge?.fontSize, 32);
        expect(textTheme.headlineLarge?.fontWeight, FontWeight.w700);
        expect(textTheme.titleMedium?.fontSize, 17);
        expect(textTheme.titleMedium?.fontWeight, FontWeight.w700);
        expect(textTheme.titleLarge?.fontSize, CfType.navTitle.size);
        expect(textTheme.bodyLarge?.fontSize, 15);
        expect(textTheme.bodyMedium?.fontSize, CfType.bodySecondary.size);
        expect(textTheme.bodySmall?.fontSize, 12);
        expect(textTheme.labelMedium?.fontSize, CfType.label.size);
        expect(textTheme.displaySmall?.fontSize, CfType.numDisplay.size);
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

      test('$brightness：金额字号 38/30/24（简报 U-1 §5）', () {
        expect(CfType.amountHero.size, 38);
        expect(CfType.amountDetail.size, 30);
        expect(CfType.amountRow.size, 24);
        for (final spec in <CfTypeSpec>[
          CfType.amountHero,
          CfType.amountDetail,
          CfType.amountTile,
          CfType.amountRow,
          CfType.amountInline,
        ]) {
          expect(
            spec.toTextStyle().fontFeatures,
            contains(const FontFeature.tabularFigures()),
          );
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

      test('$brightness：截图工具可以指定字体族，每一种文字样式都用它', () {
        final theme = buildCardFlowTheme(
          brightness,
          fontFamily: 'TestFamily',
          fontFamilyFallback: const <String>['Fallback'],
        );
        for (final style in <TextStyle?>[
          theme.textTheme.headlineLarge,
          theme.textTheme.titleLarge,
          theme.textTheme.bodyLarge,
          theme.textTheme.labelLarge,
          theme.appBarTheme.titleTextStyle,
        ]) {
          expect(style?.fontFamily, 'TestFamily');
          expect(style?.fontFamilyFallback, const <String>['Fallback']);
        }
      });
    }
  });

  test('间距与圆角取 4pt 网格；银行徽标按简报取 34', () {
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
      CfRadius.tile,
      CfRadius.card,
      CfIconSize.sm,
      CfIconSize.md,
      CfIconSize.lg,
      CfSize.iconCircle,
      CfSize.tabBar,
      CfSize.chart,
      CfTouch.minTarget,
      CfTouch.listRowMinHeight,
    ]) {
      expect(value % 4, 0, reason: '$value');
    }
    expect(CfRadius.card, inInclusiveRange(18, 22));
    expect(CfSize.bankBadge, 34);
  });
}
