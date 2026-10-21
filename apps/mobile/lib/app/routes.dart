/// 当前三个入口：用卡、卡片、我的。
abstract final class AppRoutes {
  static const home = '/home';
  static const cards = '/cards';
  static const newCard = '/cards/new';
  static const settings = '/settings';
  static const diagnostics = '/settings/diagnostics';
  static const about = '/settings/about';
  static const welcome = '/settings/welcome';
  static const settingsReset = '/settings/reset';
  static const firstRun = '/welcome';
  static const startup = '/startup';
  static const resetLocalData = '/startup/reset';
  static const initial = home;
  static const tabRoots = <String>[home, cards, settings];
  static String account(String id) => '$cards/accounts/$id';
  static String accountSettings(String id, {String? section}) => Uri(
    path: '${account(id)}/settings',
    queryParameters: section == null ? null : {'section': section},
  ).toString();
}

/// 已撤下的业务深链回用卡；仍存在的卡片设置链接保留参数。
String? legacyRedirect(Uri uri) {
  final path = uri.path;
  if (path
      .split('/')
      .any(
        (p) => const {
          'cash',
          'planner',
          'discover',
          'overview',
          'statements',
          'transactions',
          'repayments',
        }.contains(p),
      )) {
    return AppRoutes.home;
  }
  String? target;
  if (path == '/home/manage') target = AppRoutes.cards;
  if (path == '/home/new-card') target = AppRoutes.newCard;
  if (path.startsWith('/home/accounts/')) {
    target = path.replaceFirst('/home/accounts/', '/cards/accounts/');
  }
  return target == null ? null : uri.replace(path: target).toString();
}
