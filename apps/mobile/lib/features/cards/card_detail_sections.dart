/// 卡片详情（简报 U-1 §3；设计稿 `card-dark.png`）的各块：卡面、本期进度、金额区、主按钮、账单历史、分期摘要。
/// 只做展示，数据来自读模型（[CardLedgerRow]、[LedgerData]），不在这里计算口径。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/bank_badge.dart';
import '../../app/widgets/cf_layout.dart';
import '../../app/widgets/money_text.dart';
import '../../app/widgets/state_views.dart';
import '../../data/db/app_database.dart';
import '../../data/mapping/domain_mapping.dart';
import '../../data/mapping/ledger_mapping.dart' show LiabilityBreakdown;
import '../../data/repositories/card_wallet_reader.dart';
import '../../data/repositories/ledger_home.dart';
import '../../data/repositories/ledger_models.dart';
import '../../data/repositories/ledger_reader.dart';
import '../../data/repositories/models.dart';
import '../home/ledger_home_page.dart'
    show PendingRepaymentStrip, rowStatusBadge;
import '../home/quick_pay_sheet.dart';
import '../home/quick_statement_sheet.dart';
import '../statements/ledger_formatting.dart';
import 'card_formatting.dart';

/// 文字放大到这个倍数起，横排的块改为竖排。
const double _stackedScale = 1.6;

bool _stacked(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1) >= _stackedScale;

/// 卡面（设计稿 .face）：银行色渐变、银行名、产品与主/附卡、"···· 末四位"、额度条（已用/总额度）、"额度 ¥x · 可用 ¥y"。
/// 银行色白字对比度 ≥ 4.5（见 `CfBankColors`）；芯片是装饰。
class CardFace extends StatelessWidget {
  const CardFace({super.key, required this.row});

  final CardLedgerRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = bankColor(row.bankName);
    const white = CfBankColors.mark;
    final snapshot = row.sub.latestSnapshot;
    final limit = row.currentLimit;
    final used = snapshot?.usedMinor;
    final ratio = limit == null || limit <= 0 || used == null
        ? null
        : math.min(1.0, math.max(0.0, used / limit));
    final main = _mainCard(row.account);
    final subtitle = <String>[
      ?row.productName,
      if (main != null) main.kind.label,
      if (row.currency != 'CNY') row.currency,
    ].join(' · ');
    final small = theme.textTheme.bodySmall?.copyWith(color: white);
    return Container(
      padding: const EdgeInsets.all(CfSpace.md + CfSpace.xxs / 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CfRadius.card),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            base,
            Color.lerp(base, CfBankColors.faceShade, 0.35)!,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            row.bankName,
            style: theme.textTheme.headlineSmall?.copyWith(color: white),
          ),
          if (subtitle.isNotEmpty) Text(subtitle, style: small),
          const SizedBox(height: CfSpace.md),
          ExcludeSemantics(
            child: Container(
              width: CfSpace.xl + CfSpace.sm,
              height: CfSpace.xl,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(CfRadius.md),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: CfBankColors.chip,
                ),
              ),
            ),
          ),
          const SizedBox(height: CfSpace.md),
          Semantics(
            label: row.last4 == null ? '没有未停用的卡' : '尾号 ${row.last4}',
            excludeSemantics: true,
            child: Text(
              row.last4 == null ? '····' : '····  ····  ····  ${row.last4}',
              style: CfType.amountTile.toTextStyle().copyWith(
                color: white,
                letterSpacing: CfSpace.xxs,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: CfSpace.sm),
          if (ratio != null)
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(CfStroke.bar),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: CfStroke.bar,
                  color: white,
                  backgroundColor: white.withValues(alpha: 0.25),
                ),
              ),
            ),
          const SizedBox(height: CfSpace.xs),
          if (snapshot == null)
            Text('额度未记录（点「更新额度」记录）', style: small)
          else
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: CfSpace.sm,
                children: <Widget>[
                  _faceMoney('额度', limit, small),
                  _faceMoney('可用', row.sub.availableToday, small),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _faceMoney(String label, int? minor, TextStyle? style) => Wrap(
    spacing: CfSpace.xxs,
    children: <Widget>[
      ExcludeSemantics(child: Text(label, style: style)),
      MoneyText(
        minor: minor,
        currency: row.currency,
        compact: true,
        negativeLabel: '超限',
        negativeTone: MoneyTone.neutral,
        semanticsPrefix: label,
        textAlign: TextAlign.start,
        style: style,
      ),
    ],
  );
}

