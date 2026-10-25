import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/state_views.dart';
import '../../data/repositories/providers.dart';
import 'card_providers.dart';
import 'currency_pool_sections.dart';
import 'limit_snapshot_section.dart';
import 'rule_editor_section.dart';

/// P-04 的分段。
enum AccountSettingsSection {
  rule('rule', '账期规则'),
  limits('limits', '可用额度'),
  currencies('currencies', '多币种'),
  pool('pool', '共享额度');

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
/// 分段切换用一行可换行的选择标签（而不是固定高度的 TabBar），文字放大到 3 倍也不会溢出。
/// 四态：加载（骨架）、错误（「重试」）、已不存在、成功；"首次空白"为"尚未设置账期规则"。
class AccountSettingsPage extends ConsumerStatefulWidget {
  const AccountSettingsPage({
    super.key,
    required this.accountId,
    this.initialSection = AccountSettingsSection.rule,
  });

  final String accountId;
  final AccountSettingsSection initialSection;

  static const String title = '信用账户设置';

  @override
  ConsumerState<AccountSettingsPage> createState() =>
      _AccountSettingsPageState();
}

class _AccountSettingsPageState extends ConsumerState<AccountSettingsPage> {
  late AccountSettingsSection _section = widget.initialSection;

  @override
  void didUpdateWidget(covariant AccountSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId ||
        oldWidget.initialSection != widget.initialSection) {
      _section = widget.initialSection;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountId = widget.accountId;
    final wallet = ref.watch(walletProvider);
    final extra = ref.watch(accountSettingsDataProvider(accountId));
    final account = wallet.value?.account(accountId);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          account == null
              ? AccountSettingsPage.title
              : '${account.displayName} · 设置',
        ),
      ),
      body: switch ((wallet, extra)) {
        (AsyncData(), _) when account == null => ErrorBlock(
          title: '已不存在',
          detail: '这个信用账户不在当前空间里（可能已切换空间）。',
          onRetry: () => context.go(AppRoutes.home),
          retryLabel: '回到用卡',
        ),
        (AsyncData(value: final w), AsyncData(value: final data)) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CfSpace.md,
                CfSpace.xs,
                CfSpace.md,
                CfSpace.xs,
              ),
              child: Wrap(
                spacing: CfSpace.xs,
                runSpacing: CfSpace.xs,
                children: <Widget>[
                  for (final section in [
                    AccountSettingsSection.rule,
                    AccountSettingsSection.limits,
                  ])
                    ChoiceChip(
                      label: Text(section.label),
                      selected: _section == section,
                      onSelected: (_) => setState(() => _section = section),
                    ),
                ],
              ),
            ),
            ExpansionTile(
              title: const Text('更多设置'),
              children: [
                Wrap(
                  children: [
                    for (final section in [
                      AccountSettingsSection.currencies,
                      AccountSettingsSection.pool,
                    ])
                      TextButton(
                        onPressed: () => setState(() => _section = section),
                        child: Text(section.label),
                      ),
                  ],
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: switch (_section) {
                AccountSettingsSection.rule => RuleEditorSection(
                  key: ValueKey<String>('rule-${account!.id}'),
                  account: account,
                ),
                AccountSettingsSection.limits => LimitSnapshotSection(
                  key: ValueKey<String>('limits-${account!.id}'),
                  account: account,
                  history: data.snapshots,
                ),
                AccountSettingsSection.currencies => CurrencyAccountsSection(
                  account: account!,
                ),
                AccountSettingsSection.pool => PoolSection(
                  account: account!,
                  pool: w.poolOf(account.id),
                  bankPools: data.bankPools,
                ),
              },
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
    );
  }
}
