import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/money/money_format.dart';
import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/bank_badge.dart';
import '../../app/widgets/cf_layout.dart';
import '../../app/widgets/first_run_empty_state.dart';
import '../../app/widgets/money_text.dart';
import '../../app/widgets/state_views.dart';
import '../../data/repositories/ledger_home.dart';
import '../../data/repositories/ledger_reader.dart' show LiabilityTotals;
import '../../data/repositories/providers.dart';
import '../cards/card_formatting.dart';
import '../onboarding/workspace_actions.dart';
import '../statements/ledger_formatting.dart';
import 'repayment_quick_actions.dart';

/// 卡账（新首页，简报 U-1 §2；设计稿 `home-dark.png`/`home-light.png`）：打开就能看到每张卡欠多少、哪天出账、
/// 哪天还款。顶部汇总卡（本期待还、最近一笔到期、3 天内到期、总额度与可用）、待处理、"今天刷哪张"，下面按
/// 分组列出每张卡（信用卡；贷款分组在后续版本加入）。数据来自 [LedgerHome]（读模型，不在这里计算）。
///
/// 四态：首次空白（还没有卡：大号"添加第一张卡"与"体验演示"）、加载（骨架）、错误（「重试」）、成功。
class LedgerHomePage extends ConsumerStatefulWidget {
  const LedgerHomePage({super.key});

  /// 页名，同时是底部导航的标签。
  static const String title = '卡账';

  /// 首次空白。
  static const String firstRunMessage = '还没有信用卡';

  /// "今天刷哪张"弹层的口径说明（简报 §2）。
  static const String todayBasis =
      '按今天入账计算免息天数（到期日 − 今天）；入账可能延迟时按最早到期算；'
      '不考虑活动、手续费与额度是否够用。只列未冻结、有账期规则、还有可用额度的人民币卡。';

  @override
  ConsumerState<LedgerHomePage> createState() => _LedgerHomePageState();
}

