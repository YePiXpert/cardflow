/// 卡账行与卡片详情上的还款快捷操作（简报 U-1 §3"还清本期"之后）：一步推进"银行已入账""银行确认"。
///
/// 状态机与文案规则不变（PRD §6.3；不出现"还款成功"）：已登记/处理中 → 现金已扣 → 银行已入账 用已有的
/// `confirmDebit` + `markCreditPosted`（扣款与入账时点都记为现在）；银行已入账/用户已标记/待核对 → 银行确认
/// 用 `confirmByBank`（从用户已标记来时扣款时点也记为现在）。都经仓库（同样的校验与差异项检查）。
library;

import 'package:cardflow_domain/cardflow_domain.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/widgets/confirm_dialog.dart';
import '../../app/widgets/feedback.dart';
import '../../data/mapping/cash_mapping.dart' show cashTimeZone;
import '../../data/repositories/ledger_home.dart';
import '../../data/repositories/ledger_models.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/repository_errors.dart';
import '../../data/time/clock.dart';

/// 推进后的轻提示（带确认层级，不写"成功"）。
const Map<PendingStep, String> advancedMessages = <PendingStep, String>{
  PendingStep.creditPosted: '已记为银行已入账（待银行确认）',
  PendingStep.bankConfirmed: '已记为银行确认',
};

/// 一步推进 [pending]：先确认，再按状态机调用仓库。返回是否推进了。
Future<bool> advancePendingRepayment(
  BuildContext context,
  WidgetRef ref,
  PendingRepayment pending,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final step = pending.next;
  final confirmed = await confirmAction(
    context,
    title: step == PendingStep.creditPosted ? '银行已入账？' : '银行确认？',
    message: step == PendingStep.creditPosted
        ? '在银行 App 或账单里已经能看到这笔还款入账时再记。扣款与入账时间记为现在；剩余应还按入账日核销，'
              '额度以新的额度快照为准。之后还可以在核对一致时记"银行确认"。'
        : '账单或流水与这笔还款核对一致时再记。之后这期按银行确认的还款判断是否已还清。',
    confirmLabel: step.label,
  );
  if (!confirmed) {
    return false;
  }
  try {
    final repo = await ref.read(repaymentRepositoryProvider.future);
    final now = Timestamp.parse(ref.read(clockProvider).nowText(cashTimeZone));
    final id = pending.repayment.id;
    switch (step) {
      case PendingStep.creditPosted:
        if (pending.status == RepaymentStatus.recorded ||
            pending.status == RepaymentStatus.processing) {
          await repo.confirmDebit(id, now);
        }
        await repo.markCreditPosted(id, now);
      case PendingStep.bankConfirmed:
        final fromMarked =
            pending.status == RepaymentStatus.userMarkedPaid ||
            pending.status == RepaymentStatus.needsReview;
        await repo.confirmByBank(id, now, debitedAt: fromMarked ? now : null);
    }
    showFeedback(messenger, advancedMessages[step]!);
    return true;
  } on RepositoryException catch (error) {
    showFeedback(messenger, error.message);
    return false;
  }
}
