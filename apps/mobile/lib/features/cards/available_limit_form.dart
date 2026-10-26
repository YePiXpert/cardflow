import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../app/widgets/calm_panel.dart';
import '../../app/widgets/feedback.dart';
import '../../app/widgets/workspace_bound_form.dart';
import '../../data/repositories/card_wallet_reader.dart';
import '../../data/repositories/credit_pool_repository.dart'
    show maxAmountMinor;
import '../../data/repositories/limit_snapshot_repository.dart';
import '../../data/repositories/models.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/repository_errors.dart';
import '../../data/repositories/workspace_scope.dart';
import '../../data/time/clock.dart';
import 'amount_input.dart';

Future<void> recordSimpleAvailableLimit({
  required LimitSnapshotRepository repo,
  required WorkspaceScope scope,
  required CurrencyAccountView sub,
  required LocalDate today,
  required int amount,
}) {
  final now = Timestamp.parse(scope.clock.nowText());
  final previous = sub.latestSnapshot;
  final expiry = previous?.tempExpiresOn == null
      ? null
      : LocalDate.parse(previous!.tempExpiresOn!);
  final hasActiveTemp = expiry != null && expiry >= today;
  final fixedMinor = previous?.fixedMinor ?? 0;
  final tempMinor = hasActiveTemp ? previous!.tempMinor : 0;
  final usedMinor = fixedMinor > 0
      ? (fixedMinor + tempMinor - amount).clamp(0, maxAmountMinor)
      : 0;
  return repo.record(
    LimitSnapshotDraft(
      currencyAccountId: sub.row.id,
      fixedMinor: fixedMinor,
      usedMinor: usedMinor,
      tempMinor: tempMinor,
      tempExpiresOn: hasActiveTemp ? expiry : null,
      specialMinor: previous?.specialMinor ?? 0,
      specialPurpose: previous?.specialPurpose,
      availableRawMinor: amount,
      includesHolds: true,
      source: SnapshotSource.user,
      balanceAsOf: now,
      observedAt: now,
    ),
  );
}

int? fullLimitMinor(CurrencyAccountView sub, LocalDate today) {
  final prev = sub.latestSnapshot;
  if (prev == null || prev.fixedMinor <= 0) return null;
  final expiry = prev.tempExpiresOn == null
      ? null
      : LocalDate.parse(prev.tempExpiresOn!);
  final temp = expiry != null && expiry >= today ? prev.tempMinor : 0;
  return prev.fixedMinor + temp;
}

