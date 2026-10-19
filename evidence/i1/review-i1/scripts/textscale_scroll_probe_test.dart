// 审查 R-I1 探针：3.0x 字号下逐页从顶滚到底（现有 accessibility_test 只看首屏），收集布局溢出等框架错误。
// 运行：cd apps/mobile && flutter test ../../evidence/i1/review-i1/scripts/textscale_scroll_probe_test.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../apps/mobile/test/app/accessibility_test.dart' show allPages;
import '../../../../apps/mobile/test/support/forbidden_ui.dart' show forEachScreen;
import '../../../../apps/mobile/test/test_helpers.dart';

void main() {
  for (final scale in <double>[2.0, 3.0]) {
    testWidgets('文字放大到 ${scale}x：演示空间全部页面逐屏滚到底', (tester) async {
      final errors = <String>[];
      final previous = FlutterError.onError;
      String page = '';
      FlutterError.onError = (details) {
        errors.add('$page：${details.exceptionAsString().split('\n').first}');
      };
      addTearDown(() => FlutterError.onError = previous);
      await pumpCardFlowApp(tester, textScale: scale, workspace: TestWorkspace.demo);
      final pages = await allPages(tester);
      for (final p in pages) {
        page = p;
        await goTo(tester, p);
        await forEachScreen(tester, () {
          final e = tester.takeException();
          if (e != null) {
            errors.add('$p：$e');
          }
        });
      }
      FlutterError.onError = previous;
      // ignore: avoid_print
      print('SCALE $scale：检查 ${pages.length} 个页面，错误 ${errors.length} 条');
      for (final e in errors.toSet()) {
        // ignore: avoid_print
        print('  $e');
      }
    });
  }
}
