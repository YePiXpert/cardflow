import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../app/widgets/bank_badge.dart';
import '../../app/widgets/money_text.dart';
import '../../data/repositories/ledger_home.dart';
import '../../data/repositories/providers.dart';
import '../cards/card_formatting.dart';
import '../home/quick_pay_sheet.dart';

/// 资金日历与现金页的一行"未计入：信用卡本期应还 ¥x（N 张卡，登记还款后计入）"（简报 U-1 §9 Q-1）：信用卡本期
/// 还欠着、却还没有登记进现金时间线的应还。点开列出这些卡，可以直接「还清本期」。信用卡应还要不要自动作为计划
/// 流出，后续再定（BL-33）。没有这样的卡时不显示。
class UncountedDuesTile extends ConsumerWidget {
  const UncountedDuesTile({super.key});

  /// 行首的文字。
  static const String lead = '未计入：信用卡本期应还';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(ledgerHomeProvider).value;
    if (home == null || home.uncounted.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = CardFlowColors.of(context);
    final theme = Theme.of(context);
    final totals = home.uncountedByCurrency;
    final style = theme.textTheme.bodyMedium;
    return MergeSemantics(
      child: Material(
        color: colors.attention.bg,
        borderRadius: BorderRadius.circular(CfRadius.tile),
        child: InkWell(
          borderRadius: BorderRadius.circular(CfRadius.tile),
          onTap: () => unawaited(
            showModalBottomSheet<void>(
              context: context,
              useRootNavigator: true,
              isScrollControlled: true,
              builder: (_) => const UncountedDuesSheet(),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CfSpace.md,
              vertical: CfSpace.sm,
            ),
            child: Row(
              children: <Widget>[
                ExcludeSemantics(
                  child: Icon(
                    Icons.info_outline,
                    size: CfIconSize.md,
                    color: colors.attention.fg,
                  ),
                ),
                const SizedBox(width: CfSpace.xs),
                Expanded(
                  child: Wrap(
                    spacing: CfSpace.xxs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text(lead, style: style),
                      for (final entry in totals.entries)
                        MoneyText(
                          minor: entry.value,
                          currency: entry.key,
                          compact: true,
                          semanticsPrefix: '未计入的应还',
                          textAlign: TextAlign.start,
                          style: style?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      Text('（${home.uncountedCards} 张卡，登记还款后计入）', style: style),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "未计入"的明细：每张卡未计入的应还、到期日与「还清本期」。
class UncountedDuesSheet extends ConsumerWidget {
  const UncountedDuesSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(ledgerHomeProvider).value;
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final items = home?.uncounted ?? const <UncountedDue>[];
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.95,
        builder: (sheetContext, controller) => ListView(
          controller: controller,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
              child: Semantics(
                header: true,
                child: Text('未计入现金的信用卡应还', style: theme.textTheme.titleMedium),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CfSpace.md,
                CfSpace.xxs,
                CfSpace.md,
                CfSpace.xs,
              ),
              child: Text(
                '这些卡本期还欠着，但还没有登记还款，资金日历里没有它们的扣款。登记还款（或「还清本期」）后，扣款按预计扣款日计入。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            for (final u in items)
              ListTile(
                leading: BankBadge(bankName: u.row.bankName),
                title: Text(u.row.title),
                subtitle: Wrap(
                  spacing: CfSpace.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    MoneyText(
                      minor: u.amount,
                      currency: u.row.currency,
                      compact: true,
                      semanticsPrefix: '未计入',
                      textAlign: TextAlign.start,
                    ),
                    Text(
                      '· ${formatShortDate(u.row.current!.dueDate, u.row.today)} 到期',
                    ),
                  ],
                ),
                trailing: TextButton(
                  onPressed: () {
                    // 先关掉这个弹层，再用根导航器打开"还清本期"（这个弹层的 context 关掉后就不在了）。
                    final navigator = Navigator.of(sheetContext);
                    navigator.pop();
                    unawaited(showQuickPaySheet(navigator.context, u.row));
                  },
                  child: const Text(QuickPaySheet.title),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
