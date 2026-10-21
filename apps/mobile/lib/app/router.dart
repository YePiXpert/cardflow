import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/repositories/providers.dart';
import '../features/cards/account_detail_page.dart';
import '../features/cards/account_settings_page.dart';
import '../features/cards/cards_page.dart';
import '../features/cards/new_card_page.dart';
import '../features/diagnostics/diagnostics_page.dart';
import '../features/onboarding/welcome_page.dart';
import '../features/selection/selection_page.dart';
import '../features/settings/about_page.dart';
import '../features/settings/settings_page.dart';
import 'diagnostics/diagnostic_log.dart';
import 'routes.dart';
import 'shell/home_shell.dart';
import 'startup/app_gate.dart';
import 'startup/reset_local_data_page.dart';
import 'startup/startup_page.dart';
import 'widgets/not_found_page.dart';

part 'router.g.dart';

/// 根导航器。全屏页面（如欢迎页）挂在这里，覆盖底部导航。
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

/// 用 Flutter SDK 自带 Material 库的 [MaterialPage] 包装页面。
///
/// go_router 18 只把 material_ui 包里的 MaterialApp 识别为 Material 应用；本工程
/// 使用 SDK 自带的 package:flutter/material.dart，若不显式给 pageBuilder，
/// go_router 会退回无转场页面，iOS 侧滑返回也会失效。
Page<void> _page(
  GoRouterState state,
  Widget child, {
  bool fullscreenDialog = false,
}) => MaterialPage<void>(
  key: state.pageKey,
  name: state.name ?? state.path,
  fullscreenDialog: fullscreenDialog,
  child: child,
);

GoRouter createAppRouter({
  String initialLocation = AppRoutes.initial,
  ValueListenable<AppGate>? gate,
}) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    refreshListenable: gate,
    redirect: (context, state) =>
        legacyRedirect(state.uri) ??
        (gate == null ? null : gateRedirect(gate.value, state)),
    errorPageBuilder: (context, state) => _page(state, const NotFoundPage()),
    routes: <RouteBase>[
      GoRoute(path: '/', redirect: (_, _) => AppRoutes.initial),
      GoRoute(
        path: AppRoutes.startup,
        pageBuilder: (context, state) => _page(state, const StartupPage()),
        routes: <RouteBase>[
          GoRoute(
            path: 'reset',
            pageBuilder: (context, state) =>
                _page(state, const ResetLocalDataPage()),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.firstRun,
        pageBuilder: (context, state) =>
            _page(state, const WelcomePage(firstRun: true)),
      ),
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, navigationShell) =>
            _page(state, HomeShell(navigationShell: navigationShell)),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.home,
                pageBuilder: (context, state) =>
                    _page(state, const SelectionPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.cards,
                pageBuilder: (context, state) =>
                    _page(state, const CardsPage()),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'new',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) => _page(
                      state,
                      const NewCardPage(),
                      fullscreenDialog: true,
                    ),
                  ),
                  GoRoute(
                    path: 'accounts/:accountId',
                    pageBuilder: (context, state) => _page(
                      state,
                      AccountDetailPage(
                        accountId: state.pathParameters['accountId']!,
                      ),
                    ),
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'settings',
                        pageBuilder: (context, state) => _page(
                          state,
                          AccountSettingsPage(
                            accountId: state.pathParameters['accountId']!,
                            initialSection: AccountSettingsSection.parse(
                              state.uri.queryParameters['section'],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.settings,
                pageBuilder: (context, state) =>
                    _page(state, const SettingsPage()),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'diagnostics',
                    pageBuilder: (context, state) =>
                        _page(state, const DiagnosticsPage()),
                  ),
                  GoRoute(
                    path: 'about',
                    pageBuilder: (context, state) =>
                        _page(state, const AboutPage()),
                  ),
                  GoRoute(
                    path: 'welcome',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) =>
                        _page(state, const WelcomePage()),
                  ),
                  GoRoute(
                    path: 'reset',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) => _page(
                      state,
                      const ResetLocalDataPage(fromSettings: true),
                      fullscreenDialog: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// 全局路由。每次位置变化记一条诊断日志（只记路由模板，如 `/cards/accounts/:accountId`，
/// 不记参数）。启动分流跟随 [appGateProvider]。
///
/// 切换工作空间（进入/退出演示、切换空间、清除演示数据后回到真实空间）之后统一回到首页（用卡）：根导航器上
/// 的全屏表单与当前 Tab 的页面栈一并清掉，其余 Tab 的栈在下次进入时从根页开始（`HomeShell`，审查 R-15）。
/// 从没有工作空间（P-22）进入时由调用方决定去哪（例如「手工建卡」去新建卡片）。
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final log = ref.watch(diagnosticLogProvider);
  final gate = AppGateNotifier(ref.read(appGateProvider));
  ref.listen(appGateProvider, (_, next) => gate.value = next);
  final router = createAppRouter(gate: gate);
  ref.listen(currentWorkspaceProvider, (previous, next) {
    final from = previous?.value?.id;
    if (from != null && next.hasValue && next.value?.id != from) {
      router.go(AppRoutes.home);
    }
  });
  void onRouteChanged() {
    final configuration = router.routerDelegate.currentConfiguration;
    log.info(
      'route',
      'changed',
      detail: configuration.isError ? '未匹配' : configuration.fullPath,
    );
  }

  router.routerDelegate.addListener(onRouteChanged);
  ref.onDispose(() {
    router.routerDelegate.removeListener(onRouteChanged);
    router.dispose();
    gate.dispose();
  });
  return router;
}
