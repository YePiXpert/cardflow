import 'dart:async';

import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/confirm_dialog.dart';
import '../../app/widgets/feedback.dart';
import '../../app/widgets/first_run_empty_state.dart';
import '../../app/widgets/state_views.dart';
import '../../app/widgets/workspace_badges.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/cash_event_repository.dart';
import '../../data/repositories/cash_models.dart';
import '../../data/repositories/cash_plan_reader.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/repository_errors.dart';
import '../cards/card_formatting.dart';
import '../planner/planner_segments.dart';
import 'cash_formatting.dart';

/// P-08 现金账户与收支计划（ui-spec P-08）：账户列表（最新快照、"{n} 天前"、可用性、储备）、收支计划
/// （确定/预计收入、固定生活支出、其他债务、一次性支出）、周期事项（逐期覆盖/跳过在详情里）、调拨。
///
/// 四态：首次空白"添加还款用现金账户"、加载（骨架）、错误（「重试」）、成功；叠加态：余额陈旧
/// "{n} 天前" +「记录新快照」，没有快照"未计入规划"。
class CashPage extends ConsumerWidget {
  const CashPage({super.key});

  static const String title = '现金与收支';

  /// ui-spec P-08 九态"首次空白"。
  static const String firstRunMessage = '添加还款用现金账户';

  /// 保存成功的轻提示（ui-spec P-08 九态"成功"）。
  static const String savedMessage = '已保存，日历已更新';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(cashPlanProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: switch (plan) {
        AsyncData(:final value) when value.isEmpty => ListView(
          children: <Widget>[
            const PlannerSegmentBar(current: PlannerSegment.cash),
            const RootPageBadges(),
            FirstRunEmptyState(
              icon: Icons.account_balance_wallet_outlined,
              message: firstRunMessage,
              purpose: '维护现金账户、余额快照、可用性、储备与收支计划；资金日历据此逐账户计算。',
              actions: <EmptyStateAction>[
                EmptyStateAction(
                  label: '添加账户',
                  onPressed: () => context.go(AppRoutes.newCashAccount),
                ),
              ],
              scrollable: false,
            ),
          ],
        ),
        AsyncData(:final value) => _CashPlanList(view: value),
        AsyncError(:final error) => ErrorBlock(
          title: '现金与收支读取失败',
          code: '${error.runtimeType}',
          detail: '本机数据没有改动。',
          onRetry: () => ref.invalidate(cashPlanProvider),
        ),
        _ => const LoadingSkeleton(),
      },
    );
  }
}

class _CashPlanList extends ConsumerWidget {
  const _CashPlanList({required this.view});

