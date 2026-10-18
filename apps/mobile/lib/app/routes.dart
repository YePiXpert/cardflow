/// 路由路径常量。五个主导航的根路径与 ui-spec §1.1 的顺序一致。
///
/// 启动分流（`lib/app/startup/app_gate.dart`）：本机数据库还在打开或打不开 → [startup]；
/// 没有工作空间 → [welcome]（P-22）；就绪后才进入五个主导航（BL-04）。诊断页任何时候都可到达。
abstract final class AppRoutes {
  /// 总览（P-01）。
  static const String overview = '/overview';

  /// 卡包（P-02）。
  static const String cards = '/cards';

  /// 新建卡片（P-02 的新建弹层，全屏覆盖底部导航）。
  static const String newCard = '/cards/new';

  /// 规划（P-10）。
  static const String planner = '/planner';

  /// 发现（P-14）。
  static const String discover = '/discover';

  /// 我的（P-19）。
  static const String settings = '/settings';

  /// 诊断信息（我的 › 诊断信息）。
  static const String diagnostics = '/settings/diagnostics';

  /// 欢迎与开始方式（P-22，从"我的"进入，全屏覆盖底部导航，可返回）。
  static const String welcome = '/settings/welcome';

  /// 首次使用（P-22，没有工作空间时任何路由都先到这里，没有返回）。
  static const String firstRun = '/welcome';

  /// 启动：正在打开本机加密数据库，或打开失败（错误码、重试、重置本地数据）。
  static const String startup = '/startup';

  /// 重置本地数据的确认页（ui-spec §4.5：写明影响、输入"删除"）。
  static const String resetLocalData = '/startup/reset';

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

  /// 信用账户详情（P-03）。
  static String account(String accountId) => '$cards/accounts/$accountId';

  /// 信用账户设置（P-04）；[section] 为初始分段（见 `AccountSettingsSection`）。
  static String accountSettings(String accountId, {String? section}) {
    final base = '${account(accountId)}/settings';
    return section == null ? base : '$base?section=$section';
  }
}