class _LedgerHomePageState extends ConsumerState<LedgerHomePage> {
  LedgerSort _sort = LedgerSort.byDue;

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(ledgerHomeProvider);
    return Scaffold(
      appBar: largeTitleAppBar(
        context,
        title: LedgerHomePage.title,
        actions: <Widget>[
          CircleIconButton(
            icon: Icons.credit_card,
            tooltip: '管理全部卡片',
            onPressed: () => context.go(AppRoutes.cards),
          ),
          CircleIconButton(
            icon: Icons.add,
            tooltip: '添加',
            onPressed: () => unawaited(_showAddMenu(context)),
          ),
        ],
      ),
      body: switch (home) {
        AsyncData(:final value) when value.isEmpty => const _EmptyHome(),
        AsyncData(:final value) => _HomeList(
          home: value,
          sort: _sort,
          onSort: (s) => setState(() => _sort = s),
        ),
        AsyncError(:final error) => ErrorBlock(
          title: '卡账读取失败',
          code: '${error.runtimeType}',
          detail: '本机数据没有改动。',
          onRetry: () => ref.invalidate(ledgerProvider),
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
              (Icons.credit_card, '添加卡片', AppRoutes.newCard),
              (Icons.edit_note, '记一笔', AppRoutes.newTransaction()),
              (Icons.receipt_long_outlined, '录入账单', AppRoutes.newStatement()),
              (Icons.payments_outlined, '登记还款', AppRoutes.newRepayment()),
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

/// 真实空间还没有卡：大号"添加第一张卡"与"体验演示"入口（P-22 仍是首次启动页）。
class _EmptyHome extends ConsumerWidget {
  const _EmptyHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    children: <Widget>[
      FirstRunEmptyState(
        icon: Icons.credit_card_outlined,
        message: LedgerHomePage.firstRunMessage,
        purpose: '记下每张卡的账单日与还款日，打开就能看到每张卡欠多少、哪天出账、哪天还款。',
        largePrimary: true,
        actions: <EmptyStateAction>[
          EmptyStateAction(
            label: '添加第一张卡',
            onPressed: () => context.go(AppRoutes.newCard),
          ),
          EmptyStateAction(
            label: '体验演示',
            onPressed: () => unawaited(enterDemoWorkspace(context, ref)),
          ),
        ],
        scrollable: false,
      ),
    ],
  );
}

class _HomeList extends StatelessWidget {
  const _HomeList({
    required this.home,
    required this.sort,
    required this.onSort,
  });

  final LedgerHome home;
  final LedgerSort sort;
  final ValueChanged<LedgerSort> onSort;

  @override
  Widget build(BuildContext context) {
    final rows = sortRows(home.cards.rows, sort);
    final pick = home.todayPick;
    return ListView(
      padding: const EdgeInsets.only(bottom: CfSpace.xl),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CfSpace.md,
            CfSpace.xxs,
            CfSpace.md,
            0,
          ),
          child: SummaryHeroCard(home: home),
        ),
        if (home.pendingCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CfSpace.md,
              CfSpace.sm,
              CfSpace.md,
              0,
            ),
            child: _PendingTile(count: home.pendingCount),
          ),
        if (pick != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CfSpace.md,
              CfSpace.sm,
              CfSpace.md,
              0,
            ),
            child: TodayPickTile(home: home),
          ),
        SectionTitle(
          sort.label,
          trailing: TextButton.icon(
            onPressed: () => unawaited(_chooseSort(context)),
            icon: const Icon(Icons.swap_vert),
            label: const Text('排序'),
          ),
        ),
        GroupCard(
          dividerIndent: 0,
          children: <Widget>[
            for (final row in rows) CardLedgerRowTile(row: row),
          ],
        ),
        const SectionTitle('更多'),
        GroupCard(
          children: <Widget>[
            for (final (icon, label, route) in <(IconData, String, String)>[
              (Icons.account_tree_outlined, '管理全部卡片', AppRoutes.cards),
              (Icons.receipt_long_outlined, '账单中心', AppRoutes.statements()),
              (Icons.fact_check_outlined, '还款与核对', AppRoutes.repayments()),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(route),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _chooseSort(BuildContext context) async {
    final chosen = await showModalBottomSheet<LedgerSort>(
      context: context,
      useRootNavigator: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final s in LedgerSort.values)
              ListTile(
                title: Text(s.label),
                trailing: s == sort
                    ? Icon(
                        Icons.check,
                        color: CardFlowColors.of(sheetContext).action,
                      )
                    : null,
                selected: s == sort,
                onTap: () => Navigator.of(sheetContext).pop(s),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) {
      onSort(chosen);
    }
  }
}

/// 顶部汇总卡（设计稿 .hero）：本期待还合计（按币种，人民币大字）、N 张卡、最近一笔到期；3 天内到期、
/// 总额度、可用。点开是负债明细（按币种）。
class SummaryHeroCard extends StatelessWidget {
  const SummaryHeroCard({super.key, required this.home});

  final LedgerHome home;

  @override
  Widget build(BuildContext context) {
    final colors = CardFlowColors.of(context);
    final theme = Theme.of(context);
    final s = home.summary;
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: colors.heroTextSecondary,
    );
    final value = theme.textTheme.titleMedium?.copyWith(color: colors.heroText);
    final currencies = s.dueByCurrency.keys.toList();
    final mainCurrency = currencies.isEmpty ? 'CNY' : currencies.first;
    final others = currencies.skip(1).toList();
    final nearest = s.nearest;
    final today = home.rows.first.today;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors.hero,
          ),
          borderRadius: BorderRadius.circular(CfRadius.card),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(CfRadius.card),
          onTap: () => unawaited(_showLiabilities(context)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              CfSpace.md + CfSpace.xxs / 2,
              CfSpace.md,
              CfSpace.md + CfSpace.xxs / 2,
              CfSpace.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  s.owingCards > 0 ? '本期待还 · ${s.owingCards} 张卡' : '本期待还',
                  style: secondary,
                ),
                MoneyText(
                  minor: s.dueByCurrency[mainCurrency] ?? 0,
                  currency: mainCurrency,
                  compact: true,
                  semanticsPrefix: '本期待还合计',
                  textAlign: TextAlign.start,
                  style: CfType.amountHero.toTextStyle().copyWith(
                    color: colors.heroText,
                  ),
                ),
                for (final c in others)
                  MoneyText(
                    minor: s.dueByCurrency[c],
                    currency: c,
                    compact: true,
                    semanticsPrefix: '另有',
                    textAlign: TextAlign.start,
                    style: secondary,
                  ),
                const SizedBox(height: CfSpace.xxs),
                if (nearest != null)
                  Wrap(
                    spacing: CfSpace.xxs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text(
                        nearest.overdue
                            ? '最近一笔 ${formatShortDate(nearest.dueDate, today)} 到期（已逾期）·'
                                  ' ${nearest.row.bankShort}'
                            : '最近一笔 ${formatShortDate(nearest.dueDate, today)} 到期 ·'
                                  ' ${nearest.row.bankShort}',
                        style: secondary,
                      ),
                      MoneyText(
                        minor: nearest.amount,
                        currency: nearest.currency,
                        compact: true,
                        semanticsPrefix: '金额',
                        textAlign: TextAlign.start,
                        style: secondary,
                      ),
                    ],
                  )
                else
                  Text('没有要还的账单', style: secondary),
                if (s.missedStatements > 0)
                  Text('${s.missedStatements} 张卡有账单出了还没录入', style: secondary),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: CfSpace.sm),
                  child: Divider(
                    height: CfStroke.hairline,
                    color: colors.heroTextSecondary.withValues(alpha: 0.3),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: CfSpace.md,
                    runSpacing: CfSpace.xs,
                    children: <Widget>[
                      KeyValueColumn(
                        label: '3 天内到期',
                        labelColor: colors.heroTextSecondary,
                        value: Text('${s.dueSoon} 笔', style: value),
                      ),
                      _LimitValue(
                        label: '总额度',
                        minor: s.totalLimit,
                        missing: s.missingLimit,
                        style: value,
                        labelColor: colors.heroTextSecondary,
                      ),
                      _LimitValue(
                        label: '可用',
                        minor: s.available,
                        missing: s.missingLimit,
                        style: value,
                        labelColor: colors.heroTextSecondary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showLiabilities(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (sheetContext) => _LiabilitySheet(home: home),
    );
  }
}

class _LimitValue extends StatelessWidget {
  const _LimitValue({
    required this.label,
    required this.minor,
    required this.missing,
    required this.style,
    required this.labelColor,
  });

  final String label;
  final int? minor;
  final bool missing;
  final TextStyle? style;
  final Color labelColor;

  @override
  Widget build(BuildContext context) => KeyValueColumn(
    label: label,
    labelColor: labelColor,
    value: missing
        ? Text(
            '部分卡缺额度',
            style: style?.copyWith(
              fontSize: Theme.of(context).textTheme.bodyMedium?.fontSize,
            ),
          )
        : MoneyText(
            minor: minor,
            currency: 'CNY',
            compact: true,
            semanticsPrefix: label,
            textAlign: TextAlign.start,
            style: style,
          ),
  );
}

/// 汇总卡点开的负债明细（按币种，不相加）：本期应还、未出账、未来分期本金与总负债；口径说明。
class _LiabilitySheet extends ConsumerWidget {
  const _LiabilitySheet({required this.home});

  final LedgerHome home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(ledgerProvider).value;
    final totals =
        ledger?.totalsByCurrency.values.toList() ?? const <LiabilityTotals>[];
    final theme = Theme.of(context);
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (sheetContext, controller) => ListView(
          controller: controller,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
              child: Semantics(
                header: true,
                child: Text('负债明细', style: theme.textTheme.titleMedium),
              ),
            ),
            for (final t in totals) ...<Widget>[
              if (totals.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CfSpace.md,
                    CfSpace.sm,
                    CfSpace.md,
                    0,
                  ),
                  child: Text(currencyLabel(t.currency)),
                ),
              LiabilitySection.totals(t),
            ],
            Padding(
              padding: const EdgeInsets.all(CfSpace.md),
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  context.go(AppRoutes.statements());
                },
                child: const Text('账单中心'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 待处理（待核对的还款与差异项合计）：一行"N 项待处理 ›"，进还款与核对。
class _PendingTile extends StatelessWidget {
  const _PendingTile({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = CardFlowColors.of(context);
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(CfRadius.tile),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CfRadius.tile),
        ),
        leading: Icon(Icons.rule, color: colors.attention.fg),
        title: Text('$count 项待处理'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go(AppRoutes.repayments()),
      ),
    );
  }
}

/// "今天刷哪张"（设计稿 .tip）：免息天数最长的那张；点开是前 5 名与口径说明。
class TodayPickTile extends StatelessWidget {
  const TodayPickTile({super.key, required this.home});

  final LedgerHome home;

  @override
  Widget build(BuildContext context) {
    final pick = home.todayPick!;
    final colors = CardFlowColors.of(context);
    final theme = Theme.of(context);
    final today = pick.row.today;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(CfRadius.tile),
      child: InkWell(
        borderRadius: BorderRadius.circular(CfRadius.tile),
        onTap: () => unawaited(_showCandidates(context)),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CfSpace.md,
            vertical: CfSpace.sm,
          ),
          child: Row(
            children: <Widget>[
              BankBadge(bankName: pick.row.bankName),
              const SizedBox(width: CfSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '今天刷${pick.row.title}',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${formatShortDate(pick.cycle.statementDate, today)} 出账 · '
                      '${formatShortDate(pick.cycle.dueDate, today)} 还款',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: CfSpace.xs),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    '${pick.freeDays}',
                    style: CfType.amountRow.toTextStyle().copyWith(
                      color: colors.action,
                    ),
                  ),
                  Text(
                    '天免息',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCandidates(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (sheetContext) => TodayCandidatesSheet(home: home),
    );
  }
}

/// "今天刷哪张"的弹层：前 5 名候选与各自的免息天数、口径说明。
class TodayCandidatesSheet extends StatelessWidget {
  const TodayCandidatesSheet({super.key, required this.home});

  final LedgerHome home;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (sheetContext, controller) => ListView(
          controller: controller,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
              child: Semantics(
                header: true,
                child: Text('今天刷哪张', style: theme.textTheme.titleMedium),
              ),
            ),
            for (final c in home.candidates)
              ListTile(
                leading: BankBadge(bankName: c.row.bankName),
                title: Text(c.row.title),
                subtitle: Text(
                  '${formatShortDate(c.cycle.statementDate, c.row.today)} 出账 · '
                  '${formatShortDate(c.cycle.dueDate, c.row.today)} 还款',
                ),
                trailing: Text(
                  '${c.freeDays} 天免息',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.action,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(CfSpace.md),
              child: Text(
                LedgerHomePage.todayBasis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 卡账的一行（设计稿 .item）：徽标、银行简称 ···· 末四位、产品名；待还（大字）+ 状态标签 + 账单；N 天后出账；
/// N 天后还款。字号放大到 1.6 倍以上时改为纵向：金额在上，两个日期格在下（简报 §5"动态字体"）。
class CardLedgerRowTile extends ConsumerWidget {
  const CardLedgerRowTile({super.key, required this.row});

  final CardLedgerRow row;

  /// 文字放大到这个倍数起，金额与日期格改为上下排列。
  static const double stackedScale = 1.6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= stackedScale;
    final amount = _AmountColumn(row: row);
    final cells = row.needsRule || row.ruleInvalid
        ? <Widget>[_RuleCell(row: row)]
        : <Widget>[_StatementCellView(row: row), _DueCellView(row: row)];
    final pending = row.pending;
    return InkWell(
      onTap: () => context.go(AppRoutes.account(row.creditAccountId)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CfSpace.md,
          CfSpace.sm,
          CfSpace.md,
          CfSpace.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                BankBadge(bankName: row.bankName),
                const SizedBox(width: CfSpace.sm),
                Expanded(
                  child: Wrap(
                    spacing: CfSpace.xs,
                    runSpacing: CfSpace.xxs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text(
                        row.title,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (row.currency != 'CNY')
                        Text(
                          row.currency,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      if (row.frozen)
                        const StatusBadge(
                          label: '已冻结',
                          icon: Icons.ac_unit,
                          tone: NoticeTone.unknown,
                        ),
                    ],
                  ),
                ),
                if (row.productName != null && !stacked) ...<Widget>[
                  const SizedBox(width: CfSpace.xs),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: CfTouch.minTarget * 3,
                    ),
                    child: Text(
                      row.productName!,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: CfSpace.xs),
            if (stacked) ...<Widget>[
              amount,
              const SizedBox(height: CfSpace.xs),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final cell in cells) Expanded(child: cell),
                  ],
                ),
              ),
            ] else
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(flex: 23, child: amount),
                    for (final cell in cells)
                      Expanded(flex: 40 ~/ cells.length, child: cell),
                  ],
                ),
              ),
            if (pending != null) ...<Widget>[
              const SizedBox(height: CfSpace.xs),
              _PendingStrip(row: row),
            ],
          ],
        ),
      ),
    );
  }
}

