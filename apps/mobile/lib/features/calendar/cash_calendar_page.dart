import 'package:cardflow_domain/cardflow_domain.dart'
    show LocalDate, PointPhase;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/first_run_empty_state.dart';
import '../../app/widgets/money_text.dart';
import '../../app/widgets/state_views.dart';
import '../../app/widgets/workspace_badges.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/cash_forecast_reader.dart';
import '../../data/repositories/cash_models.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/scenario_repository.dart';
import '../cards/card_formatting.dart';
import '../cash/cash_formatting.dart';
import '../planner/planner_segments.dart';
import 'calendar_providers.dart';

/// P-07 资金日历（ui-spec P-07）：控制条（7/30/90/180 天、账户、口径 已确认/基准/压力情景、情景选择）→ 摘要
/// （全窗口最低点与日期、缺口数、距零/距储备）→ 逐账户的日行（流出、流入、当日最低；缺口 ▲；储备线）→
/// 全部缺口（含造成缺口的事件）→ 尾部责任（窗口外的计划事件）→ 假设（先支出后收入、快照包含、陈旧 →
/// "假设分析"）。始终逐账户计算，账户之间不互抵；数据变化自动重算（provider 依赖）。
///
/// 无缺口用中性色，不用绿色，不出现"安全/稳妥"（ui-spec §4.5、P-07 九态"成功"）。图表视图后续提供，
/// 本期只有表格。
class CashCalendarPage extends ConsumerStatefulWidget {
  const CashCalendarPage({
    super.key,
    this.initialBasis = CashBasis.baseline,
    this.initialScenario,
  });

  final CashBasis initialBasis;
  final String? initialScenario;

  static const String title = '资金日历';

  /// ui-spec P-07 九态"首次空白"。
  static const String firstRunMessage = '还没有现金账户';

  /// 窗口内没有缺口时的文案（中性色）。
  static const String noGapText = '窗口内没有缺口';

  /// 窗口外没有计划中的还款、也没有未到期的分期时的文案。
  static const String noTailText = '窗口外没有计划中的还款或分期。';

  /// 可选的窗口（天）。
  static const List<int> windows = <int>[7, 30, 90, 180];

  /// 路由参数 → 口径。
  static CashBasis parseBasis(String? code) => CashBasis.values.firstWhere(
    (b) => b.code == code,
    orElse: () => CashBasis.baseline,
  );

  @override
  ConsumerState<CashCalendarPage> createState() => _CashCalendarPageState();
}

class _CashCalendarPageState extends ConsumerState<CashCalendarPage> {
  int _window = 30;
  late CashBasis _basis = widget.initialBasis;
  late String? _scenarioKey = widget.initialScenario;
  String? _accountId;

