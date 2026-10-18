import 'package:cardflow/app/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

/// 本阶段所有可到达的页面。
const List<String> allPages = <String>[
  AppRoutes.overview,
  AppRoutes.cards,
  AppRoutes.planner,
  AppRoutes.discover,
  AppRoutes.settings,
  AppRoutes.diagnostics,
  AppRoutes.welcome,
];

void main() {
  for (final brightness in Brightness.values) {
    for (final page in allPages) {
      testWidgets('$page（$brightness）满足触控尺寸、标签与文字对比度要求', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpCardFlowApp(tester, brightness: brightness);
        await goTo(tester, page);

        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  }

  // ui-spec §3.3：跟随系统字体缩放，不做低于 2.0 倍的钳制；放大后换行而不截断、不溢出。
  for (final scale in <double>[2.0, 3.0]) {
    testWidgets('文字放大到 ${scale}x 时所有页面正常布局', (tester) async {
      await pumpCardFlowApp(tester, textScale: scale);
      for (final page in allPages) {
        await goTo(tester, page);
        expect(tester.takeException(), isNull, reason: page);
        final context = tester.element(find.byType(Scaffold).last);
        expect(
          MediaQuery.textScalerOf(context).scale(10),
          closeTo(10 * scale, 0.001),
          reason: '页面内容的文字缩放不应被钳制',
        );
      }
    });
  }
}