Future<void> showQuickLimitDialog(
  BuildContext context,
  AccountView account, {
  String? initialCurrency,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      _QuickLimitDialog(account: account, initialCurrency: initialCurrency),
);

class _QuickLimitDialog extends ConsumerStatefulWidget {
  const _QuickLimitDialog({required this.account, this.initialCurrency});

  final AccountView account;
  final String? initialCurrency;

  @override
  ConsumerState<_QuickLimitDialog> createState() => _QuickLimitDialogState();
}

class _QuickLimitDialogState extends ConsumerState<_QuickLimitDialog>
    with WorkspaceBoundForm {
  final _amount = TextEditingController();
  late String _currencyId = _resolveInitialCurrencyId();
  String? _error;
  bool _saving = false;

  String _resolveInitialCurrencyId() {
    if (widget.initialCurrency != null) {
      for (final sub in widget.account.currencies) {
        if (sub.currency == widget.initialCurrency) {
          return sub.row.id;
        }
      }
    }
    return widget.account.primaryCurrency.row.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _saveAmount(
    CurrencyAccountView sub,
    int amount,
    String feedback,
  ) async {
    setState(() => _saving = true);
    try {
      final repo = await boundRepository(
        limitSnapshotRepositoryProvider.future,
      );
      final scope = await boundRepository(workspaceScopeProvider.future);
      await recordSimpleAvailableLimit(
        repo: repo,
        scope: scope,
        sub: sub,
        today: widget.account.today,
        amount: amount,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      showFeedback(messenger, feedback);
    } on RepositoryException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败，请重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final sub = widget.account.currencies.firstWhere(
      (c) => c.row.id == _currencyId,
    );
    final (amount, error) = parseAmountMinor(
      _amount.text,
      sub.currency,
      allowNegative: true,
    );
    setState(() => _error = error);
    if (error != null) return;
    await _saveAmount(sub, amount!, '已更新可用额度');
  }

  Future<void> _addRepayment() async {
    if (_saving) return;
    final sub = widget.account.currencies.firstWhere(
      (c) => c.row.id == _currencyId,
    );
    final (delta, error) = parseAmountMinor(_amount.text, sub.currency);
    final err = error ?? (delta == 0 ? '金额须大于 0' : null);
    setState(() => _error = err);
    if (err != null) return;
    final base = sub.availableToday ?? sub.capacity ?? 0;
    await _saveAmount(sub, base + delta!, '已按还款额增加可用额度');
  }

  @override
  Widget build(BuildContext context) {
    final sub = widget.account.currencies.firstWhere(
      (c) => c.row.id == _currencyId,
    );
    final fullLimit = fullLimitMinor(sub, widget.account.today);
    final canRestoreFull =
        fullLimit != null && (sub.availableToday ?? 0) < fullLimit;
    return AlertDialog(
      title: Text('${widget.account.displayName} · 更新额度'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.account.currencies.length > 1) ...[
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _currencyId,
                decoration: const InputDecoration(labelText: '币种'),
                items: [
                  for (final c in widget.account.currencies)
                    DropdownMenuItem(value: c.row.id, child: Text(c.currency)),
                ],
                onChanged: (v) => setState(() {
                  _currencyId = v!;
                  _amount.clear();
                  _error = null;
                }),
              ),
              const SizedBox(height: CfSpace.md),
            ],
            TextField(
              controller: _amount,
              autofocus: true,
              autofillHints: null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: '当前可用额度',
                prefixText: sub.currency == 'CNY' ? '¥ ' : '${sub.currency} ',
                errorText: _error,
                errorMaxLines: 3,
                helperText: '填写银行 App 当前显示的可用额度',
                helperMaxLines: 2,
              ),
            ),
            if (canRestoreFull || sub.availableToday != null) ...[
              const SizedBox(height: CfSpace.sm),
              Wrap(
                spacing: CfSpace.xs,
                runSpacing: CfSpace.xs,
                children: [
                  if (canRestoreFull)
                    OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _saveAmount(sub, fullLimit, '已恢复满额可用额度'),
                      icon: const Icon(
                        Icons.restart_alt_rounded,
                        size: CfIconSize.sm,
                      ),
                      label: const Text('恢复满额'),
                    ),
                  if (sub.availableToday != null)
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _addRepayment,
                      icon: const Icon(
                        Icons.add_circle_outline_rounded,
                        size: CfIconSize.sm,
                      ),
                      label: const Text('按还款额增加'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '正在保存…' : '保存额度'),
        ),
      ],
    );
  }
}

class AvailableLimitForm extends ConsumerStatefulWidget {
  const AvailableLimitForm({
    super.key,
    required this.account,
    required this.onDetails,
  });
  final AccountView account;
  final VoidCallback onDetails;
  @override
  ConsumerState<AvailableLimitForm> createState() => _AvailableLimitFormState();
}

class _AvailableLimitFormState extends ConsumerState<AvailableLimitForm>
    with WorkspaceBoundForm {
  final _amount = TextEditingController();
  late String _currencyId = widget.account.primaryCurrency.row.id;
  String? _error;
  bool _saving = false;
  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _saveAmount(
    CurrencyAccountView sub,
    int amount,
    String feedback,
  ) async {
    setState(() => _saving = true);
    try {
      final repo = await boundRepository(
        limitSnapshotRepositoryProvider.future,
      );
      final scope = await boundRepository(workspaceScopeProvider.future);
      await recordSimpleAvailableLimit(
        repo: repo,
        scope: scope,
        sub: sub,
        today: widget.account.today,
        amount: amount,
      );
      if (mounted) showFeedback(ScaffoldMessenger.of(context), feedback);
    } on RepositoryException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败，请重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final sub = widget.account.currencies.firstWhere(
      (c) => c.row.id == _currencyId,
    );
    final (amount, error) = parseAmountMinor(
      _amount.text,
      sub.currency,
      allowNegative: true,
    );
    setState(() => _error = error);
    if (error != null) return;
    await _saveAmount(sub, amount!, '已更新可用额度');
  }

  Future<void> _addRepayment() async {
    if (_saving) return;
    final sub = widget.account.currencies.firstWhere(
      (c) => c.row.id == _currencyId,
    );
    final (delta, error) = parseAmountMinor(_amount.text, sub.currency);
    final err = error ?? (delta == 0 ? '金额须大于 0' : null);
    setState(() => _error = err);
    if (err != null) return;
    final base = sub.availableToday ?? sub.capacity ?? 0;
    await _saveAmount(sub, base + delta!, '已按还款额增加可用额度');
  }

  @override
  Widget build(BuildContext context) {
    final sub = widget.account.currencies.firstWhere(
      (c) => c.row.id == _currencyId,
    );
    final fullLimit = fullLimitMinor(sub, widget.account.today);
    final canRestoreFull =
        fullLimit != null && (sub.availableToday ?? 0) < fullLimit;
    return ListView(
      padding: const EdgeInsets.all(CfSpace.md),
      children: [
        CalmPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.account.currencies.length > 1) ...[
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _currencyId,
                  decoration: const InputDecoration(labelText: '币种'),
                  items: [
                    for (final sub in widget.account.currencies)
                      DropdownMenuItem(
                        value: sub.row.id,
                        child: Text(sub.currency),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _currencyId = v!;
                    _amount.clear();
                    _error = null;
                  }),
                ),
                const SizedBox(height: CfSpace.md),
              ],
              TextField(
                controller: _amount,
                autofillHints: null,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: InputDecoration(
                  labelText: '当前可用额度',
                  errorText: _error,
                  helperText: '填写银行 App 当前显示的可用额度',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: CfSpace.md),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '正在保存…' : '更新额度'),
              ),
              if (canRestoreFull || sub.availableToday != null) ...[
                const SizedBox(height: CfSpace.xs),
                Wrap(
                  spacing: CfSpace.xs,
                  runSpacing: CfSpace.xs,
                  children: [
                    if (canRestoreFull)
                      OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () => _saveAmount(sub, fullLimit, '已恢复满额可用额度'),
                        icon: const Icon(
                          Icons.restart_alt_rounded,
                          size: CfIconSize.sm,
                        ),
                        label: const Text('恢复满额'),
                      ),
                    if (sub.availableToday != null)
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _addRepayment,
                        icon: const Icon(
                          Icons.add_circle_outline_rounded,
                          size: CfIconSize.sm,
                        ),
                        label: const Text('按还款额增加'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: CfSpace.sm),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            onPressed: widget.onDetails,
            child: const Text('详细记录'),
          ),
        ),
      ],
    );
  }
}