  @override
  Widget build(BuildContext context) {
    final choices = ref.watch(scenarioChoicesProvider).value;
    final stress = choices?.stress ?? const <ScenarioView>[];
    if (_basis == CashBasis.stress &&
        _scenarioKey == null &&
        stress.isNotEmpty) {
      _scenarioKey = stress.first.key;
    }
    final query = CashForecastQuery(
      windowDays: _window,
      basis: _basis,
      scenarioKey: _basis == CashBasis.stress ? _scenarioKey : null,
      accountId: _accountId,
    );
    final forecast = ref.watch(cashForecastProvider(query));
    final value = forecast.value;
    final controls = <Widget>[
      const PlannerSegmentBar(current: PlannerSegment.calendar),
      const RootPageBadges(),
      _Controls(
        window: _window,
        basis: _basis,
        scenarioKey: _scenarioKey,
        accountId: _accountId,
        stress: stress,
        accounts:
            value?.inputs.accounts.map((a) => (a.id, a.name)).toList() ??
            const <(String, String)>[],
        onWindow: (w) => setState(() => _window = w),
        onBasis: (b) => setState(() => _basis = b),
        onScenario: (k) => setState(() => _scenarioKey = k),
        onAccount: (a) => setState(() => _accountId = a),
      ),
    ];
    final List<Widget> content;
    if (value != null && value.hasNoAccounts) {
      content = <Widget>[
        FirstRunEmptyState(
          icon: Icons.calendar_month_outlined,
          message: CashCalendarPage.firstRunMessage,
          purpose: '逐账户、分口径展示未来现金与全部缺口。',
          actions: <EmptyStateAction>[
            EmptyStateAction(
              label: '添加',
              onPressed: () => context.go(AppRoutes.newCashAccount),
            ),
          ],
          scrollable: false,
        ),
      ];
    } else if (forecast case AsyncError(:final error)
        when error is ScenarioMissingException) {
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
    } else if (value != null) {
      content = <Widget>[
        if (forecast.hasError)
          NoticeCard(
            icon: Icons.error_outline,
            tone: NoticeTone.danger,
            text: '重新计算失败（${forecast.error.runtimeType}），下面保留的是上次的结果。',
            action: OutlinedButton(
              onPressed: () => ref.invalidate(cashForecastProvider(query)),
              child: const Text('重新计算'),
            ),
          ),
        if (forecast.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: Text('摘要更新中…'),
          ),
        ..._results(context, value),
      ];
    } else if (forecast case AsyncError(:final error)) {
      content = <Widget>[
        ErrorBlockBody(
          title: '资金日历计算失败',
          code: '$error'.startsWith('CashInputsException')
              ? '$error'
              : '${error.runtimeType}',
          detail: '本机数据没有改动。',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
          child: FilledButton(
            onPressed: () => ref.invalidate(cashForecastProvider(query)),
            child: const Text('重新计算'),
          ),
        ),
      ];
    } else {
      content = const <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: CfSpace.md),
          child: Text('摘要更新中…'),
        ),
        _InlineSkeleton(),
      ];
    }
    return Scaffold(
      appBar: AppBar(title: const Text(CashCalendarPage.title)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: CfSpace.xl),
        children: <Widget>[...controls, ...content],
      ),
    );
  }

  List<Widget> _results(BuildContext context, CashForecast f) {
    final inputs = f.inputs;
    final secondary = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: CardFlowColors.of(context).textSecondary);
    return <Widget>[
      for (final a in inputs.missingSnapshot)
        NoticeCard(
          icon: Icons.checklist,
          text: '数据不全：${a.name}缺快照，未计入',
          action: OutlinedButton(
            onPressed: () => context.go(AppRoutes.recordCashSnapshot(a.id)),
            child: const Text('记录快照'),
          ),
        ),
      for (final a in inputs.excluded)
        NoticeCard(
          icon: Icons.lock_outline,
          tone: NoticeTone.unknown,
          text: '${a.name}：${inputs.availability[a.id]!.label}',
        ),
      for (final a in f.accounts)
        if (a.stale)
          NoticeCard(
            icon: Icons.access_time,
            text: '${a.row.name}的余额快照已是 ${ageText(a.ageDays)}，结果为假设分析（未补零）',
            action: OutlinedButton(
              onPressed: () =>
                  context.go(AppRoutes.recordCashSnapshot(a.row.id)),
              child: const Text('记录新快照'),
            ),
          ),
      if (f.inactiveOverrides.isNotEmpty)
        NoticeCard(
          icon: Icons.info_outline,
          tone: NoticeTone.unknown,
          text: '情景中有 ${f.inactiveOverrides.length} 项覆盖指向已删除的收支，未生效',
        ),
      if (f.nothingToCompute)
        const NoticeCard(
          icon: Icons.info_outline,
          tone: NoticeTone.neutral,
          text: '没有可以计算的账户：计入可用现金的账户都还没有余额快照。',
        )
      else ...<Widget>[
        for (final summary in f.summaries)
          _SummaryCard(forecast: f, summary: summary),
        for (final account in f.accounts)
          ..._accountSection(context, f, account),
        SectionTitle('全部缺口（${f.gaps.length}）'),
        if (f.gaps.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: Text(CashCalendarPage.noGapText, style: secondary),
          ),
        for (final gap in f.gaps) _GapTile(forecast: f, gap: gap),
      ],
      const SectionTitle('尾部责任（窗口外）'),
      if (f.tail.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
          child: Text(CashCalendarPage.noTailText, style: secondary),
        )
      else
        ExpansionTile(
          title: Text('窗口外还有 ${f.tail.length} 笔计划中的支出'),
          children: <Widget>[
            for (final t in f.tail)
              ListTile(
                title: Text('${formatDate(t.on)} · ${t.label}'),
                subtitle: Text(t.accountName),
                trailing: CashFlowLabel(
                  amountMinor: t.amountMinor,
                  currency: t.currency,
                ),
              ),
          ],
        ),
      const SectionTitle('假设'),
      for (final text in <String>[
        '同日只有日期、顺序未知时按先支出后收入（保守）校验',
        '快照当天未标记为已包含的收支按未发生处理并计入当日',
        ...f.assumptions,
      ])
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CfSpace.md,
            vertical: CfSpace.xxs,
          ),
          child: Text('· $text'),
        ),
      Padding(
        padding: const EdgeInsets.all(CfSpace.md),
        child: OutlinedButton(
          onPressed: () => context.go(AppRoutes.newScenario),
          child: const Text('以此建情景'),
        ),
      ),
    ];
  }

  List<Widget> _accountSection(
    BuildContext context,
    CashForecast f,
    CashAccountForecast a,
  ) {
    final currency = a.account.currency;
    final snapshotBreach = a.snapshotBreach;
    return <Widget>[
      SectionTitle(
        a.row.name,
        trailing: a.stale ? StaleBadge(ageDays: a.ageDays) : null,
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
        child: Wrap(
          spacing: CfSpace.xs,
          runSpacing: CfSpace.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              '快照 ${formatShortDate(LocalDate.parse(a.snapshot.balanceAsOf), f.today)}',
            ),
            BalanceText(
              minor: a.snapshot.balanceMinor,
              currency: currency,
              semanticsPrefix: '快照余额',
              textAlign: TextAlign.start,
            ),
            const Text('· 表格视图（图表后续提供）'),
          ],
        ),
      ),
      _ReserveLine(reserve: a.account.reserveFloor, currency: currency),
      if (snapshotBreach != null)
        _DayCard(
          key: ValueKey<String>('day-${a.row.id}-snapshot'),
          title: '${formatShortDate(snapshotBreach.on, f.today)} 快照时余额已低于储备',
          gap: true,
          currency: currency,
          outflow: 0,
          inflow: 0,
          low: snapshotBreach.balance,
          events: const <(String, int)>[],
        ),
      if (a.days.isEmpty)
        const Padding(
          padding: EdgeInsets.all(CfSpace.md),
          child: Text('窗口内没有收支。'),
        ),
      for (final day in a.days)
        _DayCard(
          key: ValueKey<String>('day-${a.row.id}-${day.on}'),
          title:
              '${formatShortDate(day.on, f.today)}${day.on < f.today ? '（快照后、今天前）' : ''}',
          gap: day.gap,
          currency: currency,
          outflow: day.outflow,
          inflow: day.inflow,
          low: day.low,
          belowReserve: day.low < a.account.reserveFloor,
          events: <(String, int)>[
            for (final id in day.eventIds)
              (_eventTitle(f.inputs.eventRows[id]), a.amounts[id] ?? 0),
          ],
        ),
    ];
  }
}

