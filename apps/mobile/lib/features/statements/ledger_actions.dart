/// 交易与分期的撤销入口（审查 R-16、Q-3）：交易「删除」（已转分期的先提示作废分期）与「补入账日」，分期
/// 「作废（录错了）」。都调用已有的仓库方法（校验与测试都在仓库里）；删除、作废之后引用它们的未处理差异项由
/// 仓库交给系统处理（R-07）。
library;

import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate, Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../app/widgets/confirm_dialog.dart';
import '../../app/widgets/feedback.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/ledger_models.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/repository_errors.dart';
import '../../data/time/business_tz.dart';
import '../cards/card_dialogs.dart';

/// 交易未作废的分期计划（没有时为 null）。
InstallmentPlanRow? livePlanOf(
  Iterable<InstallmentPlanRow> plans,
  String transactionId,
) {
  for (final p in plans) {
    if (p.transactionId == transactionId &&
        InstallmentPlanStatus.of(p.status).coversPrincipal) {
      return p;
    }
  }
  return null;
}

/// 分期计划能否作废（录错了）：进行中、各期都还没出账（仓库同样校验）。
bool canCancelPlan(
  InstallmentPlanRow plan,
  List<InstallmentScheduleRow> periods,
) =>
    plan.status == InstallmentPlanStatus.active.code &&
    periods.every((p) => p.status == InstallmentPeriodStatus.scheduled.code);

Future<void> _run(
  ScaffoldMessengerState messenger,
  Future<void> Function() action,
  String success,
) async {
  try {
    await action();
    showFeedback(messenger, success);
  } on RepositoryException catch (error) {
    showFeedback(messenger, error.message);
  }
}

/// 「删除」一笔交易：已转分期（计划未作废）的先提示作废分期——确认后先作废计划、再删除交易；没有分期的
/// 直接确认删除。
Future<void> deleteTransaction(
  BuildContext context,
  WidgetRef ref, {
  required CardTransactionRow txn,
  required InstallmentPlanRow? plan,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await confirmAction(
    context,
    title: plan == null ? '删除这笔交易？' : '这笔已转分期：先作废分期再删除？',
    message: plan == null
        ? '影响：这 1 笔交易从负债与账单里去掉，不可撤销；引用它的未处理差异项由系统标为已处理。'
        : '影响：先作废它的分期计划（各期一并作废，只有还没出账的分期可以作废），再删除这 1 笔交易，'
              '都不可撤销；引用它的未处理差异项由系统标为已处理。',
    confirmLabel: plan == null ? '删除' : '作废分期并删除',
    destructive: true,
  );
  if (!confirmed) {
    return;
  }
  await _run(messenger, () async {
    if (plan != null) {
      final installments = await ref.read(installmentRepositoryProvider.future);
      await installments.cancel(plan.id);
    }
    final transactions = await ref.read(transactionRepositoryProvider.future);
    await transactions.delete(txn.id);
  }, plan == null ? '已删除这笔交易' : '已作废分期并删除这笔交易');
}

/// 「补入账日」：入账日不早于交易日（账户业务时区）、不晚于今天。
Future<void> fillPostedOn(
  BuildContext context,
  WidgetRef ref, {
  required CardTransactionRow txn,
  required LocalDate today,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final first = businessDateOf(
    Timestamp.parse(txn.txnAt),
    businessTimeZoneOf(txn.txnTz),
  );
  final picked = await showDialog<LocalDate>(
    context: context,
    builder: (_) => _PostedOnDialog(first: first, last: today),
  );
  if (picked == null) {
    return;
  }
  await _run(messenger, () async {
    final transactions = await ref.read(transactionRepositoryProvider.future);
    await transactions.markPosted(txn.id, picked);
  }, '已补入账日（你已确认）');
}

/// 分期「作废（录错了）」：只有各期都还没出账的计划可以作废；原消费重新计入未出账。
Future<void> cancelPlan(
  BuildContext context,
  WidgetRef ref, {
  required InstallmentPlanRow plan,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await confirmAction(
    context,
    title: '作废这个分期计划？',
    message: '用于录错了的分期：${plan.periods} 期一并作废，原消费重新按一笔消费计入未出账，不可撤销。',
    confirmLabel: '作废',
    destructive: true,
  );
  if (!confirmed) {
    return;
  }
  await _run(messenger, () async {
    final installments = await ref.read(installmentRepositoryProvider.future);
    await installments.cancel(plan.id);
  }, '已作废分期计划');
}

class _PostedOnDialog extends StatefulWidget {
  const _PostedOnDialog({required this.first, required this.last});

  final LocalDate first;
  final LocalDate last;

  @override
  State<_PostedOnDialog> createState() => _PostedOnDialogState();
}

class _PostedOnDialogState extends State<_PostedOnDialog> {
  late LocalDate _date = widget.first > widget.last
      ? widget.last
      : widget.first;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('补入账日'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text('按银行账单或 App 里的入账日填写：账期按它重新归属。'),
          const SizedBox(height: CfSpace.sm),
          DateField(
            label: '入账日（不早于交易日、不晚于今天）',
            value: _date,
            first: widget.first,
            last: widget.last,
            onChanged: (v) => setState(() => _date = v),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_date),
        child: const Text('保存'),
      ),
    ],
  );
}
