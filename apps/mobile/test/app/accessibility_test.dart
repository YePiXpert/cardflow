import 'dart:async';

import 'package:cardflow/app/routes.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/database_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

/// 有数据（演示空间）时可到达的全部页面。P-03/P-04 用"卡 A"的账户（含两张卡、规则、快照）
/// 与"卡 D"的账户（授信池、超限）。
Future<List<String>> allPages(WidgetTester tester) async {
  final wallet = await readWallet(tester);
  final a = wallet.accounts.firstWhere((v) => v.displayName == '卡 A').id;
  final d = wallet.accounts.firstWhere((v) => v.displayName == '卡 D').id;
  return <String>[
    AppRoutes.overview,
    AppRoutes.cards,
    AppRoutes.newCard,
    AppRoutes.account(a),
    AppRoutes.account(d),
    AppRoutes.accountSettings(a),
    AppRoutes.accountSettings(a, section: 'limits'),
    AppRoutes.accountSettings(a, section: 'currencies'),
    AppRoutes.accountSettings(d, section: 'pool'),
    AppRoutes.planner,
    AppRoutes.discover,
    AppRoutes.settings,
    AppRoutes.diagnostics,
    AppRoutes.welcome,
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

void main() {
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
      for (final page in <String>[AppRoutes.overview, AppRoutes.cards]) {
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

  // ui-spec §3.3：跟随系统字体缩放，不做低于 2.0 倍的钳制；放大后换行而不截断、不溢出。
  for (final scale in <double>[2.0, 3.0]) {
    testWidgets('文字放大到 ${scale}x 时所有页面正常布局（含 P-01~P-04、新建卡片、P-22）', (
      tester,
    ) async {
      await pumpCardFlowApp(
        tester,
        textScale: scale,
        workspace: TestWorkspace.demo,
      );
      for (final page in await allPages(tester)) {
        await goTo(tester, page);
        _expectUnclamped(tester, scale, page);
      }
    });

    testWidgets('文字放大到 ${scale}x：首次空白、首次使用页与启动页', (tester) async {
      await pumpCardFlowApp(tester, textScale: scale);
      for (final page in <String>[AppRoutes.overview, AppRoutes.cards]) {
        await goTo(tester, page);
        _expectUnclamped(tester, scale, page);
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
