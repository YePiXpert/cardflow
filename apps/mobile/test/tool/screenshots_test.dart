// 截图工具（简报 U-1 §7）：只在环境变量 CARDFLOW_SCREENSHOTS=1 时运行（CI 跳过）。
//
//   CARDFLOW_SCREENSHOTS=1 flutter test test/tool/screenshots_test.dart
//
// 渲染演示空间的各页（iPhone 393×852、3 倍、iOS 平台、深色与浅色），输出到 build/screenshots/。测试环境没有
// 系统字体：加载系统中文字体文泉驿微米黑与 Flutter SDK 自带的 MaterialIcons，并让主题的每一种文字样式都用
// 这个字体族（appFontFamilyProvider），截图里不能有方块字。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cardflow/app/app.dart';
import 'package:cardflow/app/routes.dart';
import 'package:cardflow/data/repositories/ledger_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

/// 中文字体（系统自带，不打包进 App）。
const String cjkFontPath = '/usr/share/fonts/truetype/wqy/wqy-microhei.ttc';

/// 截图用的字体族名。
const String screenshotFont = 'CardFlowScreenshot';

/// 输出目录（相对 apps/mobile）。
const String outputDir = 'build/screenshots';

final bool _enabled = Platform.environment['CARDFLOW_SCREENSHOTS'] == '1';

Future<void> _loadFonts() async {
  final cjk = FontLoader(screenshotFont)
    ..addFont(
      Future<ByteData>.value(
        ByteData.sublistView(File(cjkFontPath).readAsBytesSync()),
      ),
    );
  await cjk.load();
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter-sdk';
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future<ByteData>.value(
        ByteData.sublistView(
          File(
            '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytesSync(),
        ),
      ),
    );
  await icons.load();
}

/// 一张截图：名称、位置（演示空间里取 id 的函数）、往下再截几屏（长页面）。
typedef Shot = (
  String,
  Future<String> Function(WidgetTester tester), {
  int more,
});

Future<String> _accountA(WidgetTester tester) async {
  final wallet = await readWallet(tester);
  return wallet.accounts.firstWhere((a) => a.bank.name == '星海银行').id;
}

Future<String> _statementA(WidgetTester tester) async {
  final ledger = await withCurrentScope(
    tester,
    (scope) => LedgerReader(scope).load(),
  );
  return ledger.statements.single.id;
}

final List<Shot> shots = <Shot>[
  ('01-home', (_) async => AppRoutes.home, more: 1),
  ('02-card', (t) async => AppRoutes.account(await _accountA(t)), more: 2),
  ('03-cash', (_) async => AppRoutes.cashHome, more: 2),
  ('04-planner', (_) async => AppRoutes.planner, more: 0),
  ('05-settings', (_) async => AppRoutes.settings, more: 1),
  ('06-new-card', (_) async => AppRoutes.newCard, more: 0),
  (
    '07-statement',
    (t) async => AppRoutes.statement(
      await _statementA(t),
      accountId: await _accountA(t),
    ),
    more: 1,
  ),
  (
    '08-repayment',
    (t) async => AppRoutes.newRepayment(
      accountId: await _accountA(t),
      statementId: await _statementA(t),
    ),
    more: 0,
  ),
];

/// 把页面的主滚动区往下滚 80% 屏；已经到底时返回 false。
Future<bool> _scrollDown(WidgetTester tester) async {
  final vertical = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );
  if (vertical.evaluate().isEmpty) {
    return false;
  }
  final position = tester.state<ScrollableState>(vertical.first).position;
  if (position.pixels >= position.maxScrollExtent) {
    return false;
  }
  position.jumpTo(
    (position.pixels + position.viewportDimension * 0.8).clamp(
      0,
      position.maxScrollExtent,
    ),
  );
  await tester.pumpAndSettle();
  return true;
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$outputDir/$name.png')..createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  for (final brightness in Brightness.values) {
    final mode = brightness == Brightness.dark ? 'dark' : 'light';
    testWidgets(
      '演示空间各页截图（$mode）',
      skip: !_enabled,
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      (tester) async {
        await tester.runAsync(_loadFonts);
        mockPackageInfo();
        usePhoneSurface(tester, brightness: brightness);
        // iPhone 15 的安全区：上 59、下 34（状态栏与 Home 指示条的位置留空）。
        tester.view.padding = const FakeViewPadding(
          top: 59 * 3,
          bottom: 34 * 3,
        );
        tester.view.viewPadding = const FakeViewPadding(
          top: 59 * 3,
          bottom: 34 * 3,
        );
        final db = await createWidgetTestDatabase(
          tester,
          workspace: TestWorkspace.demo,
        );
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: ProviderScope(
              overrides: [
                ...fakeDatabaseOverrides(),
                ...testDatabaseOverrides(db),
                inlineInstallmentCosts,
                appFontFamilyProvider.overrideWithValue(screenshotFont),
              ],
              child: const CardFlowApp(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final (name, location, :more) in shots) {
          await goTo(tester, await location(tester));
          await _capture(tester, key, '$name-$mode');
          for (var i = 1; i <= more; i++) {
            if (!await _scrollDown(tester)) {
              break;
            }
            await _capture(tester, key, '$name-$mode-${i + 1}');
          }
        }
      },
    );
  }
}
