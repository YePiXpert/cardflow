import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/money_text.dart';
import '../../app/widgets/state_views.dart';
import '../../data/repositories/cash_forecast_reader.dart';
import '../../data/repositories/cash_models.dart';
import '../../data/repositories/providers.dart';
import '../cards/card_formatting.dart';
import '../cash/cash_formatting.dart';

/// P-01"现金压力"卡（ui-spec P-01）：未来 30 天的最低点、首个缺口日、口径（已确认/基准预期，切换不触发
/// 求解）；陈旧 → "假设分析"徽标；缺快照的账户 → "数据不全：{账户}缺快照，未计入"；还没有现金账户 →
/// "数据不全：还没有现金账户"「添加现金账户」。点按进入资金日历（P-07）。没有缺口用中性色，不用绿色。
class CashPressureCard extends ConsumerStatefulWidget {
  const CashPressureCard({super.key});

  /// 没有现金账户时的数据不全提示。
  static const String noCashAccounts = '数据不全：还没有现金账户';

  /// 窗口（ui-spec P-01"30 天最低点"）。
  static const int windowDays = 30;

  @override
  ConsumerState<CashPressureCard> createState() => _CashPressureCardState();
}

class _CashPressureCardState extends ConsumerState<CashPressureCard> {
  CashBasis _basis = CashBasis.baseline;

  @override
  Widget build(BuildContext context) {
    final query = CashForecastQuery(
      windowDays: CashPressureCard.windowDays,
      basis: _basis,
    );
    final forecast = ref.watch(cashForecastProvider(query));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SectionTitle('现金压力'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
          child: Wrap(
            spacing: CfSpace.xs,
            runSpacing: CfSpace.xs,
            children: <Widget>[
              for (final b in <CashBasis>[
                CashBasis.confirmed,
                CashBasis.baseline,
              ])
                ChoiceChip(
                  label: Text(b.label),
                  selected: b == _basis,
                  onSelected: (_) => setState(() => _basis = b),
                ),
            ],
          ),
        ),
        ...switch (forecast) {
          AsyncData(:final value) when value.hasNoAccounts => <Widget>[
            NoticeCard(
              icon: Icons.checklist,
              text: '${CashPressureCard.noCashAccounts}：还款时现金够不够要靠现金账户与余额快照判断。',
              action: OutlinedButton(
                onPressed: () => context.go(AppRoutes.newCashAccount),
                child: const Text('添加现金账户'),
              ),
            ),
          ],
          AsyncData(:final value) => _content(context, value),
          AsyncError(:final error) => <Widget>[
            ErrorBlockBody(
              title: '现金压力读取失败',
              code: '${error.runtimeType}',
              detail: '其他卡片不受影响。',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
              child: OutlinedButton(
                onPressed: () => ref.invalidate(cashForecastProvider(query)),
                child: const Text('重试'),
              ),
            ),
          ],
          _ => const <Widget>[
            Padding(
              padding: EdgeInsets.all(CfSpace.md),
              child: Text('现金压力计算中…'),
            ),
          ],
        },
      ],
    );
  }

  List<Widget> _content(BuildContext context, CashForecast f) {
    final colors = CardFlowColors.of(context);
    final theme = Theme.of(context);
    return <Widget>[
      for (final a in f.inputs.missingSnapshot)
        NoticeCard(
          icon: Icons.checklist,
          text: '数据不全：${a.name}缺快照，未计入',
          action: OutlinedButton(
            onPressed: () => context.go(AppRoutes.recordCashSnapshot(a.id)),
            child: const Text('记录快照'),
          ),
        ),
      if (f.nothingToCompute)
        const NoticeCard(
          icon: Icons.info_outline,
          tone: NoticeTone.neutral,
          text: '还没有可计算的现金账户（计入可用现金且有余额快照的）。',
        ),
      for (final summary in f.summaries)
        InkWell(
          key: ValueKey<String>('cash-pressure-${summary.currency}'),
          onTap: () =>
              context.go(AppRoutes.cashCalendarWith(basis: _basis.code)),
          child: Container(
            margin: const EdgeInsets.all(CfSpace.md),
            padding: const EdgeInsets.all(CfSpace.sm),
            decoration: BoxDecoration(
              color: summary.gapCount > 0 ? colors.danger.bg : colors.surface,
              borderRadius: BorderRadius.circular(CfRadius.lg),
              border: Border.all(
                color: colors.borderInput,
                width: CfStroke.hairline,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '未来 ${CashPressureCard.windowDays} 天 · ${_basis.label} · ${currencyLabel(summary.currency)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: CfSpace.xxs),
                Wrap(
                  spacing: CfSpace.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    const Text('最低点'),
                    MoneyText(
                      minor: summary.lowestBalance,
                      currency: summary.currency,
                      negativeLabel: '缺口',
                      semanticsPrefix: '最低点',
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.start,
                    ),
                    Text(
                      '${formatShortDate(summary.lowestOn, f.today)} · ${summary.lowest.row.name}',
                    ),
                  ],
                ),
                const SizedBox(height: CfSpace.xxs),
                Text(
                  summary.firstGap == null
                      ? '${CashPressureCard.windowDays} 天内没有缺口'
                      : '▲ 首个缺口日 ${formatShortDate(summary.firstGap!.breach.on, f.today)}（${summary.firstGap!.account.row.name}）· 共 ${summary.gapCount} 个缺口点',
                  style: TextStyle(
                    color: summary.gapCount > 0
                        ? colors.danger.fg
                        : colors.textPrimary,
                  ),
                ),
                if (f.assumptionAnalysis)
                  const Padding(
                    padding: EdgeInsets.only(top: CfSpace.xxs),
                    child: AssumptionBadge(),
                  ),
                const SizedBox(height: CfSpace.xxs),
                Text('查看资金日历 ›', style: TextStyle(color: colors.action)),
              ],
            ),
          ),
        ),
    ];
  }
}
