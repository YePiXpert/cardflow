import 'package:flutter/material.dart';

import '../../app/widgets/first_run_empty_state.dart';

/// P-02 卡包（ui-spec §6）。本阶段只有"首次空白"态。
class CardsPage extends StatelessWidget {
  const CardsPage({super.key});

  /// 页名，同时是底部导航的标签。
  static const String title = '卡包';

  /// ui-spec P-02 九态表"首次空白"。
  static const String firstRunMessage = '还没有卡片，账单挂在信用账户上';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: const FirstRunEmptyState(
        icon: Icons.credit_card_outlined,
        message: firstRunMessage,
        purpose: '按 授信池 › 信用账户 › 币种子账户 › 卡片 浏览与新建。',
        actions: <EmptyStateAction>[
          EmptyStateAction(label: '手工建卡'),
          EmptyStateAction(label: '从账单文件开始'),
          EmptyStateAction(label: '体验演示'),
        ],
      ),
    );
  }
}
