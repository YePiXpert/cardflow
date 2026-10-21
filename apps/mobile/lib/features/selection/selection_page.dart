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
import '../../app/widgets/state_views.dart';
import '../../data/repositories/card_recommendation.dart';
import '../../data/repositories/card_wallet_reader.dart';
import '../../data/repositories/providers.dart';
import '../../data/time/business_tz.dart';
import '../../data/time/clock.dart';
import '../cards/amount_input.dart';
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
              const SizedBox(height: CfSpace.lg),
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
    final amountsHidden = ref.watch(amountsHiddenProvider);
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
        CfSpace.sm,
        CfSpace.md,
        CfSpace.lg,
      ),
      children: [
        CalmPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('这笔准备花多少？', style: t.headlineSmall),
              const SizedBox(height: CfSpace.lg),
              TextField(
                controller: _amount,
                autofillHints: null,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                style: t.displaySmall?.copyWith(
                  fontSize: CfType.purchaseAmount.size,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
                decoration: InputDecoration(
                  labelText: '消费金额',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  labelStyle: t.bodyMedium?.copyWith(color: c.textSecondary),
                  hintText: amountsHidden ? '••••' : '0.00',
                  hintStyle: t.displaySmall?.copyWith(
                    fontSize: CfType.purchaseAmount.size,
                    color: c.textTertiary,
                    fontWeight: FontWeight.w400,
                  ),
                  prefixText: _currency == 'CNY' ? '¥ ' : '$_currency ',
                  prefixStyle: t.titleLarge?.copyWith(color: c.textSecondary),
                  errorText: _error,
                  errorMaxLines: 3,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: CfSpace.sm,
                  ),
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
              const SizedBox(height: CfSpace.sm),
              Wrap(
                spacing: CfSpace.xs,
                runSpacing: CfSpace.xs,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _chooseDate(date, today),
                    icon: const Icon(Icons.calendar_today_outlined, size: 16),
                    label: Text(
                      date == today
                          ? '今天 · ${date.month}月${date.day}日'
                          : '${date.year}/${date.month}/${date.day}',
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: CfSpace.md,
                      ),
                      decoration: BoxDecoration(
                        color: c.surfaceRaised,
                        borderRadius: BorderRadius.circular(CfRadius.lg),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _currency == 'CNY' ? '人民币' : _currency,
                            style: t.labelLarge,
                          ),
                          const SizedBox(width: CfSpace.xs),
                          const Icon(Icons.expand_more, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CfSpace.lg),
              FilledButton(
                onPressed: _compare,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: CfSpace.md,
                    horizontal: CfSpace.md,
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('比较用卡'),
                    SizedBox(width: CfSpace.sm),
                    Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: CfSpace.lg),
        if (result == null) ...[
          if (wallet.isEmpty)
            CalmPanel(
              child: Column(
                children: [
                  const PocketIllustration(),
                  const SizedBox(height: CfSpace.sm),
                  Text('从第一张卡开始', style: t.titleMedium),
                  const SizedBox(height: CfSpace.xs),
                  Text(
                    '还没有卡片。先添加一张卡，填写可用额度和账期规则。',
                    textAlign: TextAlign.center,
                    style: t.bodyMedium?.copyWith(color: c.textSecondary),
                  ),
                  const SizedBox(height: CfSpace.md),
                  OutlinedButton.icon(
                    onPressed: () => context.go(AppRoutes.newCard),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('添加卡片'),
                  ),
                ],
              ),
            )
          else
            CalmPanel(
              child: Row(
                children: [
                  const PocketIllustration(),
                  const SizedBox(width: CfSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('卡片已就位', style: t.titleMedium),
                        const SizedBox(height: CfSpace.xs),
                        Text(
                          '填写金额，看看这次用哪张。',
                          style: t.bodyMedium?.copyWith(color: c.textSecondary),
                        ),
                        TextButton(
                          onPressed: () => context.go(AppRoutes.cards),
                          child: Text('查看 ${wallet.accounts.length} 个账户'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ] else ...[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: CfSpace.md,
            runSpacing: CfSpace.xs,
            children: [
              Text('本次比较', style: t.titleMedium),
              MoneyText(
                minor: _submitted,
                currency: _currency,
                semanticsPrefix: '消费金额',
                style: t.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: CfSpace.sm),
          if (result.eligible.isEmpty)
            CalmPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.search_off_rounded, color: c.textSecondary),
                  const SizedBox(height: CfSpace.sm),
                  const Text('暂无可推荐的卡，请查看下方原因。'),
                ],
              ),
            ),
          if (result.eligible.isNotEmpty)
            _recommended(result.eligible.first, date),
          if (result.eligible.length > 1) ...[
            const SizedBox(height: CfSpace.lg),
            Text('其他可用卡', style: t.titleMedium),
            const SizedBox(height: CfSpace.sm),
            CalmPanel(
              child: Column(
                children: [
                  for (var i = 1; i < result.eligible.length; i++) ...[
                    if (i > 1) const Divider(height: CfSpace.lg),
                    _alternative(result.eligible[i], date),
                  ],
                ],
              ),
            ),
          ],
          if (result.excluded.isNotEmpty) ...[
            const SizedBox(height: CfSpace.lg),
            Text('本次未参与推荐', style: t.titleMedium),
            const SizedBox(height: CfSpace.sm),
            CalmPanel(
              child: Column(
                children: [
                  for (var i = 0; i < result.excluded.length; i++) ...[
                    if (i > 0) const Divider(height: CfSpace.lg),
                    _alternative(result.excluded[i], date),
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

  String _range(CardRecommendation row, bool due) {
    final cycles = row.forecast!.cycles;
    final first = due ? cycles.first.dueDate : cycles.first.statementDate;
    final last = due ? cycles.last.dueDate : cycles.last.statementDate;
    return '$first${first == last ? '' : ' 至 $last'}';
  }

  Widget _recommended(CardRecommendation row, LocalDate date) {
    final c = CardFlowColors.of(context);
    final t = Theme.of(context).textTheme;
    return CalmPanel(
      featured: true,
      child: DefaultTextStyle(
        style: t.bodyMedium!.copyWith(color: c.heroText),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  color: c.heroTextSecondary,
                  size: 18,
                ),
                const SizedBox(width: CfSpace.xs),
                Text(
                  '推荐使用',
                  style: t.labelLarge?.copyWith(color: c.heroTextSecondary),
                ),
              ],
            ),
            const SizedBox(height: CfSpace.md),
            Text(
              row.title,
              style: t.headlineSmall?.copyWith(color: c.heroText),
            ),
            const SizedBox(height: CfSpace.lg),
            Text(
              '距预计还款',
              style: t.bodyMedium?.copyWith(color: c.heroTextSecondary),
            ),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${row.dueDate.differenceInDays(date)}',
                    style: t.displaySmall?.copyWith(
                      fontSize: CfType.recommendationDays.size,
                      height: 1.15,
                      fontWeight: FontWeight.w500,
                      color: c.heroText,
                    ),
                  ),
                  TextSpan(
                    text: ' 天',
                    style: t.titleMedium?.copyWith(color: c.heroTextSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: CfSpace.md),
            Text(
              '额度足够，预计还款日最晚',
              style: t.bodyMedium?.copyWith(color: c.heroTextSecondary),
            ),
            const SizedBox(height: CfSpace.lg),
            Divider(color: c.heroTextSecondary.withValues(alpha: .2)),
            const SizedBox(height: CfSpace.md),
            _fact(
              '可用额度',
              MoneyText(
                minor: row.capacity,
                currency: row.currency,
                semanticsPrefix: '可用额度',
                textAlign: TextAlign.start,
                style: t.titleMedium?.copyWith(color: c.heroText),
              ),
            ),
            const SizedBox(height: CfSpace.sm),
            _fact('预计账单日', Text(_range(row, false))),
            const SizedBox(height: CfSpace.sm),
            _fact('预计还款日', Text(_range(row, true))),
            if (row.forecast!.cycles.length > 1) ...[
              const SizedBox(height: CfSpace.sm),
              const Text('入账可能跨账期，按较早还款日比较。'),
            ],
            if (row.snapshotDate != null) ...[
              const SizedBox(height: CfSpace.sm),
              Text(
                '额度更新于 ${row.snapshotDate!.substring(0, 10)}',
                style: t.bodySmall?.copyWith(color: c.heroTextSecondary),
              ),
            ],
            if (row.stale) ...[
              const SizedBox(height: CfSpace.sm),
              const Text('额度超过 7 天未更新，请确认银行当前可用额度。'),
            ],
            const SizedBox(height: CfSpace.sm),
            TextButton(
              onPressed: () => context.go(AppRoutes.account(row.account.id)),
              style: TextButton.styleFrom(foregroundColor: c.heroText),
              child: const Text('查看卡片与更新资料'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fact(String label, Widget value) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    spacing: CfSpace.md,
    runSpacing: CfSpace.xxs,
    children: [Text(label), value],
  );
  Widget _alternative(CardRecommendation row, LocalDate date) {
    final c = CardFlowColors.of(context);
    final t = Theme.of(context).textTheme;
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
                BankBadge(bankName: row.account.bank.name),
                const SizedBox(width: CfSpace.sm),
                Expanded(child: Text(row.title, style: t.titleSmall)),
                Icon(Icons.chevron_right_rounded, color: c.textTertiary),
              ],
            ),
            const SizedBox(height: CfSpace.sm),
            if (row.eligible) ...[
              _fact(
                '距预计还款 ${row.dueDate.differenceInDays(date)} 天',
                MoneyText(
                  minor: row.capacity,
                  currency: row.currency,
                  semanticsPrefix: '可用额度',
                  textAlign: TextAlign.start,
                  style: t.bodyMedium,
                ),
              ),
              Text(
                '预计还款 ${_range(row, true)}',
                style: t.bodySmall?.copyWith(color: c.textSecondary),
              ),
            ] else
              Text(
                row.reason!,
                style: t.bodyMedium?.copyWith(color: c.textSecondary),
              ),
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
