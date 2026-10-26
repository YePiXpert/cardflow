import 'dart:async';

import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/bank_badge.dart';
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

/// 管理全部卡片：共享额度 › 卡片账户 的紧凑列表。
///
/// 四态：首次空白（还没有卡片）、加载（骨架）、错误（错误码 +「重试」）、成功（层级列表；已停用折叠）。
class CardsPage extends ConsumerWidget {
  const CardsPage({super.key});

  /// 页名。
  static const String title = '全部卡片';

  /// 首次空白文案。
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
          purpose: '填写可用额度和账单日、还款日，即可开始选卡。',
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
        _CycleRelaySchedule(accounts: active),
        for (final pool in pools) ...<Widget>[
          _PoolHeader(pool: pool),
          for (final account in pool.members.where((a) => !a.isInactive))
            AccountTile(account: account),
        ],
        if (unpooled.isNotEmpty && pools.isNotEmpty)
          const SectionTitle('独立额度卡片'),
        for (final account in unpooled) AccountTile(account: account),
        if (inactive.isNotEmpty)
          ExpansionTile(
            title: Text('已停用（${inactive.length}）'),
            subtitle: const Text('卡片均已销卡或换卡'),
            children: <Widget>[
              for (final account in inactive) AccountTile(account: account),
            ],
          ),
      ],
    );
  }
}

class _CycleEvent {
  const _CycleEvent({
    required this.accountName,
    required this.date,
    required this.days,
    required this.isStatement,
  });

  final String accountName;
  final LocalDate date;
  final int days;
  final bool isStatement;
}

/// 近期出账与还款接力排期：按时间先后展示各卡即将到来的账单日与还款日。
class _CycleRelaySchedule extends StatelessWidget {
  const _CycleRelaySchedule({required this.accounts});

  final List<AccountView> accounts;

