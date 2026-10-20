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
import 'account_ledger_section.dart';
import 'card_dialogs.dart';
import 'card_formatting.dart';

/// P-03 卡片/信用账户详情（ui-spec P-03）：头部（别名、规则来源、子账户切换）、本期（预测账期；有正式账单时
/// 另有账期、应还、最低还款、还款状态）、「去还款」「登记还款」、负债四分法、最近 3 期与「全部账单」（I-1c）、
/// 额度（含还款释放说明）、卡片列表（换卡/补卡、冻结/解冻、销卡）、规则说明；活动与权益区留位（I-4）。
///
/// 四态：加载（骨架）、错误（「重试」）、已不存在、成功；"首次空白"即"尚无账单，下为预测账期"。
class AccountDetailPage extends ConsumerStatefulWidget {
  const AccountDetailPage({super.key, required this.accountId});

  final String accountId;

  /// 首次空白（还没有任何账单）的说明。
  static const String noStatementsNote = AccountLedgerSection.noStatementsNote;

  /// 规则非法时的文案。
  static const String invalidRuleText = '规则非法，无法计算账期';

  @override
  ConsumerState<AccountDetailPage> createState() => _AccountDetailPageState();
}

class _AccountDetailPageState extends ConsumerState<AccountDetailPage> {
  String? _currency;

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletProvider);
    final workspace = ref.watch(currentWorkspaceProvider).value;
    final account = wallet.value?.account(widget.accountId);
    return Scaffold(
      appBar: AppBar(
        title: Text(account?.displayName ?? '信用账户'),
        actions: <Widget>[
          if (account != null)
            IconButton(
              tooltip: '账户设置',
              icon: const Icon(Icons.tune),
              onPressed: () =>
                  context.go(AppRoutes.accountSettings(widget.accountId)),
            ),
        ],
      ),
      body: switch (wallet) {
        AsyncData() when account == null => ErrorBlock(
          title: '已不存在',
          detail: '这个信用账户不在当前空间里（可能已切换空间）。',
          onRetry: () => context.go(AppRoutes.home),
          retryLabel: '回到卡账',
        ),
        AsyncData(:final value) => _AccountDetail(
          account: account!,
          pool: value.poolOf(account.id),
          currency: _currency ?? account.primaryCurrency.currency,
          demo: workspace?.isDemo ?? false,
          onCurrency: (c) => setState(() => _currency = c),
        ),
        AsyncError(:final error) => ErrorBlock(
          title: '读取失败',
          code: '${error.runtimeType}',
          detail: '本机数据没有改动。',
          onRetry: () => ref.invalidate(walletProvider),
        ),
        _ => const LoadingSkeleton(rows: 4),
      },
    );
  }
}

class _AccountDetail extends ConsumerWidget {
  const _AccountDetail({
    required this.account,
    required this.pool,
    required this.currency,
    required this.demo,
    required this.onCurrency,
  });

  final AccountView account;
  final PoolView? pool;
  final String currency;
  final bool demo;
  final ValueChanged<String> onCurrency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: colors.textSecondary,
    );
    final sub = account.currencies.firstWhere(
      (c) => c.currency == currency,
      orElse: () => account.primaryCurrency,
    );
    final source = account.ruleSource;
    return ListView(
      padding: const EdgeInsets.only(bottom: CfSpace.xl),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CfSpace.md,
            CfSpace.sm,
            CfSpace.md,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                <String>[
                  account.bank.name,
                  ?account.account.productName,
                  '持卡人 ${account.account.holderAlias}',
                ].join(' · '),
                style: secondary,
              ),
              const SizedBox(height: CfSpace.xs),
              Wrap(
                spacing: CfSpace.xs,
                runSpacing: CfSpace.xxs,
                children: <Widget>[
                  if (source == null)
                    const StatusBadge(
                      label: '账期规则未设置',
                      icon: Icons.checklist,
                      tone: NoticeTone.attention,
                    )
                  else
                    StatusBadge(
                      label: source.label,
                      icon: Icons.person_outline,
                      tone: NoticeTone.unknown,
                    ),
                  if (demo)
                    const StatusBadge(
                      label: '仅示例',
                      icon: Icons.science_outlined,
                      tone: NoticeTone.unknown,
                    ),
                ],
              ),
              if (account.currencies.length > 1) ...<Widget>[
                const SizedBox(height: CfSpace.sm),
                Wrap(
                  spacing: CfSpace.xs,
                  runSpacing: CfSpace.xs,
                  children: <Widget>[
                    for (final c in account.currencies)
                      ChoiceChip(
                        label: Text(currencyLabel(c.currency)),
                        selected: c.currency == sub.currency,
                        onSelected: (_) => onCurrency(c.currency),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SectionTitle('本期'),
        _ForecastSection(account: account, sub: sub),
        AccountLedgerSection(account: account, sub: sub),
        SectionTitle(
          '额度',
          trailing: TextButton(
            onPressed: () => context.go(
              AppRoutes.accountSettings(account.id, section: 'limits'),
            ),
            child: const Text('更新额度'),
          ),
        ),
        _LimitSection(sub: sub, pool: pool),
        const SectionTitle('卡片'),
        for (final card in account.activeCards)
          _CardRowTile(card: card, account: account),
        if (account.inactiveCards.isNotEmpty)
          ExpansionTile(
            title: Text('已停用的卡（${account.inactiveCards.length}）'),
            children: <Widget>[
              for (final card in account.inactiveCards)
                _CardRowTile(card: card, account: account),
            ],
          ),
        const SectionTitle('规则说明'),
        _RuleExplanation(account: account, sub: sub),
        const SectionTitle('活动与权益'),
        const NoticeCard(
          icon: Icons.schedule,
          tone: NoticeTone.unknown,
          text: '本账户的活动、权益、积分与年费在后续版本提供。',
        ),
      ],
    );
  }
}

