/// 现金相关页面共用的文案、徽标与金额展示（只做展示，不含业务计算）。
library;

import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate;
import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../app/widgets/money_text.dart';
import '../../app/widgets/state_views.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/cash_models.dart';
import '../cards/card_formatting.dart';

/// 事件的显示名：名称，没有名称时用类别。
String cashEventTitle(CashEventRow row) =>
    row.label ??
    (CashPlanType.ofEvent(row)?.label ?? CashCategory.of(row.category).label);

/// 事件的一行说明：日期（与今天同年写 MM-DD）、时刻、层级、发生状态。
String cashEventSubtitle(CashEventRow row, LocalDate today) {
  final on = LocalDate.parse(row.eventOn);
  final time = row.eventAt == null ? '' : ' ${row.eventAt!.substring(11, 16)}';
  final parts = <String>[
    '${formatShortDate(on, today)}$time',
    CashEventClass.of(row.cls).label,
    PostingStatus.of(row.postingStatus).label,
    if (row.recurringItemId != null) '周期事项',
    if (row.transferGroupId != null) '调拨',
  ];
  return parts.join(' · ');
}

/// "收入 ¥8,500.00" / "支出 ¥1,000.00"：方向用文字表达，金额用绝对值（支出不是缺口，不着危险色）。
class CashFlowAmount extends StatelessWidget {
  const CashFlowAmount({
    super.key,
    required this.amountMinor,
    required this.currency,
    this.textAlign = TextAlign.end,
  });

  final int amountMinor;
  final String currency;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final direction = amountMinor < 0 ? '支出' : '收入';
    return MoneyText(
      minor: amountMinor.abs(),
      currency: currency,
      semanticsPrefix: direction,
      textAlign: textAlign,
    );
  }
}

/// 一行"方向词 + 金额"（列表右侧）。
class CashFlowLabel extends StatelessWidget {
  const CashFlowLabel({
    super.key,
    required this.amountMinor,
    required this.currency,
  });

  final int amountMinor;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: CfSpace.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.end,
      children: <Widget>[
        ExcludeSemantics(child: Text(amountMinor < 0 ? '支出' : '收入')),
        CashFlowAmount(amountMinor: amountMinor, currency: currency),
      ],
    );
  }
}

/// 余额（负数 = 透支，用语义词）。
class BalanceText extends StatelessWidget {
  const BalanceText({
    super.key,
    required this.minor,
    required this.currency,
    this.negativeLabel = '透支',
    this.semanticsPrefix,
    this.style,
    this.textAlign = TextAlign.end,
  });

  final int? minor;
  final String currency;
  final String negativeLabel;
  final String? semanticsPrefix;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) => MoneyText(
    minor: minor,
    currency: currency,
    negativeLabel: negativeLabel,
    semanticsPrefix: semanticsPrefix,
    style: style,
    textAlign: textAlign,
  );
}

/// 层级徽标：确定 / 预计 / 计划（不用绿色）。
class CashClassBadge extends StatelessWidget {
  const CashClassBadge(this.cls, {super.key});

  final CashEventClass cls;

  @override
  Widget build(BuildContext context) => StatusBadge(
    label: cls.label,
    icon: switch (cls) {
      CashEventClass.confirmed => Icons.task_alt,
      CashEventClass.expected => Icons.schedule,
      CashEventClass.planned => Icons.event_note_outlined,
    },
    tone: cls == CashEventClass.confirmed
        ? NoticeTone.neutral
        : NoticeTone.unknown,
  );
}

/// "{n} 天前"的陈旧徽标（时钟图标 + 文字，ui-spec §2"余额陈旧"）。
class StaleBadge extends StatelessWidget {
  const StaleBadge({super.key, required this.ageDays});

  final int ageDays;

  @override
  Widget build(BuildContext context) => StatusBadge(
    label: ageText(ageDays),
    icon: Icons.access_time,
    tone: NoticeTone.attention,
  );
}

/// "假设分析"徽标（R-CASH-09：快照陈旧时结果全程带它）。
class AssumptionBadge extends StatelessWidget {
  const AssumptionBadge({super.key});

  static const String label = '假设分析';

  @override
  Widget build(BuildContext context) => const StatusBadge(
    label: label,
    icon: Icons.fact_check_outlined,
    tone: NoticeTone.attention,
  );
}

/// 可用性的徽标（可用于还款 / {日期}起可用 / 不计入可用现金）。
class AvailabilityBadge extends StatelessWidget {
  const AvailabilityBadge(this.availability, {super.key});

  final CashAvailability availability;

  @override
  Widget build(BuildContext context) => StatusBadge(
    label: availability.label,
    icon: availability.counted
        ? Icons.account_balance_wallet_outlined
        : Icons.lock_outline,
    tone: availability.counted ? NoticeTone.neutral : NoticeTone.unknown,
  );
}
