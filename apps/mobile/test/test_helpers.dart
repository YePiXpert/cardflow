import 'package:cardflow/app/app.dart';
import 'package:cardflow/app/router.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/database_providers.dart';
import 'package:cardflow/data/demo/demo_workspace.dart';
import 'package:cardflow/data/repositories/card_wallet_reader.dart';
import 'package:cardflow/data/repositories/cash_plan_reader.dart';
import 'package:cardflow/data/repositories/models.dart';
import 'package:cardflow/data/repositories/providers.dart';
import 'package:cardflow/data/repositories/workspace_repository.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow/data/time/clock.dart';
import 'package:cardflow/features/diagnostics/crypto_status.dart';
import 'package:cardflow/features/statements/installment_cost.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    version: '0.0.2',
    buildNumber: '7',
    buildSignature: '',
  );
}

/// 组件测试默认使用的加密库状态。
const CryptoLibraryStatus fakeCryptoStatus = CryptoLibraryReady(
  library: 'SQLite3 Multiple Ciphers 2.6.1',
  cipher: 'chacha20',
);

/// 组件测试里替换加密本地库状态的 provider：诊断页显示的加密库与密钥状态。真实加密库的行为见
/// test/data/db/；在组件测试里用真实加密库的例子见 test/features/diagnostics/diagnostics_page_test.dart。
List<Override> fakeDatabaseOverrides({
  CryptoLibraryStatus status = fakeCryptoStatus,
  bool keyExists = true,
}) => <Override>[
  cryptoLibraryStatusProvider.overrideWith((ref) async => status),
  databaseKeyExistsProvider.overrideWith((ref) async => keyExists),
];

/// 组件测试里本地库的预设。
enum TestWorkspace {
  /// 没有工作空间：启动后进 P-22。
  none,

  /// 一个空的真实空间（默认）。
  real,

  /// 演示空间（合成数据）为当前工作空间。
  demo,
}

/// 组件测试里真实空间的"现在"：北京时间 2026-10-18 12:00（演示空间固定 2026-10-16）。
final FixedClock widgetTestClock = FixedClock(DateTime.utc(2026, 10, 18, 4));

/// 最近一次 [createWidgetTestDatabase] 建的内存库。
AppDatabase? _lastTestDatabase;

/// 当前组件测试的内存库（用 [readWallet] 一类辅助在 `tester.runAsync` 里直接查数据）。
AppDatabase get testDatabase =>
    _lastTestDatabase ?? (throw StateError('pumpCardFlowApp 还没有建内存库'));

/// 真实空间在组件测试里用的时钟（[pumpCardFlowApp] 的 `realClock` 可替换，例如判断陈旧的时钟）。
AppClock _realClock = widgetTestClock;

/// 直接查库得到当前工作空间的卡包读模型（不经 provider：在真实事件循环里建 provider 的订阅，
/// 会让之后伪时钟里的查询等不到结果）。
Future<WalletView> readWallet(WidgetTester tester) async =>
    withCurrentScope(tester, (scope) => CardWalletReader(scope).load());

/// 直接查库得到当前工作空间的现金与收支读模型（同 [readWallet]）。
Future<CashPlanView> readCashPlan(WidgetTester tester) async =>
    withCurrentScope(tester, (scope) => CashPlanReader(scope).load());

/// 在真实事件循环里以当前工作空间的作用域运行 [action]（读写数据、调用仓库）。
Future<T> withCurrentScope<T>(
  WidgetTester tester,
  Future<T> Function(WorkspaceScope scope) action,
) async {
  late T result;
  await tester.runAsync(() async {
    final db = testDatabase;
    final row = await WorkspaceRepository(db).current();
    final scope = WorkspaceScope(
      db: db,
      workspaceId: row!.id,
      clock: row.kind == WorkspaceKind.demo.code ? demoClock : _realClock,
    );
    result = await action(scope);
  });
  return result;
}

