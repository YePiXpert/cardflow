import 'dart:async';

import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/cf_layout.dart';
import '../../app/widgets/first_run_empty_state.dart';
import '../../app/widgets/money_text.dart';
import '../../app/widgets/state_views.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/cash_forecast_reader.dart';
import '../../data/repositories/cash_models.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/scenario_repository.dart';
import '../calendar/calendar_providers.dart';
import '../cards/card_formatting.dart';
import 'balance_chart.dart';
import 'cash_formatting.dart';
import 'cash_page.dart';
import 'uncounted_dues.dart';

/// 现金（简报 U-1 §4；设计稿 `cash-dark.png`）：顶部 7/30/90/180 天分段与紧凑的口径菜单（已确认/基准预期/
/// 情景）；余额曲线（所选账户，默认最差的那个；"表格"切回资金日历的逐日行表）；"未计入"的信用卡应还；"接下来"
/// 的收支与还款（日期块、名称、账户、金额，缺口点穿插其中）；下面是现金账户与收支计划（原 P-08 内容）。
/// 语义不变：逐账户计算、账户之间从不相加、没有缺口不用绿色、不出现"安全/稳妥"。
class CashHomePage extends ConsumerStatefulWidget {
  const CashHomePage({super.key});

  /// 页名，同时是底部导航的标签。
  static const String title = '现金';

  /// 可选的窗口（天）。
  static const List<int> windows = <int>[7, 30, 90, 180];

  /// "接下来"最多列出的条数（其余在表格视图里）。
  static const int upcomingLimit = 8;

  @override
  ConsumerState<CashHomePage> createState() => _CashHomePageState();
}

