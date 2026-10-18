import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/widgets/state_views.dart';
import '../../data/repositories/providers.dart';
import 'card_providers.dart';
import 'currency_pool_sections.dart';
import 'limit_snapshot_section.dart';
import 'rule_editor_section.dart';

/// P-04 的分段。
enum AccountSettingsSection {
  rule('rule', '账期规则'),
  limits('limits', '额度快照'),
  currencies('currencies', '币种子账户'),
  pool('pool', '授信池');

  const AccountSettingsSection(this.code, this.label);

  /// 路由参数 `?section=` 的取值。
  final String code;
  final String label;

  /// 解析路由参数；未知或缺省时为账期规则。
  static AccountSettingsSection parse(String? code) =>
      values.firstWhere((s) => s.code == code, orElse: () => rule);
}

/// P-04 信用账户设置（ui-spec P-04）：账期规则（含 3 期预览、版本历史）、额度快照（表单 + 历史）、
/// 币种子账户（增删，主子账户不可删）、授信池（新建/加入/移出，池上限与池内合计）。
///
/// 四态：加载（骨架）、错误（「重试」）、已不存在、成功；"首次空白"为"尚未设置账期规则"。
class AccountSettingsPage extends ConsumerWidget {
  const AccountSettingsPage({
    super.key,
    required this.accountId,
    this.initialSection = AccountSettingsSection.rule,
  });

  final String accountId;
  final AccountSettingsSection initialSection;

  static const String title = '信用账户设置';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletProvider);
    final extra = ref.watch(accountSettingsDataProvider(accountId));
    final account = wallet.value?.account(accountId);
    return DefaultTabController(
      length: AccountSettingsSection.values.length,
      initialIndex: initialSection.index,
      child: Scaffold(
        appBar: AppBar(
          title: Text(account == null ? title : '${account.displayName} · 设置'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: <Widget>[
              for (final section in AccountSettingsSection.values)
                Tab(text: section.label),
            ],
          ),
        ),
        body: switch ((wallet, extra)) {
          (AsyncData(), _) when account == null => ErrorBlock(
            title: '已不存在',
            detail: '这个信用账户不在当前空间里（可能已切换空间）。',
            onRetry: () => context.go(AppRoutes.cards),
            retryLabel: '回到卡包',
          ),
          (AsyncData(value: final w), AsyncData(value: final data)) =>
            TabBarView(
              children: <Widget>[
                RuleEditorSection(
                  key: ValueKey<String>('rule-${account!.id}'),
                  account: account,
                ),
                LimitSnapshotSection(
                  key: ValueKey<String>('limits-${account.id}'),
                  account: account,
                  history: data.snapshots,
                ),
                CurrencyAccountsSection(account: account),
                PoolSection(
                  account: account,
                  pool: w.poolOf(account.id),
                  bankPools: data.bankPools,
                ),
              ],
            ),
          (AsyncError(:final error), _) ||
          (_, AsyncError(:final error)) => ErrorBlock(
            title: '读取失败',
            code: '${error.runtimeType}',
            detail: '本机数据没有改动。',
            onRetry: () => ref
              ..invalidate(walletProvider)
              ..invalidate(accountSettingsDataProvider(accountId)),
          ),
          _ => const LoadingSkeleton(rows: 4),
        },
      ),
    );
  }
}