/// 账户的主卡（未停用的主卡，没有时第一张未停用的卡）。
CardRow? _mainCard(AccountView account) {
  final active = account.activeCards;
  for (final c in active) {
    if (c.kind == HolderKind.primary) {
      return c;
    }
  }
  return active.isEmpty ? null : active.first;
}

/// 本期进度（设计稿 .cycle）：出账日 → 今天 → 还款日的进度条，"还剩 N 天还款"/"今天还款"/"已逾期 N 天"；没有
/// 已出账单（或已结清）时写"下期 MM-DD 出账 · MM-DD 还款"（预测）；账单出了还没录入时提示并给「记本期账单」。
class CycleCard extends StatelessWidget {
  const CycleCard({super.key, required this.row});

  final CardLedgerRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final current = row.current;
    final today = row.today;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: colors.textSecondary,
    );
    final children = <Widget>[];
    if (current != null && current.status.owes) {
      final total = math.max(
        1,
        current.dueDate.differenceInDays(current.statementDate),
      );
      final elapsed = today.differenceInDays(current.statementDate);
      final fraction = math.min(1.0, math.max(0.0, elapsed / total));
      final due = row.due!;
      final (String head, Color tone) = switch (due.tone) {
        DueTone.today => ('今天还款', colors.attention.fg),
        DueTone.overdue => ('已逾期 ${due.overdueDays} 天', colors.danger.fg),
        _ => ('还剩 ${due.days} 天还款', colors.textPrimary),
      };
      children.addAll(<Widget>[
        _header(context, '本期账单', head, tone),
        const SizedBox(height: CfSpace.sm),
        _Track(
          fraction: fraction,
          color: due.tone == DueTone.overdue ? colors.danger.fg : colors.action,
        ),
        const SizedBox(height: CfSpace.xs),
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: CfSpace.sm,
            children: <Widget>[
              Text(
                '${formatShortDate(current.statementDate, today)} 出账',
                style: theme.textTheme.bodySmall,
              ),
              Text('今天 ${formatShortDate(today, today)}', style: small),
              Text(
                '${formatShortDate(current.dueDate, today)} 还款',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ]);
    } else {
      final missed = row.missedStatement;
      final forecast = row.forecast;
      if (missed != null) {
        children.addAll(<Widget>[
          _header(
            context,
            '本期账单',
            '${formatShortDate(missed.statementDate, today)} 账单未录入',
            colors.attention.fg,
          ),
          const SizedBox(height: CfSpace.xxs),
          Text(
            '预计 ${formatShortDate(missed.dueDate, today)} 还款；录入账单后按账单的金额与到期日计算。',
            style: small,
          ),
        ]);
      } else if (current != null) {
        children.add(
          _header(context, '本期账单', effectiveStatusText(current), null),
        );
      } else {
        children.add(_header(context, '本期账单', '还没有已出账单', null));
      }
      if (forecast is ForecastPredicted && missed == null) {
        final c = forecast.conservative;
        children.addAll(<Widget>[
          const SizedBox(height: CfSpace.xxs),
          Text(
            '下期 ${formatShortDate(c.statementDate, today)} 出账 · '
            '${formatShortDate(c.dueDate, today)} 还款（预测）',
            style: theme.textTheme.bodyMedium,
          ),
        ]);
      } else if (forecast is ForecastNoRule) {
        children.add(Text('账期规则未设置：设置后才能算出账日与还款日。', style: small));
      } else if (forecast is ForecastInvalid) {
        children.add(Text('规则非法，无法计算账期', style: small));
      }
    }
    final needsStatement = current == null || row.missedStatement != null;
    final ruleMissing = row.needsRule || row.ruleInvalid;
    return Container(
      padding: const EdgeInsets.all(CfSpace.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(CfRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ...children,
          if (ruleMissing || needsStatement) ...<Widget>[
            const SizedBox(height: CfSpace.xs),
            Wrap(
              spacing: CfSpace.xs,
              runSpacing: CfSpace.xs,
              children: <Widget>[
                if (ruleMissing)
                  OutlinedButton(
                    onPressed: () => context.go(
                      AppRoutes.accountSettings(
                        row.creditAccountId,
                        section: 'rule',
                      ),
                    ),
                    child: Text(row.ruleInvalid ? '修改账期规则' : '设置账期'),
                  ),
                if (needsStatement)
                  OutlinedButton(
                    onPressed: () => unawaited(
                      showQuickStatementSheet(
                        context,
                        account: row.account,
                        sub: row.sub,
                      ),
                    ),
                    child: const Text(QuickStatementSheet.title),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _header(
    BuildContext context,
    String left,
    String right,
    Color? rightColor,
  ) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: CfSpace.sm,
      runSpacing: CfSpace.xxs,
      children: <Widget>[
        Text(
          left,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.textSecondary,
          ),
        ),
        Text(
          right,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: rightColor ?? colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// 进度条：轨道、已走的部分与今天的圆点。
class _Track extends StatelessWidget {
  const _Track({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = CardFlowColors.of(context);
    const knob = CfSpace.md;
    return ExcludeSemantics(
      child: SizedBox(
        height: knob,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final x = (width - knob) * fraction;
            return Stack(
              alignment: Alignment.centerLeft,
              children: <Widget>[
                Container(
                  height: CfStroke.bar * 1.5,
                  decoration: BoxDecoration(
                    color: colors.divider,
                    borderRadius: BorderRadius.circular(CfStroke.bar),
                  ),
                ),
                Container(
                  width: x + knob / 2,
                  height: CfStroke.bar * 1.5,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(CfStroke.bar),
                  ),
                ),
                Positioned(
                  left: x,
                  child: Container(
                    width: knob,
                    height: knob,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: CfStroke.bar - 1),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 金额区（设计稿 .grid）：待还（大字）与最低还款；本期账单；未出账（N 笔）。还欠着时给「还清本期」，有等银行
/// 证据的还款时给一步推进。
class AmountGrid extends StatelessWidget {
  const AmountGrid({super.key, required this.row, required this.liability});

  final CardLedgerRow row;

  /// 负债四分法（"未出账 · N 笔"的笔数）；没有时为 null。
  final LiabilityBreakdown? liability;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final label = theme.textTheme.bodySmall?.copyWith(
      color: colors.textSecondary,
    );
    final current = row.current;
    final remaining = row.remaining;
    final unbilledCount = liability?.unbilledCount ?? 0;
    final minDue = current?.current.minDueMinor;
    Widget tile(Widget child) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CfSpace.md,
        vertical: CfSpace.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(CfRadius.tile),
      ),
      child: child,
    );
    final mainLeft = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: CfSpace.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text('待还', style: label),
            if (row.status case final status?) rowStatusBadge(status),
          ],
        ),
        MoneyText(
          minor: remaining,
          currency: row.currency,
          compact: true,
          semanticsPrefix: '待还',
          textAlign: TextAlign.start,
          style: CfType.amountDetail.toTextStyle().copyWith(
            color: remaining == null || remaining == 0
                ? colors.textTertiary
                : colors.textPrimary,
          ),
        ),
      ],
    );
    final mainRight = current == null
        ? null
        : KeyValueColumn(
            label: '最低还款',
            crossAxisAlignment: CrossAxisAlignment.end,
            value: minDue == null
                ? Text(LedgerAmountRow.missingText, style: label)
                : MoneyText(
                    minor: minDue,
                    currency: row.currency,
                    compact: true,
                    semanticsPrefix: '最低还款',
                    style: theme.textTheme.titleMedium,
                  ),
          );
    final stacked = _stacked(context);
    final pending = row.pending;
    final billedTile = tile(
      KeyValueColumn(
        label: '本期账单',
        value: MoneyText(
          minor: row.billed,
          currency: row.currency,
          compact: true,
          negativeLabel: '贷方',
          negativeTone: MoneyTone.neutral,
          semanticsPrefix: '本期账单',
          textAlign: TextAlign.start,
          style: CfType.amountTile.toTextStyle(),
        ),
      ),
    );
    final unbilledTile = tile(
      KeyValueColumn(
        label: unbilledCount > 0 ? '未出账 · $unbilledCount 笔' : '未出账',
        value: MoneyText(
          minor: row.unbilled,
          currency: row.currency,
          compact: true,
          negativeLabel: '贷方',
          negativeTone: MoneyTone.neutral,
          semanticsPrefix: '未出账',
          textAlign: TextAlign.start,
          style: CfType.amountTile.toTextStyle(),
        ),
      ),
    );
    final canPay = current != null && current.status.owes && pending == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        tile(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (stacked || mainRight == null) ...<Widget>[
                mainLeft,
                ?mainRight,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(child: mainLeft),
                    mainRight,
                  ],
                ),
              if (canPay) ...<Widget>[
                const SizedBox(height: CfSpace.xs),
                OutlinedButton(
                  onPressed: () => unawaited(showQuickPaySheet(context, row)),
                  child: const Text(QuickPaySheet.title),
                ),
              ],
              if (pending != null) ...<Widget>[
                const SizedBox(height: CfSpace.xs),
                PendingRepaymentStrip(row: row),
              ],
            ],
          ),
        ),
        const SizedBox(height: CfSpace.sm),
        if (stacked) ...<Widget>[
          billedTile,
          const SizedBox(height: CfSpace.sm),
          unbilledTile,
        ] else
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: billedTile),
                const SizedBox(width: CfSpace.sm),
                Expanded(child: unbilledTile),
              ],
            ),
          ),
      ],
    );
  }
}

/// 三个主按钮：登记还款（主色）、记一笔、更新额度。
class DetailActions extends StatelessWidget {
  const DetailActions({super.key, required this.row});

  final CardLedgerRow row;

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      FilledButton(
        onPressed: () => context.go(
          AppRoutes.newRepayment(
            accountId: row.creditAccountId,
            statementId: row.current?.statement.id,
            currencyAccountId: row.currencyAccountId,
          ),
        ),
        child: const Text('登记还款'),
      ),
      OutlinedButton(
        onPressed: () => context.go(
          AppRoutes.newTransaction(
            accountId: row.creditAccountId,
            currencyAccountId: row.currencyAccountId,
          ),
        ),
        child: const Text('记一笔'),
      ),
      OutlinedButton(
        onPressed: () => context.go(
          AppRoutes.accountSettings(row.creditAccountId, section: 'limits'),
        ),
        child: const Text('更新额度'),
      ),
    ];
    if (_stacked(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var i = 0; i < buttons.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: CfSpace.xs),
            buttons[i],
          ],
        ],
      );
    }
    return Row(
      children: <Widget>[
        for (var i = 0; i < buttons.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: CfSpace.xs),
          Expanded(child: buttons[i]),
        ],
      ],
    );
  }
}

