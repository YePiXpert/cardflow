/// 路由路径常量。四个主导航的根路径与底部导航的顺序一致（简报 U-1 §1：卡账、现金、规划、我的）。
///
/// 启动分流（`lib/app/startup/app_gate.dart`）：本机数据库还在打开或打不开 → [startup]；
/// 没有工作空间 → [firstRun]（P-22）；就绪后才进入主导航（BL-04）。诊断页任何时候都可到达。
/// 0.0.1 的旧路径（`/overview`、`/cards`、`/planner/cash`、`/planner/calendar`、`/discover` 等）由
/// [legacyRedirect] 重定向到新位置，深链仍可用。
abstract final class AppRoutes {
  /// 卡账（新首页：合并原"总览"与"卡包"）。
  static const String home = '/home';

  /// 管理全部卡片（P-02：授信池 › 信用账户 › 币种子账户 › 卡片 的层级列表）。
  static const String cards = '$home/manage';

  /// 新建卡片（P-02 的新建弹层，全屏覆盖底部导航）。
  static const String newCard = '$home/new-card';

  /// 现金（资金日历 + 现金账户与收支计划）。
  static const String cashHome = '/cash';

  /// 资金日历的表格视图（P-07 的逐日行表）。
  static const String cashCalendar = '$cashHome/calendar';

  /// 现金账户与收支计划（P-08，现金页下半部分；表单与详情挂在它下面）。
  static const String cash = cashHome;

  /// 规划（情景与假设对比；消费规划后续版本提供）。
  static const String planner = '/planner';

  /// 情景与假设对比（P-09）：就是规划页本身。
  static const String scenarios = planner;

  /// 消费规划（P-10，首次空白：后续版本提供）。
  static const String plan = '$planner/plan';

  /// 活动（P-14，首次空白：活动功能后续版本提供；原"发现"标签）。
  static const String discover = '$planner/discover';

  /// 添加现金账户（全屏）。
  static const String newCashAccount = '$cash/new-account';

  /// 新增调拨（全屏）。
  static const String newTransfer = '$cash/new-transfer';

  /// 新增周期事项（全屏）。
  static const String newRecurring = '$cash/new-recurring';

  /// 新建压力情景（全屏）。
  static const String newScenario = '$planner/scenarios/new';

  /// 我的（P-19）。
  static const String settings = '/settings';

  /// 诊断信息（我的 › 诊断信息）。
  static const String diagnostics = '/settings/diagnostics';

  /// 关于（我的 › 关于卡序）：版本、公测说明、源码与反馈。
  static const String about = '/settings/about';

  /// 欢迎与开始方式（P-22，从"我的"进入，全屏覆盖底部导航，可返回）。
  static const String welcome = '/settings/welcome';

  /// 重置本地数据（我的 › 重置本地数据；确认页按 ui-spec §4.5，须输入"删除"）。
  static const String settingsReset = '/settings/reset';

  /// 首次使用（P-22，没有工作空间时任何路由都先到这里，没有返回）。
  static const String firstRun = '/welcome';

  /// 启动：正在打开本机加密数据库，或打开失败（错误码、重试、重置本地数据）。
  static const String startup = '/startup';

  /// 重置本地数据的确认页（打开失败时；ui-spec §4.5：写明影响、输入"删除"）。
  static const String resetLocalData = '/startup/reset';

  /// 启动时的初始位置。
  static const String initial = home;

  /// 主导航根路径，顺序与底部导航一致。
  static const List<String> tabRoots = <String>[
    home,
    cashHome,
    planner,
    settings,
  ];

  /// 卡片详情（信用账户，P-03）。
  static String account(String accountId) => '$home/accounts/$accountId';

  /// 资金日历的表格视图，带初始口径（`confirmed`/`baseline`/`stress`）与情景。
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
      '$planner/scenarios/edit/$scenarioId';

