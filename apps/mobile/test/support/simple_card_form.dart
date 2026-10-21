import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pickSimpleDay(WidgetTester tester, String label, int day) async {
  final field = find.widgetWithText(DropdownButtonFormField<int>, label);
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  final menu = find.byType(Scrollable).last;
  final choice = find.descendant(of: menu, matching: find.text('每月 $day 日'));
  await tester.scrollUntilVisible(choice, 80, scrollable: menu);
  await tester.tap(choice.last);
  await tester.pumpAndSettle();
}

Future<void> fillSimpleCard(
  WidgetTester tester, {
  String name = '招行生活卡',
  String amount = '5000',
}) async {
  await tester.enterText(find.widgetWithText(TextField, '卡名'), name);
  await tester.enterText(find.widgetWithText(TextField, '末四位'), '4321');
  await tester.enterText(find.widgetWithText(TextField, '当前可用额度'), amount);
  await pickSimpleDay(tester, '账单日', 10);
  await pickSimpleDay(tester, '还款日', 28);
}