  final CashPlanView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: colors.textSecondary,
    );
    final active = view.accounts.where((a) => a.active).toList();
    final closed = view.accounts.where((a) => !a.active).toList();
    final byType = <CashPlanType?, List<CashEventRow>>{};
    for (final e in view.plan) {
      byType
          .putIfAbsent(CashPlanType.ofEvent(e), () => <CashEventRow>[])
          .add(e);
    }
    String currencyOf(String accountId) =>
        view.account(accountId)?.row.currency ?? 'CNY';
    String nameOf(String accountId) => view.account(accountId)?.row.name ?? '';
    return ListView(
      padding: const EdgeInsets.only(bottom: CfSpace.xl),
      children: <Widget>[
        const PlannerSegmentBar(current: PlannerSegment.cash),
        const RootPageBadges(),
        SectionTitle(
          '现金账户',
          trailing: TextButton(
            onPressed: () => context.go(AppRoutes.newCashAccount),
            child: const Text('添加账户'),
          ),
        ),
        for (final account in active)
          _AccountTile(summary: account, today: view.today),
        if (closed.isNotEmpty)
          ExpansionTile(
            title: Text('已停用（${closed.length}）'),
            subtitle: const Text('不进入资金日历，历史保留'),
            children: <Widget>[
              for (final account in closed)
                _AccountTile(summary: account, today: view.today),
            ],
          ),
        SectionTitle(
          '收支计划',
          trailing: TextButton(
            onPressed: active.isEmpty
                ? null
                : () => context.go(AppRoutes.newCashEvent()),
            child: const Text('新增收支'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
          child: Text('每笔收支须选层级（确定/预计），不设概率；已确认口径只算确定的。', style: secondary),
        ),
        if (view.plan.isEmpty)
          Padding(
            padding: const EdgeInsets.all(CfSpace.md),
            child: Text('还没有收支计划。', style: secondary),
          ),
        for (final type in <CashPlanType?>[...CashPlanType.values, null])
          if (byType[type] case final rows?) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CfSpace.md,
                CfSpace.sm,
                CfSpace.md,
                0,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  type?.label ?? '其他',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ),
            for (final row in rows)
              _EventTile(
                row: row,
                today: view.today,
                currency: currencyOf(row.cashAccountId),
                accountName: nameOf(row.cashAccountId),
              ),
          ],
        SectionTitle(
          '周期事项',
          trailing: TextButton(
            onPressed: active.isEmpty
                ? null
                : () => context.go(AppRoutes.newRecurring),
            child: const Text('新增周期事项'),
          ),
        ),
        if (view.recurring.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: Text('还没有周期事项。每期可单独覆盖或跳过，不影响其他各期。', style: secondary),
          ),
        for (final item in view.recurring)
          _RecurringTile(
            item: item,
            today: view.today,
            currency: currencyOf(item.row.cashAccountId),
            accountName: nameOf(item.row.cashAccountId),
          ),
        SectionTitle(
          '调拨',
          trailing: TextButton(
            onPressed: active.length < 2
                ? null
                : () => context.go(AppRoutes.newTransfer),
            child: const Text('新增调拨'),
          ),
        ),
        if (view.transfers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: Text(
              active.length < 2 ? '有两个以上的现金账户时才能登记调拨（转出与到账两端）。' : '还没有调拨。',
              style: secondary,
            ),
          ),
        for (final transfer in view.transfers)
          _TransferTile(
            transfer: transfer,
            today: view.today,
            currency: currencyOf(transfer.out.cashAccountId),
            fromName: nameOf(transfer.out.cashAccountId),
            toName: nameOf(transfer.into.cashAccountId),
          ),
      ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.summary, required this.today});

  final CashAccountSummary summary;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final row = summary.row;
    final snapshot = summary.latestSnapshot;
    return ListTile(
      onTap: () => context.go(AppRoutes.cashAccount(row.id)),
      title: Text(row.name),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: CfSpace.xxs),
        child: Wrap(
          spacing: CfSpace.xs,
          runSpacing: CfSpace.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(summary.kind.label),
            AvailabilityBadge(summary.availability),
            if (summary.stale) StaleBadge(ageDays: summary.ageDays!),
            if (summary.missingSnapshot)
              const StatusBadge(
                label: '未计入规划（缺快照）',
                icon: Icons.checklist,
                tone: NoticeTone.attention,
              ),
            if (row.reserveFloorMinor > 0)
              Wrap(
                spacing: CfSpace.xxs,
                children: <Widget>[
                  const Text('储备'),
                  BalanceText(
                    minor: row.reserveFloorMinor,
                    currency: row.currency,
                    semanticsPrefix: '储备',
                    textAlign: TextAlign.start,
                  ),
                ],
              ),
            if (snapshot != null && !summary.stale)
              Text('快照 ${ageText(summary.ageDays!)}'),
            if (summary.active && (summary.stale || summary.missingSnapshot))
              TextButton(
                onPressed: () =>
                    context.go(AppRoutes.recordCashSnapshot(row.id)),
                child: const Text('记录新快照'),
              ),
          ],
        ),
      ),
      trailing: snapshot == null
          ? const Text('—')
          : BalanceText(
              minor: snapshot.balanceMinor,
              currency: row.currency,
              semanticsPrefix: '余额',
            ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.row,
    required this.today,
    required this.currency,
    required this.accountName,
  });

  final CashEventRow row;
  final LocalDate today;
  final String currency;
  final String accountName;

  @override
  Widget build(BuildContext context) {
    // 调拨、周期事项的单期、还款或计划生成的（层级"计划"）不在这里改。
    final editable =
        row.transferGroupId == null &&
        row.recurringItemId == null &&
        row.linkedRepaymentId == null &&
        row.linkedPlanRunId == null &&
        row.cls != CashEventClass.planned.code;
    return ListTile(
      onTap: editable ? () => context.go(AppRoutes.cashEvent(row.id)) : null,
      title: Text(cashEventTitle(row)),
      subtitle: Text('${cashEventSubtitle(row, today)} · $accountName'),
      trailing: CashFlowLabel(amountMinor: row.amountMinor, currency: currency),
    );
  }
}

class _RecurringTile extends StatelessWidget {
  const _RecurringTile({
    required this.item,
    required this.today,
    required this.currency,
    required this.accountName,
  });

  final RecurringItemSummary item;
  final LocalDate today;
  final String currency;
  final String accountName;

  @override
  Widget build(BuildContext context) {
    final row = item.row;
    final next = item.next;
    final parts = <String>[
      RecurringFrequency.of(row.frequency).label,
      CashEventClass.of(row.cls).label,
      if (!row.active) '已停用',
      if (next != null) '下一期 ${next.eventOn}',
      if (item.exceptions > 0) '单期例外 ${item.exceptions} 项',
      accountName,
    ];
    return ListTile(
      onTap: () => context.go(AppRoutes.recurring(row.id)),
      title: Text(row.label),
      subtitle: Text(parts.join(' · ')),
      trailing: CashFlowLabel(amountMinor: row.amountMinor, currency: currency),
    );
  }
}

class _TransferTile extends ConsumerWidget {
  const _TransferTile({
    required this.transfer,
    required this.today,
    required this.currency,
    required this.fromName,
    required this.toName,
  });

  final TransferView transfer;
  final LocalDate today;
  final String currency;
  final String fromName;
  final String toName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final out = transfer.out;
    return ListTile(
      title: Text('$fromName → $toName'),
      subtitle: Text(
        '转出 ${out.eventOn} · 到账 ${transfer.into.eventOn} · '
        '${CashEventClass.of(out.cls).label}'
        '${out.label == null ? '' : ' · ${out.label}'}',
      ),
      trailing: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          CashFlowAmount(amountMinor: -out.amountMinor, currency: currency),
          IconButton(
            tooltip: '删除调拨',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => unawaited(_delete(context, ref)),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await confirmAction(
      context,
      title: '删除这笔调拨？',
      message: '影响：转出与到账 2 条记录一起删除，资金日历随之更新。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed) {
      return;
    }
    try {
      final repo = await ref.read(cashEventRepositoryProvider.future);
      await repo.delete(transfer.out.id);
      showFeedback(messenger, CashPage.savedMessage);
    } on RepositoryException catch (error) {
      showFeedback(messenger, error.message);
    }
  }
}