class _CashHomePageState extends ConsumerState<CashHomePage> {
  int _window = 30;
  CashBasis _basis = CashBasis.baseline;
  String? _scenarioKey;
  String? _accountId;

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(cashPlanProvider);
    return Scaffold(
      appBar: largeTitleAppBar(
        context,
        title: CashHomePage.title,
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
              child: CfSegmented<int>(
                values: CashHomePage.windows,
                selected: _window,
                labelOf: (w) => '$w 天',
                onSelected: (w) => setState(() => _window = w),
              ),
            ),
            ..._forecastSection(context),
            ...CashPlanSections.children(context, value),
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

  CashForecastQuery get _query => CashForecastQuery(
    windowDays: _window,
    basis: _basis,
    scenarioKey: _basis == CashBasis.stress ? _scenarioKey : null,
  );

  List<Widget> _forecastSection(BuildContext context) {
    final forecast = ref.watch(cashForecastProvider(_query));
    final choices = ref.watch(scenarioChoicesProvider).value;
    final stress = choices?.stress ?? const <ScenarioView>[];
    final basisLabel = _basis == CashBasis.stress
        ? '压力：${stress.where((s) => s.key == _scenarioKey).firstOrNull?.name ?? '未选'}'
        : _basis.label;
    final controls = Padding(
      padding: const EdgeInsets.fromLTRB(CfSpace.md, CfSpace.xs, CfSpace.xs, 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextButton.icon(
              style: TextButton.styleFrom(
                alignment: AlignmentDirectional.centerStart,
                padding: EdgeInsets.zero,
              ),
              onPressed: () => unawaited(_chooseBasis(context, stress)),
              icon: const Icon(Icons.tune),
              label: Text('口径：$basisLabel'),
            ),
          ),
          TextButton.icon(
            onPressed: () => context.go(
              AppRoutes.cashCalendarWith(
                basis: _basis.code,
                scenario: _basis == CashBasis.stress ? _scenarioKey : null,
              ),
            ),
            icon: const Icon(Icons.table_rows_outlined),
            label: const Text('表格'),
          ),
        ],
      ),
    );
    final List<Widget> content;
    switch (forecast) {
      case AsyncData(:final value) when value.nothingToCompute:
        content = <Widget>[
          for (final a in value.inputs.missingSnapshot)
            NoticeCard(
              icon: Icons.checklist,
              text: '数据不全：${a.name}缺快照，未计入',
              action: OutlinedButton(
                onPressed: () => context.go(AppRoutes.recordCashSnapshot(a.id)),
                child: const Text('记录快照'),
              ),
            ),
          const NoticeCard(
            icon: Icons.info_outline,
            tone: NoticeTone.neutral,
            text: '还没有可计算的现金账户（计入可用现金且有余额快照的）。',
          ),
        ];
      case AsyncData(:final value):
        final account = _selected(value);
        content = <Widget>[
          for (final a in value.inputs.missingSnapshot)
            NoticeCard(
              icon: Icons.checklist,
              text: '数据不全：${a.name}缺快照，未计入',
              action: OutlinedButton(
                onPressed: () => context.go(AppRoutes.recordCashSnapshot(a.id)),
                child: const Text('记录快照'),
              ),
            ),
          if (value.accounts.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CfSpace.md,
                0,
                CfSpace.md,
                CfSpace.xs,
              ),
              child: Wrap(
                spacing: CfSpace.xs,
                runSpacing: CfSpace.xs,
                children: <Widget>[
                  for (final a in value.accounts)
                    ChoiceChip(
                      label: Text(a.row.name),
                      selected: a.row.id == account.row.id,
                      onSelected: (_) => setState(() => _accountId = a.row.id),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: BalanceChartCard(
              forecast: value,
              account: account,
              windowDays: _window,
            ),
          ),
          if (value.assumptionAnalysis)
            const Padding(
              padding: EdgeInsets.fromLTRB(
                CfSpace.md,
                CfSpace.xs,
                CfSpace.md,
                0,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: AssumptionBadge(),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(CfSpace.md, CfSpace.sm, CfSpace.md, 0),
            child: UncountedDuesTile(),
          ),
          SectionTitle(
            '接下来',
            trailing: TextButton(
              onPressed: () => context.go(
                AppRoutes.cashCalendarWith(
                  basis: _basis.code,
                  scenario: _basis == CashBasis.stress ? _scenarioKey : null,
                ),
              ),
              child: const Text('全部'),
            ),
          ),
          UpcomingList(forecast: value, limit: CashHomePage.upcomingLimit),
        ];
      case AsyncError(:final error) when error is ScenarioMissingException:
        content = <Widget>[
          NoticeCard(
            icon: Icons.tune,
            tone: NoticeTone.unknown,
            text: '还没有压力情景：先建一个（例如收入推迟 3 天），再用它查看资金日历。',
            action: OutlinedButton(
              onPressed: () => context.go(AppRoutes.newScenario),
              child: const Text('新建情景'),
            ),
          ),
        ];
      case AsyncError(:final error):
        content = <Widget>[
          ErrorBlockBody(
            title: '资金日历计算失败',
            code: '${error.runtimeType}',
            detail: '本机数据没有改动。',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: OutlinedButton(
              onPressed: () => ref.invalidate(cashForecastProvider(_query)),
              child: const Text('重新计算'),
            ),
          ),
        ];
      case _:
        content = const <Widget>[
          Padding(padding: EdgeInsets.all(CfSpace.md), child: Text('计算中…')),
        ];
    }
    return <Widget>[controls, ...content];
  }

  /// 所选账户；没选或已不在计算里时默认"最差的那个"（人民币里最低点最低的账户，没有人民币时取第一个币种）。
  CashAccountForecast _selected(CashForecast f) {
    for (final a in f.accounts) {
      if (a.row.id == _accountId) {
        return a;
      }
    }
    final summary =
        f.summaries.where((s) => s.currency == 'CNY').firstOrNull ??
        f.summaries.first;
    return summary.lowest;
  }

  Future<void> _chooseBasis(
    BuildContext context,
    List<ScenarioView> stress,
  ) async {
    final chosen = await showModalBottomSheet<(CashBasis, String?)>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final b in <CashBasis>[
                CashBasis.confirmed,
                CashBasis.baseline,
              ])
                ListTile(
                  title: Text(b.label),
                  subtitle: Text(
                    b == CashBasis.confirmed ? '只算确定的收支' : '预计收支按期发生',
                  ),
                  selected: _basis == b,
                  trailing: _basis == b ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.of(sheetContext).pop((b, null)),
                ),
              for (final s in stress)
                ListTile(
                  title: Text('压力情景：${s.name}'),
                  selected: _basis == CashBasis.stress && _scenarioKey == s.key,
                  trailing: _basis == CashBasis.stress && _scenarioKey == s.key
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () =>
                      Navigator.of(sheetContext).pop((CashBasis.stress, s.key)),
                ),
              if (stress.isEmpty)
                ListTile(
                  title: const Text('压力情景'),
                  subtitle: const Text('还没有：去"规划"新建一个'),
                  onTap: () =>
                      Navigator.of(sheetContext).pop((CashBasis.stress, null)),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null) {
      setState(() {
        _basis = chosen.$1;
        _scenarioKey = chosen.$2;
      });
    }
  }

  Future<void> _showAddMenu(BuildContext context) async {
    final target = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
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
      ),
    );
    if (target != null && context.mounted) {
      context.go(target);
    }
  }
}

