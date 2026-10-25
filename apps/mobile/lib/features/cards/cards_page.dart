import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/calm_panel.dart';
import '../../app/widgets/first_run_empty_state.dart';
import '../../app/widgets/money_text.dart';
import '../../app/widgets/premium.dart';
import '../../app/widgets/state_views.dart';
import '../../data/mapping/domain_mapping.dart';
import '../../data/repositories/card_wallet_reader.dart';
import '../../data/repositories/models.dart';
import '../../data/repositories/providers.dart';
import '../onboarding/workspace_actions.dart';
import 'available_limit_form.dart';
import 'card_formatting.dart';

/// P-02 管理全部卡片（原"卡包"，从卡账右上角或列表底部进入）：授信池 › 信用账户 › 币种子账户 › 卡片 的层级列表。
///
/// 四态：首次空白（还没有卡片）、加载（骨架）、错误（错误码 +「重试」）、成功（层级列表；已停用折叠）。
class CardsPage extends ConsumerWidget {
  const CardsPage({super.key});

  /// 页名（卡账 › 管理全部卡片）。
  static const String title = '全部卡片';

  /// ui-spec P-02 九态表"首次空白"。
  static const String firstRunMessage = '添加卡片，比较消费时用哪张卡';

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
          purpose: '填写可用额度和账期规则，即可开始选卡。',
          actions: <EmptyStateAction>[
            EmptyStateAction(
              label: '手工建卡',
              onPressed: () => context.go(AppRoutes.newCard),
            ),
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

/// 共享池概要；额度已计入各卡，完整资料在账户设置中维护。
class _PoolHeader extends StatelessWidget {
  const _PoolHeader({required this.pool});
  final PoolView pool;
  @override
  Widget build(BuildContext context) {
    final c = CardFlowColors.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CfSpace.md,
        CfSpace.md,
        CfSpace.md,
        CfSpace.xs,
      ),
      child: CalmPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: CfSize.bankBadge,
                  height: CfSize.bankBadge,
                  decoration: BoxDecoration(
                    color: c.actionTint,
                    borderRadius: BorderRadius.circular(CfRadius.lg),
                  ),
                  child: Icon(
                    Icons.hub_rounded,
                    color: c.action,
                    size: CfIconSize.md,
                  ),
                ),
                const SizedBox(width: CfSpace.sm),
                Expanded(
                  child: Text('授信池 · ${pool.pool.name}', style: t.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: CfSpace.sm),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: CfSpace.md,
              runSpacing: CfSpace.xxs,
              children: [
                Text(
                  '池上限',
                  style: t.bodyMedium?.copyWith(color: c.textSecondary),
                ),
                MoneyText(
                  minor: pool.pool.sharedLimitMinor,
                  currency: pool.pool.currency,
                  compact: true,
                  semanticsPrefix: '池上限',
                  style: t.titleMedium,
                ),
              ],
            ),
            if (pool.missingSnapshots > 0) ...[
              const SizedBox(height: CfSpace.sm),
              const HintStrip(
                icon: Icons.info_outline_rounded,
                text: '成员额度资料不全，请更新后再比较。',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 一个信用账户：银行卡面（名称、末四位、额度条）、可用容量（超限时标注）、距出账/距还款、账期规则、快照时点。
class AccountTile extends StatelessWidget {
  const AccountTile({super.key, required this.account});

  final AccountView account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final primary = account.primaryCurrency;
    final source = account.ruleSource;
    final rule = account.currentRule;
    final forecast = primary.forecast;
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: colors.textSecondary,
    );
    final predicted = forecast is ForecastPredicted
        ? forecast.conservative
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CfSpace.md,
        vertical: CfSpace.xs,
      ),
      child: CalmPanel(
        padding: const EdgeInsets.all(CfSpace.xs),
        child: InkWell(
          borderRadius: BorderRadius.circular(CfRadius.hero),
          onTap: () => context.go(AppRoutes.account(account.id)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              BankCardFace(
                compact: true,
                bankName: account.bank.name,
                subtitle: account.displayName,
                last4s: <String>[for (final c in account.activeCards) c.last4],
                badge: account.pool == null ? null : '共享额度',
                badgeIcon: Icons.hub_rounded,
                fraction: capacityFraction(primary),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CfSpace.sm,
                  CfSpace.md,
                  CfSpace.sm,
                  CfSpace.xxs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    MetricRow(
                      metrics: <Metric>[
                        Metric(
                          label: '可用额度',
                          value: MoneyText(
                            minor: primary.capacity,
                            currency: primary.currency,
                            compact: true,
                            semanticsPrefix: '可用容量',
                            textAlign: TextAlign.start,
                          ),
                        ),
                        if (predicted != null)
                          Metric(
                            label: '今天刷距预计还款',
                            value: Text(
                              '${predicted.dueDate.differenceInDays(account.today)} 天',
                            ),
                            caption:
                                '${monthDay(predicted.dueDate)} 还款 · ${_statementIn(predicted.statementDate.differenceInDays(account.today))}',
                            emphasized: true,
                          ),
                      ],
                    ),
                    if (rule != null) ...<Widget>[
                      const SizedBox(height: CfSpace.sm),
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.event_repeat_rounded,
                            size: CfIconSize.sm,
                            color: colors.textSecondary,
                          ),
                          const SizedBox(width: CfSpace.xs),
                          Expanded(
                            child: Text(
                              '${describeStatementDay(rule.statementDay)}出账 · ${describeDue(dueOf(rule))}还款',
                              style: secondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                    // 一行至多一个状态标签（简报 U-1 §5）：超限 > 缺账期规则 > 额度快照陈旧。
                    if (primary.overLimit)
                      const _AccountStatus(
                        label: '超限',
                        icon: Icons.warning_amber_outlined,
                        tone: NoticeTone.danger,
                      )
                    else if (source == null)
                      const _AccountStatus(
                        label: '账期规则未设置',
                        icon: Icons.checklist,
                        tone: NoticeTone.attention,
                      )
                    else if (primary.stale)
                      _AccountStatus(
                        label: '额度 ${ageText(primary.snapshotAgeDays!)}',
                        icon: Icons.schedule,
                        tone: NoticeTone.attention,
                      ),
                    if (account.currencies.length > 1) ...<Widget>[
                      const SizedBox(height: CfSpace.xxs),
                      Text(
                        '币种子账户：${account.currencies.map((c) => c.row.isPrimary ? '${currencyLabel(c.currency)}（主）' : currencyLabel(c.currency)).join('、')}',
                        style: secondary,
                      ),
                    ],
                    if (account.inactiveCards.isNotEmpty)
                      Text(
                        '已停用的卡 ${account.inactiveCards.length} 张（详情页查看）',
                        style: secondary,
                      ),
                    if (account.cards.any(
                      (c) => c.cardStatus == CardStatus.frozen,
                    ))
                      Text('有卡片已冻结', style: secondary),
                    const SizedBox(height: CfSpace.xs),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: CfSpace.sm,
                      runSpacing: CfSpace.xxs,
                      children: <Widget>[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.update_rounded,
                              size: CfIconSize.sm,
                              color: colors.textSecondary,
                            ),
                            const SizedBox(width: CfSpace.xxs),
                            Flexible(
                              child: Text(
                                primary.latestSnapshot == null
                                    ? '额度未记录'
                                    : '额度 ${ageText(primary.snapshotAgeDays!)}',
                                style: secondary,
                              ),
                            ),
                          ],
                        ),
                        if (!account.isInactive)
                          TextButton(
                            onPressed: () => unawaited(
                              showQuickLimitDialog(context, account),
                            ),
                            style: TextButton.styleFrom(
                              backgroundColor: colors.actionTint,
                              shape: const StadiumBorder(),
                            ),
                            child: const Text('快速改额度'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 距出账的说明（"4 天后出账""今天出账"）。
String _statementIn(int days) => days <= 0 ? '今天出账' : '$days 天后出账';

/// 账户的状态标签（一行一个）。
class _AccountStatus extends StatelessWidget {
  const _AccountStatus({
    required this.label,
    required this.icon,
    required this.tone,
  });

  final String label;
  final IconData icon;
  final NoticeTone tone;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: CfSpace.xs),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: StatusBadge(label: label, icon: icon, tone: tone),
    ),
  );
}
