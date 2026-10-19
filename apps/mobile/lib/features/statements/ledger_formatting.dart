/// 账单、交易、分期与还款页面共用的文案、徽标与小组件（只做展示，不含业务计算）。
///
/// 文案约束（ui-spec §2、§4.5）：确认层级只写"系统估计/你已确认/银行确认"；任何地方都不出现"还款成功"，
/// 也不用绿色勾（绿色只属于 FEASIBLE_ROBUST）；银行确认用 confirm.bank 色与印章图标。
library;

import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate, Timestamp;
import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../app/widgets/money_text.dart';
import '../../app/widgets/state_views.dart';
import '../../data/db/app_database.dart';
import '../../data/mapping/ledger_mapping.dart';
import '../../data/repositories/ledger_models.dart';
import '../../data/repositories/ledger_reader.dart';
import '../cards/card_formatting.dart';

/// 账单状态徽标。
StatusBadge statementStatusBadge(StatementStatus status) => StatusBadge(
  label: status.label,
  icon: switch (status) {
    StatementStatus.predicted => Icons.calculate_outlined,
    StatementStatus.issued => Icons.receipt_long_outlined,
    StatementStatus.amended => Icons.edit_note,
    StatementStatus.partiallySettled ||
    StatementStatus.settled => Icons.approval_outlined,
    StatementStatus.overdue => Icons.warning_amber_outlined,
  },
  tone: switch (status) {
    StatementStatus.partiallySettled ||
    StatementStatus.settled => NoticeTone.bank,
    StatementStatus.overdue => NoticeTone.danger,
    _ => NoticeTone.unknown,
  },
);

/// 还款状态徽标（"已登记（待银行确认）"等；没有"成功"）。
StatusBadge repaymentStatusBadge(RepaymentStatus status) => StatusBadge(
  label: status.label,
  icon: switch (status) {
    RepaymentStatus.recorded => Icons.edit_calendar_outlined,
    RepaymentStatus.processing => Icons.hourglass_top,
    RepaymentStatus.cashDebited => Icons.account_balance_wallet_outlined,
    RepaymentStatus.creditPosted => Icons.input,
    RepaymentStatus.bankConfirmed => Icons.approval_outlined,
    RepaymentStatus.failed => Icons.error_outline,
    RepaymentStatus.userMarkedPaid => Icons.how_to_reg_outlined,
    RepaymentStatus.needsReview => Icons.help_outline,
    RepaymentStatus.reversed => Icons.undo,
  },
  tone: switch (status) {
    RepaymentStatus.bankConfirmed => NoticeTone.bank,
    RepaymentStatus.failed || RepaymentStatus.reversed => NoticeTone.danger,
    RepaymentStatus.recorded ||
    RepaymentStatus.userMarkedPaid ||
    RepaymentStatus.needsReview => NoticeTone.attention,
    _ => NoticeTone.unknown,
  },
);

/// 确认层级徽标（ui-spec §4.3）。
StatusBadge confirmationBadge(ConfirmationShown level) => StatusBadge(
  label: level.label,
  icon: switch (level) {
    ConfirmationShown.systemEstimated => Icons.calculate_outlined,
    ConfirmationShown.userConfirmed => Icons.how_to_reg_outlined,
    ConfirmationShown.bankConfirmed => Icons.approval_outlined,
  },
  tone: level == ConfirmationShown.bankConfirmed
      ? NoticeTone.bank
      : NoticeTone.unknown,
);

/// 差异项状态徽标。
StatusBadge reconciliationBadge(ReconciliationStatus status) => StatusBadge(
  label: status.label,
  icon: switch (status) {
    ReconciliationStatus.open => Icons.rule,
    ReconciliationStatus.resolved => Icons.archive_outlined,
    ReconciliationStatus.dismissed => Icons.do_not_disturb_on_outlined,
  },
  tone: status == ReconciliationStatus.open
      ? NoticeTone.attention
      : NoticeTone.unknown,
);

/// 交易的账期归属文字（F-15：入账不确定时"可能账期"）。
String cycleText(TxnCycle cycle, LocalDate today) => switch (cycle) {
  TxnCycleKnown(:final cycle) =>
    '账单 ${formatShortDate(cycle.statementDate, today)} · 到期 ${formatShortDate(cycle.dueDate, today)}'
        '${cycle.ruleId.startsWith('issued:') ? '' : '（系统估计）'}',
  TxnCyclePossible(:final cycles) =>
    '可能账期：${cycles.map((c) => '${formatShortDate(c.statementDate, today)} 出账').join(' 或 ')}'
        '（入账日未知，保守按最早到期 ${formatShortDate(cycles.first.dueDate, today)}）',
  TxnCycleNoRule() => '账期规则未设置',
  TxnCycleInvalid() => '规则非法，无法计算账期',
};