/// 待还列：小字"待还" + 状态标签；待还（24 粗，整元省略 .00；已还清/0 用第三级文字色）；账单或未出账。
class _AmountColumn extends StatelessWidget {
  const _AmountColumn({required this.row});

  final CardLedgerRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(
      color: colors.textSecondary,
    );
    final remaining = row.remaining;
    final muted = remaining != null && remaining == 0;
    final missed = row.missedStatement;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        Wrap(
          spacing: CfSpace.xs,
          runSpacing: CfSpace.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text('待还', style: small),
            if (row.status case final status?) rowStatusBadge(status),
          ],
        ),
        if (missed != null)
          Text(
            noAmountText,
            style: CfType.amountRow.toTextStyle().copyWith(
              color: colors.textTertiary,
            ),
          )
        else
          MoneyText(
            minor: remaining,
            currency: row.currency,
            compact: true,
            semanticsPrefix: '待还',
            textAlign: TextAlign.start,
            style: CfType.amountRow.toTextStyle().copyWith(
              color: muted || remaining == null
                  ? colors.textTertiary
                  : colors.textPrimary,
            ),
          ),
        if (missed != null)
          Text(
            '${formatShortDate(missed.statementDate, row.today)} 账单未录入',
            style: small?.copyWith(color: colors.attention.fg),
          )
        else if (row.current == null)
          _inline('未出账', row.unbilled, small)
        else
          _inline('账单', row.billed, small),
      ],
    );
  }

  Widget _inline(String label, int? minor, TextStyle? style) => Wrap(
    spacing: CfSpace.xxs,
    children: <Widget>[
      ExcludeSemantics(child: Text(label, style: style)),
      MoneyText(
        minor: minor,
        currency: row.currency,
        compact: true,
        semanticsPrefix: label,
        negativeLabel: '贷方',
        negativeTone: MoneyTone.neutral,
        textAlign: TextAlign.start,
        style: style,
      ),
    ],
  );
}

