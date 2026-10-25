import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/money/amount_visibility.dart';
import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/bank_badge.dart';
import '../../app/widgets/calm_panel.dart';
import '../../app/widgets/money_text.dart';
import '../../app/widgets/premium.dart';
import '../../app/widgets/state_views.dart';
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

class _SelectionFormState extends ConsumerState<_SelectionForm> {
  final _amount = TextEditingController();
  String _currency = 'CNY';
  LocalDate? _date;
  int? _submitted;
  String? _error;
  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
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
              Text('选卡，简单一点', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: CfSpace.md),
              const Text(
                '在额度足够的卡中，优先选择预计还款日更晚的一张。同日优先可用额度较多的卡。假设还款资金充足，不需要录入现金或账单。',
              ),
              const SizedBox(height: CfSpace.md),
              const Text(
                '按已录入的额度与账期估算，实际日期以银行为准。“距预计还款”不代表银行承诺的免息期。比较不会记账或占用额度。',
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
    final result = _submitted == null
        ? null
        : recommendCards(
            wallet: wallet,
            amount: _submitted!,
            currency: _currency,
            on: date,
          );
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        CfSpace.md,
        CfSpace.xs,
        CfSpace.md,
        CfSpace.xl,
      ),
      children: [
        _dashboard(wallet, overview, date, today, currencies),
        if (result == null) ...[
          if (wallet.isEmpty)
            _emptyState()
          else if (overview != null && overview.eligible.isNotEmpty) ...[
            SectionHeader(
              title: '当日选卡排行',
              trailing: _manageCardsLink(wallet.accounts.length),
            ),
            _featured(overview.eligible.first, date, badge: '今日首选'),
            for (var i = 1; i < overview.eligible.length; i++) ...[
              const SizedBox(height: CfSpace.sm),
              CalmPanel(child: _rankTile(overview.eligible[i], i + 1, date)),
            ],
          ] else ...[
            SectionHeader(
              title: '选卡排行',
              trailing: _manageCardsLink(wallet.accounts.length),
            ),
            CalmPanel(
              child: Text(
                '暂时没有可用的卡，请补充可用额度或账期规则。',
                style: t.bodyMedium?.copyWith(color: c.textSecondary),
              ),
            ),
          ],
        ] else ...[
          SectionHeader(
            title: '本次比较',
            trailing: MoneyText(
              minor: _submitted,
              currency: _currency,
              semanticsPrefix: '消费金额',
              style: t.titleMedium,
            ),
          ),
          if (result.eligible.isEmpty) ...[
            CalmPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _iconBubble(Icons.search_off_rounded),
                  const SizedBox(height: CfSpace.sm),
                  Text('暂无可推荐的卡，请查看下方原因。', style: t.bodyLarge),
                  if (result.splitPlan.isEmpty &&
                      result.totalCapacity > 0 &&
                      result.totalCapacity < _submitted!) ...[
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
                    for (var i = 0; i < result.splitPlan.length; i++) ...[
                      if (i > 0) const Divider(height: CfSpace.lg),
                      _splitItemTile(result.splitPlan[i], i + 1, date),
                    ],
                  ],
                ),
              ),
            ],
          ],
          if (result.eligible.isNotEmpty)
            _featured(
              result.eligible.first,
              date,
              badge: '推荐使用',
              reason: '额度足够，预计还款日最晚',
            ),
          if (result.eligible.length > 1) ...[
            const SectionHeader(title: '其他可用卡'),
            for (var i = 1; i < result.eligible.length; i++) ...[
              if (i > 1) const SizedBox(height: CfSpace.sm),
              CalmPanel(child: _rankTile(result.eligible[i], i + 1, date)),
            ],
          ],
          if (result.excluded.isNotEmpty) ...[
            const SectionHeader(title: '本次未参与推荐'),
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
        const SizedBox(height: CfSpace.lg),
        Text(
          '按额度与账期比较 · 预计日期以银行为准',
          textAlign: TextAlign.center,
          style: t.bodySmall?.copyWith(color: c.textSecondary),
        ),
      ],
    );
  }

  /// 顶部看板：可用总额度、可用卡数、最长距还款，以及金额/日期/币种的试算条。
  Widget _dashboard(
    WalletView wallet,
    RecommendationResult? overview,
    LocalDate date,
    LocalDate today,
    List<String> currencies,
  ) {
    final c = CardFlowColors.of(context);
    final t = Theme.of(context).textTheme;
    final amountsHidden = ref.watch(amountsHiddenProvider);
    final eligible = overview?.eligible ?? const <CardRecommendation>[];
    final top = eligible.isEmpty ? null : eligible.first;
    final secondary = t.bodyMedium?.copyWith(color: c.heroTextSecondary);
    final pillStyle = TextButton.styleFrom(
      foregroundColor: c.heroText,
      backgroundColor: c.heroText.withValues(alpha: .14),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
    );
    return HeroPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: CfSpace.sm,
            runSpacing: CfSpace.xs,
            children: [
              Text(
                date == today ? '今日可用总额度' : '${monthDay(date)} 可用总额度',
                style: secondary,
              ),
              if (eligible.isNotEmpty)
                HeroPill(
                  icon: Icons.credit_card_rounded,
                  label: '${eligible.length} 张可用',
                ),
            ],
          ),
          const SizedBox(height: CfSpace.xs),
          MoneyText(
            minor: (overview?.totalCapacity ?? 0) > 0
                ? overview!.totalCapacity
                : null,
            currency: _currency,
            compact: true,
            semanticsPrefix: '可用总额度',
            textAlign: TextAlign.start,
            style: CfType.amountHero.toTextStyle().copyWith(color: c.heroText),
          ),
          const SizedBox(height: CfSpace.xxs),
          Text(
            top != null
                ? '最长距还款 ${top.dueDate.differenceInDays(date)} 天 · ${top.title}'
                : wallet.isEmpty
                ? '添加卡片后，这里显示可用总额度'
                : '暂时没有可用的卡',
            style: secondary,
          ),
          const SizedBox(height: CfSpace.md),
          Divider(color: c.heroText.withValues(alpha: .18)),
          const SizedBox(height: CfSpace.xs),
          TextField(
            controller: _amount,
            autofillHints: null,
            cursorColor: c.heroText,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            style: CfType.purchaseAmount.toTextStyle().copyWith(
              color: c.heroText,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
            decoration: InputDecoration(
              labelText: '消费金额',
              floatingLabelBehavior: FloatingLabelBehavior.always,
              labelStyle: secondary,
              floatingLabelStyle: secondary,
              hintText: amountsHidden ? '••••' : '0.00',
              hintStyle: CfType.purchaseAmount.toTextStyle().copyWith(
                color: c.heroTextSecondary,
                fontWeight: FontWeight.w400,
              ),
              prefixText: _currency == 'CNY' ? '¥ ' : '$_currency ',
              prefixStyle: t.titleLarge?.copyWith(color: c.heroTextSecondary),
              contentPadding: const EdgeInsets.symmetric(vertical: CfSpace.xs),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
            onChanged: (_) => setState(() {
              _submitted = null;
              _error = null;
            }),
            onSubmitted: (_) => _compare(),
          ),
          if (_error != null) ...[
            const SizedBox(height: CfSpace.xs),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.danger.bg,
                  borderRadius: BorderRadius.circular(CfRadius.lg),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CfSpace.sm,
                    vertical: CfSpace.xxs,
                  ),
                  child: Text(
                    _error!,
                    style: t.bodySmall?.copyWith(
                      color: c.danger.fg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: CfSpace.sm),
          Wrap(
            spacing: CfSpace.xs,
            runSpacing: CfSpace.xs,
            children: [
              TextButton(
                onPressed: () => _chooseDate(date, today),
                style: pillStyle,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.event_rounded, size: CfIconSize.sm),
                    const SizedBox(width: CfSpace.xs),
                    Flexible(
                      child: Text(
                        date == today
                            ? '今天 · ${date.month}月${date.day}日'
                            : '${date.year}/${date.month}/${date.day}',
                      ),
                    ),
                  ],
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
                  padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
                  decoration: BoxDecoration(
                    color: c.heroText.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(CfRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.currency_exchange_rounded,
                        size: CfIconSize.sm,
                        color: c.heroText,
                      ),
                      const SizedBox(width: CfSpace.xs),
                      Text(
                        _currency == 'CNY' ? '人民币' : _currency,
                        style: t.labelLarge?.copyWith(color: c.heroText),
                      ),
                      const SizedBox(width: CfSpace.xxs),
                      Icon(
                        Icons.expand_more_rounded,
                        size: CfIconSize.md,
                        color: c.heroText,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CfSpace.md),
          FilledButton(
            onPressed: _compare,
            style: FilledButton.styleFrom(
              backgroundColor: c.heroText,
              foregroundColor: c.hero[1],
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(
                vertical: CfSpace.md,
                horizontal: CfSpace.md,
              ),
            ),
            child: const Text('比较用卡'),
          ),
        ],
      ),
    );
  }

  Widget _manageCardsLink(int count) => TextButton(
    onPressed: () => context.go(AppRoutes.cards),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text('已添加 $count 个账户')),
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
      padding: const EdgeInsets.only(top: CfSpace.lg),
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
              '还没有卡片。先添加一张卡，填写可用额度和账期规则。',
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

  /// 首选卡：拟物卡面 + 大字距还款天数 + 时间轴 + 操作。
  Widget _featured(
    CardRecommendation row,
    LocalDate date, {
    required String badge,
    String? reason,
  }) {
    final c = CardFlowColors.of(context);
    final t = Theme.of(context).textTheme;
    final days = row.dueDate.differenceInDays(date);
    final actionStyle = TextButton.styleFrom(
      backgroundColor: c.actionTint,
      foregroundColor: c.action,
      shape: const StadiumBorder(),
    );
    return CalmPanel(
      featured: true,
      padding: const EdgeInsets.all(CfSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BankCardFace(
            bankName: row.account.bank.name,
            subtitle: row.account.displayName,
            last4s: [row.card.last4],
            badge: badge,
            fraction: capacityFraction(_subOf(row)),
            footer: _FaceFigures(
              left: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '可用额度',
                    style: t.bodySmall?.copyWith(color: CfBankColors.mark),
                  ),
                  MoneyText(
                    minor: row.capacity,
                    currency: row.currency,
                    compact: true,
                    semanticsPrefix: '可用额度',
                    textAlign: TextAlign.start,
                    style: CfType.amountDetail.toTextStyle().copyWith(
                      color: CfBankColors.mark,
                    ),
                  ),
                ],
              ),
              right: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '距预计还款',
                    style: t.bodySmall?.copyWith(color: CfBankColors.mark),
                  ),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$days',
                          style: CfType.amountDetail.toTextStyle().copyWith(
                            color: CfBankColors.mark,
                          ),
                        ),
                        TextSpan(
                          text: ' 天',
                          style: t.titleMedium?.copyWith(
                            color: CfBankColors.mark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CfSpace.xs,
              CfSpace.md,
              CfSpace.xs,
              CfSpace.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ActionPair(
                  first: TextButton(
                    onPressed: () => showQuickLimitDialog(
                      context,
                      row.account,
                      initialCurrency: row.currency,
                    ),
                    style: actionStyle,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_rounded, size: CfIconSize.sm),
                        SizedBox(width: CfSpace.xs),
                        Flexible(child: Text('快速改额度')),
                      ],
                    ),
                  ),
                  second: TextButton(
                    onPressed: () =>
                        context.go(AppRoutes.account(row.account.id)),
                    style: actionStyle,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.credit_card_rounded, size: CfIconSize.sm),
                        SizedBox(width: CfSpace.xs),
                        Flexible(child: Text('查看卡片')),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: CfSpace.lg),
                SwipeTimeline(
                  swipeOn: date,
                  statementDate: row.forecast!.conservative.statementDate,
                  dueDate: row.dueDate,
                  swipeLabel: date == row.account.today ? '今天刷' : '刷卡日',
                ),
                if (row.nextCycleHint != null) ...[
                  const SizedBox(height: CfSpace.md),
                  HintStrip(text: _hintText(row.nextCycleHint!)),
                ],
                if (row.forecast!.cycles.length > 1) ...[
                  const SizedBox(height: CfSpace.sm),
                  _fact(
                    '入账可能跨账期，按较早还款日比较',
                    Text(_range(row, true), style: t.bodySmall),
                  ),
                ],
                if (row.stale) ...[
                  const SizedBox(height: CfSpace.sm),
                  const HintStrip(
                    icon: Icons.schedule_rounded,
                    text: '额度超过 7 天未更新，请确认银行当前可用额度。',
                  ),
                ],
                const SizedBox(height: CfSpace.md),
                Text(
                  [
                    ?reason,
                    if (row.snapshotDate != null)
                      '额度更新于 ${row.snapshotDate!.substring(0, 10)}',
                    '预计账单日 ${_range(row, false)}',
                  ].join(' · '),
                  style: t.bodySmall?.copyWith(color: c.textSecondary),
                ),
              ],
            ),
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
  Widget _rankTile(CardRecommendation row, int rank, LocalDate date) {
    final c = CardFlowColors.of(context);
    final t = Theme.of(context).textTheme;
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
                    Text(row.title, style: t.titleSmall),
                    Text(
                      row.account.displayName,
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

/// 卡面底部的两组大字：左边可用额度、右边距预计还款；文字放大时上下排列。
class _FaceFigures extends StatelessWidget {
  const _FaceFigures({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    if (useStackedLayout(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          left,
          const SizedBox(height: CfSpace.xs),
          Align(alignment: AlignmentDirectional.centerStart, child: right),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: left),
        const SizedBox(width: CfSpace.sm),
        right,
      ],
    );
  }
}