/// RFC 3339 → `YYYY-MM-DD HH:MM`（存库时已是所属业务时区的偏移）。
String timestampText(String text) {
  final t = Timestamp.parse(text);
  return '${t.date} ${text.substring(11, 16)}';
}

/// 账单的标题："卡 A · 2026-10-10 账单"。
String statementTitle(LedgerData data, StatementRow s) =>
    '${data.accountName(s.currencyAccountId)} · ${s.statementDate} 账单';

/// 一行"标签：金额"，金额来源未含此项时显示"来源未含此项"（不当 0，ui-spec P-05 数据不全）。
class LedgerAmountRow extends StatelessWidget {
  const LedgerAmountRow({
    super.key,
    required this.label,
    required this.minor,
    required this.currency,
    this.source,
    this.negativeLabel,
  });

  final String label;
  final int? minor;
  final String currency;

  /// 来源与版本（如"手工录入 · v1"）；为空时不显示。
  final String? source;
  final String? negativeLabel;

  /// 来源未含此项。
  static const String missingText = '来源未含此项';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CfSpace.md,
        vertical: CfSpace.xxs,
      ),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: CfSpace.sm,
              children: <Widget>[
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                if (minor == null)
                  Text(missingText, style: theme.textTheme.bodyMedium)
                else
                  MoneyText(
                    minor: minor,
                    currency: currency,
                    semanticsPrefix: label,
                    negativeLabel: negativeLabel ?? '负数',
                    negativeTone: MoneyTone.neutral,
                    style: theme.textTheme.bodyLarge,
                  ),
              ],
            ),
            if (source != null)
              Text(
                source!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 负债四分法（R-STMT-02、F-30）：总负债、本期应还、未出账、未来分期本金分列，不重复相加。
class LiabilitySection extends StatelessWidget {
  const LiabilitySection({
    super.key,
    required this.currency,
    required this.total,
    required this.currentDue,
    required this.unbilled,
    required this.futurePrincipal,
    required this.creditBalance,
    this.pendingRefunds = 0,
  });

  factory LiabilitySection.of(LiabilityBreakdown l) => LiabilitySection(
    currency: l.currency,
    total: l.total,
    currentDue: l.currentDue,
    unbilled: l.unbilled,
    futurePrincipal: l.futureInstallmentPrincipal,
    creditBalance: l.creditBalance,
    pendingRefunds: l.pendingRefunds,
  );

  factory LiabilitySection.totals(LiabilityTotals t) => LiabilitySection(
    currency: t.currency,
    total: t.total,
    currentDue: t.currentDue,
    unbilled: t.unbilled,
    futurePrincipal: t.futureInstallmentPrincipal,
    creditBalance: t.creditBalance,
  );

  final String currency;
  final int total;
  final int currentDue;
  final int unbilled;
  final int futurePrincipal;
  final int creditBalance;
  final int pendingRefunds;

  /// 口径说明。
  static const String basisNote =
      '总负债 = 已出账未还 + 未出账 + 未来分期本金（不含未计提的分期手续费）；四项分列、不重复相加。'
      '口径：只扣减银行已入账的还款，"我已还款"不扣减。';

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: CardFlowColors.of(context).textSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LedgerAmountRow(
          label: '总负债',
          minor: total,
          currency: currency,
          negativeLabel: '贷方',
        ),
        LedgerAmountRow(label: '本期应还', minor: currentDue, currency: currency),
        LedgerAmountRow(label: '未出账', minor: unbilled, currency: currency),
        LedgerAmountRow(
          label: '未来分期本金',
          minor: futurePrincipal,
          currency: currency,
        ),
        if (creditBalance > 0)
          LedgerAmountRow(
            label: '贷方余额（溢缴款）',
            minor: creditBalance,
            currency: currency,
          ),
        if (pendingRefunds > 0)
          LedgerAmountRow(
            label: '退款待核对（未计入）',
            minor: pendingRefunds,
            currency: currency,
          ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CfSpace.md,
            vertical: CfSpace.xxs,
          ),
          child: Text(basisNote, style: secondary),
        ),
      ],
    );
  }
}
