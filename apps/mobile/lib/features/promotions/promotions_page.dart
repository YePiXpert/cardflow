import 'package:flutter/material.dart';

import '../../app/widgets/first_run_empty_state.dart';

/// P-14 发现：活动列表（发现 Tab 根页，ui-spec §6）。本阶段只有"首次空白"态。
///
/// ui-spec 要求此处不推荐办卡，所以空白态不提供任何办卡入口。
class PromotionsPage extends StatelessWidget {
  const PromotionsPage({super.key});

  /// 页名，同时是底部导航的标签。
  static const String title = '发现';

  /// ui-spec P-14 九态表"首次空白"。
  static const String firstRunMessage = '还没有活动';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: const FirstRunEmptyState(
        icon: Icons.explore_outlined,
        message: firstRunMessage,
        purpose: '发现活动，查看结构化条款、来源与资格三态。',
        actions: <EmptyStateAction>[EmptyStateAction(label: '添加活动')],
      ),
    );
  }
}
