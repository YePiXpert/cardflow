import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/money/amount_visibility.dart';
import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/bank_badge.dart';
import '../../app/widgets/calm_panel.dart';
import '../../app/widgets/feedback.dart';
import '../../app/widgets/money_text.dart';
import '../../app/widgets/premium.dart';
import '../../app/widgets/state_views.dart';
import '../../app/widgets/workspace_bound_form.dart';
import '../../data/repositories/card_recommendation.dart';
import '../../data/repositories/card_wallet_reader.dart';
import '../../data/repositories/providers.dart';
import '../../data/time/business_tz.dart';
import '../../data/time/clock.dart';
import '../cards/amount_input.dart';
import '../cards/available_limit_form.dart';
import '../cards/card_dialogs.dart';

class SelectionPage extends ConsumerWidget {
  const SelectionPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => _SelectionForm(
    key: ValueKey(ref.watch(currentWorkspaceProvider).value?.id),
  );
}

class _SelectionForm extends ConsumerStatefulWidget {
  const _SelectionForm({super.key});
  @override
  ConsumerState<_SelectionForm> createState() => _SelectionFormState();
}

class _SelectionFormState extends ConsumerState<_SelectionForm>
    with WorkspaceBoundForm {
  static const List<int> _feeOptions = <int>[0, 55, 58, 60, 63, 65];

  final _amount = TextEditingController();
  String _currency = 'CNY';
  LocalDate? _date;
  int? _submitted;
  int _feeBps = 0;
  bool _reverseFeeMode = false;
  bool _deducting = false;
  String? _error;
  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  static String _feeOptionLabel(int bps) => switch (bps) {
    0 => '不计费率',
    60 => '费率 0.6%',
    _ => '费率 0.$bps%',
  };

  static int _grossFromTargetNet(int targetNetMinor, int feeBps) {
    if (feeBps <= 0) return targetNetMinor;
    var gross = (targetNetMinor * 10000) ~/ (10000 - feeBps);
    while (gross - ((gross * feeBps + 5000) ~/ 10000) < targetNetMinor) {
      gross++;
    }
    while (gross > 1 &&
        (gross - 1) - (((gross - 1) * feeBps + 5000) ~/ 10000) >=
            targetNetMinor) {
      gross--;
    }
    return gross;
  }

  Future<void> _deductSwipe(
    List<(AccountView account, String currency, int amount)> items,
  ) async {
    if (_deducting || items.isEmpty) return;
    setState(() => _deducting = true);
    try {
      final repo = await boundRepository(
        limitSnapshotRepositoryProvider.future,
      );
      final scope = await boundRepository(workspaceScopeProvider.future);
      for (final (account, currency, deductMinor) in items) {
        final sub = account.currencies.firstWhere(
          (c) => c.currency == currency,
          orElse: () => account.primaryCurrency,
        );
        final current = sub.availableToday ?? sub.capacity ?? 0;
        await recordSimpleAvailableLimit(
          repo: repo,
          scope: scope,
          sub: sub,
          today: account.today,
          amount: current - deductMinor,
        );
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      setState(() {
        _submitted = null;
        _error = null;
        _amount.clear();
      });
      showFeedback(
        messenger,
        items.length == 1
            ? '已从${items.first.$1.displayName}扣减本次刷卡额度'
            : '已按组合方案扣减 ${items.length} 张卡可用额度',
      );
    } catch (_) {
      if (mounted) {
        showFeedback(ScaffoldMessenger.of(context), '扣减额度失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _deducting = false);
    }
  }

  void _compare() {
    final (minor, error) = parseAmountMinor(_amount.text, _currency);
    setState(() {
      _error = error ?? (minor == 0 ? '消费金额须大于 0' : null);
      _submitted = _error == null ? minor : null;
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(clockProvider).today(defaultBusinessTimeZone);
    final wallet = ref.watch(walletProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('这笔消费，用哪张卡'),
        actions: [
          IconButton(
            tooltip: '选卡说明',
            onPressed: _explain,
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),
      body: switch (wallet) {
        AsyncData(:final value) => _content(value, _date ?? today, today),
        AsyncError(:final error) => ErrorBlock(
          title: '卡片读取失败',
          code: '${error.runtimeType}',
          onRetry: () => ref.invalidate(walletProvider),
        ),
        _ => const LoadingSkeleton(),
      },
    );
  }

  void _explain() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(CfSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('排序规则', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: CfSpace.md),
              const Text('优先推荐可用额度充足、预计还款日最晚的卡片；预计还款日相同时，优先推荐可用额度更高的一张。'),
              const SizedBox(height: CfSpace.md),
              const Text(
                '单张卡额度不足时，自动按还款日由晚到早生成多卡拆分方案。所有日期按已录入的账单日与还款日推算，实际入账及还款日以银行账单为准。',
              ),
              const SizedBox(height: CfSpace.md),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseDate(LocalDate date, LocalDate today) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: pickerDate(date),
      firstDate: pickerDate(today < date ? today : date),
      lastDate: pickerDate(today.addDays(3650)),
    );
    if (picked != null && mounted) {
      setState(() {
        _date = fromPicker(picked);
        _submitted = null;
      });
    }
  }

  List<CardRecommendation> _uniqueByAccount(List<CardRecommendation> rows) {
    final seen = <String>{};
    return <CardRecommendation>[
      for (final row in rows)
        if (seen.add(row.account.id)) row,
    ];
  }

  String _tailText(CardRecommendation row, List<CardRecommendation> pool) {
    final tails = <String>[
      for (final r in pool)
        if (r.account.id == row.account.id) r.card.last4,
    ];
    return '尾号 ${(tails.isEmpty ? <String>[row.card.last4] : tails).join(' / ')}';
  }

  Widget? _cycleBadge(CardRecommendation row, LocalDate date) {
    final c = CardFlowColors.of(context);
    final t = Theme.of(context).textTheme;
    if (row.nextCycleHint != null) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CfSpace.xs,
          vertical: CfSpace.xxs / 2,
        ),
        decoration: BoxDecoration(
          color: c.attention.bg,
          borderRadius: BorderRadius.circular(CfRadius.pill),
        ),
        child: Text(
          '临近出账',
          style: t.labelSmall?.copyWith(
            color: c.attention.fg,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    final forecast = row.forecast;
    if (forecast == null) return null;
    final statementDays = forecast.conservative.statementDate.differenceInDays(
      date,
    );
    final dueDays = row.dueDate.differenceInDays(date);
    if (statementDays >= 24 || dueDays >= 42) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CfSpace.xs,
          vertical: CfSpace.xxs / 2,
        ),
        decoration: BoxDecoration(
          color: c.bank.bg,
          borderRadius: BorderRadius.circular(CfRadius.pill),
        ),
        child: Text(
          '黄金免息期',
          style: t.labelSmall?.copyWith(
            color: c.bank.fg,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return null;
  }

  Widget _content(WalletView wallet, LocalDate date, LocalDate today) {
    final c = CardFlowColors.of(context);
    final t = Theme.of(context).textTheme;
    final currencies = <String>{
      'CNY',
      for (final a in wallet.accounts)
        for (final s in a.currencies) s.currency,
    }.toList()..sort();
    if (!currencies.contains(_currency)) {
      _currency = 'CNY';
      _submitted = null;
    }
    final overview = wallet.isEmpty
        ? null
        : recommendCards(
            wallet: wallet,
            amount: 1,
            currency: _currency,
            on: date,
          );
    final effectiveSwipe = _submitted == null
        ? null
        : (_feeBps > 0 && _reverseFeeMode)
        ? _grossFromTargetNet(_submitted!, _feeBps)
        : _submitted!;
    final result = effectiveSwipe == null
        ? null
        : recommendCards(
            wallet: wallet,
            amount: effectiveSwipe,
            currency: _currency,
            on: date,
          );
    final overviewCards = overview == null
        ? const <CardRecommendation>[]
        : _uniqueByAccount(overview.eligible);
    final resultCards = result == null
        ? const <CardRecommendation>[]
        : _uniqueByAccount(result.eligible);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        CfSpace.md,
        CfSpace.xs,
        CfSpace.md,
        CfSpace.xl,
      ),
      children: [
        _dashboard(wallet, overview, overviewCards, date, today, currencies),
        if (result == null) ...[
          if (wallet.isEmpty)
            _emptyState()
          else if (overview != null && overviewCards.isNotEmpty) ...[
            SectionHeader(
              title: '当日选卡排行',
              trailing: _manageCardsLink(wallet.accounts.length),
            ),
            _featured(
              overviewCards.first,
              date,
              badge: '今日首选',
              tail: _tailText(overviewCards.first, overview.eligible),
            ),
            for (var i = 1; i < overviewCards.length; i++) ...[
              const SizedBox(height: CfSpace.sm),
              CalmPanel(
                child: _rankTile(
                  overviewCards[i],
                  i + 1,
                  date,
                  tail: _tailText(overviewCards[i], overview.eligible),
                ),
              ),
            ],
          ] else ...[
            SectionHeader(
              title: '选卡排行',
              trailing: _manageCardsLink(wallet.accounts.length),
            ),
            CalmPanel(
              child: Text(
                '暂无可用卡片，请先补充可用额度或账期规则。',
                style: t.bodyMedium?.copyWith(color: c.textSecondary),
              ),
            ),
          ],
        ] else ...[
          SectionHeader(
            title: '本次比较',
            trailing: MoneyText(
              minor: effectiveSwipe,
              currency: _currency,
              semanticsPrefix: '消费金额',
              style: t.titleMedium,
            ),
          ),
          if (resultCards.isEmpty) ...[
            CalmPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _iconBubble(Icons.search_off_rounded),
                  const SizedBox(height: CfSpace.sm),
                  Text('暂无可推荐的卡，请查看下方原因。', style: t.bodyLarge),
                  if (result.splitPlan.isEmpty &&
                      result.totalCapacity > 0 &&
                      result.totalCapacity < effectiveSwipe!) ...[
                    const SizedBox(height: CfSpace.sm),
                    _fact(
                      '全部可用卡合计最多可刷',
                      MoneyText(
                        minor: result.totalCapacity,
                        currency: _currency,
                        semanticsPrefix: '合计可刷额度',
                        style: t.titleMedium,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (result.splitPlan.isNotEmpty) ...[
              const SectionHeader(title: '组合用卡方案'),
              CalmPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '单张卡可用额度不足，按还款日从晚到早分 ${result.splitPlan.length} 张卡刷齐：',
                      style: t.bodyMedium?.copyWith(color: c.textSecondary),
                    ),
                    const SizedBox(height: CfSpace.sm),
                    FilledButton.tonalIcon(
                      onPressed: _deducting
                          ? null
                          : () => _deductSwipe([
                              for (final item in result.splitPlan)
                                (
                                  item.card.account,
                                  item.card.currency,
                                  item.amount,
                                ),
                            ]),
                      icon: const Icon(
                        Icons.done_all_rounded,
                        size: CfIconSize.md,
                      ),
                      label: const Text('按方案一键扣减额度'),
                    ),
                    const SizedBox(height: CfSpace.sm),
                    for (var i = 0; i < result.splitPlan.length; i++) ...[
                      if (i > 0) const Divider(height: CfSpace.lg),
                      _splitItemTile(result.splitPlan[i], i + 1, date),
                    ],
                  ],
                ),
              ),
            ],
          ],
          if (resultCards.isNotEmpty)
            _featured(
              resultCards.first,
              date,
              badge: '推荐使用',
              reason: '额度充足 · 还款最晚',
              tail: _tailText(resultCards.first, result.eligible),
              deductMinor: effectiveSwipe,
            ),
          if (resultCards.length > 1) ...[
            const SectionHeader(title: '其他可用卡'),
            for (var i = 1; i < resultCards.length; i++) ...[
              if (i > 1) const SizedBox(height: CfSpace.sm),
              CalmPanel(
                child: _rankTile(
                  resultCards[i],
                  i + 1,
                  date,
                  tail: _tailText(resultCards[i], result.eligible),
                ),
              ),
            ],
          ],
          if (result.excluded.isNotEmpty) ...[
            const SectionHeader(title: '未参与本次推荐'),
            CalmPanel(
              child: Column(
                children: [
                  for (var i = 0; i < result.excluded.length; i++) ...[
                    if (i > 0) const Divider(height: CfSpace.lg),
                    _excludedTile(result.excluded[i]),
                  ],
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  /// 紧凑型总额度概览与金额试算面板：首屏同时展示总额度、试算输入与前序推荐卡。
  Widget _dashboard(
    WalletView wallet,
    RecommendationResult? overview,
    List<CardRecommendation> eligible,
    LocalDate date,
    LocalDate today,
    List<String> currencies,
  ) {
    final c = CardFlowColors.of(context);
    final t = Theme.of(context).textTheme;
    final amountsHidden = ref.watch(amountsHiddenProvider);
    final top = eligible.isEmpty ? null : eligible.first;
    final stacked = useStackedLayout(context);
    final swipeMinor = _submitted != null && _feeBps > 0
        ? (_reverseFeeMode
              ? _grossFromTargetNet(_submitted!, _feeBps)
              : _submitted!)
        : null;
    final feeMinor = swipeMinor != null
        ? (swipeMinor * _feeBps + 5000) ~/ 10000
        : null;
    final netMinor = swipeMinor != null && feeMinor != null
        ? swipeMinor - feeMinor
        : null;

    final amountField = TextField(
      controller: _amount,
      autofillHints: null,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      style: CfType.amountInline.toTextStyle().copyWith(
        color: c.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        labelText: '消费金额',
        hintText: amountsHidden ? '••••' : '0.00',
        prefixText: _currency == 'CNY' ? '¥ ' : '$_currency ',
        errorText: _error,
        errorMaxLines: 2,
        constraints: const BoxConstraints(minHeight: CfTouch.minTarget),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: CfSpace.md,
          vertical: CfSpace.sm,
        ),
      ),
      onChanged: (_) => setState(() {
        _submitted = null;
        _error = null;
      }),
      onSubmitted: (_) => _compare(),
    );

    final compareButton = FilledButton(
      onPressed: _compare,
      child: const Text('比较用卡'),
    );

    return CalmPanel(
      padding: const EdgeInsets.all(CfSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: CfSpace.sm,
            runSpacing: CfSpace.xs,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    date == today ? '今日可用总额度' : '${monthDay(date)} 可用总额度',
                    style: t.bodySmall?.copyWith(color: c.textSecondary),
                  ),
                  const SizedBox(height: CfSpace.xxs / 2),
                  MoneyText(
                    minor: (overview?.totalCapacity ?? 0) > 0
                        ? overview!.totalCapacity
                        : null,
                    currency: _currency,
                    compact: true,
                    semanticsPrefix: '可用总额度',
                    textAlign: TextAlign.start,
                    style: CfType.amountDetail.toTextStyle().copyWith(
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
              if (eligible.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CfSpace.sm,
                    vertical: CfSpace.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: c.actionTint,
                    borderRadius: BorderRadius.circular(CfRadius.pill),
                  ),
                  child: Text(
                    top != null
                        ? '${eligible.length} 张可用 · 最长 ${top.dueDate.differenceInDays(date)} 天'
                        : '${eligible.length} 张可用',
                    style: t.labelMedium?.copyWith(color: c.action),
                  ),
                ),
            ],
          ),
          const SizedBox(height: CfSpace.sm),
          if (stacked) ...[
            amountField,
            const SizedBox(height: CfSpace.xs),
            compareButton,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: amountField),
                const SizedBox(width: CfSpace.xs),
                compareButton,
              ],
            ),
          const SizedBox(height: CfSpace.xs),
          Wrap(
            spacing: CfSpace.xs,
            runSpacing: CfSpace.xs,
            children: [
              TextButton.icon(
                onPressed: () => _chooseDate(date, today),
                style: TextButton.styleFrom(
                  backgroundColor: c.surfaceRaised,
                  foregroundColor: c.textPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: CfSpace.xs),
                ),
                icon: Icon(
                  Icons.event_rounded,
                  size: CfIconSize.sm,
                  color: c.textSecondary,
                ),
                label: Text(
                  date == today
                      ? '今天 ${monthDay(date)}'
                      : '${date.year}/${date.month}/${date.day}',
                  style: t.bodySmall?.copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '消费币种',
                initialValue: _currency,
                onSelected: (v) => setState(() {
                  _currency = v;
                  _submitted = null;
                  _error = null;
                }),
                itemBuilder: (_) => [
                  for (final v in currencies)
                    PopupMenuItem(value: v, child: Text(v)),
                ],
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: CfTouch.minTarget,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: CfSpace.xs),
                  decoration: BoxDecoration(
                    color: c.surfaceRaised,
                    borderRadius: BorderRadius.circular(CfRadius.lg),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.currency_exchange_rounded,
                        size: CfIconSize.sm,
                        color: c.textSecondary,
                      ),
                      const SizedBox(width: CfSpace.xxs),
                      Text(
                        _currency == 'CNY' ? '人民币' : _currency,
                        style: t.bodySmall?.copyWith(
                          color: c.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: CfSpace.xxs / 2),
                      Icon(
                        Icons.expand_more_rounded,
                        size: CfIconSize.sm,
                        color: c.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              PopupMenuButton<int>(
                tooltip: '费率试算',
                initialValue: _feeBps,
                onSelected: (v) => setState(() => _feeBps = v),
                itemBuilder: (_) => [
                  for (final bps in _feeOptions)
                    PopupMenuItem(
                      value: bps,
                      child: Text(_feeOptionLabel(bps)),
                    ),
                ],
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: CfTouch.minTarget,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: CfSpace.xs),
                  decoration: BoxDecoration(
                    color: _feeBps > 0 ? c.actionTint : c.surfaceRaised,
                    borderRadius: BorderRadius.circular(CfRadius.lg),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.percent_rounded,
                        size: CfIconSize.sm,
                        color: _feeBps > 0 ? c.action : c.textSecondary,
                      ),
                      const SizedBox(width: CfSpace.xxs),
                      Text(
                        _feeBps == 0 ? '费率试算' : _feeOptionLabel(_feeBps),
                        style: t.bodySmall?.copyWith(
                          color: _feeBps > 0 ? c.action : c.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: CfSpace.xxs / 2),
                      Icon(
                        Icons.expand_more_rounded,
                        size: CfIconSize.sm,
                        color: _feeBps > 0 ? c.action : c.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              if (_feeBps > 0)
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _reverseFeeMode = !_reverseFeeMode),
                  style: TextButton.styleFrom(
                    backgroundColor: _reverseFeeMode
                        ? c.actionTint
                        : c.surfaceRaised,
                    foregroundColor: _reverseFeeMode ? c.action : c.textPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: CfSpace.xs),
                  ),
                  icon: Icon(
                    Icons.swap_horiz_rounded,
                    size: CfIconSize.sm,
                    color: _reverseFeeMode ? c.action : c.textSecondary,
                  ),
                  label: Text(
                    _reverseFeeMode ? '按需到账反推' : '按刷卡额正算',
                    style: t.bodySmall?.copyWith(
                      color: _reverseFeeMode ? c.action : c.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          if (swipeMinor != null && feeMinor != null && netMinor != null) ...[
            const SizedBox(height: CfSpace.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: CfSpace.sm,
                vertical: CfSpace.xs,
              ),
              decoration: BoxDecoration(
                color: c.surfaceRaised,
                borderRadius: BorderRadius.circular(CfRadius.lg),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: CfSpace.md,
                runSpacing: CfSpace.xxs,
                children: [
                  if (_reverseFeeMode)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '应刷金额 ',
                          style: t.bodySmall?.copyWith(color: c.textSecondary),
                        ),
                        MoneyText(
                          minor: swipeMinor,
                          currency: _currency,
                          semanticsPrefix: '应刷金额',
                          textAlign: TextAlign.start,
                          style: t.bodySmall?.copyWith(
                            color: c.action,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '预计手续费 ',
                        style: t.bodySmall?.copyWith(color: c.textSecondary),
                      ),
                      MoneyText(
                        minor: feeMinor,
                        currency: _currency,
                        semanticsPrefix: '预计手续费',
                        textAlign: TextAlign.start,
                        style: t.bodySmall?.copyWith(
                          color: c.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '预计到账 ',
                        style: t.bodySmall?.copyWith(color: c.textSecondary),
                      ),
                      MoneyText(
                        minor: netMinor,
                        currency: _currency,
                        semanticsPrefix: '预计到账',
                        textAlign: TextAlign.start,
                        style: t.bodySmall?.copyWith(
                          color: c.action,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _manageCardsLink(int count) => TextButton(
    onPressed: () => context.go(AppRoutes.cards),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text('共 $count 张卡')),
        const Icon(Icons.chevron_right_rounded, size: CfIconSize.md),
      ],
    ),
  );

  Widget _iconBubble(IconData icon) {
    final c = CardFlowColors.of(context);
    return Container(
      width: CfTouch.minTarget,
      height: CfTouch.minTarget,
      decoration: BoxDecoration(color: c.actionTint, shape: BoxShape.circle),
      child: Icon(icon, color: c.action),
    );
  }

  Widget _emptyState() {
    final c = CardFlowColors.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: CfSpace.md),
      child: CalmPanel(
        padding: const EdgeInsets.all(CfSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _iconBubble(Icons.add_card_rounded),
            const SizedBox(height: CfSpace.md),
            Text('从第一张卡开始', style: t.titleMedium),
            const SizedBox(height: CfSpace.xs),
            Text(
              '添加一张信用卡，填写可用额度和账单日、还款日，即可自动比较刷哪张卡最划算。',
              style: t.bodyMedium?.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: CfSpace.md),
            FilledButton(
              onPressed: () => context.go(AppRoutes.newCard),
              child: const Text('添加卡片'),
            ),
          ],
        ),
      ),
    );
  }

  String _range(CardRecommendation row, bool due) {
    final cycles = row.forecast!.cycles;
    final first = due ? cycles.first.dueDate : cycles.first.statementDate;
    final last = due ? cycles.last.dueDate : cycles.last.statementDate;
    return '$first${first == last ? '' : ' 至 $last'}';
  }

  String _hintText(NextCycleHint hint) =>
      '再等 ${hint.waitDays} 天（${hint.swipeOn.month}月${hint.swipeOn.day}日）刷，'
      '预计还款延至 ${hint.nextDueDate}（多 ${hint.extraDays} 天）';

  String _daysText(int days, String today) => days <= 0 ? today : '$days 天';

  CurrencyAccountView? _subOf(CardRecommendation row) {
    for (final s in row.account.currencies) {
      if (s.currency == row.currency) return s;
    }
    return null;
  }

  List<Metric> _metrics(CardRecommendation row, LocalDate date, bool top) {
    final statement = row.forecast!.conservative.statementDate;
    return [
      Metric(
        label: '可用额度',
        value: MoneyText(
          minor: row.capacity,
          currency: row.currency,
          compact: true,
          semanticsPrefix: '可用额度',
          textAlign: TextAlign.start,
        ),
      ),
      Metric(
        label: '距出账',
        value: Text(_daysText(statement.differenceInDays(date), '今天')),
        caption: monthDay(statement),
      ),
      Metric(
        label: '距还款',
        value: Text('${row.dueDate.differenceInDays(date)} 天'),
        caption: monthDay(row.dueDate),
        emphasized: top,
      ),
    ];
  }

  Widget _splitItemTile(CardSplitItem item, int order, LocalDate date) {
    final c = CardFlowColors.of(context);
    final t = Theme.of(context).textTheme;
    final row = item.card;
    return InkWell(
      borderRadius: BorderRadius.circular(CfRadius.lg),
      onTap: () => context.go(AppRoutes.account(row.account.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CfSpace.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                RankDot(rank: order),
                const SizedBox(width: CfSpace.sm),
                BankBadge(bankName: row.account.bank.name),
                const SizedBox(width: CfSpace.sm),
                Expanded(child: Text(row.title, style: t.titleSmall)),
                Icon(Icons.chevron_right_rounded, color: c.textTertiary),
              ],
            ),
            const SizedBox(height: CfSpace.sm),
            _fact(
              '本卡刷',
              MoneyText(
                minor: item.amount,
                currency: row.currency,
                semanticsPrefix: '组合刷卡金额',
                textAlign: TextAlign.start,
                style: CfType.amountInline.toTextStyle().copyWith(
                  fontSize: CfType.groupTitle.size + 1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: CfSpace.xs),
            if (_submitted != null && _submitted! > 0)
              LimitBar(fraction: (item.amount / _submitted!).clamp(0, 1)),
            const SizedBox(height: CfSpace.xs),
            _fact(
              '距预计还款 ${row.dueDate.differenceInDays(date)} 天（${_range(row, true)}）',
              MoneyText(
                minor: row.capacity,
                currency: row.currency,
                semanticsPrefix: '可用额度',
                textAlign: TextAlign.start,
                style: t.bodySmall?.copyWith(color: c.textSecondary),
              ),
            ),
            if (row.nextCycleHint != null) ...[
              const SizedBox(height: CfSpace.xs),
              HintStrip(text: _hintText(row.nextCycleHint!)),
            ],
          ],
        ),
      ),
    );
  }

  /// 首选卡：单层紧凑金融卡片（银行标识 + 状态标签 + 三栏指标 + 时间轴 + 快捷操作）。
  Widget _featured(
    CardRecommendation row,
    LocalDate date, {
    required String badge,
    String? reason,
    String? tail,
    int? deductMinor,
  }) {
    final c = CardFlowColors.of(context);
    final t = Theme.of(context).textTheme;
    final frac = capacityFraction(_subOf(row));
    final cycleBadge = _cycleBadge(row, date);
    return CalmPanel(
      featured: true,
      padding: const EdgeInsets.all(CfSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const RankDot(rank: 1),
              const SizedBox(width: CfSpace.sm),
              BankBadge(bankName: row.account.bank.name),
              const SizedBox(width: CfSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: CfSpace.xs,
                      runSpacing: CfSpace.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${row.account.bank.name} · ${row.account.displayName}',
                          style: t.titleMedium,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: CfSpace.xs,
                            vertical: CfSpace.xxs / 2,
                          ),
                          decoration: BoxDecoration(
                            color: c.actionTint,
                            borderRadius: BorderRadius.circular(CfRadius.pill),
                          ),
                          child: Text(
                            badge,
                            style: t.labelSmall?.copyWith(
                              color: c.action,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        ?cycleBadge,
                      ],
                    ),
                    Text(
                      [tail ?? '尾号 ${row.card.last4}', ?reason].join(' · '),
                      style: t.bodySmall?.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (frac != null) ...[
            const SizedBox(height: CfSpace.sm),
            LimitBar(fraction: frac),
          ],
          const SizedBox(height: CfSpace.md),
          MetricRow(metrics: _metrics(row, date, true)),
          const SizedBox(height: CfSpace.md),
          SwipeTimeline(
            swipeOn: date,
            statementDate: row.forecast!.conservative.statementDate,
            dueDate: row.dueDate,
            swipeLabel: date == row.account.today ? '今天刷' : '刷卡日',
          ),
          if (row.nextCycleHint != null) ...[
            const SizedBox(height: CfSpace.sm),
            HintStrip(text: _hintText(row.nextCycleHint!)),
          ],
          if (row.forecast!.cycles.length > 1) ...[
            const SizedBox(height: CfSpace.xs),
            _fact(
              '账单日附近消费，按较早还款日比较',
              Text(_range(row, true), style: t.bodySmall),
            ),
          ],
          if (row.stale) ...[
            const SizedBox(height: CfSpace.xs),
            const HintStrip(
              icon: Icons.schedule_rounded,
              text: '额度超过 7 天未更新，请确认银行当前可用额度。',
            ),
          ],
          const SizedBox(height: CfSpace.sm),
          const Divider(height: CfSpace.md),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: CfSpace.xs,
            runSpacing: CfSpace.xxs,
            children: [
              Wrap(
                spacing: CfSpace.xs,
                runSpacing: CfSpace.xxs,
                children: [
                  if (deductMinor != null && deductMinor > 0)
                    FilledButton(
                      onPressed: _deducting
                          ? null
                          : () => _deductSwipe([
                              (row.account, row.currency, deductMinor),
                            ]),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: CfSpace.sm,
                        ),
                      ),
                      child: const Text('已刷 · 扣减额度'),
                    ),
                  TextButton(
                    onPressed: () => showQuickLimitDialog(
                      context,
                      row.account,
                      initialCurrency: row.currency,
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: c.actionTint,
                      foregroundColor: c.action,
                      padding: const EdgeInsets.symmetric(
                        horizontal: CfSpace.sm,
                      ),
                    ),
                    child: const Text('快速改额度'),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => context.go(AppRoutes.account(row.account.id)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: CfSpace.xs),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('卡片详情'),
                    Icon(Icons.chevron_right_rounded, size: CfIconSize.md),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fact(String label, Widget value) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: CfSpace.md,
    runSpacing: CfSpace.xxs,
    children: [Text(label), value],
  );

  /// 排行中的一张可用卡：序号、徽标、名称，三栏指标与跨账单日提示。
  Widget _rankTile(
    CardRecommendation row,
    int rank,
    LocalDate date, {
    String? tail,
  }) {
    final c = CardFlowColors.of(context);
    final t = Theme.of(context).textTheme;
    final cycleBadge = _cycleBadge(row, date);
    return InkWell(
      borderRadius: BorderRadius.circular(CfRadius.lg),
      onTap: () => context.go(AppRoutes.account(row.account.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              RankDot(rank: rank),
              const SizedBox(width: CfSpace.sm),
              BankBadge(bankName: row.account.bank.name),
              const SizedBox(width: CfSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: CfSpace.xs,
                      runSpacing: CfSpace.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${row.account.bank.name} · ${row.account.displayName}',
                          style: t.titleSmall,
                        ),
                        ?cycleBadge,
                      ],
                    ),
                    Text(
                      tail ?? '尾号 ${row.card.last4}',
                      style: t.bodySmall?.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '快速改额度',
                color: c.textSecondary,
                onPressed: () => showQuickLimitDialog(
                  context,
                  row.account,
                  initialCurrency: row.currency,
                ),
                icon: const Icon(Icons.edit_outlined, size: CfIconSize.md),
              ),
            ],
          ),
          const SizedBox(height: CfSpace.sm),
          MetricRow(metrics: _metrics(row, date, false)),
          if (row.nextCycleHint != null) ...[
            const SizedBox(height: CfSpace.sm),
            HintStrip(text: _hintText(row.nextCycleHint!)),
          ],
          if (row.stale) ...[
            const SizedBox(height: CfSpace.xs),
            Text('额度待更新', style: t.bodySmall?.copyWith(color: c.attention.fg)),
          ],
        ],
      ),
    );
  }

  /// 未参与推荐的卡：原因与跨账单日提示。
  Widget _excludedTile(CardRecommendation row) {
    final c = CardFlowColors.of(context);
    final t = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(CfRadius.lg),
      onTap: () => context.go(AppRoutes.account(row.account.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CfSpace.xxs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                BankBadge(bankName: row.account.bank.name),
                const SizedBox(width: CfSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.title, style: t.titleSmall),
                      Text(
                        row.reason ?? '',
                        style: t.bodySmall?.copyWith(color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.textTertiary),
              ],
            ),
            if (row.nextCycleHint != null) ...[
              const SizedBox(height: CfSpace.xs),
              HintStrip(text: _hintText(row.nextCycleHint!)),
            ],
            if (row.stale)
              Text(
                '额度待更新',
                style: t.bodySmall?.copyWith(color: c.attention.fg),
              ),
          ],
        ),
      ),
    );
  }
}