String _eventTitle(CashEventRow? row) =>
    row == null ? '（已删除）' : cashEventTitle(row);

/// 控制条：窗口、口径、情景、账户（可换行的单选标签）。
class _Controls extends StatelessWidget {
  const _Controls({
    required this.window,
    required this.basis,
    required this.scenarioKey,
    required this.accountId,
    required this.stress,
    required this.accounts,
    required this.onWindow,
    required this.onBasis,
    required this.onScenario,
    required this.onAccount,
  });

  final int window;
  final CashBasis basis;
  final String? scenarioKey;
  final String? accountId;
  final List<ScenarioView> stress;
  final List<(String, String)> accounts;
  final ValueChanged<int> onWindow;
  final ValueChanged<CashBasis> onBasis;
  final ValueChanged<String> onScenario;
  final ValueChanged<String?> onAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget group(String label, List<Widget> chips) => Padding(
      padding: const EdgeInsets.fromLTRB(CfSpace.md, CfSpace.xs, CfSpace.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: theme.textTheme.bodyMedium),
          const SizedBox(height: CfSpace.xxs),
          Wrap(spacing: CfSpace.xs, runSpacing: CfSpace.xs, children: chips),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        group('窗口', <Widget>[
          for (final w in CashCalendarPage.windows)
            ChoiceChip(
              label: Text('$w 天'),
              selected: w == window,
              onSelected: (_) => onWindow(w),
            ),
        ]),
        group('口径', <Widget>[
          for (final b in CashBasis.values)
            ChoiceChip(
              label: Text(b.label),
              selected: b == basis,
              onSelected: (_) => onBasis(b),
            ),
        ]),
        if (basis == CashBasis.stress && stress.isNotEmpty)
          group('情景', <Widget>[
            for (final s in stress)
              ChoiceChip(
                label: Text(s.name),
                selected: s.key == scenarioKey,
                onSelected: (_) => onScenario(s.key),
              ),
          ]),
        if (accounts.length > 1 || accountId != null)
          group('账户（始终逐账户计算，不互抵）', <Widget>[
            ChoiceChip(
              label: const Text('全部账户'),
              selected: accountId == null,
              onSelected: (_) => onAccount(null),
            ),
            for (final (id, name) in accounts)
              ChoiceChip(
                label: Text(name),
                selected: id == accountId,
                onSelected: (_) => onAccount(id),
              ),
          ]),
      ],
    );
  }
}