/// 组件测试的本地库：内存库（不加密，`AppDatabase.forTesting`），按 [workspace] 预置数据，
/// [seed] 可在真实空间里再写入数据。写入在真实事件循环里完成（`tester.runAsync`），测试结束时关闭。
Future<AppDatabase> createWidgetTestDatabase(
  WidgetTester tester, {
  TestWorkspace workspace = TestWorkspace.real,
  Future<void> Function(WorkspaceScope scope)? seed,
  AppClock? realClock,
}) async {
  final db = _lastTestDatabase = AppDatabase.forTesting(
    NativeDatabase.memory(),
  );
  await tester.runAsync(() async {
    final workspaces = WorkspaceRepository(db, clock: widgetTestClock);
    switch (workspace) {
      case TestWorkspace.none:
        await workspaces.current();
      case TestWorkspace.real:
        final row = await workspaces.ensure(WorkspaceKind.real);
        await workspaces.setCurrent(row.id);
        if (seed != null) {
          await seed(
            WorkspaceScope(
              db: db,
              workspaceId: row.id,
              clock: realClock ?? widgetTestClock,
            ),
          );
        }
      case TestWorkspace.demo:
        final row = await ensureDemoWorkspace(db);
        await workspaces.setCurrent(row.id);
    }
  });
  // 关库给一个上限：测试失败中途退出时，可能还有排在伪时钟里的查询占着 drift 的锁。
  addTearDown(
    () => tester.runAsync(
      () => db.close().timeout(const Duration(seconds: 5), onTimeout: () {}),
    ),
  );
  return db;
}

/// 用内存库 [db] 替换本机加密库；时钟：演示空间固定 2026-10-16，真实空间固定 [realClock]
/// （默认 [widgetTestClock]）。
List<Override> testDatabaseOverrides(AppDatabase db, {AppClock? realClock}) =>
    <Override>[
      databaseProvider.overrideWith((ref) async => db),
      clockProvider.overrideWith((ref) {
        final workspace = ref.watch(currentWorkspaceProvider).value;
        return workspace != null && workspace.isDemo
            ? demoClock
            : realClock ?? widgetTestClock;
      }),
    ];

/// 组件测试里的分期成本就地计算：伪时钟里等不到后台 isolate 的结果（审查 R-04 的测试另用真正的后台
/// isolate，见 `installment_cost_test.dart`）。
final Override inlineInstallmentCosts = installmentCostRunnerProvider
    .overrideWithValue((input) async => input.compute());

/// 启动完整 App（真实路由、主题与 Provider），可选覆盖。
///
/// 默认：加密库状态用 [fakeDatabaseOverrides]，本地库用内存库并预置 [workspace]（默认一个空的
/// 真实空间，启动后停在总览）。[databaseOverrides] 替换加密库状态；要用真实加密库（钥匙串与目录
/// 的替身）时同时传 `useMemoryDatabase: false`。分期成本默认就地计算（[inlineInstallmentCosts]）；
/// [backgroundCosts] 为真时保留 App 的后台 isolate 计算。
Future<void> pumpCardFlowApp(
  WidgetTester tester, {
  double textScale = 1.0,
  Brightness brightness = Brightness.light,
  List<Override> overrides = const <Override>[],
  List<Override>? databaseOverrides,
  TestWorkspace workspace = TestWorkspace.real,
  Future<void> Function(WorkspaceScope scope)? seed,
  bool useMemoryDatabase = true,
  AppClock? realClock,
  bool backgroundCosts = false,
}) async {
  mockPackageInfo();
  usePhoneSurface(tester, textScale: textScale, brightness: brightness);
  _realClock = realClock ?? widgetTestClock;
  addTearDown(() => _realClock = widgetTestClock);
  final memory = useMemoryDatabase
      ? testDatabaseOverrides(
          await createWidgetTestDatabase(
            tester,
            workspace: workspace,
            seed: seed,
            realClock: realClock,
          ),
          realClock: realClock,
        )
      : const <Override>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        ...(databaseOverrides ?? fakeDatabaseOverrides()),
        ...memory,
        if (!backgroundCosts) inlineInstallmentCosts,
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

/// 截获写入剪贴板的文字。
List<String> captureClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        final arguments = call.arguments as Map<Object?, Object?>;
        copied.add(arguments['text']! as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}