/// 账单历史：每行一个状态标签（有效状态；已并入的写"已并入 MM-DD 账单"）。
class StatementHistory extends StatelessWidget {
  const StatementHistory({super.key, required this.row, required this.data});

  final CardLedgerRow row;
  final LedgerData data;

  /// 列出的期数。
  static const int shown = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statements = data.statementsOf(row.currencyAccountId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionTitle(
          '账单历史',
          trailing: TextButton(
            onPressed: () => context.go(
              AppRoutes.statements(accountId: row.creditAccountId),
            ),
            child: const Text('全部账单'),
          ),
        ),
        if (statements.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CfSpace.md + CfSpace.xxs,
            ),
            child: Text(
              '还没有正式账单。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: CardFlowColors.of(context).textSecondary,
              ),
            ),
          )
        else
          GroupCard(
            children: <Widget>[
              for (final s in statements.take(shown))
                if (data.balances[s.id] case final b?)
                  MergeSemantics(
                    child: InkWell(
                      onTap: () => context.go(
                        AppRoutes.statement(
                          s.id,
                          accountId: row.creditAccountId,
                        ),
                      ),
                      child: Container(
                        alignment: AlignmentDirectional.centerStart,
                        constraints: const BoxConstraints(
                          minHeight: CfTouch.listRowMinHeight + CfSpace.xs,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: CfSpace.md,
                            vertical: CfSpace.xs,
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: CfSpace.sm,
                              runSpacing: CfSpace.xxs,
                              children: <Widget>[
                                Text(
                                  '${formatShortDate(b.statementDate, row.today)} 账单',
                                  style: theme.textTheme.bodyLarge,
                                ),
                                Wrap(
                                  spacing: CfSpace.xs,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: <Widget>[
                                    MoneyText(
                                      minor: b.basis,
                                      currency: row.currency,
                                      compact: true,
                                      negativeLabel: '贷方',
                                      negativeTone: MoneyTone.neutral,
                                      semanticsPrefix: '新增账单',
                                      style: theme.textTheme.bodyLarge,
                                    ),
                                    effectiveStatusBadge(b),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
      ],
    );
  }
}

/// 分期摘要："{商户} · 第 k/n 期 · 本期 ¥x"（进行中的计划；成本与各期在账单详情）。
class InstallmentSummary extends StatelessWidget {
  const InstallmentSummary({super.key, required this.row, required this.data});

  final CardLedgerRow row;
  final LedgerData data;

  @override
  Widget build(BuildContext context) {
    final plans = <InstallmentPlanRow>[
      for (final p in data.plansOf(row.currencyAccountId))
        if (p.status == InstallmentPlanStatus.active.code) p,
    ];
    if (plans.isEmpty) {
      return const SizedBox.shrink();
    }
    final latest = row.current?.statementDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SectionTitle('分期'),
        GroupCard(
          children: <Widget>[
            for (final plan in plans) _planTile(context, plan, latest),
          ],
        ),
      ],
    );
  }

  Widget _planTile(
    BuildContext context,
    InstallmentPlanRow plan,
    LocalDate? latest,
  ) {
    final periods = data.periods[plan.id] ?? const <InstallmentScheduleRow>[];
    final billed = <InstallmentScheduleRow>[
      for (final p in periods)
        if (latest != null && LocalDate.parse(p.statementDate) <= latest) p,
    ];
    final currentPeriod = billed.isEmpty
        ? (periods.isEmpty ? null : periods.first)
        : billed.last;
    final txn = data.transaction(plan.transactionId);
    return ListTile(
      title: Text(txn?.merchant ?? '分期'),
      subtitle: Wrap(
        spacing: CfSpace.xxs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text('第 ${billed.length}/${plan.periods} 期 · 每期'),
          MoneyText(
            minor: currentPeriod == null
                ? null
                : currentPeriod.principalMinor + currentPeriod.feeMinor,
            currency: row.currency,
            compact: true,
            semanticsPrefix: '每期',
            textAlign: TextAlign.start,
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () =>
          context.go(AppRoutes.statements(accountId: row.creditAccountId)),
    );
  }
}
