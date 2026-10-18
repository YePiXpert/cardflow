import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../time/clock.dart';

/// 一个仓库实例的作用域：数据库、**当前工作空间**与时钟。
///
/// 所有业务仓库都由它构造，查询一律带 `workspace_id = scope.workspaceId`；写入一律写这个
/// 工作空间（工作空间隔离，R-SYS-13；测试见 `test/data/repositories/workspace_isolation_test.dart`）。
/// 切换工作空间 = 换一个 scope（provider 会重建所有仓库）。
@immutable
final class WorkspaceScope {
  const WorkspaceScope({
    required this.db,
    required this.workspaceId,
    required this.clock,
  });

  final AppDatabase db;
  final String workspaceId;

  /// 真实空间是系统时钟，演示空间是固定的 2026-10-16。
  final AppClock clock;
}
