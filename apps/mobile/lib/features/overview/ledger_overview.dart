import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/money_text.dart';
import '../../app/widgets/state_views.dart';
import '../../data/mapping/ledger_mapping.dart' show StatementBalance;
import '../../data/repositories/ledger_reader.dart';
import '../../data/repositories/providers.dart';
import '../cards/card_formatting.dart';
import '../statements/ledger_formatting.dart';

/// P-01 的账单部分（I-1c，ui-spec P-01）：待办条（待核对的还款、差异项）、快捷新增（登记还款、记一笔）、
/// 近期到期 14 天（本期剩余应还 > 0 的账单：应还、到期、有效状态 + 确认层级 → P-05；已并入下一期的旧账单
/// 不列）、负债四分法（按币种，口径：只扣减银行已入账的还款）。读取失败只在这一块报错（ui-spec P-01 九态
/// "仅失败卡片报错"）。
class OverviewLedgerSection extends ConsumerWidget {
  const OverviewLedgerSection({super.key});

  /// 近期到期为空时的文案。
  static const String noUpcoming = '14 天内没有到期的账单。';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(ledgerProvider);
    return switch (ledger) {
      AsyncData(:final value) => _section(context, value),
      AsyncError(:final error) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ErrorBlockBody(
            title: '账单读取失败',
            code: '${error.runtimeType}',
            detail: '本机数据没有改动。',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: OutlinedButton(
              onPressed: () => ref.invalidate(ledgerProvider),
              child: const Text('重试'),
            ),
          ),
        ],
      ),
      _ => const Padding(
        padding: EdgeInsets.all(CfSpace.md),
        child: Text('账单读取中…'),
      ),
    };
  }

  Widget _section(BuildContext context, LedgerData data) {
    final secondary = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: CardFlowColors.of(context).textSecondary);
    final awaiting = data.awaitingEvidence.length;
    final items = data.openItems.length;
    final upcoming = data.upcoming();
    final totals = data.totalsByCurrency.values.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (awaiting > 0 || items > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CfSpace.md,
              CfSpace.sm,
              CfSpace.md,
              0,
            ),
            child: Wrap(
              spacing: CfSpace.xs,
              runSpacing: CfSpace.xs,
              children: <Widget>[
                if (awaiting > 0)
                  ActionChip(
                    avatar: const Icon(Icons.help_outline),
                    label: Text('待核对的还款 $awaiting'),
                    onPressed: () => context.go(AppRoutes.repayments()),
                  ),
                if (items > 0)
                  ActionChip(
                    avatar: const Icon(Icons.rule),
                    label: Text('差异 $items'),
                    onPressed: () => context.go(AppRoutes.repayments()),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CfSpace.md,
            CfSpace.sm,
            CfSpace.md,
            0,
          ),
          child: Wrap(
            spacing: CfSpace.xs,
            runSpacing: CfSpace.xs,
            children: <Widget>[
              FilledButton(
                onPressed: () => context.go(AppRoutes.newRepayment()),
                child: const Text('登记还款'),
              ),
              OutlinedButton(
                onPressed: () => context.go(AppRoutes.newTransaction()),
                child: const Text('记一笔'),
              ),
            ],
          ),
        ),
        SectionTitle(
          '近期到期（14 天）',
          trailing: TextButton(
            onPressed: () => context.go(AppRoutes.statements()),
            child: const Text('账单中心'),
          ),
        ),
        if (upcoming.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: Text(noUpcoming, style: secondary),
          ),
        for (final b in upcoming) _UpcomingTile(data: data, balance: b),
        if (totals.isNotEmpty) ...<Widget>[
          const SectionTitle('负债四分法'),
          for (final t in totals) ...<Widget>[
            if (totals.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
                child: Text(currencyLabel(t.currency), style: secondary),
              ),
            LiabilitySection.totals(t),
          ],
        ],
      ],
    );
  }
}

/// 近期到期的一行：剩余应还、到期、账单的有效状态与确认层级、最近一笔还款的状态（"已标记"到期仍无证据时
/// 显示待核对）。
class _UpcomingTile extends StatelessWidget {
  const _UpcomingTile({required this.data, required this.balance});

  final LedgerData data;
  final StatementBalance balance;

  @override
  Widget build(BuildContext context) {
    final b = balance;
    final s = b.statement;
    final today = data.todayByCurrencyAccount[s.currencyAccountId]!;
    final currency = data.currencyAccounts[s.currencyAccountId]!.currency;
    final repayment = data.latestRepaymentOn(s.id);
    final repaymentStatus = repayment == null
        ? null
        : data.repaymentStatusOf(repayment);
    return ListTile(
      title: Wrap(
        spacing: CfSpace.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(
            '${data.accountName(s.currencyAccountId)} · 到期 ${formatShortDate(b.dueDate, today)}',
          ),
          MoneyText(
            minor: b.remaining,
            currency: currency,
            semanticsPrefix: '剩余应还',
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: CfSpace.xxs),
        child: Wrap(
          spacing: CfSpace.xs,
          runSpacing: CfSpace.xxs,
          children: <Widget>[
            effectiveStatusBadge(b),
            confirmationBadge(data.confirmationOf(s.id)),
            if (repaymentStatus != null) repaymentStatusBadge(repaymentStatus),
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(AppRoutes.statement(s.id)),
    );
  }
}
