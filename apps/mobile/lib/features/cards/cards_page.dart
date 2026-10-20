import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/first_run_empty_state.dart';
import '../../app/widgets/money_text.dart';
import '../../app/widgets/state_views.dart';
import '../../data/repositories/card_wallet_reader.dart';
import '../../data/repositories/models.dart';
import '../../data/repositories/providers.dart';
import '../onboarding/workspace_actions.dart';
import 'card_formatting.dart';

/// P-02 管理全部卡片（原"卡包"，从卡账右上角或列表底部进入）：授信池 › 信用账户 › 币种子账户 › 卡片 的层级列表。
///
/// 四态：首次空白（还没有卡片）、加载（骨架）、错误（错误码 +「重试」）、成功（层级列表；已停用折叠）。
class CardsPage extends ConsumerWidget {
  const CardsPage({super.key});

  /// 页名（卡账 › 管理全部卡片）。
  static const String title = '全部卡片';

  /// ui-spec P-02 九态表"首次空白"。
  static const String firstRunMessage = '还没有卡片，账单挂在信用账户上';

  /// 读取失败的标题。
  static const String errorTitle = '卡片读取失败';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(title),
        actions: <Widget>[
          IconButton(
            tooltip: '添加卡片',
            icon: const Icon(Icons.add),
            onPressed: () => context.go(AppRoutes.newCard),
          ),
        ],
      ),
      body: switch (wallet) {
        AsyncData(:final value) when value.isEmpty => FirstRunEmptyState(
          icon: Icons.credit_card_outlined,
          message: firstRunMessage,
          purpose: '按 授信池 › 信用账户 › 币种子账户 › 卡片 浏览与新建。',
          actions: <EmptyStateAction>[
            EmptyStateAction(
              label: '手工建卡',
              onPressed: () => context.go(AppRoutes.newCard),
            ),
            const EmptyStateAction(label: '从账单文件开始', stage: '后续版本提供'),
            EmptyStateAction(
              label: '体验演示',
              onPressed: () => unawaited(enterDemoWorkspace(context, ref)),
            ),
          ],
        ),
        AsyncData(:final value) => _WalletList(wallet: value),
        AsyncError(:final error) => ErrorBlock(
          title: errorTitle,
          code: '${error.runtimeType}',
          detail: '本机数据没有改动。',
          onRetry: () => ref.invalidate(walletProvider),
        ),
        _ => const LoadingSkeleton(),
      },
    );
  }
}

class _WalletList extends StatelessWidget {
  const _WalletList({required this.wallet});

  final WalletView wallet;

  @override
  Widget build(BuildContext context) {
    final active = wallet.accounts.where((a) => !a.isInactive).toList();
    final inactive = wallet.accounts.where((a) => a.isInactive).toList();
    final pools = wallet.pools.where((p) => p.members.isNotEmpty).toList();
    final unpooled = active.where((a) => a.pool == null).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: CfSpace.lg),
      children: <Widget>[
        for (final pool in pools) ...<Widget>[
          _PoolHeader(pool: pool),
          for (final account in pool.members.where((a) => !a.isInactive))
            AccountTile(account: account),
        ],
        if (unpooled.isNotEmpty && pools.isNotEmpty)
          const SectionTitle('不在授信池里的账户'),
        for (final account in unpooled) AccountTile(account: account),
        if (inactive.isNotEmpty)
          ExpansionTile(
            title: Text('已停用（${inactive.length}）'),
            subtitle: const Text('卡片都已销卡或换卡的信用账户'),
            children: <Widget>[
              for (final account in inactive) AccountTile(account: account),
            ],
          ),
      ],
    );
  }
}

/// 授信池的标题行：池上限、池内已用、池可用、池内账户可用合计（F-23）。
class _PoolHeader extends StatelessWidget {
  const _PoolHeader({required this.pool});

  final PoolView pool;

  @override
  Widget build(BuildContext context) {
    final currency = pool.pool.currency;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionTitle('授信池 · ${pool.pool.name}'),
        LabeledValue(
          label: '池上限',
          value: MoneyText(
            minor: pool.pool.sharedLimitMinor,
            currency: currency,
            semanticsPrefix: '池上限',
          ),
        ),
        if (pool.missingSnapshots > 0)
          NoticeCard(
            icon: Icons.checklist,
            text: '池可用：数据不全（${pool.missingSnapshots} 个账户缺额度快照），不以 0 代替。',
          )
        else ...<Widget>[
          LabeledValue(
            label: '池内已用',
            value: MoneyText(
              minor: pool.usedTotal,
              currency: currency,
              semanticsPrefix: '池内已用',
            ),
          ),
          LabeledValue(
            label: '池内账户可用合计（不超过池可用）',
            value: MoneyText(
              minor: pool.combinedCapacity,
              currency: currency,
              semanticsPrefix: '池内账户可用合计',
            ),
          ),
          if ((pool.rawAvailable ?? 0) < 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: CfSpace.md),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: StatusBadge(
                  label: '池已超限',
                  icon: Icons.warning_amber_outlined,
                  tone: NoticeTone.danger,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// 一个信用账户：名称、银行与产品、规则来源、可用容量（超限时标注）、快照时点、子账户、卡片。
class AccountTile extends StatelessWidget {
  const AccountTile({super.key, required this.account});

  final AccountView account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final primary = account.primaryCurrency;
    final source = account.ruleSource;
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: colors.textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CfSpace.md,
        vertical: CfSpace.xs,
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.go(AppRoutes.account(account.id)),
          child: Padding(
            padding: const EdgeInsets.all(CfSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(account.displayName, style: theme.textTheme.titleMedium),
                const SizedBox(height: CfSpace.xxs),
                Text(
                  <String>[
                    account.bank.name,
                    ?account.account.productName,
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
                    if (primary.overLimit)
                      const StatusBadge(
                        label: '超限',
                        icon: Icons.warning_amber_outlined,
                        tone: NoticeTone.danger,
                      ),
                    if (primary.stale)
                      StatusBadge(
                        label: '额度 ${ageText(primary.snapshotAgeDays!)}',
                        icon: Icons.schedule,
                        tone: NoticeTone.attention,
                      ),
                  ],
                ),
                const SizedBox(height: CfSpace.xs),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: CfSpace.sm,
                  children: <Widget>[
                    Text('可用容量', style: secondary),
                    MoneyText(
                      minor: primary.capacity,
                      currency: primary.currency,
                      semanticsPrefix: '可用容量',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
                Text(
                  primary.latestSnapshot == null
                      ? '额度未记录'
                      : '额度 ${ageText(primary.snapshotAgeDays!)}',
                  style: secondary,
                ),
                if (account.currencies.length > 1) ...<Widget>[
                  const SizedBox(height: CfSpace.xxs),
                  Text(
                    '币种子账户：${account.currencies.map((c) => c.row.isPrimary ? '${currencyLabel(c.currency)}（主）' : currencyLabel(c.currency)).join('、')}',
                    style: secondary,
                  ),
                ],
                const Divider(height: CfSpace.lg),
                for (final card in account.activeCards)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: CfSpace.xxs),
                    child: Text(
                      card.alias == null
                          ? cardSummary(card)
                          : '${cardSummary(card)} · ${card.alias}',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                if (account.inactiveCards.isNotEmpty)
                  Text(
                    '已停用的卡 ${account.inactiveCards.length} 张（详情页查看）',
                    style: secondary,
                  ),
                if (account.cards.any((c) => c.cardStatus == CardStatus.frozen))
                  Text('有卡片已冻结', style: secondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
