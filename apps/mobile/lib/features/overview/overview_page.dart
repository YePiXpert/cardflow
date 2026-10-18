import 'package:flutter/material.dart';

import '../../app/widgets/first_run_empty_state.dart';

/// P-01 总览（ui-spec §6）。本阶段只有"首次空白"态。
class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  /// 页名，同时是底部导航的标签。
  static const String title = '总览';

  /// ui-spec P-01 九态表"首次空白"。
  static const String firstRunMessage = '还没有信用账户';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: const FirstRunEmptyState(
        icon: Icons.dashboard_outlined,
        message: firstRunMessage,
        purpose: '一屏看清近期应还、现金缺口、待办与数据新鲜度。',
        actions: <EmptyStateAction>[
          EmptyStateAction(label: '建卡'),
          EmptyStateAction(label: '导入'),
          EmptyStateAction(label: '体验演示'),
        ],
      ),
    );
  }
}
