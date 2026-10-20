import 'dart:async';

import 'package:cardflow/app/routes.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/database_providers.dart';
import 'package:cardflow/data/repositories/ledger_reader.dart';
import 'package:cardflow/data/repositories/scenario_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../support/forbidden_ui.dart' show forEachScreen;
import '../test_helpers.dart';

/// 有数据（演示空间）时可到达的全部页面（简报 U-1 的四个标签与其下各页）。P-03/P-04 用"卡 A"的账户（含两张卡、规则、快照）
/// 与"卡 D"的账户（授信池、超限）；P-08 用"工资卡"（快照含已包含事件）、"定期存款"（受限）、
/// 一笔收支计划与周期事项"房租"；P-05/P-06（I-1c）用卡 A 的 10-10 账单（两个版本、分期、两笔还款、
/// 疑似重复）、两笔还款与"超市"消费的转分期表单，卡账首页栈与卡片详情栈各一套。
Future<List<String>> allPages(WidgetTester tester) async {
  final wallet = await readWallet(tester);
  final a = wallet.accounts.firstWhere((v) => v.displayName == '卡 A').id;
  final d = wallet.accounts.firstWhere((v) => v.displayName == '卡 D').id;
  final cash = await readCashPlan(tester);
  final salary = cash.accounts.firstWhere((x) => x.row.name == '工资卡').row.id;
  final deposit = cash.accounts.firstWhere((x) => x.row.name == '定期存款').row.id;
  final event = cash.plan.firstWhere((e) => e.label == '工资').id;
  final rent = cash.recurring.single.row.id;
  final stress = await withCurrentScope(
    tester,
    (scope) async => (await ScenarioRepository(
      scope,
    ).rows()).firstWhere((r) => r.kind == 'user_stress').id,
  );
  final ledger = await withCurrentScope(
    tester,
    (scope) => LedgerReader(scope).load(),
  );
  final statement = ledger.statements.single.id;
  final manual = ledger.repayments.firstWhere((r) => r.method == 'manual').id;
  final auto = ledger.repayments.firstWhere((r) => r.method == 'auto_debit').id;
  final groceries = ledger.transactions
      .firstWhere((t) => t.merchant == '超市' && t.txnType == 'purchase')
      .id;
  return <String>[
    AppRoutes.statements(),
    AppRoutes.statement(statement),
    AppRoutes.newStatement(),
    AppRoutes.correctStatement(statement),
    AppRoutes.newTransaction(),
    AppRoutes.newInstallment(groceries),
    AppRoutes.repayments(),
    AppRoutes.repayment(manual),
    AppRoutes.repayment(auto),
    AppRoutes.newRepayment(statementId: statement),
    AppRoutes.statements(accountId: a),
    AppRoutes.statement(statement, accountId: a),
    AppRoutes.repayments(accountId: a),
    AppRoutes.cashCalendar,
    AppRoutes.cashCalendarWith(basis: 'confirmed'),
    AppRoutes.cashCalendarWith(basis: 'stress', scenario: stress),
    AppRoutes.newScenario,
    AppRoutes.editScenario(stress),
    AppRoutes.scenarioCompare(),
    AppRoutes.cashHome,
    AppRoutes.cashAccount(salary),
    AppRoutes.cashAccount(deposit),
    AppRoutes.recordCashSnapshot(salary),
    AppRoutes.newCashAccount,
    AppRoutes.newCashEvent('income'),
    AppRoutes.cashEvent(event),
    AppRoutes.newTransfer,
    AppRoutes.newRecurring,
    AppRoutes.recurring(rent),
    AppRoutes.editRecurring(rent),
    AppRoutes.home,
    AppRoutes.cards,
    AppRoutes.newCard,
    AppRoutes.account(a),
    AppRoutes.account(d),
    AppRoutes.accountSettings(a),
    AppRoutes.accountSettings(a, section: 'limits'),
    AppRoutes.accountSettings(a, section: 'currencies'),
    AppRoutes.accountSettings(d, section: 'pool'),
    AppRoutes.planner,
    AppRoutes.plan,
    AppRoutes.discover,
    AppRoutes.settings,
    AppRoutes.diagnostics,
    AppRoutes.about,
    AppRoutes.welcome,
    AppRoutes.settingsReset,
  ];
}

Future<void> _checkGuidelines(WidgetTester tester, String page) async {
  await expectLater(
    tester,
    meetsGuideline(iOSTapTargetGuideline),
    reason: page,
  );
  await expectLater(
    tester,
    meetsGuideline(androidTapTargetGuideline),
    reason: page,
  );
  await expectLater(
    tester,
    meetsGuideline(labeledTapTargetGuideline),
    reason: page,
  );
  await expectLater(
    tester,
    meetsGuideline(textContrastGuideline),
    reason: page,
  );
}

void _expectUnclamped(WidgetTester tester, double scale, String page) {
  expect(tester.takeException(), isNull, reason: page);
  final context = tester.element(find.byType(Scaffold).last);
  expect(
    MediaQuery.textScalerOf(context).scale(10),
    closeTo(10 * scale, 0.001),
    reason: '页面内容的文字缩放不应被钳制：$page',
  );
}

