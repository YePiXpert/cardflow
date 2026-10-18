import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/cards/cards_page.dart';
import '../features/diagnostics/diagnostic_log.dart';
import '../features/diagnostics/diagnostics_page.dart';
import '../features/onboarding/welcome_page.dart';
import '../features/overview/overview_page.dart';
import '../features/planner/planner_page.dart';
import '../features/promotions/promotions_page.dart';
import '../features/settings/settings_page.dart';
import 'routes.dart';
import 'shell/home_shell.dart';
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
Page<void> _page(GoRouterState state, Widget child) => MaterialPage<void>(
  key: state.pageKey,
  name: state.name ?? state.path,
  child: child,
);

/// 构建路由表：五个主导航各一个分支（StatefulShellRoute，切换 Tab 保留栈位置）。
GoRouter createAppRouter({String initialLocation = AppRoutes.initial}) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    errorPageBuilder: (context, state) => _page(state, const NotFoundPage()),
    routes: <RouteBase>[
      GoRoute(path: '/', redirect: (_, _) => AppRoutes.initial),
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, navigationShell) =>
            _page(state, HomeShell(navigationShell: navigationShell)),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.overview,
                pageBuilder: (context, state) =>
                    _page(state, const OverviewPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.cards,
                pageBuilder: (context, state) =>
                    _page(state, const CardsPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.planner,
                pageBuilder: (context, state) =>
                    _page(state, const PlannerPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.discover,
                pageBuilder: (context, state) =>
                    _page(state, const PromotionsPage()),
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
                    path: 'welcome',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) =>
                        _page(state, const WelcomePage()),
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

/// 全局路由。每次位置变化记一条诊断日志（只记路由模板，如 `/settings/diagnostics`，
/// 不记参数）。
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final log = ref.watch(diagnosticLogProvider);
  final router = createAppRouter();
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
  });
  return router;
}
