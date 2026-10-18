// P-22 首次使用/欢迎/演示模式（ui-spec §6 P-22、§4.2）与演示横幅：开始方式的开放与禁用、体验演示
// （生成合成数据、横幅常驻且不可关闭、退出须确认）、真实↔演示切换须确认、清除演示数据写明影响数量。
import 'package:cardflow/app/routes.dart';
import 'package:cardflow/app/widgets/demo_banner.dart';
import 'package:cardflow/data/repositories/models.dart';
import 'package:cardflow/data/repositories/providers.dart';
import 'package:cardflow/features/onboarding/welcome_page.dart';
import 'package:cardflow/features/overview/overview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers.dart';

Finder _option(String label) => find.ancestor(
  of: find.text(label),
  matching: find.bySubtype<ButtonStyleButton>(),
);

void main() {
  testWidgets('五种开始方式：手工建卡、体验演示可用；其余禁用并注明所属阶段', (tester) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.none);
    for (final item in WelcomePage.boundaries) {
      expect(find.text(item), findsOneWidget);
    }
    for (final option in WelcomePage.startOptions) {
      final button = tester.widget<ButtonStyleButton>(
        _option(option.label).first,
      );
      if (option.stage == null) {
        expect(button.onPressed, isNotNull, reason: option.label);
      } else {
        expect(button.onPressed, isNull, reason: option.label);
        await tester.scrollUntilVisible(
          find.text('${option.label}：${option.stage}'),
          100,
        );
        expect(find.text('${option.label}：${option.stage}'), findsOneWidget);
      }
    }
    expect(
      WelcomePage.startOptions
          .where((o) => o.stage != null)
          .map((o) => o.stage),
      <String>['I-3 提供', 'I-4 提供', '后续提供（自托管同步）'],
    );
  });

  testWidgets('体验演示：生成演示空间并进入总览；横幅常驻、没有关闭按钮；退出须确认', (tester) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.none);
    await tester.tap(_option('体验演示'));
    await tester.pumpAndSettle();

    expect(appBarTitle(OverviewPage.title), findsOneWidget);
    expect(find.text(demoBannerText), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    final workspace = appContainer(tester).read(currentWorkspaceProvider).value;
    expect(workspace!.kind, WorkspaceKind.demo);

    // 每一页都有横幅。
    for (final path in <String>[
      AppRoutes.cards,
      AppRoutes.settings,
      AppRoutes.diagnostics,
    ]) {
      await goTo(tester, path);
      expect(find.text(demoBannerText), findsOneWidget, reason: path);
    }

    // 诊断页不受启动分流约束（数据库打不开时它是唯一的反馈渠道），所以回到总览再退出。
    await goTo(tester, AppRoutes.overview);
    await tester.tap(find.text('退出演示'));
    await tester.pumpAndSettle();
    expect(find.text('退出演示？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text(demoBannerText), findsOneWidget);

    await tester.tap(find.text('退出演示').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '退出演示'));
    await tester.pumpAndSettle();
    // 没有真实空间：回到首次使用页，横幅消失。
    expect(find.text(demoBannerText), findsNothing);
    expect(appBarTitle(WelcomePage.title), findsOneWidget);
  });

  testWidgets('从真实空间体验演示须确认；取消则留在真实空间', (tester) async {
    await pumpCardFlowApp(tester);
    await goTo(tester, AppRoutes.welcome);
    await tester.tap(_option('体验演示'));
    await tester.pumpAndSettle();
    expect(find.text('切换到演示空间？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(
      appContainer(tester).read(currentWorkspaceProvider).value!.kind,
      WorkspaceKind.real,
    );
    expect(find.text(demoBannerText), findsNothing);

    await tester.tap(_option('体验演示'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('进入演示'));
    await tester.pumpAndSettle();
    expect(find.text(demoBannerText), findsOneWidget);
    expect(appBarTitle(OverviewPage.title), findsOneWidget);
  });

  testWidgets('清除演示数据：确认框写明影响数量；清除后回到真实空间', (tester) async {
    await pumpCardFlowApp(tester);
    final container = appContainer(tester);
    await tester.runAsync(
      () => container.read(currentWorkspaceProvider.notifier).enterDemo(),
    );
    await tester.pumpAndSettle();
    expect(find.text(demoBannerText), findsOneWidget);

    await goTo(tester, AppRoutes.welcome);
    final clear = find.text('清除演示数据');
    await tester.scrollUntilVisible(clear, 200);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('4 个信用账户、5 张卡片、4 个账期规则版本、4 条额度快照、1 个授信池'),
      findsOneWidget,
    );
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();
    expect(find.text(demoBannerText), findsNothing);
    expect(
      container.read(currentWorkspaceProvider).value!.kind,
      WorkspaceKind.real,
    );
    expect(container.read(demoWorkspaceRowsProvider).value, isNull);
  });
}
