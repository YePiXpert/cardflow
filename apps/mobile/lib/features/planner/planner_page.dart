import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/widgets/first_run_empty_state.dart';
import '../../app/widgets/workspace_badges.dart';
import 'planner_segments.dart';

/// P-10 规划输入（规划 Tab 根页，ui-spec §6）。本阶段只有"首次空白"态；顶部是规划 Tab 的分段
/// （消费规划｜资金日历｜现金与收支｜情景）。
class PlannerPage extends StatelessWidget {
  const PlannerPage({super.key});

  /// 页名，同时是底部导航的标签。
  static const String title = '规划';

  /// ui-spec P-10 九态表"首次空白"：无账户→"先添加账户"。
  static const String firstRunMessage = '先添加账户';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: ListView(
        children: <Widget>[
          const PlannerSegmentBar(current: PlannerSegment.plan),
          const RootPageBadges(),
          FirstRunEmptyState(
            icon: Icons.event_note_outlined,
            message: firstRunMessage,
            purpose: '录入计划消费及约束，计算前做数据检查（消费规划在 I-2 提供）。',
            actions: <EmptyStateAction>[
              EmptyStateAction(
                label: '去卡包添加账户',
                onPressed: () => context.go(AppRoutes.cards),
              ),
            ],
            scrollable: false,
          ),
        ],
      ),
    );
  }
}
