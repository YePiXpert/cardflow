import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/feedback.dart';
import '../../app/widgets/money_text.dart';
import '../../app/widgets/state_views.dart';
import '../../data/db/app_database.dart';
import '../../data/mapping/domain_mapping.dart';
import '../../data/repositories/card_repository.dart';
import '../../data/repositories/card_wallet_reader.dart';
import '../../data/repositories/models.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/repository_errors.dart';
import '../../data/time/business_tz.dart';
import 'card_dialogs.dart';
import 'card_formatting.dart';

/// 卡片资料与额度、账期；不依赖账单或现金数据。
class AccountDetailPage extends ConsumerWidget {
  const AccountDetailPage({super.key, required this.accountId});
  final String accountId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('卡片详情')),
      body: switch (wallet) {
        AsyncData(:final value) => _details(context, value),
        AsyncError(:final error) => ErrorBlock(
          title: '卡片读取失败',
          code: '${error.runtimeType}',
          onRetry: () => ref.invalidate(walletProvider),
        ),
        _ => const LoadingSkeleton(),
      },
    );
  }

  Widget _details(BuildContext context, WalletView wallet) {
    final matches = wallet.accounts.where((a) => a.id == accountId);
    if (matches.isEmpty) return const Center(child: Text('卡片已不存在'));
    final a = matches.first;
    return ListView(
      padding: const EdgeInsets.all(CfSpace.md),
      children: <Widget>[
        Text(a.displayName, style: Theme.of(context).textTheme.headlineSmall),
        Wrap(
          spacing: CfSpace.sm,
          children: <Widget>[
            FilledButton(
              onPressed: () => context.go(
                AppRoutes.accountSettings(a.id, section: 'limits'),
              ),
              child: const Text('更新额度'),
            ),
            OutlinedButton(
              onPressed: () => context.go(AppRoutes.accountSettings(a.id)),
              child: const Text('账期与账户设置'),
            ),
          ],
        ),
        for (final sub in a.currencies) ...<Widget>[
          SectionTitle(sub.currency),
          _LimitSection(sub: sub),
          _RuleExplanation(account: a, sub: sub),
        ],
        const SectionTitle('卡片管理'),
        for (final card in a.cards) _CardRowTile(card: card, account: a),
      ],
    );
  }
}

/// 换卡/补卡：新末四位 + 生效日，旧卡 replaced、新卡 active。
Future<void> replaceCardFlow(
  BuildContext context,
  WidgetRef ref,
  CardRow card,
  AccountView account,
) async {
  final input = await showReplaceCardDialog(
    context,
    oldTail: cardTail(card),
    today: account.today,
  );
  if (input == null || !context.mounted) {
    return;
  }
  await runCardAction(
    context,
    ref,
    (repo) => repo.replace(
      card.id,
      newLast4: input.last4,
      effectiveFrom: input.effectiveFrom,
    ),
    '已换卡，历史不变',
  );
}

/// 销卡：销卡日不晚于今天。
Future<void> closeCardFlow(
  BuildContext context,
  WidgetRef ref,
  CardRow card,
  AccountView account,
) async {
  final closedOn = await showCloseCardDialog(
    context,
    tail: cardTail(card),
    today: account.today,
  );
  if (closedOn == null || !context.mounted) {
    return;
  }
  await runCardAction(
    context,
    ref,
    (repo) => repo.close(card.id, closedOn: closedOn),
    '已销卡',
  );
}

/// 调用卡片仓库并给出轻提示（失败时显示仓库的说明）。
Future<void> runCardAction(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function(CardRepository repo) action,
  String success,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final repo = await ref.read(cardRepositoryProvider.future);
    await action(repo);
    showFeedback(messenger, success);
  } on RepositoryException catch (error) {
    showFeedback(messenger, error.message);
  }
}

/// 额度区：固定/临时/专项、银行可用原值（可负，"超限"）、是否已含预授权、可用容量、快照时点。
class _LimitSection extends StatelessWidget {
  const _LimitSection({required this.sub});

  final CurrencyAccountView sub;

