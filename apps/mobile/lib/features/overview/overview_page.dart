import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/first_run_empty_state.dart';
import '../../app/widgets/state_views.dart';
import '../../app/widgets/workspace_badges.dart';
import '../../data/mapping/domain_mapping.dart';
import '../../data/repositories/card_wallet_reader.dart';
import '../../data/repositories/providers.dart';
import '../cards/card_formatting.dart';
import '../onboarding/workspace_actions.dart';

/// P-01 总览（最小版，ui-spec P-01）：顶部空间标识（真实/演示）与"纯本地"；每个信用账户一行
/// "预测账期（未出账）"与到期日；还没有现金账户 → "数据不全：还没有现金账户"（入口在 I-1b）。
///
/// 四态：首次空白（还没有信用账户）、加载（骨架）、错误（「重试」）、成功。
class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  /// 页名，同时是底部导航的标签。
  static const String title = '总览';

  /// ui-spec P-01 九态表"首次空白"。
  static const String firstRunMessage = '还没有信用账户';

  /// 没有现金账户时的数据不全提示。
  static const String noCashAccounts = '数据不全：还没有现金账户';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: switch (wallet) {
        AsyncData(:final value) when value.isEmpty => ListView(
          children: <Widget>[
            const RootPageBadges(),
            FirstRunEmptyState(
              icon: Icons.dashboard_outlined,
              message: firstRunMessage,
              purpose: '一屏看清近期应还、现金缺口、待办与数据新鲜度。',
              actions: <EmptyStateAction>[
                EmptyStateAction(
                  label: '建卡',
                  onPressed: () => context.go(AppRoutes.newCard),
                ),
                const EmptyStateAction(label: '导入', stage: 'I-3 提供'),
                EmptyStateAction(
                  label: '体验演示',
                  onPressed: () => unawaited(enterDemoWorkspace(context, ref)),
                ),
              ],
              scrollable: false,
            ),
          ],
        ),
        AsyncData(:final value) => _Overview(wallet: value),
        AsyncError(:final error) => ErrorBlock(
          title: '总览读取失败',
          code: '${error.runtimeType}',
          detail: '本机数据没有改动。',
          onRetry: () => ref.invalidate(walletProvider),
        ),
        _ => const LoadingSkeleton(),
      },
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.wallet});

  final WalletView wallet;

  @override
  Widget build(BuildContext context) {
    final accounts = wallet.accounts.where((a) => !a.isInactive).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: CfSpace.xl),
      children: <Widget>[
        const RootPageBadges(),
        const NoticeCard(
          icon: Icons.checklist,
          text:
              '${OverviewPage.noCashAccounts}。现金账户、余额与资金日历在 I-1b 提供，届时才能判断还款时现金够不够。',
          action: OutlinedButton(onPressed: null, child: Text('添加现金账户')),
        ),
        const SectionTitle('预测账期（未出账）'),
        for (final account in accounts) _AccountCycleRow(account: account),
        if (accounts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: Text('信用账户都已停用。'),
          ),
      ],
    );
  }
}

class _AccountCycleRow extends StatelessWidget {
  const _AccountCycleRow({required this.account});

  final AccountView account;

  @override
  Widget build(BuildContext context) {
    final forecast = account.forecast;
    final today = account.today;
    final subtitle = switch (forecast) {
      ForecastPredicted(:final cycles) when cycles.length > 1 =>
        '可能账期：${cycles.map((c) => '${formatShortDate(c.statementDate, today)} 出账、${formatShortDate(c.dueDate, today)} 到期').join('，或 ')}（系统估计）',
      ForecastPredicted(:final conservative) =>
        '账单日 ${formatShortDate(conservative.statementDate, today)} · 到期 ${formatShortDate(conservative.dueDate, today)}（系统估计）',
      ForecastNoRule() => '账期规则未设置',
      ForecastInvalid() => '规则非法，无法计算账期',
    };
    return ListTile(
      title: Text(account.displayName),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(AppRoutes.account(account.id)),
    );
  }
}
