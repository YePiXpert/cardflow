import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';

/// 规划 Tab 根页的分段（ui-spec §1.1）：消费规划 P-10｜资金日历 P-07｜现金与收支 P-08｜情景 P-09。
enum PlannerSegment {
  plan('消费规划', AppRoutes.planner),
  calendar('资金日历', AppRoutes.cashCalendar),
  cash('现金与收支', AppRoutes.cash),
  scenarios('情景', AppRoutes.scenarios);

  const PlannerSegment(this.label, this.route);

  final String label;
  final String route;
}

/// 分段切换：一行可换行的选择标签（文字放大到 3 倍也不会溢出），切换时替换当前页（没有返回）。
class PlannerSegmentBar extends StatelessWidget {
  const PlannerSegmentBar({super.key, required this.current});

  final PlannerSegment current;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(CfSpace.md, CfSpace.xs, CfSpace.md, 0),
      child: Wrap(
        spacing: CfSpace.xs,
        runSpacing: CfSpace.xs,
        children: <Widget>[
          for (final segment in PlannerSegment.values)
            ChoiceChip(
              label: Text(segment.label),
              selected: segment == current,
              onSelected: (_) {
                if (segment != current) {
                  context.go(segment.route);
                }
              },
            ),
        ],
      ),
    );
  }
}