/// 摘要（一个币种）：缺口时用危险色并带 ▲；没有缺口用中性色（不用绿色，不说"安全/稳妥"）。
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.forecast, required this.summary});

  final CashForecast forecast;
  final CashSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = CardFlowColors.of(context);
    final theme = Theme.of(context);
    final hasGap = summary.gapCount > 0;
    final tone = hasGap
        ? colors.danger
        : CfTone(fg: colors.textPrimary, bg: colors.surface);
    final text = theme.textTheme.bodyLarge?.copyWith(color: tone.fg);
    final currency = summary.currency;
    final first = summary.firstGap;
    final scenario = forecast.scenario;
    final basisText = scenario.isBuiltin
        ? scenario.name
        : '压力情景：${scenario.name}';
    final windowDays = forecast.horizonEnd.differenceInDays(forecast.today) + 1;
    return Container(
      key: ValueKey<String>('cash-summary-$currency'),
      margin: const EdgeInsets.all(CfSpace.md),
      padding: const EdgeInsets.all(CfSpace.md),
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(CfRadius.lg),
        border: Border.all(color: colors.borderInput, width: CfStroke.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MergeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ExcludeSemantics(
                  child: Icon(
                    hasGap ? Icons.warning_amber_rounded : Icons.info_outline,
                    color: tone.fg,
                    size: CfIconSize.lg,
                  ),
                ),
                const SizedBox(width: CfSpace.xs),
                Expanded(
                  child: Text(
                    hasGap
                        ? '▲ ${summary.gapCount} 个缺口点 · 首个 ${formatShortDate(first!.breach.on, forecast.today)}（${first.account.row.name}）'
                        : CashCalendarPage.noGapText,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: tone.fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: CfSpace.xs),
          Text(
            '$basisText · 未来 $windowDays 天 · ${currencyLabel(currency)}',
            style: text,
          ),
          const SizedBox(height: CfSpace.xxs),
          Wrap(
            spacing: CfSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text('全窗口最低点', style: text),
              MoneyText(
                minor: summary.lowestBalance,
                currency: currency,
                negativeLabel: '缺口',
                semanticsPrefix: '全窗口最低点',
                style: text,
                textAlign: TextAlign.start,
              ),
              Text(
                '${formatShortDate(summary.lowestOn, forecast.today)} · ${summary.lowest.row.name}',
                style: text,
              ),
            ],
          ),
          Wrap(
            spacing: CfSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(summary.marginToZero < 0 ? '距零：缺' : '距零：高于零', style: text),
              MoneyText(
                minor: summary.marginToZero.abs(),
                currency: currency,
                semanticsPrefix: summary.marginToZero < 0 ? '距零缺' : '高于零',
                style: text,
                textAlign: TextAlign.start,
              ),
            ],
          ),
          Wrap(
            spacing: CfSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                summary.marginToReserve < 0 ? '距储备：低于储备' : '距储备：高于储备',
                style: text,
              ),
              MoneyText(
                minor: summary.marginToReserve.abs(),
                currency: currency,
                semanticsPrefix: summary.marginToReserve < 0 ? '低于储备' : '高于储备',
                style: text,
                textAlign: TextAlign.start,
              ),
            ],
          ),
          if (forecast.assumptionAnalysis)
            const Padding(
              padding: EdgeInsets.only(top: CfSpace.xs),
              child: AssumptionBadge(),
            ),
        ],
      ),
    );
  }
}

/// 储备线：一条虚线 + "储备 {金额}"（表格视图里的储备虚线图例；低于它的日行标"低于储备"）。
class _ReserveLine extends StatelessWidget {
  const _ReserveLine({required this.reserve, required this.currency});

