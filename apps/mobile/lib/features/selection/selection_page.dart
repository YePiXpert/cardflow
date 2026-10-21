import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/money_text.dart';
import '../../app/widgets/state_views.dart';
import '../../data/repositories/card_recommendation.dart';
import '../../data/repositories/card_wallet_reader.dart';
import '../../data/repositories/providers.dart';
import '../../data/time/business_tz.dart';
import '../../data/time/clock.dart';
import '../cards/amount_input.dart';
import '../cards/card_dialogs.dart';

/// 工作空间变化时丢弃上一次消费输入和结果。
class SelectionPage extends ConsumerWidget {
  const SelectionPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(currentWorkspaceProvider).value?.id;
    return _SelectionForm(key: ValueKey(id));
  }
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
    final date = _date ?? today;
    final wallet = ref.watch(walletProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('这笔消费，用哪张卡')),
      body: switch (wallet) {
        AsyncData(:final value) => _content(value, date, today),
        AsyncError(:final error) => ErrorBlock(
          title: '卡片读取失败',
          code: '${error.runtimeType}',
          onRetry: () => ref.invalidate(walletProvider),
        ),
        _ => const LoadingSkeleton(),
      },
    );
  }

  Widget _content(WalletView wallet, LocalDate date, LocalDate today) {
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
      padding: const EdgeInsets.all(CfSpace.md),
      children: <Widget>[
        const Text('在额度足够的卡中，优先选择预计还款日更晚的一张。假设还款资金充足，不需要录入现金或账单。'),
        const SizedBox(height: CfSpace.md),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: '消费金额',
            errorText: _error,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {
            _submitted = null;
            _error = null;
          }),
          onSubmitted: (_) => _compare(),
        ),
        const SizedBox(height: CfSpace.md),
        DropdownButtonFormField<String>(
          key: ValueKey(_currency),
          initialValue: _currency,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '消费币种',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final c in currencies)
              DropdownMenuItem(value: c, child: Text(c)),
          ],
          onChanged: (c) => setState(() {
            _currency = c!;
            _submitted = null;
            _error = null;
          }),
        ),
        const SizedBox(height: CfSpace.md),
        DateField(
          label: '消费日期',
          value: date,
          first: today < date ? today : date,
          last: today.addDays(3650),
          onChanged: (d) {
            if (mounted) {
              setState(() {
                _date = d;
                _submitted = null;
              });
            }
          },
        ),
        const SizedBox(height: CfSpace.md),
        FilledButton(onPressed: _compare, child: const Text('比较用卡')),
        if (wallet.isEmpty) ...<Widget>[
          const SizedBox(height: CfSpace.md),
          const Text('还没有卡片。先添加一张卡，填写可用额度和账期规则。'),
          OutlinedButton(
            onPressed: () => context.go(AppRoutes.newCard),
            child: const Text('添加卡片'),
          ),
        ],
        if (result != null) ...<Widget>[
          const SizedBox(height: CfSpace.lg),
          const Text('本次比较金额'),
          MoneyText(
            minor: _submitted,
            currency: _currency,
            semanticsPrefix: '消费金额',
            textAlign: TextAlign.start,
          ),
          if (result.eligible.isEmpty) const Text('暂无可推荐的卡，请查看下方原因。'),
          for (var i = 0; i < result.eligible.length; i++)
            _resultCard(result.eligible[i], date, i == 0 ? '推荐使用' : '其他可用卡'),
          if (result.excluded.isNotEmpty) const SectionTitle('本次未参与推荐'),
          for (final row in result.excluded)
            _resultCard(row, date, row.reason!),
          const Text(
            '按已录入的额度与账期估算；实际入账、还款日期以银行为准。距预计还款的天数不代表银行承诺的免息期。比较不会记账或占用额度。',
          ),
        ],
      ],
    );
  }

  Widget _resultCard(CardRecommendation row, LocalDate date, String heading) {
    final cycles = row.forecast?.cycles;
    final first = row.forecast?.conservative;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: CfSpace.sm),
      child: Padding(
        padding: const EdgeInsets.all(CfSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(heading, style: Theme.of(context).textTheme.titleMedium),
            Text(row.title, style: Theme.of(context).textTheme.titleLarge),
            const Text('可用额度'),
            MoneyText(
              minor: row.capacity,
              currency: row.currency,
              semanticsPrefix: '可用额度',
              textAlign: TextAlign.start,
            ),
            if (row.eligible && first != null) ...<Widget>[
              Text('距预计还款 ${first.dueDate.differenceInDays(date)} 天'),
              Text(
                '预计账单日 ${first.statementDate}${cycles!.length > 1 ? ' 至 ${cycles.last.statementDate}' : ''}',
              ),
              Text(
                '预计还款日 ${first.dueDate}${cycles.length > 1 ? ' 至 ${cycles.last.dueDate}' : ''}',
              ),
              if (cycles.length > 1) const Text('入账延迟可能跨账期，按较早还款日保守比较。'),
              if (heading == '推荐使用') const Text('额度足够，预计还款日最晚；同日优先可用额度较多的卡。'),
            ],
            if (row.snapshotDate != null)
              Text('额度更新于 ${row.snapshotDate!.substring(0, 10)}'),
            if (row.stale) const Text('额度超过 7 天未更新，请确认银行当前可用额度。'),
            TextButton(
              onPressed: () => context.go(AppRoutes.account(row.account.id)),
              child: const Text('查看卡片与更新资料'),
            ),
          ],
        ),
      ),
    );
  }
}
