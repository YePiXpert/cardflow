import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/providers.dart';
import '../startup/app_gate.dart';
import '../theme/tokens.dart';
import 'confirm_dialog.dart';

/// 演示横幅的文字。
const String demoBannerText = '演示数据 · 与真实数据隔离';

/// 演示模式横幅（ui-spec §4.2、R-SYS-13）：在演示空间时，每一页顶部常驻紫色横幅（烧瓶图标 +
/// "演示数据 · 与真实数据隔离" +「退出演示」），**不可关闭**。放在 `MaterialApp.builder` 里，
/// 所以覆盖全部页面（含全屏页面与对话框底下的页面）。
///
/// 横幅占用了状态栏的上边距，下面的页面不再重复留出。
class DemoBannerFrame extends ConsumerWidget {
  const DemoBannerFrame({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  final Widget child;

  /// 根导航器：横幅在 Navigator 之上，弹确认框要用它的 context。
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(appGateProvider);
    final inDemo = gate is GateReady && gate.workspace.isDemo;
    if (!inDemo) {
      return child;
    }
    return Column(
      children: <Widget>[
        _DemoBanner(onExit: () => unawaited(_confirmExit(ref))),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmExit(WidgetRef ref) async {
    final dialogContext = navigatorKey.currentContext;
    if (dialogContext == null) {
      return;
    }
    final confirmed = await confirmAction(
      dialogContext,
      title: '退出演示？',
      message: '退出后将回到你的卡片列表；演示数据保留，可随时在“我的”页面清除。',
      confirmLabel: '退出演示',
    );
    if (confirmed) {
      await ref.read(currentWorkspaceProvider.notifier).exitDemo();
    }
  }
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner({required this.onExit});

  final VoidCallback onExit;

  /// 横幅是常驻的外框（同底部导航），文字放大最多到 2 倍（ui-spec §3.3：不做低于 2.0 倍的钳制），
  /// 放大到 3 倍时不至于占去半屏。
  static const double maxTextScale = 2;

  @override
  Widget build(BuildContext context) {
    final colors = CardFlowColors.of(context);
    final theme = Theme.of(context);
    // 简报 U-1 §1：紫色横幅保留，可以更细——一行，高度就是一个触控目标（48）。
    return Material(
      color: colors.demo.bg,
      child: SafeArea(
        bottom: false,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: maxTextScale,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: CfTouch.minTarget),
            child: Padding(
              padding: const EdgeInsets.only(left: CfSpace.md),
              child: Row(
                children: <Widget>[
                  ExcludeSemantics(
                    child: Icon(
                      Icons.science_outlined,
                      size: CfIconSize.sm,
                      color: colors.demo.fg,
                    ),
                  ),
                  const SizedBox(width: CfSpace.xs),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        demoBannerText,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.demo.fg,
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: colors.demo.fg,
                      textStyle: theme.textTheme.labelMedium,
                    ),
                    onPressed: onExit,
                    child: const Text('退出演示'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
