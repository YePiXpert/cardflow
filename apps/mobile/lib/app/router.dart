import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/repositories/cash_models.dart';
import '../data/repositories/providers.dart';
import '../features/calendar/cash_calendar_page.dart';
import '../features/cards/account_detail_page.dart';
import '../features/cards/account_settings_page.dart';
import '../features/cards/cards_page.dart';
import '../features/cards/new_card_page.dart';
import '../features/cash/cash_account_pages.dart';
import '../features/cash/cash_entry_pages.dart';
import '../features/cash/cash_home_page.dart';
import '../features/diagnostics/diagnostics_page.dart';
import '../features/home/ledger_home_page.dart';
import '../features/onboarding/welcome_page.dart';
import '../features/planner/planner_page.dart';
import '../features/promotions/promotions_page.dart';
import '../features/repayments/repayment_form_page.dart';
import '../features/repayments/repayment_pages.dart';
import '../features/scenarios/scenario_pages.dart';
import '../features/settings/about_page.dart';
import '../features/settings/settings_page.dart';
import '../features/statements/statement_forms.dart';
import '../features/statements/statement_pages.dart';
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

/// 账单与还款（P-05/P-06）的子路由：挂在卡账首页（`/home`）与卡片详情（`/home/accounts/:accountId`）两处。
/// 页面拿到 `accountId`（首页栈里为空）用来拼回到同一个栈里的链接；表单是全屏页（根导航器）。
List<RouteBase> _ledgerRoutes() {
  String? accountOf(GoRouterState state) => state.pathParameters['accountId'];
  return <RouteBase>[
    GoRoute(
      path: 'statements',
      pageBuilder: (context, state) =>
          _page(state, StatementCenterPage(accountId: accountOf(state))),
      routes: <RouteBase>[
        GoRoute(
          path: 'new',
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (context, state) => _page(
            state,
            StatementEntryPage(
              accountId: accountOf(state),
              currencyAccountId: state.uri.queryParameters['currency'],
            ),
            fullscreenDialog: true,
          ),
        ),
        GoRoute(
          path: ':statementId',
          pageBuilder: (context, state) => _page(
            state,
            StatementDetailPage(
              statementId: state.pathParameters['statementId']!,
              accountId: accountOf(state),
            ),
          ),
          routes: <RouteBase>[
            GoRoute(
              path: 'correct',
              parentNavigatorKey: rootNavigatorKey,
              pageBuilder: (context, state) => _page(
                state,
                StatementCorrectionPage(
                  statementId: state.pathParameters['statementId']!,
                  accountId: accountOf(state),
                ),
                fullscreenDialog: true,
              ),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: 'transactions/new',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) => _page(
        state,
        TransactionFormPage(
          accountId: accountOf(state),
          currencyAccountId: state.uri.queryParameters['currency'],
        ),
        fullscreenDialog: true,
      ),
    ),
    GoRoute(
      path: 'transactions/:transactionId/installment',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) => _page(
        state,
        InstallmentFormPage(
          transactionId: state.pathParameters['transactionId']!,
          accountId: accountOf(state),
        ),
        fullscreenDialog: true,
      ),
    ),
    GoRoute(
      path: 'repayments',
      pageBuilder: (context, state) =>
          _page(state, RepaymentCenterPage(accountId: accountOf(state))),
      routes: <RouteBase>[
        GoRoute(
          path: 'new',
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (context, state) => _page(
            state,
            RepaymentFormPage(
              accountId: accountOf(state),
              statementId: state.uri.queryParameters['statement'],
              currencyAccountId: state.uri.queryParameters['currency'],
            ),
            fullscreenDialog: true,
          ),
        ),
        GoRoute(
          path: ':repaymentId',
          pageBuilder: (context, state) => _page(
            state,
            RepaymentDetailPage(
              repaymentId: state.pathParameters['repaymentId']!,
              accountId: accountOf(state),
            ),
          ),
        ),
      ],
    ),
  ];
}

/// 构建路由表：启动页、首次使用页与四个主导航（StatefulShellRoute，切换 Tab 保留栈位置）。
///
/// [gate] 非空时启用启动分流（`app_gate.dart` 的 [gateRedirect]）：数据库打开中或打不开 →
/// 启动页；没有工作空间 → P-22；它变化时路由重新判断。0.0.1 的旧路径先经 [legacyRedirect] 换成新位置。
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
          // 卡账：首页、管理全部卡片（P-02）、卡片详情（P-03）与设置（P-04）、账单与还款（P-05/P-06）。
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.home,
                pageBuilder: (context, state) =>
                    _page(state, const LedgerHomePage()),
                routes: <RouteBase>[
                  ..._ledgerRoutes(),
                  GoRoute(
                    path: 'manage',
                    pageBuilder: (context, state) =>
                        _page(state, const CardsPage()),
                  ),
                  GoRoute(
                    path: 'new-card',
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
                      ..._ledgerRoutes(),
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
          // 现金：余额曲线与"接下来"、现金账户与收支计划（P-08）、资金日历的表格视图（P-07）。
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.cashHome,
                pageBuilder: (context, state) =>
                    _page(state, const CashHomePage()),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'calendar',
                    pageBuilder: (context, state) => _page(
                      state,
                      CashCalendarPage(
                        // 带不同的初始口径进入时重建页面状态。
                        key: ValueKey<String>(state.uri.toString()),
                        initialBasis: CashCalendarPage.parseBasis(
                          state.uri.queryParameters['basis'],
                        ),
                        initialScenario: state.uri.queryParameters['scenario'],
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'new-account',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) => _page(
                      state,
                      const NewCashAccountPage(),
                      fullscreenDialog: true,
                    ),
                  ),
                  GoRoute(
                    path: 'new-event',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) => _page(
                      state,
                      CashEventFormPage(
                        initialType: CashPlanType.parse(
                          state.uri.queryParameters['type'],
                        ),
                      ),
                      fullscreenDialog: true,
                    ),
                  ),
                  GoRoute(
                    path: 'new-transfer',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) => _page(
                      state,
                      const TransferFormPage(),
                      fullscreenDialog: true,
                    ),
                  ),
                  GoRoute(
                    path: 'new-recurring',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) => _page(
                      state,
                      const RecurringFormPage(),
                      fullscreenDialog: true,
                    ),
                  ),
                  GoRoute(
                    path: 'events/:eventId',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) => _page(
                      state,
                      CashEventFormPage(
                        eventId: state.pathParameters['eventId'],
                      ),
                      fullscreenDialog: true,
                    ),
                  ),
                  GoRoute(
                    path: 'accounts/:accountId',
                    pageBuilder: (context, state) => _page(
                      state,
                      CashAccountDetailPage(
                        accountId: state.pathParameters['accountId']!,
                      ),
                    ),
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'snapshot',
                        parentNavigatorKey: rootNavigatorKey,
                        pageBuilder: (context, state) => _page(
                          state,
                          RecordCashSnapshotPage(
                            accountId: state.pathParameters['accountId']!,
                          ),
                          fullscreenDialog: true,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'recurring/:itemId',
                    pageBuilder: (context, state) => _page(
                      state,
                      RecurringDetailPage(
                        itemId: state.pathParameters['itemId']!,
                      ),
                    ),
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'edit',
                        parentNavigatorKey: rootNavigatorKey,
                        pageBuilder: (context, state) => _page(
                          state,
                          RecurringFormPage(
                            itemId: state.pathParameters['itemId'],
                          ),
                          fullscreenDialog: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          // 规划：情景与假设对比（P-09）；消费规划（P-10）与活动（P-14）后续版本提供。
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.planner,
                pageBuilder: (context, state) =>
                    _page(state, const ScenariosPage()),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'plan',
                    pageBuilder: (context, state) =>
                        _page(state, const PlannerPage()),
                  ),
                  GoRoute(
                    path: 'discover',
                    pageBuilder: (context, state) =>
                        _page(state, const PromotionsPage()),
                  ),
                  GoRoute(
                    path: 'scenarios/new',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) => _page(
                      state,
                      const ScenarioEditorPage(),
                      fullscreenDialog: true,
                    ),
                  ),
                  GoRoute(
                    path: 'scenarios/compare',
                    pageBuilder: (context, state) => _page(
                      state,
                      ScenarioComparePage(
                        key: ValueKey<String>(state.uri.toString()),
                        a: state.uri.queryParameters['a'],
                        b: state.uri.queryParameters['b'],
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'scenarios/edit/:scenarioId',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) => _page(
                      state,
                      ScenarioEditorPage(
                        scenarioId: state.pathParameters['scenarioId'],
                      ),
                      fullscreenDialog: true,
                    ),
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
/// 切换工作空间（进入/退出演示、切换空间、清除演示数据后回到真实空间）之后统一回到首页（卡账）：根导航器上
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
