// 诊断日志与诊断报告不含金额、末四位以外的卡片数字、别名与其他用户文本（I-1a 简报 §4"日志"、
// 审查 R-03）：走一遍建卡（含粘贴完整卡号被拦下）、记录额度快照、换卡、切换演示空间，再复制诊断
// 报告，用掩码形态与原样形态同时检查（test/support/sensitive_text.dart）。
import 'package:cardflow/app/diagnostics/diagnostic_log.dart';
import 'package:cardflow/app/routes.dart';
import 'package:cardflow/data/validation/text_rules.dart';
import 'package:cardflow/features/cards/account_detail_page.dart';
import 'package:cardflow/features/cards/limit_snapshot_section.dart';
import 'package:cardflow/features/cards/new_card_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sensitive_text.dart';
import '../support/simple_card_form.dart';
import '../test_helpers.dart';

const String _alias = '我的工资卡';
const String _product = '经典白金';
const String _fullNumber = '6222020200114321';
const int _amountMinor = 1234567;

Finder _inPage(Type page, Finder finder) =>
    find.descendant(of: find.byType(page), matching: finder);

Future<void> _scrollIn(WidgetTester tester, Type page, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find
        .descendant(of: find.byType(page), matching: find.byType(Scrollable))
        .first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

/// 报告与日志里的时间戳是日志自己的元数据，不是用户数据：比较前换成占位。
String _withoutTimestamps(String text) =>
    text.replaceAll(RegExp(r'[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z'), '<time>');

void main() {
  testWidgets('建卡、快照、换卡、切换空间之后：日志与诊断报告不含金额、卡号数字、别名', (tester) async {
    await pumpCardFlowApp(tester);

    // 1. 建卡：先把完整卡号粘贴进卡名（被拦下），再改正后保存。
    await goTo(tester, AppRoutes.newCard);
    await fillSimpleCard(tester, name: _alias);
    final product = find.widgetWithText(TextField, '卡名');
    await _scrollIn(tester, NewCardPage, product);
    await tester.enterText(product, '卡号 $_fullNumber');
    await tester.pump();
    expect(find.text(fullCardNumberMessage), findsOneWidget);
    final save = _inPage(NewCardPage, find.widgetWithText(FilledButton, '保存'));
    await _scrollIn(tester, NewCardPage, save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(appBarTitle(NewCardPage.title), findsOneWidget, reason: '完整卡号被拦下');
    await _scrollIn(tester, NewCardPage, product);
    await tester.enterText(product, _alias);
    await _scrollIn(tester, NewCardPage, save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text(NewCardPage.savedMessage), findsOneWidget);

    // 2. 记录一次额度快照（金额 12,345.67）。
    final accountId = (await readWallet(tester)).accounts.single.id;
    await goTo(tester, AppRoutes.accountSettings(accountId, section: 'limits'));
    await tester.tap(find.text('详细记录'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '固定额度'), '12,345.67');
    final used = find.widgetWithText(TextField, '已用');
    await _scrollIn(tester, LimitSnapshotSection, used);
    await tester.enterText(used, '0');
    await tester.enterText(
      find.widgetWithText(TextField, '银行可用（银行显示的数，可为负）'),
      '12,345.67',
    );
    final record = find.widgetWithText(FilledButton, '记录新快照');
    await _scrollIn(tester, LimitSnapshotSection, record);
    await tester.tap(record);
    await tester.pumpAndSettle();
    expect(find.text(LimitSnapshotSection.savedMessage), findsOneWidget);

    // 3. 换卡（新末四位 8765）。
    await goTo(tester, AppRoutes.account(accountId));
    final replace = find.text('换卡/补卡');
    await _scrollIn(tester, AccountDetailPage, replace);
    await tester.tap(replace);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '新卡末四位'), '8765');
    await tester.tap(find.text('确认换卡'));
    await tester.pumpAndSettle();
    expect(find.text('已换卡，历史不变'), findsOneWidget);

    // 4. 进出演示空间。
    await goTo(tester, AppRoutes.welcome);
    await tester.tap(find.text('体验演示'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('进入演示'));
    await tester.pumpAndSettle();
    await goTo(tester, AppRoutes.home);
    await tester.tap(find.text('退出演示'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '退出演示'));
    await tester.pumpAndSettle();

    // 5. 复制诊断报告。
    await goTo(tester, AppRoutes.diagnostics);
    final copied = captureClipboard(tester);
    await tester.tap(find.text('复制诊断信息'));
    await tester.pump();
    final report = _withoutTimestamps(copied.single);

    final log = appContainer(tester).read(diagnosticLogProvider);
    final lines = <String>[
      for (final entry in log.entries) _withoutTimestamps(entry.toReportText()),
    ];
    expect(
      lines.where((l) => l.contains('workspace/')),
      isNotEmpty,
      reason: '流程里确实写了日志',
    );
    for (final text in <String>[report, ...lines]) {
      expect(containsUserText(text, _alias), isFalse, reason: text);
      expect(containsUserText(text, _product), isFalse, reason: text);
      expect(containsAmount(text, _amountMinor, 'CNY'), isFalse, reason: text);
      expect(containsCardDigits(text, _fullNumber), isFalse, reason: text);
    }
    expect(report, contains('卡序 CardFlow 诊断信息'));
  });
}
