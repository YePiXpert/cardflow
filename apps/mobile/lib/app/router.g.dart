// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'router.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 全局路由。每次位置变化记一条诊断日志（只记路由模板，如 `/cards/accounts/:accountId`，
/// 不记参数）。启动分流跟随 [appGateProvider]。
///
/// 切换工作空间（进入/退出演示、切换空间、清除演示数据后回到真实空间）之后统一回到首页（总览）：根导航器上
/// 的全屏表单与当前 Tab 的页面栈一并清掉，其余 Tab 的栈在下次进入时从根页开始（`HomeShell`，审查 R-15）。
/// 从没有工作空间（P-22）进入时由调用方决定去哪（例如「手工建卡」去新建卡片）。

@ProviderFor(appRouter)
final appRouterProvider = AppRouterProvider._();

/// 全局路由。每次位置变化记一条诊断日志（只记路由模板，如 `/cards/accounts/:accountId`，
/// 不记参数）。启动分流跟随 [appGateProvider]。
///
/// 切换工作空间（进入/退出演示、切换空间、清除演示数据后回到真实空间）之后统一回到首页（总览）：根导航器上
/// 的全屏表单与当前 Tab 的页面栈一并清掉，其余 Tab 的栈在下次进入时从根页开始（`HomeShell`，审查 R-15）。
/// 从没有工作空间（P-22）进入时由调用方决定去哪（例如「手工建卡」去新建卡片）。

final class AppRouterProvider
    extends $FunctionalProvider<GoRouter, GoRouter, GoRouter>
    with $Provider<GoRouter> {
  /// 全局路由。每次位置变化记一条诊断日志（只记路由模板，如 `/cards/accounts/:accountId`，
  /// 不记参数）。启动分流跟随 [appGateProvider]。
  ///
  /// 切换工作空间（进入/退出演示、切换空间、清除演示数据后回到真实空间）之后统一回到首页（总览）：根导航器上
  /// 的全屏表单与当前 Tab 的页面栈一并清掉，其余 Tab 的栈在下次进入时从根页开始（`HomeShell`，审查 R-15）。
  /// 从没有工作空间（P-22）进入时由调用方决定去哪（例如「手工建卡」去新建卡片）。
  AppRouterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appRouterProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appRouterHash();

  @$internal
  @override
  $ProviderElement<GoRouter> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GoRouter create(Ref ref) {
    return appRouter(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GoRouter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GoRouter>(value),
    );
  }
}

String _$appRouterHash() => r'd6e603719fc221eb4e94610b0627cb5e61ff54b3';
