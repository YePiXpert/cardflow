import 'package:cardflow/app/diagnostics/diagnostic_log.dart';
import 'package:cardflow/app/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('用卡、卡片、我的三个入口；卡片与设置栈可返回', (t) async {
    await pumpCardFlowApp(t);
    expect(
      t
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .map((d) => d.label),
      ['用卡', '卡片', '我的'],
    );
    for (final (label, path) in [
      ('卡片', AppRoutes.cards),
      ('我的', AppRoutes.settings),
      ('用卡', AppRoutes.home),
    ]) {
      await t.tap(navLabel(label));
      await t.pumpAndSettle();
      expect(appRouter(t).routeInformationProvider.value.uri.path, path);
    }
    await goTo(t, AppRoutes.diagnostics);
    await t.tap(navLabel('用卡'));
    await t.pumpAndSettle();
    await t.tap(navLabel('我的'));
    await t.pumpAndSettle();
    expect(
      appRouter(t).routeInformationProvider.value.uri.path,
      AppRoutes.diagnostics,
    );
    await t.tap(navLabel('我的'));
    await t.pumpAndSettle();
    expect(
      appRouter(t).routeInformationProvider.value.uri.path,
      AppRoutes.settings,
    );
  });
  testWidgets('撤下业务深链回用卡；卡片旧链接仍到达资料页', (t) async {
    await pumpCardFlowApp(t);
    for (final path in [
      '/cash',
      '/planner/plan',
      '/discover',
      '/overview',
      '/home/statements/secret',
      '/cards/accounts/x/repayments/new',
    ]) {
      await goTo(t, path);
      expect(
        appRouter(t).routeInformationProvider.value.uri.path,
        AppRoutes.home,
      );
    }
    await goTo(t, '/home/accounts/private-id/settings?section=limits');
    expect(
      appRouter(t).routeInformationProvider.value.uri.path,
      AppRoutes.accountSettings('private-id'),
    );
    final log = appContainer(t)
        .read(diagnosticLogProvider)
        .entries
        .map((e) => e.detail)
        .join('\n');
    expect(log, isNot(contains('private-id')));
  });
  test('旧卡片链接保留设置参数，不把撤下业务参数带入首页', () {
    expect(
      legacyRedirect(Uri.parse('/home/accounts/x/settings?section=limits')),
      '/cards/accounts/x/settings?section=limits',
    );
    expect(legacyRedirect(Uri.parse('/cash?amount=100')), AppRoutes.home);
    expect(legacyRedirect(Uri.parse('/cards')), isNull);
  });
}
