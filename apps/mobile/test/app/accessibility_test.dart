import 'dart:async';

import 'package:cardflow/app/routes.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/database_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../support/forbidden_ui.dart' show forEachScreen;
import '../test_helpers.dart';

/// 当前可到达的全部页面，覆盖卡片和共享池设置。
Future<List<String>> allPages(WidgetTester tester) async {
  final wallet = await readWallet(tester);
  final a = wallet.accounts.firstWhere((v) => v.displayName == '卡 A').id;
  final d = wallet.accounts.firstWhere((v) => v.displayName == '卡 D').id;
  return <String>[
    AppRoutes.home,
    AppRoutes.cards,
    AppRoutes.newCard,
    AppRoutes.account(a),
    AppRoutes.account(d),
    AppRoutes.accountSettings(a),
    AppRoutes.accountSettings(a, section: 'limits'),
    AppRoutes.accountSettings(a, section: 'currencies'),
    AppRoutes.accountSettings(d, section: 'pool'),
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
      for (final page in <String>[AppRoutes.home, AppRoutes.cards]) {
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
    testWidgets('文字放大到 ${scale}x 时所有页面正常布局（用卡、卡片、设置与欢迎页），逐屏滚到底', (
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
      expect(pages, hasLength(14));
    });

    testWidgets('文字放大到 ${scale}x：首次空白、首次使用页与启动页，逐屏滚到底', (tester) async {
      await pumpCardFlowApp(tester, textScale: scale);
      for (final page in <String>[AppRoutes.home, AppRoutes.cards]) {
        await goTo(tester, page);
        _expectUnclamped(tester, scale, page);
        if (page.startsWith('/cards/accounts/') &&
            !page.contains('/settings')) {
          for (final label in ['额度明细', '账期规则']) {
            await tester.scrollUntilVisible(
              find.text(label),
              200,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.ensureVisible(find.text(label).first);
            await tester.tap(find.text(label).first);
            await tester.pumpAndSettle();
          }
          final scroll = tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position;
          scroll.jumpTo(0);
          await tester.pumpAndSettle();
        }
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
