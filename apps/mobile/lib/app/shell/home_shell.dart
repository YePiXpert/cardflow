import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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

/// 五个主导航（ui-spec §1.1：固定，顺序不变）。
const List<HomeTab> homeTabs = <HomeTab>[
  HomeTab(
    label: '总览',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
  ),
  HomeTab(
    label: '卡包',
    icon: Icons.credit_card_outlined,
    selectedIcon: Icons.credit_card,
  ),
  HomeTab(
    label: '规划',
    icon: Icons.event_note_outlined,
    selectedIcon: Icons.event_note,
  ),
  HomeTab(
    label: '发现',
    icon: Icons.explore_outlined,
    selectedIcon: Icons.explore,
  ),
  HomeTab(label: '我的', icon: Icons.person_outline, selectedIcon: Icons.person),
];

/// 底部 Tab 外壳。每个 Tab 有独立的导航栈，切换 Tab 保留栈位置；
/// 再次点按当前 Tab 回到该 Tab 的根页。
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: <Widget>[
          for (final tab in homeTabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}
