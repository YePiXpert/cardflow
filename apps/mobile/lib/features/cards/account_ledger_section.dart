import 'dart:async';

import 'package:cardflow_domain/cardflow_domain.dart' show fromMinorText;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/feedback.dart';
import '../../app/widgets/state_views.dart';
import '../../data/repositories/card_wallet_reader.dart';
import '../../data/repositories/ledger_models.dart';
import '../../data/repositories/ledger_reader.dart';
import '../../data/repositories/providers.dart';
import '../statements/ledger_formatting.dart';
import 'card_formatting.dart';

/// P-03 的账单部分（I-1c，ui-spec P-03）：本期（账期、应还、最低还款、还款状态）、「去还款」「登记还款」、
/// 负债四分法、最近 3 期与「全部账单」。还没有正式账单时只给出入口（预测账期在上方的本期区）。
class AccountLedgerSection extends ConsumerWidget {
  const AccountLedgerSection({
    super.key,
    required this.account,
    required this.sub,
  });

  final AccountView account;
  final CurrencyAccountView sub;

  /// 首次空白（还没有任何正式账单）的说明（ui-spec P-03 九态）。
  static const String noStatementsNote = '尚无账单，下为预测账期';

  /// 没有已核验官方链接时「去还款」显示的操作说明（ui-spec §4.1）。
  static const String instructions =
      '没有已核验的官方还款链接：请通过发卡行官方 App、官网或客服办理。卡序不会代你付款，也不会跳转。'
      '办完后回来「登记还款」，并在银行入账后补充证据。';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(ledgerProvider);
    return switch (ledger) {
      AsyncData(:final value) => _section(context, value),
      AsyncError(:final error) => ErrorBlockBody(
        title: '账单读取失败',
        code: '${error.runtimeType}',
        detail: '本机数据没有改动。',
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
    final currency = sub.currency;
    final statements = data.statementsOf(sub.row.id);
    final latest = statements.isEmpty
        ? null
        : data.balances[statements.first.id];
    final liability = data.liabilities[sub.row.id];
    final repayment = latest == null
        ? null
        : data.latestRepaymentOn(latest.statement.id);
    final unreleased = LedgerReader.unreleasedRepayments(data, sub.row.id);
    final awaiting =
        repayment != null &&
        !latest!.status.isSettled &&
        const <RepaymentStatus>{
          RepaymentStatus.userMarkedPaid,
          RepaymentStatus.needsReview,
        }.contains(RepaymentStatus.of(repayment.status));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (latest != null) ...<Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: Wrap(
              spacing: CfSpace.xs,
              runSpacing: CfSpace.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  '本期账单（${latest.statement.statementDate} 出账）',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                statementStatusBadge(latest.status),
                confirmationBadge(data.confirmationOf(latest.statement.id)),
              ],
            ),
          ),
          LabeledValue(label: '到期还款日', value: Text(latest.statement.dueDate)),
          LedgerAmountRow(
            label: '本期应还（剩余）',
            minor: latest.remaining,
            currency: currency,
          ),
          LedgerAmountRow(
            label: '最低还款额',
            minor: latest.current.minDueMinor,
            currency: currency,
          ),
          if (latest.creditBalance > 0)
            LedgerAmountRow(
              label: '贷方余额（溢缴款）',
              minor: latest.creditBalance,
              currency: currency,
            ),
          LabeledValue(
            label: '还款状态',
            value: repayment == null
                ? const Text('还没有还款登记')
                : repaymentStatusBadge(RepaymentStatus.of(repayment.status)),
          ),
          if (awaiting)
            const NoticeCard(
              icon: Icons.help_outline,
              text: '待核对：你已标记还款，但还没有银行确认，账单不结清。',
            ),
        ] else
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: Text(noStatementsNote),
          ),
        Padding(
          padding: const EdgeInsets.all(CfSpace.md),
          child: Wrap(
            spacing: CfSpace.xs,
            runSpacing: CfSpace.xs,
            children: <Widget>[
              OutlinedButton(
                onPressed: () =>
                    unawaited(_showInstructions(context, latest?.remaining)),
                child: const Text('去还款：查看操作说明'),
              ),
              FilledButton(
                onPressed: () => context.go(
                  AppRoutes.newRepayment(
                    accountId: account.id,
                    statementId: latest?.statement.id,
                    currencyAccountId: sub.row.id,
                  ),
                ),
                child: const Text('登记还款'),
              ),
            ],
          ),
        ),
        if (unreleased > 0) ...<Widget>[
          LedgerAmountRow(
            label: '已银行入账、尚未计入额度的还款',
            minor: unreleased,
            currency: currency,
          ),
          const NoticeCard(
            icon: Icons.schedule,
            tone: NoticeTone.unknown,
            text: '额度释放时滞未知：银行入账后暂不计入可用容量，以新的额度快照为准（F-28）。',
          ),
        ],
        if (liability != null) ...<Widget>[
          const SectionTitle('负债四分法'),
          LiabilitySection.of(liability),
        ],
        SectionTitle(
          '最近 3 期',
          trailing: TextButton(
            onPressed: () =>
                context.go(AppRoutes.statements(accountId: account.id)),
            child: const Text('全部账单'),
          ),
        ),
        if (statements.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: Text('还没有正式账单。', style: secondary),
          ),
        for (final s in statements.take(3))
          if (data.balances[s.id] case final b?)
            ListTile(
              title: Text('${s.statementDate} 账单'),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: CfSpace.xxs),
                child: Wrap(
                  spacing: CfSpace.xs,
                  runSpacing: CfSpace.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    statementStatusBadge(b.status),
                    Text('到期 ${formatShortDate(b.dueDate, account.today)}'),
                  ],
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  context.go(AppRoutes.statement(s.id, accountId: account.id)),
            ),
      ],
    );
  }

  Future<void> _showInstructions(BuildContext context, int? remaining) async {
    final messenger = ScaffoldMessenger.of(context);
    final card = account.activeCards.isEmpty ? null : account.activeCards.first;
    Future<void> copy(String text, String what) async {
      await Clipboard.setData(ClipboardData(text: text));
      showFeedback(messenger, '已复制$what');
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('查看操作说明'),
        content: const SingleChildScrollView(child: Text(instructions)),
        actions: <Widget>[
          if (remaining != null && remaining > 0)
            TextButton(
              onPressed: () =>
                  unawaited(copy(fromMinorText(remaining, sub.currency), '金额')),
              child: const Text('复制金额'),
            ),
          if (card != null)
            TextButton(
              onPressed: () => unawaited(copy(card.last4, '末四位')),
              child: const Text('复制末四位'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}
