import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 分组表面；推荐与详情使用细边框。
class CalmPanel extends StatelessWidget {
  const CalmPanel({super.key, required this.child, this.featured = false});
  final Widget child;
  final bool featured;
  @override
  Widget build(BuildContext context) {
    final c = CardFlowColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: featured ? Border.all(color: c.divider) : null,
        borderRadius: BorderRadius.circular(CfRadius.card),
      ),
      child: Padding(padding: const EdgeInsets.all(CfSpace.md), child: child),
    );
  }
}
