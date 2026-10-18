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

  /// 规划（P-10，规划 Tab 的根页；同一 Tab 的分段：资金日历 P-07、现金与收支 P-08、情景 P-09）。
  static const String planner = '/planner';

  /// 资金日历（P-07，规划分段）。
  static const String cashCalendar = '/planner/calendar';

  /// 现金账户与收支计划（P-08，规划分段）。
  static const String cash = '/planner/cash';

  /// 情景与假设对比（P-09，规划分段）。
  static const String scenarios = '/planner/scenarios';

  /// 添加现金账户（全屏）。
  static const String newCashAccount = '/planner/cash/new-account';

  /// 新增调拨（全屏）。
  static const String newTransfer = '/planner/cash/new-transfer';

  /// 新增周期事项（全屏）。
  static const String newRecurring = '/planner/cash/new-recurring';

  /// 新建压力情景（全屏）。
  static const String newScenario = '/planner/scenarios/new';

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

  /// 资金日历，带初始口径（`confirmed`/`baseline`/`stress`）与情景。
  static String cashCalendarWith({String? basis, String? scenario}) {
    final query = <String, String>{'basis': ?basis, 'scenario': ?scenario};
    return Uri(
      path: cashCalendar,
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  /// 现金账户详情（P-08）。
  static String cashAccount(String accountId) => '$cash/accounts/$accountId';

  /// 记录新快照（全屏）。
  static String recordCashSnapshot(String accountId) =>
      '${cashAccount(accountId)}/snapshot';

  /// 新增收支（全屏）；[type] 是 `CashPlanType.code`。
  static String newCashEvent([String? type]) =>
      type == null ? '$cash/new-event' : '$cash/new-event?type=$type';

  /// 修改一笔收支（全屏）。
  static String cashEvent(String eventId) => '$cash/events/$eventId';

  /// 周期事项详情（各期覆盖/跳过）。
  static String recurring(String itemId) => '$cash/recurring/$itemId';

  /// 修改周期事项（全屏）。
  static String editRecurring(String itemId) => '${recurring(itemId)}/edit';

  /// 修改压力情景（全屏）。
  static String editScenario(String scenarioId) =>
      '$scenarios/edit/$scenarioId';

  /// 情景/版本对比；[a]、[b] 是计算版本 id。
  static String scenarioCompare({String? a, String? b}) {
    final query = <String, String>{'a': ?a, 'b': ?b};
    return Uri(
      path: '$scenarios/compare',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  /// 信用账户设置（P-04）；[section] 为初始分段（见 `AccountSettingsSection`）。
  static String accountSettings(String accountId, {String? section}) {
    final base = '${account(accountId)}/settings';
    return section == null ? base : '$base?section=$section';
  }
}