  @override
  Widget build(BuildContext context) {
    final events = <_CycleEvent>[];
    for (final a in accounts) {
      final forecast = a.primaryCurrency.forecast;
      if (forecast is! ForecastPredicted) continue;
      final predicted = forecast.conservative;
      events.add(
        _CycleEvent(
          accountName: a.displayName,
          date: predicted.statementDate,
          days: predicted.statementDate.differenceInDays(a.today),
          isStatement: true,
        ),
      );
      events.add(
        _CycleEvent(
          accountName: a.displayName,
          date: predicted.dueDate,
          days: predicted.dueDate.differenceInDays(a.today),
          isStatement: false,
        ),
      );
    }
    if (events.isEmpty) return const SizedBox.shrink();
    events.sort((a, b) {
      final cmp = a.days.compareTo(b.days);
      if (cmp != 0) return cmp;
      if (a.isStatement != b.isStatement) return a.isStatement ? -1 : 1;
      return a.accountName.compareTo(b.accountName);
    });
    final upcoming = events.take(4).toList();
    final c = CardFlowColors.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CfSpace.md,
        CfSpace.xs,
        CfSpace.md,
        CfSpace.xxs,
      ),
      child: CalmPanel(
        padding: const EdgeInsets.symmetric(
          horizontal: CfSpace.md,
          vertical: CfSpace.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: CfSpace.xs,
              runSpacing: CfSpace.xxs,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.event_note_rounded,
                      color: c.action,
                      size: CfIconSize.md,
                    ),
                    const SizedBox(width: CfSpace.xs),
                    Flexible(child: Text('近期出账与还款排期', style: t.titleSmall)),
                  ],
                ),
                Text(
                  '出账次日刷卡享最长免息期',
                  style: t.bodySmall?.copyWith(color: c.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: CfSpace.xs),
            Wrap(
              spacing: CfSpace.xs,
              runSpacing: CfSpace.xs,
              children: <Widget>[
                for (final e in upcoming) _buildChip(context, e, c, t),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(
    BuildContext context,
    _CycleEvent e,
    CardFlowColors c,
    TextTheme t,
  ) {
    final tone = e.isStatement ? c.bank : c.attention;
    final tag = e.isStatement ? '出账' : '还款';
    final dayLabel = e.days <= 0 ? '今天' : '${e.days} 天后';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CfSpace.xs,
        vertical: CfSpace.xxs,
      ),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(CfRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: CfSpace.xxs + 2,
              vertical: 1,
            ),
            decoration: BoxDecoration(
              color: tone.bg,
              borderRadius: BorderRadius.circular(CfRadius.pill),
            ),
            child: Text(
              tag,
              style: t.labelSmall?.copyWith(
                color: tone.fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: CfSpace.xxs),
          Flexible(
            child: Text(
              '${e.accountName} · $dayLabel（${monthDay(e.date)}）',
              style: t.bodySmall?.copyWith(
                color: c.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 共享额度概要；完整资料在卡片设置中维护。
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
        CfSpace.sm,
        CfSpace.md,
        CfSpace.xxs,
      ),
      child: CalmPanel(
        padding: const EdgeInsets.symmetric(
          horizontal: CfSpace.md,
          vertical: CfSpace.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: CfSpace.sm,
              runSpacing: CfSpace.xxs,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.hub_rounded,
                      color: c.action,
                      size: CfIconSize.md,
                    ),
                    const SizedBox(width: CfSpace.xs),
                    Flexible(
                      child: Text(
                        '共享额度 · ${pool.pool.name}',
                        style: t.titleSmall,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: CfSpace.xs,
                  runSpacing: CfSpace.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '共享上限',
                      style: t.bodySmall?.copyWith(color: c.textSecondary),
                    ),
                    MoneyText(
                      minor: pool.pool.sharedLimitMinor,
                      currency: pool.pool.currency,
                      compact: true,
                      semanticsPrefix: '共享上限',
                      style: t.titleSmall,
                    ),
                  ],
                ),
              ],
            ),
            if (pool.missingSnapshots > 0) ...[
              const SizedBox(height: CfSpace.xs),
              const HintStrip(
                icon: Icons.info_outline_rounded,
                text: '部分卡片尚未记录额度，请更新后再比较。',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 单层高密度卡片项：银行徽标、卡名、尾号、可用额度、距还款天数与快捷改额度。
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
    final statementDays = predicted?.statementDate.differenceInDays(
      account.today,
    );
    final dueDays = predicted?.dueDate.differenceInDays(account.today);
    final isNearStatement =
        !account.isInactive &&
        !primary.overLimit &&
        statementDays != null &&
        statementDays >= 0 &&
        statementDays <= 3;
    final isGoldenWindow =
        !account.isInactive &&
        !primary.overLimit &&
        !isNearStatement &&
        ((statementDays != null && statementDays >= 24) ||
            (dueDays != null && dueDays >= 42));
    final last4s = <String>[for (final c in account.activeCards) c.last4];
    final tailText = last4s.isEmpty ? '未记录尾号' : '尾号 ${last4s.join(' / ')}';
    final frac = capacityFraction(primary);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CfSpace.md,
        vertical: CfSpace.xs,
      ),
      child: CalmPanel(
        padding: const EdgeInsets.all(CfSpace.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(CfRadius.lg),
          onTap: () => context.go(AppRoutes.account(account.id)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  BankBadge(bankName: account.bank.name),
                  const SizedBox(width: CfSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Wrap(
                          spacing: CfSpace.xs,
                          runSpacing: CfSpace.xxs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            Text(
                              account.bank.name,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              account.displayName,
                              style: theme.textTheme.titleMedium,
                            ),
                            if (account.pool != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: CfSpace.xs,
                                  vertical: CfSpace.xxs / 2,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.actionTint,
                                  borderRadius: BorderRadius.circular(
                                    CfRadius.pill,
                                  ),
                                ),
                                child: Text(
                                  '共享额度',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colors.action,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            if (isNearStatement)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: CfSpace.xs,
                                  vertical: CfSpace.xxs / 2,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.attention.bg,
                                  borderRadius: BorderRadius.circular(
                                    CfRadius.pill,
                                  ),
                                ),
                                child: Text(
                                  '临近出账',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colors.attention.fg,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            else if (isGoldenWindow)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: CfSpace.xs,
                                  vertical: CfSpace.xxs / 2,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.bank.bg,
                                  borderRadius: BorderRadius.circular(
                                    CfRadius.pill,
                                  ),
                                ),
                                child: Text(
                                  '黄金免息期',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colors.bank.fg,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Text(
                          rule == null
                              ? tailText
                              : '$tailText · ${describeStatementDay(rule.statementDay)}出账 · ${describeDue(dueOf(rule))}还款',
                          style: secondary,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.textTertiary,
                    size: CfIconSize.md,
                  ),
                ],
              ),
              if (frac != null) ...<Widget>[
                const SizedBox(height: CfSpace.sm),
                LimitBar(fraction: frac),
              ],
              const SizedBox(height: CfSpace.sm),
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
              // 一行至多一个状态标签：超限 > 缺账期规则 > 额度快照陈旧。
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
                  '支持币种：${account.currencies.map((c) => c.row.isPrimary ? '${currencyLabel(c.currency)}（默认）' : currencyLabel(c.currency)).join('、')}',
                  style: secondary,
                ),
              ],
              if (account.inactiveCards.isNotEmpty)
                Text(
                  '含 ${account.inactiveCards.length} 张已停用卡片',
                  style: secondary,
                ),
              if (account.cards.any((c) => c.cardStatus == CardStatus.frozen))
                Text('有卡片已冻结', style: secondary),
              const SizedBox(height: CfSpace.xs),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: CfSpace.sm,
                runSpacing: CfSpace.xxs,
                children: <Widget>[
                  Text(
                    primary.latestSnapshot == null
                        ? '额度未记录'
                        : '额度更新于 ${ageText(primary.snapshotAgeDays!)}',
                    style: secondary,
                  ),
                  if (!account.isInactive)
                    TextButton(
                      onPressed: () =>
                          unawaited(showQuickLimitDialog(context, account)),
                      style: TextButton.styleFrom(
                        backgroundColor: colors.actionTint,
                        foregroundColor: colors.action,
                        padding: const EdgeInsets.symmetric(
                          horizontal: CfSpace.md,
                        ),
                      ),
                      child: const Text('快速改额度'),
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
