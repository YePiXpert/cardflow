import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/providers.dart';
import '../money/amount_visibility.dart';
import '../theme/tokens.dart';

/// 一个主导航项。
@immutable
class HomeTab {
  const HomeTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// 四个主导航（简报 U-1 §1）：卡账（新首页，合并原"总览"与"卡包"）、现金、规划、我的。原"发现"标签去掉
/// （活动功能未实现，活动页从"规划"进入）。
const List<HomeTab> homeTabs = <HomeTab>[
  HomeTab(
    label: '卡账',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
  ),
  HomeTab(
    label: '现金',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet,
  ),
  HomeTab(
    label: '规划',
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights,
  ),
  HomeTab(label: '我的', icon: Icons.person_outline, selectedIcon: Icons.person),
];

/// 底部 Tab 外壳。每个 Tab 有独立的导航栈，切换 Tab 保留栈位置；
/// 再次点按当前 Tab 回到该 Tab 的根页。
///
/// 切换工作空间之后（审查 R-15）：路由回到首页（`appRouterProvider`，卡账 Tab 的栈从根页开始），其余 Tab
/// 在切换之前留下的页面栈作废——下次点进那个 Tab 时从它的根页开始，不会再露出上一个空间的页面。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  /// 工作空间切换的次数，与每个 Tab 的栈是在第几次切换之后开始的。
  int _epoch = 0;
  final Map<int, int> _branchEpoch = <int, int>{};

  @override
  void initState() {
    super.initState();
    // 本机数据库已打开（外壳只在就绪后出现）：读回"隐藏金额"开关。
    unawaited(ref.read(amountsHiddenProvider.notifier).restore());
  }

  void _select(int index) {
    final shell = widget.navigationShell;
    final stale = (_branchEpoch[index] ?? 0) != _epoch;
    _branchEpoch[index] = _epoch;
    shell.goBranch(
      index,
      initialLocation: stale || index == shell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentWorkspaceProvider.select((w) => w.value?.id), (
      previous,
      next,
    ) {
      if (previous != null && previous != next) {
        _epoch++;
        // 路由同时回到首页：卡账 Tab 的栈已从根页开始。
        _branchEpoch[0] = _epoch;
      }
    });
    final navigationShell = widget.navigationShell;
    final colors = CardFlowColors.of(context);
    return Scaffold(
      body: navigationShell,
      // 标签栏与页底同色，上沿一条分隔线（iOS 15 起滚动到底时标签栏透明）。
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: colors.divider, width: CfStroke.hairline),
          ),
        ),
        child: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: _select,
          destinations: <Widget>[
            for (final tab in homeTabs)
              NavigationDestination(
                icon: Icon(tab.icon),
                selectedIcon: Icon(tab.selectedIcon),
                label: tab.label,
              ),
          ],
        ),
      ),
    );
  }
}