/// 卡账行的状态标签（至多一个；颜色、图标、文字三者都有，没有绿色）。
StatusBadge rowStatusBadge(CardRowStatus status) => StatusBadge(
  label: status.label,
  icon: switch (status) {
    CardRowStatus.paid => Icons.approval_outlined,
    CardRowStatus.overdue => Icons.warning_amber_outlined,
    CardRowStatus.markedPaid => Icons.how_to_reg_outlined,
    CardRowStatus.partiallyPaid => Icons.timelapse,
    CardRowStatus.postedAwaitingBank => Icons.input,
    CardRowStatus.converted => Icons.call_split,
    CardRowStatus.nothingDue => Icons.remove_circle_outline,
  },
  tone: switch (status) {
    CardRowStatus.paid => NoticeTone.bank,
    CardRowStatus.overdue => NoticeTone.danger,
    CardRowStatus.partiallyPaid => NoticeTone.attention,
    _ => NoticeTone.unknown,
  },
);

/// 日期格（设计稿 .cell）：左侧一条分隔线；大字数字 + 小字说明；下面一行日期。
class _DateCell extends StatelessWidget {
  const _DateCell({required this.parts, required this.dateLine, this.color});

  /// （文字, 是否大字）。
  final List<(String, bool)> parts;
  final String dateLine;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final big = CfType.amountRow.toTextStyle().copyWith(
      color: color ?? colors.textPrimary,
    );
    final small = theme.textTheme.bodySmall?.copyWith(
      color: color ?? colors.textSecondary,
    );
    return Container(
      padding: const EdgeInsets.only(left: CfSpace.sm),
      margin: const EdgeInsets.only(left: CfSpace.xs),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: colors.divider, width: CfStroke.hairline),
        ),
      ),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  for (final (text, isBig) in parts)
                    TextSpan(text: text, style: isBig ? big : small),
                ],
              ),
            ),
            Text(
              dateLine,
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

class _StatementCellView extends StatelessWidget {
  const _StatementCellView({required this.row});

  final CardLedgerRow row;

  @override
  Widget build(BuildContext context) {
    final cell = row.statement!;
    return _DateCell(
      parts: cell.isToday
          ? const <(String, bool)>[('今天', true), ('出账', false)]
          : <(String, bool)>[('${cell.days}', true), (' 天后出账', false)],
      dateLine: formatShortDate(cell.date, row.today),
    );
  }
}

class _DueCellView extends StatelessWidget {
  const _DueCellView({required this.row});

  final CardLedgerRow row;

  @override
  Widget build(BuildContext context) {
    final colors = CardFlowColors.of(context);
    final due = row.due;
    if (due == null) {
      return const _DateCell(
        parts: <(String, bool)>[('—', true)],
        dateLine: '没有待还',
      );
    }
    final date = formatShortDate(due.date, row.today);
    switch (due.tone) {
      case DueTone.normal:
        return _DateCell(
          parts: <(String, bool)>[('${due.days}', true), (' 天后还款', false)],
          dateLine: date,
        );
      case DueTone.today:
        return _DateCell(
          parts: const <(String, bool)>[('今天', true), ('还款', false)],
          dateLine: date,
          color: colors.attention.fg,
        );
      case DueTone.overdue:
        return _DateCell(
          parts: <(String, bool)>[
            ('已逾期 ', false),
            ('${due.overdueDays}', true),
            (' 天', false),
          ],
          dateLine: '$date 到期',
          color: colors.danger.fg,
        );
      case DueTone.predicted:
        final line = row.missedStatement != null ? '$date 预计' : '下期 $date';
        if (due.days < 0) {
          return _DateCell(
            parts: <(String, bool)>[
              ('已过 ', false),
              ('${-due.days}', true),
              (' 天', false),
            ],
            dateLine: line,
            color: colors.attention.fg,
          );
        }
        return _DateCell(
          parts: due.days == 0
              ? const <(String, bool)>[('今天', true), ('还款', false)]
              : <(String, bool)>[('${due.days}', true), (' 天后还款', false)],
          dateLine: line,
          color: colors.textSecondary,
        );
    }
  }
}

/// 没有账期规则（或规则给不出账期）：两个日期格合成一个"设置账期 ›"入口（去 P-04）。
class _RuleCell extends StatelessWidget {
  const _RuleCell({required this.row});

  final CardLedgerRow row;

  @override
  Widget build(BuildContext context) {
    final colors = CardFlowColors.of(context);
    final due = row.due;
    return Container(
      padding: const EdgeInsets.only(left: CfSpace.sm),
      margin: const EdgeInsets.only(left: CfSpace.xs),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: colors.divider, width: CfStroke.hairline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          if (due != null)
            Text(
              '${formatShortDate(due.date, row.today)} 到期',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: due.tone == DueTone.overdue
                    ? colors.danger.fg
                    : colors.textSecondary,
              ),
            ),
          TextButton.icon(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              alignment: AlignmentDirectional.centerStart,
            ),
            iconAlignment: IconAlignment.end,
            onPressed: () => context.go(
              AppRoutes.accountSettings(row.creditAccountId, section: 'rule'),
            ),
            icon: const Icon(Icons.chevron_right),
            label: Text(row.ruleInvalid ? '账期规则有误' : '设置账期'),
          ),
        ],
      ),
    );
  }
}

/// 本期账单上等银行证据的还款：一步推进"银行已入账""银行确认"。
class _PendingStrip extends ConsumerWidget {
  const _PendingStrip({required this.row});

  final CardLedgerRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = row.pending!;
    final colors = CardFlowColors.of(context);
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: colors.textSecondary);
    return Container(
      padding: const EdgeInsets.only(left: CfSpace.sm),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(CfRadius.lg),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Wrap(
              spacing: CfSpace.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text('${pending.status.label} ·', style: style),
                MoneyText(
                  minor: pending.repayment.amountMinor,
                  currency: row.currency,
                  compact: true,
                  semanticsPrefix: '还款',
                  textAlign: TextAlign.start,
                  style: style,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () =>
                unawaited(advancePendingRepayment(context, ref, pending)),
            child: Text(pending.next.label),
          ),
        ],
      ),
    );
  }
}
