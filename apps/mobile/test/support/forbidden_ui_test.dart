// 先自检禁止项检查（forbidden_ui.dart）本身：它能发现"还款成功"、绿色的文字、绿色勾图标、绿色底色与
// 只有滚到下面才构建出来的违规；干净的页面不误报。
import 'package:cardflow/app/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'forbidden_ui.dart';

Future<void> _pump(WidgetTester tester, List<Widget> children) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ListView(children: children)),
      ),
    );

Future<TestFailure?> _failureOf(Future<void> Function() check) async {
  try {
    await check();
  } on TestFailure catch (failure) {
    return failure;
  }
  return null;
}

void main() {
  final green = CardFlowColors.light.robust;
  final cases = <String, List<Widget>>{
    '文案"还款成功"': <Widget>[const Text('还款成功')],
    '绿色文字': <Widget>[Text('已登记', style: TextStyle(color: green.fg))],
    '绿色勾图标': <Widget>[Icon(Icons.check_circle, color: green.fg)],
    '绿色底色': <Widget>[Container(height: 40, color: green.bg)],
    '深色主题的绿色': <Widget>[
      Icon(Icons.check, color: CardFlowColors.dark.robust.fg),
    ],
    '滚到下面才出现的违规': <Widget>[
      for (var i = 0; i < 60; i++) Text('第 $i 行'),
      const Text('还款成功'),
    ],
  };
  cases.forEach((name, children) {
    testWidgets('发现：$name', (tester) async {
      await _pump(tester, children);
      final failure = await _failureOf(
        () => expectNoForbiddenRepaymentUi(tester, page: name),
      );
      expect(failure, isNotNull, reason: name);
    });
  });

  testWidgets('不误报：中性色、银行确认色与"已登记（待银行确认）"', (tester) async {
    await _pump(tester, <Widget>[
      const Text('已登记（待银行确认）'),
      Icon(Icons.approval_outlined, color: CardFlowColors.light.bank.fg),
      Container(height: 40, color: CardFlowColors.light.unknown.bg),
      for (var i = 0; i < 60; i++) Text('第 $i 行'),
    ]);
    expect(
      await _failureOf(
        () => expectNoForbiddenRepaymentUi(tester, page: '干净的页面'),
      ),
      isNull,
    );
  });
}