/// 预测账期（未出账）：领域包算出的下一个账单日与到期日（ui-spec P-03 本期区）。
class _ForecastSection extends StatelessWidget {
  const _ForecastSection({required this.account, required this.sub});

  final AccountView account;
  final CurrencyAccountView sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final forecast = sub.forecast;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
          child: Wrap(
            spacing: CfSpace.xs,
            runSpacing: CfSpace.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text('预测账期（未出账）', style: theme.textTheme.bodyLarge),
              const StatusBadge(
                label: '系统估计',
                icon: Icons.calculate_outlined,
                tone: NoticeTone.unknown,
              ),
            ],
          ),
        ),
        switch (forecast) {
          ForecastPredicted(:final cycles) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              LabeledValue(
                label: '下一个账单日',
                value: Text(formatDate(cycles.first.statementDate)),
              ),
              LabeledValue(
                label: '到期还款日',
                value: Text(formatDate(cycles.first.dueDate)),
              ),
              if (cycles.length > 1)
                NoticeCard(
                  icon: Icons.help_outline,
                  tone: NoticeTone.unknown,
                  text:
                      '入账时间不确定，可能账期：${cycles.map((c) => '${formatDate(c.statementDate)} 出账、${formatDate(c.dueDate)} 到期').join('，或 ')}（保守按最早到期）。',
                ),
            ],
          ),
          ForecastNoRule() => NoticeCard(
            icon: Icons.checklist,
            text: '账期规则：未设置',
            action: TextButton(
              onPressed: () => context.go(
                AppRoutes.accountSettings(account.id, section: 'rule'),
              ),
              child: const Text('去设置'),
            ),
          ),
          ForecastInvalid() => NoticeCard(
            icon: Icons.error_outline,
            tone: NoticeTone.danger,
            text: AccountDetailPage.invalidRuleText,
            action: TextButton(
              onPressed: () => context.go(
                AppRoutes.accountSettings(account.id, section: 'rule'),
              ),
              child: const Text('去修改'),
            ),
          ),
        },
      ],
    );
  }
}

/// 额度区：固定/临时/专项、银行可用原值（可负，"超限"）、是否已含预授权、可用容量、快照时点。
class _LimitSection extends StatelessWidget {
  const _LimitSection({required this.sub, required this.pool});

  final CurrencyAccountView sub;
  final PoolView? pool;

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
        if (pool != null &&
            sub.currency == pool!.pool.currency &&
            pool!.combinedCapacity != null)
          NoticeCard(
            icon: Icons.account_tree_outlined,
            tone: NoticeTone.unknown,
            text: '与同池账户共享授信池「${pool!.pool.name}」：池内账户可用合计不超过池可用。',
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

  Future<void> _run(
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = card.cardStatus;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CfSpace.md,
        vertical: CfSpace.xxs,
      ),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(CfSpace.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(cardSummary(card), style: theme.textTheme.bodyLarge),
              if (card.alias != null) Text(card.alias!),
              if (card.effectiveFrom != null) Text('生效日 ${card.effectiveFrom}'),
              if (card.closedOn != null) Text('销卡日 ${card.closedOn}'),
              if (!status.isInactive)
                Wrap(
                  spacing: CfSpace.xs,
                  children: <Widget>[
                    if (status.canBecome(CardStatus.replaced))
                      TextButton(
                        onPressed: () async {
                          final input = await showReplaceCardDialog(
                            context,
                            oldTail: cardTail(card),
                            today: account.today,
                          );
                          if (input == null || !context.mounted) {
                            return;
                          }
                          await _run(
                            context,
                            ref,
                            (repo) => repo.replace(
                              card.id,
                              newLast4: input.last4,
                              effectiveFrom: input.effectiveFrom,
                            ),
                            '已换卡，历史不变',
                          );
                        },
                        child: const Text('换卡/补卡'),
                      ),
                    if (status == CardStatus.active)
                      TextButton(
                        onPressed: () => unawaited(
                          _run(context, ref, (r) => r.freeze(card.id), '已冻结'),
                        ),
                        child: const Text('冻结'),
                      ),
                    if (status == CardStatus.frozen)
                      TextButton(
                        onPressed: () => unawaited(
                          _run(context, ref, (r) => r.unfreeze(card.id), '已解冻'),
                        ),
                        child: const Text('解冻'),
                      ),
                    if (status.canBecome(CardStatus.closed))
                      TextButton(
                        onPressed: () async {
                          final closedOn = await showCloseCardDialog(
                            context,
                            tail: cardTail(card),
                            today: account.today,
                          );
                          if (closedOn == null || !context.mounted) {
                            return;
                          }
                          await _run(
                            context,
                            ref,
                            (repo) => repo.close(card.id, closedOn: closedOn),
                            '已销卡',
                          );
                        },
                        child: const Text('销卡'),
                      ),
                  ],
                ),
            ],
          ),
        ),
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
