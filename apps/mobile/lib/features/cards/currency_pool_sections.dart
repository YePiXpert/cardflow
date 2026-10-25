import 'dart:async';

import 'package:cardflow_domain/cardflow_domain.dart' show minorDigits;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../app/widgets/confirm_dialog.dart';
import '../../app/widgets/feedback.dart';
import '../../app/widgets/money_text.dart';
import '../../app/widgets/state_views.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/card_wallet_reader.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/repository_errors.dart';
import '../../data/validation/text_rules.dart';
import 'amount_input.dart';
import 'card_formatting.dart';

Future<void> _runAndReport(
  BuildContext context,
  Future<void> Function() action,
  String success,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    showFeedback(messenger, success);
  } on RepositoryException catch (error) {
    showFeedback(messenger, error.message);
  }
}

/// P-04 币种子账户：列表、增加（只列领域包 minorDigits 的 13 种币种）、删除（主子账户不可删）。
class CurrencyAccountsSection extends ConsumerStatefulWidget {
  const CurrencyAccountsSection({super.key, required this.account});

  final AccountView account;

  @override
  ConsumerState<CurrencyAccountsSection> createState() =>
      _CurrencyAccountsSectionState();
}

class _CurrencyAccountsSectionState
    extends ConsumerState<CurrencyAccountsSection> {
  String? _toAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final existing = widget.account.currencies.map((c) => c.currency).toSet();
    final available = minorDigits.keys
        .where((code) => !existing.contains(code))
        .toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: CfSpace.xl),
      children: <Widget>[
        const SectionTitle('已启用币种'),
        for (final sub in widget.account.currencies)
          ListTile(
            title: Text(currencyLabel(sub.currency)),
            subtitle: Text(sub.row.isPrimary ? '默认币种' : '外币子账户'),
            trailing: sub.row.isPrimary
                ? null
                : IconButton(
                    tooltip: '删除${currencyLabel(sub.currency)}子账户',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final confirmed = await confirmAction(
                        context,
                        title: '删除${currencyLabel(sub.currency)}子账户？',
                        message: '删除后将移除该外币币种；已有额度记录或账期规则的子账户无法删除。',
                        confirmLabel: '删除',
                        destructive: true,
                      );
                      if (!confirmed || !context.mounted) {
                        return;
                      }
                      final repo = await ref.read(
                        creditAccountRepositoryProvider.future,
                      );
                      if (!context.mounted) {
                        return;
                      }
                      await _runAndReport(
                        context,
                        () => repo.removeCurrencyAccount(sub.row.id),
                        '已删除',
                      );
                    },
                  ),
          ),
        const SectionTitle('增加外币币种'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _toAdd,
                decoration: const InputDecoration(
                  labelText: '选择外币币种',
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<String>>[
                  for (final code in available)
                    DropdownMenuItem<String>(
                      value: code,
                      child: Text(
                        currencyLabel(code),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _toAdd = value),
              ),
              const SizedBox(height: CfSpace.sm),
              FilledButton(
                onPressed: _toAdd == null
                    ? null
                    : () async {
                        final code = _toAdd!;
                        final repo = await ref.read(
                          creditAccountRepositoryProvider.future,
                        );
                        if (!context.mounted) {
                          return;
                        }
                        await _runAndReport(
                          context,
                          () =>
                              repo.addCurrencyAccount(widget.account.id, code),
                          '已增加${currencyLabel(code)}子账户',
                        );
                        if (mounted) {
                          setState(() => _toAdd = null);
                        }
                      },
                child: const Text('增加'),
              ),
              const SizedBox(height: CfSpace.xs),
              Text(
                '账单与额度按币种子账户分别记录；不同币种不相加。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// P-04 授信池：账户所在池（池上限、池内已用、池内账户可用合计，F-23）与移出；不在池里时可
/// 加入同银行的池或新建池（单层，协议 v1 只有一层池）。
class PoolSection extends ConsumerStatefulWidget {
  const PoolSection({
    super.key,
    required this.account,
    required this.pool,
    required this.bankPools,
  });

  final AccountView account;
  final PoolView? pool;
  final List<CreditPoolRow> bankPools;

  @override
  ConsumerState<PoolSection> createState() => _PoolSectionState();
}

class _PoolSectionState extends ConsumerState<PoolSection> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _limit = TextEditingController();
  String _currency = 'CNY';
  String? _nameError;
  String? _limitError;

  @override
  void dispose() {
    _name.dispose();
    _limit.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final nameProblem = validateFreeText(
      _name.text,
      required: true,
      fieldName: '池名称',
    );
    final (limit, limitProblem) = parseAmountMinor(_limit.text, _currency);
    setState(() {
      _nameError = nameProblem;
      _limitError = limitProblem;
    });
    if (nameProblem != null || limitProblem != null) {
      return;
    }
    final pools = await ref.read(creditPoolRepositoryProvider.future);
    final accounts = await ref.read(creditAccountRepositoryProvider.future);
    if (!mounted) {
      return;
    }
    await _runAndReport(context, () async {
      final pool = await pools.create(
        bankId: widget.account.bank.id,
        name: _name.text,
        sharedLimitMinor: limit!,
        currency: _currency,
      );
      await accounts.joinPool(widget.account.id, pool.id);
    }, '已新建并加入授信池');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: colors.textSecondary,
    );
    final pool = widget.pool;
    final others = widget.bankPools
        .where((p) => p.id != widget.account.account.poolId)
        .toList();
    final currencies = widget.account.currencies
        .map((c) => c.currency)
        .toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: CfSpace.xl),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(CfSpace.md),
          child: Text('同一家银行的多张卡片共享总额度时，可加入共享授信池统一计算可用上限。', style: secondary),
        ),
        if (pool != null) ...<Widget>[
          SectionTitle('当前授信池 · ${pool.pool.name}'),
          LabeledValue(
            label: '池上限',
            value: MoneyText(
              minor: pool.pool.sharedLimitMinor,
              currency: pool.pool.currency,
              semanticsPrefix: '池上限',
            ),
          ),
          if (pool.missingSnapshots > 0)
            NoticeCard(
              icon: Icons.checklist,
              text: '还有 ${pool.missingSnapshots} 张卡片未记录额度，请补充后再计算共享可用额度。',
            )
          else ...<Widget>[
            LabeledValue(
              label: '池内已用合计',
              value: MoneyText(
                minor: pool.usedTotal,
                currency: pool.pool.currency,
                semanticsPrefix: '池内已用合计',
              ),
            ),
            LabeledValue(
              label: '共享池剩余可用',
              value: MoneyText(
                minor: pool.rawAvailable,
                currency: pool.pool.currency,
                negativeLabel: '超限',
                semanticsPrefix: '池可用',
              ),
            ),
            LabeledValue(
              label: '池内账户可用合计',
              value: MoneyText(
                minor: pool.combinedCapacity,
                currency: pool.pool.currency,
                semanticsPrefix: '池内账户可用合计',
              ),
            ),
          ],
          LabeledValue(
            label: '成员',
            value: Text(pool.members.map((m) => m.displayName).join('、')),
          ),
          Padding(
            padding: const EdgeInsets.all(CfSpace.md),
            child: OutlinedButton(
              onPressed: () async {
                final confirmed = await confirmAction(
                  context,
                  title: '移出授信池？',
                  message: '影响：本账户不再受池上限约束；池本身与其他成员不变。',
                  confirmLabel: '移出',
                );
                if (!confirmed || !context.mounted) {
                  return;
                }
                final repo = await ref.read(
                  creditAccountRepositoryProvider.future,
                );
                if (!context.mounted) {
                  return;
                }
                await _runAndReport(
                  context,
                  () => repo.leavePool(widget.account.id),
                  '已移出授信池',
                );
              },
              child: const Text('移出授信池'),
            ),
          ),
        ] else ...<Widget>[
          const SectionTitle('加入同银行的授信池'),
          if (others.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
              child: Text(
                '${widget.account.bank.name}还没有授信池。',
                style: secondary,
              ),
            ),
          for (final candidate in others)
            ListTile(
              title: Text(candidate.name),
              subtitle: Text('${currencyLabel(candidate.currency)} 池'),
              trailing: TextButton(
                onPressed: () async {
                  final repo = await ref.read(
                    creditAccountRepositoryProvider.future,
                  );
                  if (!context.mounted) {
                    return;
                  }
                  await _runAndReport(
                    context,
                    () => repo.joinPool(widget.account.id, candidate.id),
                    '已加入授信池',
                  );
                },
                child: const Text('加入'),
              ),
            ),
          const SectionTitle('新建授信池'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  controller: _name,
                  autofillHints: null,
                  decoration: InputDecoration(
                    labelText: '池名称',
                    errorText: _nameError,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: CfSpace.sm),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _currency,
                  decoration: const InputDecoration(
                    labelText: '币种（账户须有该币种子账户）',
                    border: OutlineInputBorder(),
                  ),
                  items: <DropdownMenuItem<String>>[
                    for (final code in currencies)
                      DropdownMenuItem<String>(
                        value: code,
                        child: Text(
                          currencyLabel(code),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _currency = value!),
                ),
                const SizedBox(height: CfSpace.sm),
                TextField(
                  controller: _limit,
                  autofillHints: null,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: '池上限',
                    errorText: _limitError,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: CfSpace.sm),
                FilledButton(
                  onPressed: () => unawaited(_create()),
                  child: const Text('新建并加入'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
