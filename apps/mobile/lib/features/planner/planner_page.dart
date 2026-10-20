import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/widgets/first_run_empty_state.dart';

/// P-10 消费规划（规划 › 消费规划，ui-spec §6）。本期只有"首次空白"态：消费规划在后续版本提供。
class PlannerPage extends StatelessWidget {
  const PlannerPage({super.key});

  /// 页名。
  static const String title = '消费规划';

  /// ui-spec P-10 九态"首次空白"：无账户→"先添加账户"。
  static const String firstRunMessage = '先添加账户';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: ListView(
        children: <Widget>[
          FirstRunEmptyState(
            icon: Icons.shopping_bag_outlined,
            message: firstRunMessage,
            purpose: '录入计划消费及约束，计算前做数据检查（消费规划在后续版本提供）。',
            actions: <EmptyStateAction>[
              EmptyStateAction(
                label: '去管理卡片',
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
