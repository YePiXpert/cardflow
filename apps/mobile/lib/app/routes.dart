/// 路由路径常量。五个主导航的根路径与 ui-spec §1.1 的顺序一致。
abstract final class AppRoutes {
  /// 总览（P-01）。
  static const String overview = '/overview';

  /// 卡包（P-02）。
  static const String cards = '/cards';

  /// 规划（P-10）。
  static const String planner = '/planner';

  /// 发现（P-14）。
  static const String discover = '/discover';

  /// 我的（P-19）。
  static const String settings = '/settings';

  /// 诊断信息（我的 › 诊断信息）。
  static const String diagnostics = '/settings/diagnostics';

  /// 欢迎与开始方式（P-22，全屏，覆盖底部导航）。
  static const String welcome = '/settings/welcome';

  /// 启动时的初始位置。
  static const String initial = overview;

  /// 五个主导航根路径，顺序固定（ui-spec §1.1）。
  static const List<String> tabRoots = <String>[
    overview,
    cards,
    planner,
    discover,
    settings,
  ];
}