  final int reserve;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = CardFlowColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CfSpace.md,
        vertical: CfSpace.xs,
      ),
      child: Wrap(
        spacing: CfSpace.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          ExcludeSemantics(
            child: SizedBox(
              width: CfSpace.xl * 2,
              height: CfStroke.hairline * 2,
              child: CustomPaint(painter: _DashPainter(colors.textSecondary)),
            ),
          ),
          const Text('储备线'),
          BalanceText(
            minor: reserve,
            currency: currency,
            semanticsPrefix: '储备线',
            textAlign: TextAlign.start,
          ),
        ],
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.height;
    const dash = CfSpace.xxs;
    for (var x = 0.0; x < size.width; x += dash * 2) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(x + dash, size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 一天：流出、流入、当日最低；缺口 ▲；点按展开当天的事件（情景变换后的金额）。
class _DayCard extends StatelessWidget {
  const _DayCard({
    super.key,
    required this.title,
    required this.gap,
    required this.currency,
    required this.outflow,
    required this.inflow,
    required this.low,
    required this.events,
    this.belowReserve = false,
  });

  final String title;
  final bool gap;
  final bool belowReserve;
  final String currency;
  final int outflow;
  final int inflow;
  final int low;
  final List<(String, int)> events;

  @override
  Widget build(BuildContext context) {
    final colors = CardFlowColors.of(context);
    return ExpansionTile(
      title: Wrap(
        spacing: CfSpace.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(title),
          if (gap)
            Text('▲ 缺口', style: TextStyle(color: colors.danger.fg))
          else if (belowReserve)
            Text('低于储备', style: TextStyle(color: colors.attention.fg)),
        ],
      ),
      subtitle: Wrap(
        spacing: CfSpace.sm,
        runSpacing: CfSpace.xxs,
        children: <Widget>[
          _pair(
            '流出',
            MoneyText(
              minor: -outflow,
              currency: currency,
              semanticsPrefix: '流出',
              textAlign: TextAlign.start,
            ),
          ),
          _pair(
            '流入',
            MoneyText(
              minor: inflow,
              currency: currency,
              semanticsPrefix: '流入',
              textAlign: TextAlign.start,
            ),
          ),
          _pair(
            '当日最低',
            MoneyText(
              minor: low,
              currency: currency,
              negativeLabel: '缺口',
              semanticsPrefix: '当日最低',
              textAlign: TextAlign.start,
            ),
          ),
        ],
      ),
      children: <Widget>[
        for (final (name, amount) in events)
          ListTile(
            dense: true,
            title: Text(name),
            trailing: CashFlowLabel(amountMinor: amount, currency: currency),
          ),
      ],
    );
  }

  Widget _pair(String label, Widget value) => Wrap(
    spacing: CfSpace.xxs,
    children: <Widget>[
      ExcludeSemantics(child: Text(label)),
      value,
    ],
  );
}

/// 缺口列表的一项：日期、账户、余额、距零/距储备、造成缺口的事件。
class _GapTile extends StatelessWidget {
  const _GapTile({required this.forecast, required this.gap});

  final CashForecast forecast;
  final CashGap gap;

  @override
  Widget build(BuildContext context) {
    final b = gap.breach;
    final currency = gap.account.account.currency;
    final colors = CardFlowColors.of(context);
    final causes = <String>[
      for (final id in b.eventIds) _eventTitle(forecast.inputs.eventRows[id]),
    ];
    return ListTile(
      title: Text(
        '▲ ${formatShortDate(b.on, forecast.today)} · ${gap.account.row.name}'
        '${b.phase == PointPhase.snapshot ? '（快照时已低于储备）' : ''}',
        style: TextStyle(color: colors.danger.fg),
      ),
      subtitle: Wrap(
        spacing: CfSpace.sm,
        runSpacing: CfSpace.xxs,
        children: <Widget>[
          _gapValue('余额', b.balance, currency, negativeLabel: '缺口'),
          _gapValue('距零缺', b.gapToZero, currency),
          _gapValue('距储备缺', b.gapToReserve, currency),
          if (causes.isNotEmpty) Text('原因：${causes.join('、')}'),
        ],
      ),
    );
  }

  Widget _gapValue(
    String label,
    int minor,
    String currency, {
    String? negativeLabel,
  }) => Wrap(
    spacing: CfSpace.xxs,
    children: <Widget>[
      ExcludeSemantics(child: Text(label)),
      MoneyText(
        minor: minor,
        currency: currency,
        negativeLabel: negativeLabel,
        semanticsPrefix: label,
        textAlign: TextAlign.start,
      ),
    ],
  );
}

/// 页内的静态骨架（加载中；减少动效时也不需要特殊处理）。
class _InlineSkeleton extends StatelessWidget {
  const _InlineSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = CardFlowColors.of(context);
    return Semantics(
      label: LoadingSkeleton.semanticsLabel,
      container: true,
      child: ExcludeSemantics(
        child: Column(
          children: <Widget>[
            for (var i = 0; i < 3; i++)
              Container(
                height: CfTouch.listRowMinHeight * 2,
                margin: const EdgeInsets.all(CfSpace.md),
                decoration: BoxDecoration(
                  color: colors.unknown.bg,
                  borderRadius: BorderRadius.circular(CfRadius.lg),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
