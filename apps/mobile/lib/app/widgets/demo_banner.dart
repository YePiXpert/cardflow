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
      message: '将回到真实数据（没有真实数据时回到欢迎页）。演示数据保留，可在欢迎页「清除演示数据」。',
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

  @override
  Widget build(BuildContext context) {
    final colors = CardFlowColors.of(context);
    final theme = Theme.of(context);
    return Material(
      color: colors.demo.bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CfSpace.md,
            vertical: CfSpace.xxs,
          ),
          child: Row(
            children: <Widget>[
              ExcludeSemantics(
                child: Icon(
                  Icons.science_outlined,
                  size: CfIconSize.md,
                  color: colors.demo.fg,
                ),
              ),
              const SizedBox(width: CfSpace.xs),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    demoBannerText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.demo.fg,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: CfSpace.xs),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: colors.demo.fg),
                onPressed: onExit,
                child: const Text('退出演示'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
