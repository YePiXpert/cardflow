import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/cf_layout.dart';
import '../../app/widgets/first_run_empty_state.dart';
import '../../app/widgets/state_views.dart';
import '../../data/repositories/providers.dart';
import 'cash_page.dart';
import 'cash_pressure_card.dart';

/// 现金（简报 U-1 §4；设计稿 `cash-dark.png`）：资金日历的摘要与表格入口，下面是现金账户与收支计划（原 P-08
/// 内容）。语义不变：逐账户计算、账户之间从不相加、没有缺口不用绿色。
class CashHomePage extends ConsumerWidget {
  const CashHomePage({super.key});

  /// 页名，同时是底部导航的标签。
  static const String title = '现金';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(cashPlanProvider);
    return Scaffold(
      appBar: largeTitleAppBar(
        context,
        title: title,
        actions: <Widget>[
          CircleIconButton(
            icon: Icons.add,
            tooltip: '添加',
            onPressed: () => unawaited(_showAddMenu(context)),
          ),
        ],
      ),
      body: switch (plan) {
        AsyncData(:final value) when value.isEmpty => ListView(
          children: <Widget>[
            FirstRunEmptyState(
              icon: Icons.account_balance_wallet_outlined,
              message: CashPage.firstRunMessage,
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
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.only(bottom: CfSpace.xl),
          children: <Widget>[
            const CashPressureCard(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
              child: OutlinedButton(
                onPressed: () => context.go(AppRoutes.cashCalendar),
                child: const Text('资金日历（表格）'),
              ),
            ),
            CashPlanSections(view: value),
          ],
        ),
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

  Future<void> _showAddMenu(BuildContext context) async {
    final target = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final (icon, label, route) in <(IconData, String, String)>[
              (
                Icons.account_balance_outlined,
                '添加现金账户',
                AppRoutes.newCashAccount,
              ),
              (Icons.add_card, '新增收支', AppRoutes.newCashEvent()),
              (Icons.event_repeat, '新增周期事项', AppRoutes.newRecurring),
              (Icons.swap_horiz, '新增调拨', AppRoutes.newTransfer),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                onTap: () => Navigator.of(sheetContext).pop(route),
              ),
          ],
        ),
      ),
    );
    if (target != null && context.mounted) {
      context.go(target);
    }
  }
}
