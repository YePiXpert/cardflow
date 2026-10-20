import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/db/database_errors.dart';
import '../../data/db/database_failures.dart';
import '../../data/repositories/models.dart';
import '../../data/repositories/providers.dart';
import '../money/amount_visibility.dart';
import '../routes.dart';

part 'app_gate.g.dart';

/// 启动分流的状态：本机数据库打开中 / 打不开 / 没有工作空间 / 就绪。
sealed class AppGate {
  const AppGate();
}

/// 正在打开本机加密数据库（或重试、重置后重新打开）。
final class GateLoading extends AppGate {
  const GateLoading();

  @override
  bool operator ==(Object other) => other is GateLoading;

  @override
  int get hashCode => 0;
}

/// 本机数据库打不开（只含错误码）。
final class GateDatabaseError extends AppGate {
  const GateDatabaseError(this.error);

  final DatabaseOpenException error;

  @override
  bool operator ==(Object other) =>
      other is GateDatabaseError && other.error == error;

  @override
  int get hashCode => error.hashCode;
}

/// 还没有工作空间：先进 P-22 选择开始方式（ui-spec §1.1，BL-04）。
final class GateNoWorkspace extends AppGate {
  const GateNoWorkspace();

  @override
  bool operator ==(Object other) => other is GateNoWorkspace;

  @override
  int get hashCode => 1;
}

/// 就绪：有当前工作空间。
final class GateReady extends AppGate {
  const GateReady(this.workspace);

  final Workspace workspace;

  @override
  bool operator ==(Object other) =>
      other is GateReady && other.workspace == workspace;

  @override
  int get hashCode => workspace.hashCode;
}

/// 当前的启动分流状态（由当前工作空间 provider 推出；它依赖本机数据库）。"隐藏金额"开关读回之前不进入主导航
/// （页面不会先露出金额）。
@Riverpod(keepAlive: true)
AppGate appGate(Ref ref) {
  final workspace = ref.watch(currentWorkspaceProvider);
  final restoring = ref.watch(amountsHiddenRestoredProvider).isLoading;
  return switch (workspace) {
    AsyncData(value: null) => const GateNoWorkspace(),
    AsyncData(:final value?) =>
      restoring ? const GateLoading() : GateReady(value),
    AsyncError(:final error) => GateDatabaseError(
      databaseOpenExceptionFrom(error),
    ),
    _ => const GateLoading(),
  };
}

/// 路由重定向：
/// - 诊断页任何时候都可以到达（数据库打不开时它是唯一的反馈渠道）；
/// - 打开中或打不开 → 启动页（[AppRoutes.startup]，带上原目标 `from`）；
/// - 没有工作空间 → P-22 首次使用页（[AppRoutes.firstRun]）；
/// - 就绪时离开启动页，回到原目标或卡账。
String? gateRedirect(AppGate gate, GoRouterState state) {
  final path = state.uri.path;
  if (path == AppRoutes.diagnostics) {
    return null;
  }
  final atStartup =
      path == AppRoutes.startup || path == AppRoutes.resetLocalData;
  switch (gate) {
    case GateLoading() || GateDatabaseError():
      if (atStartup) {
        return null;
      }
      final from = state.uri.toString();
      return Uri(
        path: AppRoutes.startup,
        queryParameters: path == AppRoutes.firstRun
            ? null
            : <String, String>{'from': from},
      ).toString();
    case GateNoWorkspace():
      return path == AppRoutes.firstRun ? null : AppRoutes.firstRun;
    case GateReady():
      if (atStartup) {
        final from = state.uri.queryParameters['from'];
        return from == null || from.startsWith(AppRoutes.startup)
            ? AppRoutes.initial
            : from;
      }
      return null;
  }
}

/// 把 [appGate] 的变化转成 go_router 的 `refreshListenable`。
final class AppGateNotifier extends ValueNotifier<AppGate> {
  AppGateNotifier(super.value);
}
