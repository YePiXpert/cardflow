import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 同一套柔和分组表面；强调面用于推荐与卡片详情。
class CalmPanel extends StatelessWidget {
  const CalmPanel({super.key, required this.child, this.featured = false});
  final Widget child;
  final bool featured;
  @override
  Widget build(BuildContext context) {
    final c = CardFlowColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: featured ? null : c.surface,
        gradient: featured
            ? LinearGradient(
                colors: c.hero,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        borderRadius: BorderRadius.circular(CfRadius.card),
      ),
      child: Padding(padding: const EdgeInsets.all(CfSpace.lg), child: child),
    );
  }
}

/// 用原生图形画两张轻巧的卡片，空白状态也能辨认产品用途。
class PocketIllustration extends StatelessWidget {
  const PocketIllustration({super.key});
  @override
  Widget build(BuildContext context) {
    final c = CardFlowColors.of(context);
    return ExcludeSemantics(
      child: SizedBox(
        width: 120,
        height: 90,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Transform.rotate(
              angle: -.18,
              child: Container(
                width: 90,
                height: 58,
                decoration: BoxDecoration(
                  color: c.surfaceRaised,
                  borderRadius: BorderRadius.circular(CfRadius.lg),
                  border: Border.all(color: c.divider),
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(10, 8),
              child: Transform.rotate(
                angle: .12,
                child: Container(
                  width: 90,
                  height: 58,
                  padding: const EdgeInsets.all(CfSpace.sm),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: c.hero),
                    borderRadius: BorderRadius.circular(CfRadius.lg),
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Icon(
                      Icons.spa_outlined,
                      color: c.heroTextSecondary,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