/// 把当前页面从顶滚到底，每一屏都没有布局溢出等框架错误（[forEachScreen]）。
Future<void> _expectEachScreenLaidOut(WidgetTester tester, String page) =>
    forEachScreen(
      tester,
      () => expect(tester.takeException(), isNull, reason: '$page（逐屏滚动）'),
    );

void main() {
  testWidgets('自检：逐屏检查能发现只有滚到下面才出现的布局溢出，干净的页面不误报', (tester) async {
    Future<TestFailure?> failureOf(List<Widget> tail) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: <Widget>[
                for (var i = 0; i < 60; i++) Text('第 $i 行'),
                ...tail,
              ],
            ),
          ),
        ),
      );
      try {
        await _expectEachScreenLaidOut(tester, '自检');
      } on TestFailure catch (failure) {
        return failure;
      }
      return null;
    }

    final overflow = await failureOf(<Widget>[
      const Row(children: <Widget>[SizedBox(width: 2000, height: 10)]),
    ]);
    expect(overflow, isNotNull);
    expect(await failureOf(const <Widget>[Text('末行')]), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('全部页面（$brightness）满足触控尺寸、标签与文字对比度要求（演示数据）', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCardFlowApp(
        tester,
        brightness: brightness,
        workspace: TestWorkspace.demo,
      );
      for (final page in await allPages(tester)) {
        await goTo(tester, page);
        await _checkGuidelines(tester, page);
      }
      handle.dispose();
    });

    testWidgets('首次空白与首次使用页（$brightness）满足同样的要求', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCardFlowApp(tester, brightness: brightness);
      for (final page in <String>[
        AppRoutes.home,
        AppRoutes.cards,
        AppRoutes.cashHome,
        AppRoutes.cashCalendar,
        AppRoutes.planner,
        AppRoutes.statements(),
        AppRoutes.repayments(),
      ]) {
        await goTo(tester, page);
        await _checkGuidelines(tester, page);
      }
      handle.dispose();
    });
  }

  testWidgets('P-22 首次使用页（没有工作空间）满足同样的要求', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpCardFlowApp(tester, workspace: TestWorkspace.none);
    await _checkGuidelines(tester, AppRoutes.firstRun);
    handle.dispose();
  });

  testWidgets('启动页（打不开：wrong_key）满足同样的要求', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpCardFlowApp(
      tester,
      useMemoryDatabase: false,
      overrides: <Override>[
        databaseProvider.overrideWith(
          (ref) => Future<AppDatabase>.error(Exception('wrong_key')),
        ),
      ],
    );
    await _checkGuidelines(tester, AppRoutes.startup);
    handle.dispose();
  });

  // ui-spec §3.3：跟随系统字体缩放，不做低于 2.0 倍的钳制；放大后换行而不截断、不溢出。每一页从顶滚到底、
  // 逐屏检查（审查 R-12：ListView 只构建可见的子项，只看首屏会漏掉下面的内容）。
  for (final scale in <double>[2.0, 3.0]) {
    testWidgets('文字放大到 ${scale}x 时所有页面正常布局（含 P-01~P-09、新建卡片、P-22），逐屏滚到底', (
      tester,
    ) async {
      await pumpCardFlowApp(
        tester,
        textScale: scale,
        workspace: TestWorkspace.demo,
      );
      final pages = await allPages(tester);
      for (final page in pages) {
        await goTo(tester, page);
        _expectUnclamped(tester, scale, page);
        await _expectEachScreenLaidOut(tester, page);
      }
      expect(pages, hasLength(47));
    });

    testWidgets('文字放大到 ${scale}x：首次空白、首次使用页与启动页，逐屏滚到底', (tester) async {
      await pumpCardFlowApp(tester, textScale: scale);
      for (final page in <String>[
        AppRoutes.home,
        AppRoutes.cards,
        AppRoutes.cashHome,
        AppRoutes.cashCalendar,
        AppRoutes.planner,
        AppRoutes.statements(),
        AppRoutes.repayments(),
      ]) {
        await goTo(tester, page);
        _expectUnclamped(tester, scale, page);
        await _expectEachScreenLaidOut(tester, page);
      }
    });

    testWidgets('文字放大到 ${scale}x：P-22 首次使用页', (tester) async {
      await pumpCardFlowApp(
        tester,
        textScale: scale,
        workspace: TestWorkspace.none,
      );
      _expectUnclamped(tester, scale, AppRoutes.firstRun);
    });

    testWidgets('文字放大到 ${scale}x：启动页（打开中）', (tester) async {
      final pending = Completer<AppDatabase>();
      await pumpCardFlowApp(
        tester,
        textScale: scale,
        useMemoryDatabase: false,
        overrides: <Override>[
          databaseProvider.overrideWith((ref) => pending.future),
        ],
      );
      _expectUnclamped(tester, scale, AppRoutes.startup);
    });
  }
}
