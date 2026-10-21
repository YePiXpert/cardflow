import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../app/widgets/feedback.dart';
import '../../app/widgets/workspace_bound_form.dart';
import '../../data/repositories/card_wallet_reader.dart';
import '../../data/repositories/limit_snapshot_repository.dart';
import '../../data/repositories/models.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/repository_errors.dart';
import '../../data/time/clock.dart';
import 'amount_input.dart';

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
    setState(() => _saving = true);
    try {
      final repo = await boundRepository(
        limitSnapshotRepositoryProvider.future,
      );
      final scope = await boundRepository(workspaceScopeProvider.future);
      final now = Timestamp.parse(scope.clock.nowText());
      final previous = sub.latestSnapshot;
      final expiry = previous?.tempExpiresOn == null
          ? null
          : LocalDate.parse(previous!.tempExpiresOn!);
      final hasActiveTemp = expiry != null && expiry >= widget.account.today;
      await repo.record(
        LimitSnapshotDraft(
          currencyAccountId: _currencyId,
          fixedMinor: 0,
          usedMinor: 0,
          tempMinor: hasActiveTemp ? previous!.tempMinor : 0,
          tempExpiresOn: hasActiveTemp ? expiry : null,
          specialMinor: previous?.specialMinor ?? 0,
          specialPurpose: previous?.specialPurpose,
          availableRawMinor: amount!,
          includesHolds: true,
          source: SnapshotSource.user,
          balanceAsOf: now,
          observedAt: now,
        ),
      );
      if (mounted) showFeedback(ScaffoldMessenger.of(context), '已更新可用额度');
    } on RepositoryException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败，请重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(CfSpace.md),
    children: [
      if (widget.account.currencies.length > 1)
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _currencyId,
          decoration: const InputDecoration(labelText: '币种'),
          items: [
            for (final sub in widget.account.currencies)
              DropdownMenuItem(value: sub.row.id, child: Text(sub.currency)),
          ],
          onChanged: (v) => setState(() {
            _currencyId = v!;
            _amount.clear();
            _error = null;
          }),
        ),
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
      const SizedBox(height: CfSpace.sm),
      const Text('更新时间自动记录。临时额度变化后，请重新更新可用额度。'),
      TextButton(onPressed: widget.onDetails, child: const Text('详细记录')),
    ],
  );
}
