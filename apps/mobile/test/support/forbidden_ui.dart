// 测试辅助：账单与还款页面的禁止项（ui-spec §2"成功"、§3.1、§4.5 与 P-06）——任何地方都不出现
// "还款成功"，也不用绿色勾：绿色（robust 色 token）只属于 FEASIBLE_ROBUST。
//
// [expectNoForbiddenRepaymentUi] 把当前页面从顶滚到底（[forEachScreen]；ListView 只构建可见的子项），每一屏检查：
// - 可见文字（RichText，含图标字形与 MoneyText；输入框的内容）不含"还款成功"；
// - 用到的颜色（文字与文字片段、装饰的底色与边框、Material、ColoredBox）不是浅色或深色主题里的
//   robust 前景色或底色。图标经 Icon 渲染成 RichText，所以"绿色勾"也在文字片段的颜色里。
import 'dart:math' as math;

import 'package:cardflow/app/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 禁止的文案（无银行确认时的"还款成功"；本 App 任何地方都不用）。
const String forbiddenRepaymentCopy = '还款成功';

/// 浅色与深色主题里的 robust 色（前景与底色）。
final Set<Color> robustColors = <Color>{
  CardFlowColors.light.robust.fg,
  CardFlowColors.light.robust.bg,
  CardFlowColors.dark.robust.fg,
  CardFlowColors.dark.robust.bg,
};

/// 当前已构建、在台上的全部文字（RichText 的纯文本与输入框内容）。
List<String> visibleTexts(WidgetTester tester) => <String>[
  for (final w in tester.widgetList<RichText>(find.byType(RichText)))
    w.text.toPlainText(),
  for (final w in tester.widgetList<EditableText>(find.byType(EditableText)))
    w.controller.text,
];

/// 当前已构建、在台上的组件用到的颜色：（出处, 颜色）。
List<(String, Color)> usedColors(WidgetTester tester) {
  final colors = <(String, Color)>[];
  void add(String where, Color? color) {
    if (color != null) {
      colors.add((where, color));
    }
  }

  void decoration(String where, Decoration? d) {
    if (d is BoxDecoration) {
      add(where, d.color);
      final border = d.border;
      if (border is Border) {
        for (final side in <BorderSide>[
          border.top,
          border.right,
          border.bottom,
          border.left,
        ]) {
          add('$where 边框', side.color);
        }
      }
      for (final c in d.gradient?.colors ?? const <Color>[]) {
        add('$where 渐变', c);
      }
    } else if (d is ShapeDecoration) {
      add(where, d.color);
    }
  }

  for (final w in tester.widgetList<RichText>(find.byType(RichText))) {
    final text = w.text.toPlainText();
    w.text.visitChildren((span) {
      add('文字"$text"', span.style?.color);
      add('文字"$text"的底色', span.style?.backgroundColor);
      return true;
    });
  }
  for (final w in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))) {
    decoration('装饰', w.decoration);
  }
  for (final w in tester.widgetList<Material>(find.byType(Material))) {
    add('Material', w.color);
  }
  for (final w in tester.widgetList<ColoredBox>(find.byType(ColoredBox))) {
    add('ColoredBox', w.color);
  }
  return colors;
}

void _checkScreen(WidgetTester tester, String page) {
  for (final text in visibleTexts(tester)) {
    expect(
      text.contains(forbiddenRepaymentCopy),
      isFalse,
      reason: '$page："$text"',
    );
  }
  for (final (where, color) in usedColors(tester)) {
    expect(
      robustColors.contains(color),
      isFalse,
      reason: '$page：$where 用了 robust（绿色）',
    );
  }
}

/// 把当前页面（第一个纵向滚动区）从顶滚到底，每一屏调用 [check]；结束时回到顶部。ListView 只构建
/// 可见的子项，所以只查第一屏会漏掉下面的内容。
Future<void> forEachScreen(WidgetTester tester, void Function() check) async {
  check();
  final vertical = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );
  if (vertical.evaluate().isEmpty) {
    return;
  }
  final position = tester.state<ScrollableState>(vertical.first).position;
  var guard = 0;
  while (position.pixels < position.maxScrollExtent && guard++ < 200) {
    position.jumpTo(
      math.min(
        position.pixels + position.viewportDimension * 0.8,
        position.maxScrollExtent,
      ),
    );
    await tester.pump();
    check();
  }
  position.jumpTo(0);
  await tester.pump();
}

/// 把当前页面从顶滚到底，每一屏检查禁止的文案与颜色。
Future<void> expectNoForbiddenRepaymentUi(
  WidgetTester tester, {
  required String page,
}) => forEachScreen(tester, () => _checkScreen(tester, page));
