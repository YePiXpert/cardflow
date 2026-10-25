import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 分组表面：浅色模式用柔和投影，深色模式用一条细边勾出层次；[featured] 时边框更明显。
class CalmPanel extends StatelessWidget {
  const CalmPanel({
    super.key,
    required this.child,
    this.featured = false,
    this.padding = const EdgeInsets.all(CfSpace.md),
  });
  final Widget child;
  final bool featured;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) {
    final c = CardFlowColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: dark || featured
            ? Border.all(color: c.divider, width: CfStroke.hairline)
            : null,
        borderRadius: BorderRadius.circular(CfRadius.card),
        boxShadow: dark ? null : CfShadow.soft,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
