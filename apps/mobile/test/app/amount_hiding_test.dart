// 隐藏金额的整页检查（简报 U-1 §9 R-09；ui-spec §3.6"金额一律显示固定 4 个点"）：打开"隐藏金额"后，演示空间的
// 每一页从顶滚到底，渲染出来的文字（输入框里正在编辑的内容除外）没有一处数字金额。检查本身先用正反例自检。
import 'package:cardflow/app/money/amount_visibility.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/forbidden_ui.dart' show forEachScreen;
import '../test_helpers.dart';
import 'accessibility_test.dart' show allPages;

/// 像金额的写法：¥ 或币种代码后跟数字、带千分位的数字、两位小数（后面不是数字、% 或点：费率、年化与
/// "6.12.111"一类版本号不算）。
final RegExp amountPattern = RegExp(
  r'¥\s?\d|\b(?:CNY|USD|EUR|HKD|GBP|MOP|TWD|JPY|KRW|VND|KWD|BHD|JOD) \d'
  r'|\d{1,3}(?:,\d{3})+|(?<![\d.])\d+\.\d{2}(?![\d%.])',
);

/// 当前已构建的文字里像金额的（输入框内容不算：编辑时要看得见自己输入的数）。
List<String> visibleAmounts(WidgetTester tester) => <String>[
  for (final w in tester.widgetList<RichText>(find.byType(RichText)))
    if (amountPattern.hasMatch(w.text.toPlainText())) w.text.toPlainText(),
];

void main() {
  group('像金额的写法：自检', () {
    for (final text in <String>[
      '¥2,393.33',
      '账单 ¥12,300',
      '支出 30.00',
      'USD 12.50',
      '−¥200',
      '储备 2,000',
    ]) {
      test('命中：$text', () => expect(amountPattern.hasMatch(text), isTrue));
    }
    for (final text in <String>[
      '••••',
      '账单 ••••',
      '2026-10-16',
      '10-28 到期',
      '每期费率 0.6%',
      '实际年化 36.7571%',
      '第 1/12 期',
      '25 天后出账',
      '43 天免息',
      '版本 0.0.2（构建 7）',
      'SQLite3 Multiple Ciphers 2.6.1',
      '内核 6.12.111',
      '3 项待处理',
    ]) {
      test('不命中：$text', () => expect(amountPattern.hasMatch(text), isFalse));
    }
  });

  testWidgets('打开隐藏金额后，演示空间的每一页（逐屏滚到底）没有数字金额', (tester) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
    appContainer(tester).read(amountsHiddenProvider.notifier).setHidden(true);
    await tester.pumpAndSettle();
    final pages = await allPages(tester);
    for (final page in pages) {
      await goTo(tester, page);
      await forEachScreen(tester, () {
        expect(visibleAmounts(tester), isEmpty, reason: page);
      });
    }
    // ignore: avoid_print
    print('检查了演示空间的 ${pages.length} 个页面');
  });
}
