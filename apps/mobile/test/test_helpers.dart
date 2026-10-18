import 'package:cardflow/app/app.dart';
import 'package:cardflow/app/router.dart';
import 'package:cardflow/data/db/database_providers.dart';
import 'package:cardflow/features/diagnostics/crypto_status.dart';
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

/// 组件测试默认使用的加密库状态。
const CryptoLibraryStatus fakeCryptoStatus = CryptoLibraryReady(
  library: 'SQLite3 Multiple Ciphers 2.6.1',
  cipher: 'chacha20',
);

/// 组件测试里替换加密本地库的 provider：不碰钥匙串、文件与后台 isolate（组件测试的
/// 伪异步时钟里跑不了真实 I/O）。真实加密库的行为见 test/data/db/；在组件测试里用真实
/// 加密库的例子见 test/features/diagnostics/diagnostics_page_test.dart。
List<Override> fakeDatabaseOverrides({
  CryptoLibraryStatus status = fakeCryptoStatus,
  bool keyExists = true,
}) => <Override>[
  cryptoLibraryStatusProvider.overrideWith((ref) async => status),
  databaseKeyExistsProvider.overrideWith((ref) async => keyExists),
];

/// 启动完整 App（真实路由、主题与 Provider），可选覆盖。
///
/// [databaseOverrides] 默认是 [fakeDatabaseOverrides]；要换加密库状态或改用真实加密库时传入。
Future<void> pumpCardFlowApp(
  WidgetTester tester, {
  double textScale = 1.0,
  Brightness brightness = Brightness.light,
  List<Override> overrides = const <Override>[],
  List<Override>? databaseOverrides,
}) async {
  mockPackageInfo();
  usePhoneSurface(tester, textScale: textScale, brightness: brightness);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        ...(databaseOverrides ?? fakeDatabaseOverrides()),
        ...overrides,
      ],
      child: const CardFlowApp(),
    ),
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