  @override
  Widget build(BuildContext context) {
    final snapshot = sub.latestSnapshot;
    if (snapshot == null) {
      return const NoticeCard(
        icon: Icons.checklist,
        text: '还没有额度快照：可用容量未知（不以 0 代替）。点「更新额度」记录。',
      );
    }
    final c = sub.currency;
    final expires = parseOptionalDate(snapshot.tempExpiresOn);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LabeledValue(
          label: '固定额度',
          value: MoneyText(
            minor: snapshot.fixedMinor,
            currency: c,
            semanticsPrefix: '固定额度',
          ),
        ),
        if (snapshot.tempMinor > 0)
          LabeledValue(
            label: expires == null ? '临时额度' : '临时额度（${formatDate(expires)} 到期）',
            value: MoneyText(
              minor: snapshot.tempMinor,
              currency: c,
              semanticsPrefix: '临时额度',
            ),
          ),
        if (snapshot.specialMinor > 0)
          LabeledValue(
            label: '专项额度（${snapshot.specialPurpose ?? ''}，不用于普通消费）',
            value: MoneyText(
              minor: snapshot.specialMinor,
              currency: c,
              semanticsPrefix: '专项额度',
            ),
          ),
        LabeledValue(
          label: '已用',
          value: MoneyText(
            minor: snapshot.usedMinor,
            currency: c,
            semanticsPrefix: '已用',
          ),
        ),
        LabeledValue(
          label: '银行可用（原值）',
          value: MoneyText(
            minor: snapshot.availableRawMinor,
            currency: c,
            negativeLabel: '超限',
            semanticsPrefix: '银行可用',
          ),
        ),
        LabeledValue(
          label: '预授权',
          value: Text(
            snapshot.includesHolds ? '已含在银行可用里，不再扣减' : '未含在银行可用里，按已知金额扣减',
          ),
        ),
        if (!snapshot.includesHolds && snapshot.holdsMinor > 0)
          LabeledValue(
            label: '预授权金额',
            value: MoneyText(
              minor: snapshot.holdsMinor,
              currency: c,
              semanticsPrefix: '预授权',
            ),
          ),
        LabeledValue(
          label: '可用容量',
          value: MoneyText(
            minor: sub.capacity,
            currency: c,
            semanticsPrefix: '可用容量',
          ),
        ),
        if (sub.overLimit)
          const NoticeCard(
            icon: Icons.warning_amber_outlined,
            tone: NoticeTone.danger,
            text: '超限：银行可用额为负（原值保留），可供新增消费的容量为 0。',
          ),
        LabeledValue(
          label: '快照时点',
          value: Text(
            '${snapshot.balanceAsOf.substring(0, 16).replaceFirst('T', ' ')} · ${ageText(sub.snapshotAgeDays ?? 0)}',
          ),
        ),
        if (sub.stale)
          const NoticeCard(
            icon: Icons.schedule,
            text: '额度快照已超过 7 天，可用容量只是假设分析。',
          ),
      ],
    );
  }
}

/// 一张卡与它的操作（换卡/补卡、冻结/解冻、销卡）。
class _CardRowTile extends ConsumerWidget {
  const _CardRowTile({required this.card, required this.account});

  final CardRow card;
  final AccountView account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = card.cardStatus;
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: CardFlowColors.of(context).textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CfSpace.md,
        CfSpace.sm,
        CfSpace.md,
        CfSpace.xxs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(cardSummary(card), style: theme.textTheme.bodyLarge),
          if (card.alias != null) Text(card.alias!, style: secondary),
          if (card.effectiveFrom != null)
            Text('生效日 ${card.effectiveFrom}', style: secondary),
          if (card.closedOn != null)
            Text('销卡日 ${card.closedOn}', style: secondary),
          if (!status.isInactive)
            Wrap(
              spacing: CfSpace.xs,
              children: <Widget>[
                if (status.canBecome(CardStatus.replaced))
                  TextButton(
                    onPressed: () =>
                        unawaited(replaceCardFlow(context, ref, card, account)),
                    child: const Text('换卡/补卡'),
                  ),
                if (status == CardStatus.active)
                  TextButton(
                    onPressed: () => unawaited(
                      runCardAction(
                        context,
                        ref,
                        (r) => r.freeze(card.id),
                        '已冻结',
                      ),
                    ),
                    child: const Text('冻结'),
                  ),
                if (status == CardStatus.frozen)
                  TextButton(
                    onPressed: () => unawaited(
                      runCardAction(
                        context,
                        ref,
                        (r) => r.unfreeze(card.id),
                        '已解冻',
                      ),
                    ),
                    child: const Text('解冻'),
                  ),
                if (status.canBecome(CardStatus.closed))
                  TextButton(
                    onPressed: () =>
                        unawaited(closeCardFlow(context, ref, card, account)),
                    child: const Text('销卡'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 规则说明：当天归属、到期、顺延、入账延迟、截止时点、业务时区（ui-spec P-03）。
class _RuleExplanation extends StatelessWidget {
  const _RuleExplanation({required this.account, required this.sub});

  final AccountView account;
  final CurrencyAccountView sub;

  @override
  Widget build(BuildContext context) {
    final forecast = sub.forecast;
    BillingRuleVersionRow? rule;
    if (forecast is ForecastPredicted) {
      rule = sub.ruleVersions.firstWhere((r) => r.id == forecast.ruleVersionId);
    } else if (sub.ruleVersions.isNotEmpty) {
      rule = sub.ruleVersions.last;
    }
    if (rule == null) {
      return const NoticeCard(icon: Icons.checklist, text: '账期规则未设置。');
    }
    final lines = <(String, String)>[
      ('账单日', describeStatementDay(rule.statementDay)),
      ('当天归属', describeInclusive(rule.statementDayInclusive)),
      ('到期', describeDue(dueOf(rule))),
      ('顺延', describeRollover(rule.holidayRollover)),
      (
        '入账延迟',
        describePostingDelay(
          rule.postingDelayMinDays,
          rule.postingDelayMaxDays,
        ),
      ),
      ('截止时点', describeCutoff(rule.cutoffTime)),
      ('业务时区', describeZone(account.account.businessTz)),
      ('规则版本', '第 ${rule.version} 版 · ${describeEffectiveRange(rule)}'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final (label, value) in lines)
          LabeledValue(label: label, value: Text(value)),
        if (findBusinessTimeZone(account.account.businessTz) == null)
          const NoticeCard(icon: Icons.public, text: '该时区本期不支持。'),
      ],
    );
  }
}