/// 分段控件（设计稿 .seg）：等宽的几段，选中的一段用次级表面与粗体；每段的触控高度 48。
class CfSegmented<T> extends StatelessWidget {
  const CfSegmented({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = CardFlowColors.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(CfSpace.xxs / 2),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(CfRadius.lg),
      ),
      child: Row(
        children: <Widget>[
          for (final v in values)
            Expanded(
              child: Semantics(
                container: true,
                button: true,
                selected: v == selected,
                child: Material(
                  color: v == selected
                      ? colors.surfaceRaised
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(CfRadius.md),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(CfRadius.md),
                    onTap: () => onSelected(v),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: CfTouch.minTarget,
                      ),
                      child: Center(
                        child: Text(
                          labelOf(v),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: v == selected
                                ? colors.textPrimary
                                : colors.textSecondary,
                            fontWeight: v == selected
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "接下来"的一项：收支（日期、名称、账户、金额）或缺口点。
@immutable
final class UpcomingItem {
  const UpcomingItem.event({
    required this.on,
    required this.row,
    required this.amount,
    required this.account,
  }) : gap = null;

  const UpcomingItem.gap({
    required this.on,
    required CashGap this.gap,
    required this.account,
  }) : row = null,
       amount = 0;

  final LocalDate on;
  final CashEventRow? row;

  /// 情景变换后的金额（流出为负）。
  final int amount;
  final CashAccountForecast account;
  final CashGap? gap;
}

/// 从今天起窗口内的收支与缺口点，按日期（同日缺口在后）、再按账户顺序。
List<UpcomingItem> upcomingItems(CashForecast f) {
  final items = <UpcomingItem>[];
  for (final a in f.accounts) {
    for (final day in a.days) {
      if (day.on < f.today) {
        continue;
      }
      for (final id in day.eventIds) {
        final row = f.inputs.eventRows[id];
        if (row == null) {
          continue;
        }
        items.add(
          UpcomingItem.event(
            on: day.on,
            row: row,
            amount: a.amounts[id] ?? row.amountMinor,
            account: a,
          ),
        );
      }
    }
  }
  for (final g in f.gaps) {
    if (g.breach.on >= f.today) {
      items.add(UpcomingItem.gap(on: g.breach.on, gap: g, account: g.account));
    }
  }
  final order = {for (var i = 0; i < f.accounts.length; i++) f.accounts[i]: i};
  items.sort((x, y) {
    final byDate = x.on.compareTo(y.on);
    if (byDate != 0) {
      return byDate;
    }
    final gap = (x.gap == null ? 0 : 1).compareTo(y.gap == null ? 0 : 1);
    if (gap != 0) {
      return gap;
    }
    return order[x.account]!.compareTo(order[y.account]!);
  });
  return items;
}

/// "接下来"的列表（设计稿 .ev）：日期块（月、日）、名称、账户 · 层级、金额（收入用强调色）；缺口点用危险色与 ▲。
class UpcomingList extends StatelessWidget {
  const UpcomingList({super.key, required this.forecast, required this.limit});

  final CashForecast forecast;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final items = upcomingItems(forecast).take(limit).toList();
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CfSpace.md + CfSpace.xxs,
        ),
        child: Text(
          '窗口内没有收支。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
      );
    }
    return GroupCard(
      children: <Widget>[
        for (final item in items)
          _UpcomingTile(item: item, today: forecast.today),
      ],
    );
  }
}

class _UpcomingTile extends StatelessWidget {
  const _UpcomingTile({required this.item, required this.today});

  final UpcomingItem item;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final gap = item.gap;
    final tone = gap == null ? null : colors.danger.fg;
    final currency = item.account.account.currency;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: colors.textSecondary,
    );
    final Widget title;
    final String subtitle;
    final Widget trailing;
    if (gap != null) {
      final b = gap.breach;
      title = Wrap(
        spacing: CfSpace.xxs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(
            '缺口 · 余额',
            style: theme.textTheme.bodyLarge?.copyWith(color: tone),
          ),
          MoneyText(
            minor: b.balance,
            currency: currency,
            compact: true,
            negativeLabel: '透支',
            semanticsPrefix: '缺口时余额',
            textAlign: TextAlign.start,
            style: theme.textTheme.bodyLarge?.copyWith(color: tone),
          ),
        ],
      );
      subtitle = b.balance < 0
          ? '${item.account.row.name} · 低于零（先支出后收入）'
          : '${item.account.row.name} · 低于储备（先支出后收入）';
      trailing = Text(
        '▲',
        style: theme.textTheme.titleMedium?.copyWith(color: tone),
      );
    } else {
      final row = item.row!;
      title = Text(cashEventTitle(row), style: theme.textTheme.bodyLarge);
      subtitle =
          '${item.account.row.name} · ${CashEventClass.of(row.cls).label}'
          '${row.linkedRepaymentId != null ? ' · 还款' : ''}';
      final income = item.amount > 0;
      trailing = Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          ExcludeSemantics(
            child: Text(
              income ? '+' : '−',
              style: theme.textTheme.titleMedium?.copyWith(
                color: income ? colors.action : colors.textPrimary,
              ),
            ),
          ),
          MoneyText(
            minor: item.amount.abs(),
            currency: currency,
            compact: true,
            semanticsPrefix: income ? '收入' : '支出',
            style: theme.textTheme.titleMedium?.copyWith(
              color: income ? colors.action : colors.textPrimary,
            ),
          ),
        ],
      );
    }
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    if (stacked) {
      // 字号放大时上下排列：日期、名称、说明、金额各占一行，金额不被挤掉。
      return MergeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CfSpace.md,
            vertical: CfSpace.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                formatShortDate(item.on, today),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w700,
                ),
              ),
              title,
              Text(subtitle, style: small),
              trailing,
            ],
          ),
        ),
      );
    }
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CfSpace.md,
          vertical: CfSpace.sm,
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: CfSpace.xl + CfSpace.sm,
              child: Column(
                children: <Widget>[
                  Text('${item.on.month}月', style: small),
                  Text(
                    item.on.day.toString().padLeft(2, '0'),
                    style: CfType.amountRow.toTextStyle().copyWith(
                      color: tone ?? colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: CfSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  title,
                  Text(subtitle, style: small),
                ],
              ),
            ),
            const SizedBox(width: CfSpace.xs),
            trailing,
          ],
        ),
      ),
    );
  }
}