  /// 情景/版本对比；[a]、[b] 是计算版本 id。
  static String scenarioCompare({String? a, String? b}) {
    final query = <String, String>{'a': ?a, 'b': ?b};
    return Uri(
      path: '$planner/scenarios/compare',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  // ---- 账单与还款：P-05/P-06 在卡账栈与卡片详情栈里都有 ----

  /// 账单与还款页面所在的栈：卡账（[accountId] 为空）或某卡片详情（P-03）。
  static String ledgerBase([String? accountId]) =>
      accountId == null ? home : account(accountId);

  /// 账单中心（P-05 列表）；从卡片详情进入时只看该账户。
  static String statements({String? accountId}) =>
      '${ledgerBase(accountId)}/statements';

  /// 账单详情（P-05）。
  static String statement(String statementId, {String? accountId}) =>
      '${statements(accountId: accountId)}/$statementId';

  /// 录入正式账单（全屏）；[currencyAccountId] 预选子账户。
  static String newStatement({String? accountId, String? currencyAccountId}) {
    final query = <String, String>{'currency': ?currencyAccountId};
    return Uri(
      path: '${statements(accountId: accountId)}/new',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  /// 人工修正（全屏）。
  static String correctStatement(String statementId, {String? accountId}) =>
      '${statement(statementId, accountId: accountId)}/correct';

  /// 记一笔（全屏）；[currencyAccountId] 预选子账户。
  static String newTransaction({String? accountId, String? currencyAccountId}) {
    final query = <String, String>{'currency': ?currencyAccountId};
    return Uri(
      path: '${ledgerBase(accountId)}/transactions/new',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  /// 把一笔消费转成分期（全屏）。
  static String newInstallment(String transactionId, {String? accountId}) =>
      '${ledgerBase(accountId)}/transactions/$transactionId/installment';

  /// 还款与核对（P-06 列表：待核对、全部还款、差异清单）。
  static String repayments({String? accountId}) =>
      '${ledgerBase(accountId)}/repayments';

  /// 还款详情（P-06 时间线与动作）。
  static String repayment(String repaymentId, {String? accountId}) =>
      '${repayments(accountId: accountId)}/$repaymentId';

  /// 登记还款（P-06 表单，全屏）；[statementId] 预选账单，[currencyAccountId] 预选子账户。
  static String newRepayment({
    String? accountId,
    String? statementId,
    String? currencyAccountId,
  }) {
    final query = <String, String>{
      'statement': ?statementId,
      'currency': ?currencyAccountId,
    };
    return Uri(
      path: '${repayments(accountId: accountId)}/new',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  /// 信用账户设置（P-04）；[section] 为初始分段（见 `AccountSettingsSection`）。
  static String accountSettings(String accountId, {String? section}) {
    final base = '${account(accountId)}/settings';
    return section == null ? base : '$base?section=$section';
  }
}

/// 0.0.1 的旧路径 → 新位置（简报 U-1 §1：旧路由重定向，深链仍可用）；不是旧路径时为 null。查询参数原样保留。
///
/// | 旧 | 新 |
/// |---|---|
/// | `/overview`、`/overview/…`（总览与它栈里的账单、还款） | `/home`、`/home/…` |
/// | `/cards`（卡包） | `/home/manage` |
/// | `/cards/new` | `/home/new-card` |
/// | `/cards/accounts/…`（详情、设置、账单、还款） | `/home/accounts/…` |
/// | `/planner/cash`、`/planner/cash/…` | `/cash`、`/cash/…` |
/// | `/planner/calendar` | `/cash/calendar` |
/// | `/planner/scenarios`（列表） | `/planner` |
/// | `/discover` | `/planner/discover` |
String? legacyRedirect(Uri uri) {
  final path = uri.path;
  String? target;
  String rest(String prefix) => path.substring(prefix.length);
  if (path == '/overview' || path.startsWith('/overview/')) {
    target = '${AppRoutes.home}${rest('/overview')}';
  } else if (path == '/cards') {
    target = AppRoutes.cards;
  } else if (path == '/cards/new') {
    target = AppRoutes.newCard;
  } else if (path.startsWith('/cards/accounts/')) {
    target = '${AppRoutes.home}/accounts/${rest('/cards/accounts/')}';
  } else if (path == '/planner/cash' || path.startsWith('/planner/cash/')) {
    target = '${AppRoutes.cashHome}${rest('/planner/cash')}';
  } else if (path == '/planner/calendar') {
    target = AppRoutes.cashCalendar;
  } else if (path == '/planner/scenarios') {
    target = AppRoutes.planner;
  } else if (path == '/discover') {
    target = AppRoutes.discover;
  }
  if (target == null) {
    return null;
  }
  return uri.hasQuery ? '$target?${uri.query}' : target;
}
