import 'package:cardflow/app/app.dart';
import 'package:cardflow/app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// iPhone 15 的逻辑分辨率。
const Size phoneLogicalSize = Size(393, 852);

/// 把测试视图设为手机尺寸，并设置文字缩放与深浅色。
void usePhoneSurface(
  WidgetTester tester, {
  double textScale = 1.0,
  Brightness brightness = Brightness.light,
}) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = phoneLogicalSize * 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

/// 模拟 package_info_plus 的平台返回值。
void mockPackageInfo() {
  PackageInfo.setMockInitialValues(
    appName: '卡序',
    packageName: 'li.yep.cardflow',
    version: '0.0.1',
    buildNumber: '7',
    buildSignature: '',
  );
}

/// 启动完整 App（真实路由、主题与 Provider），可选覆盖。
Future<void> pumpCardFlowApp(
  WidgetTester tester, {
  double textScale = 1.0,
  Brightness brightness = Brightness.light,
  List<Override> overrides = const <Override>[],
}) async {
  mockPackageInfo();
  usePhoneSurface(tester, textScale: textScale, brightness: brightness);
  await tester.pumpWidget(
    ProviderScope(overrides: overrides, child: const CardFlowApp()),
  );
  await tester.pumpAndSettle();
}

/// App 使用的 Provider 容器。
ProviderContainer appContainer(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(CardFlowApp)));

/// App 使用的路由。
GoRouter appRouter(WidgetTester tester) =>
    appContainer(tester).read(appRouterProvider);

/// 跳转到指定位置并等待转场结束。
Future<void> goTo(WidgetTester tester, String location) async {
  appRouter(tester).go(location);
  await tester.pumpAndSettle();
}

/// 底部导航中的某个标签。
Finder navLabel(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

/// 顶栏中的页名。
Finder appBarTitle(String title) =>
    find.descendant(of: find.byType(AppBar), matching: find.text(title));
