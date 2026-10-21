import 'dart:async';

import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../app/widgets/feedback.dart';
import '../../app/widgets/money_text.dart';
import '../../app/widgets/state_views.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/card_wallet_reader.dart';
import '../../data/repositories/limit_snapshot_repository.dart';
import '../../data/repositories/models.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/repository_errors.dart';
import '../../data/time/business_tz.dart';
import '../../data/time/clock.dart';
import '../../data/validation/text_rules.dart';
import 'amount_input.dart';
import 'available_limit_form.dart';
import 'card_dialogs.dart';
import 'card_formatting.dart';

/// P-04 额度快照：表单（固定/临时/专项、已用、银行可用、是否已含预授权、来源、实际时点）+ 历史。
///
/// 校验（P-04、G1/G3）：临时额度须到期日、专项须用途；银行可用可负；实际余额时点不晚于现在。
class LimitSnapshotSection extends ConsumerStatefulWidget {
  const LimitSnapshotSection({
    super.key,
    required this.account,
    required this.history,
  });

  final AccountView account;

  /// 币种子账户 id → 快照历史（最新在前）。
  final Map<String, List<LimitSnapshotRow>> history;

  /// 记录成功的轻提示。
  static const String savedMessage = '已记录额度快照';

  @override
  ConsumerState<LimitSnapshotSection> createState() =>
      _LimitSnapshotSectionState();
}

class _LimitSnapshotSectionState extends ConsumerState<LimitSnapshotSection> {
  late String _currencyAccountId = widget.account.primaryCurrency.row.id;
  final TextEditingController _fixed = TextEditingController();
  final TextEditingController _temp = TextEditingController();
  final TextEditingController _special = TextEditingController();
  final TextEditingController _purpose = TextEditingController();
  final TextEditingController _used = TextEditingController();
  final TextEditingController _available = TextEditingController();
  final TextEditingController _holds = TextEditingController();
  final TextEditingController _time = TextEditingController();
  bool _includesHolds = true;
  SnapshotSource _source = SnapshotSource.bankApp;
  late LocalDate _asOfDate = widget.account.today;
  LocalDate? _tempExpires;
  final Map<String, String> _errors = <String, String>{};
  String? _saveError;
  bool _saving = false;
  bool _details = false;

  @override
  void initState() {
    super.initState();
    final now = ref.read(clockProvider).now();
    final local = timestampTextIn(now, widget.account.zone);
    _time.text = local.substring(11, 16);
  }

  @override
  void dispose() {
    for (final c in <TextEditingController>[
      _fixed,
      _temp,
      _special,
      _purpose,
      _used,
      _available,
      _holds,
      _time,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  CurrencyAccountView get _sub => widget.account.currencies.firstWhere(
    (c) => c.row.id == _currencyAccountId,
    orElse: () => widget.account.primaryCurrency,
  );

  Future<void> _save() async {
    final currency = _sub.currency;
    final errors = <String, String>{};
    int amount(
      String field,
      TextEditingController c, {
      bool allowNegative = false,
      bool required = true,
    }) {
      final (value, error) = parseAmountMinor(
        c.text,
        currency,
        allowNegative: allowNegative,
        required: required,
      );
      if (error != null) {
        errors[field] = error;
      }
      return value ?? 0;
    }

    final fixed = amount('fixed', _fixed);
    final temp = amount('temp', _temp, required: false);
    final special = amount('special', _special, required: false);
    final used = amount('used', _used);
    final available = amount('available', _available, allowNegative: true);
    final holds = amount('holds', _holds, required: false);
    if (temp > 0 && _tempExpires == null) {
      errors['tempExpiresOn'] = '临时额度须填写到期日';
    }
    if (special > 0) {
      final problem = validateFreeText(
        _purpose.text,
        required: true,
        fieldName: '专项额度用途',
      );
      if (problem != null) {
        errors['specialPurpose'] = problem;
      }
    }
    final timeMatch = RegExp(r'^([01][0-9]|2[0-3]):([0-5][0-9])$')
        .firstMatch(_time.text.trim());
    if (timeMatch == null) {
      errors['time'] = '时刻格式应为 HH:MM';
    }
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
      _saveError = null;
    });
    if (errors.isNotEmpty) {
      return;
    }
    final zone = widget.account.zone;
    final clock = ref.read(clockProvider);
    final asOf = instantAt(
      _asOfDate,
      zone,
      hour: int.parse(timeMatch!.group(1)!),
      minute: int.parse(timeMatch.group(2)!),
    );
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(limitSnapshotRepositoryProvider.future);
      await repo.record(
        LimitSnapshotDraft(
          currencyAccountId: _currencyAccountId,
          fixedMinor: fixed,
          tempMinor: temp,
          tempExpiresOn: temp > 0 ? _tempExpires : null,
          specialMinor: special,
          specialPurpose: special > 0 ? _purpose.text : null,
          usedMinor: used,
          availableRawMinor: available,
          holdsMinor: holds,
          includesHolds: _includesHolds,
          source: _source,
          balanceAsOf: Timestamp.parse(timestampTextIn(asOf, zone)),
          observedAt: Timestamp.parse(clock.nowText(zone)),
        ),
      );
      showFeedback(messenger, LimitSnapshotSection.savedMessage);
    } on ValidationException catch (error) {
      if (mounted) {
        setState(() {
          _errors[error.field] = error.message;
          _saveError = error.message;
        });
      }
    } on RepositoryException catch (error) {
      if (mounted) {
        setState(() => _saveError = error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_details && widget.account.pool == null) {
      return AvailableLimitForm(
        account: widget.account,
        onDetails: () => setState(() => _details = true),
      );
    }
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: colors.textSecondary,
    );
    final sub = _sub;
    final history = widget.history[sub.row.id] ?? const <LimitSnapshotRow>[];
    final today = widget.account.today;
    return ListView(
      padding: const EdgeInsets.only(bottom: CfSpace.xl),
      children: <Widget>[
        if (widget.account.currencies.length > 1)
          _padded(
            Wrap(
              spacing: CfSpace.xs,
              runSpacing: CfSpace.xs,
              children: <Widget>[
                for (final c in widget.account.currencies)
                  ChoiceChip(
                    label: Text(currencyLabel(c.currency)),
                    selected: c.row.id == sub.row.id,
                    onSelected: (_) =>
                        setState(() => _currencyAccountId = c.row.id),
                  ),
              ],
            ),
          ),
        const SectionTitle('记录新快照'),
        _padded(
          Text(
            '金额按${currencyLabel(sub.currency)}填写；银行可用可以是负数（超限）。',
            style: secondary,
          ),
        ),
        _amount(_fixed, '固定额度', 'fixed'),
        _amount(_temp, '临时额度（可选）', 'temp'),
        _padded(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              DateField(
                label: '临时额度到期日（有临时额度时必填）',
                value: _tempExpires,
                initial: today.addDays(30),
                first: LocalDate(2000, 1, 1),
                last: today.addDays(3650),
                onChanged: (value) => setState(() => _tempExpires = value),
              ),
              if (_errors['tempExpiresOn'] != null)
                Text(
                  _errors['tempExpiresOn']!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.danger.fg,
                  ),
                ),
            ],
          ),
        ),
        _amount(_special, '专项额度（可选，不用于普通消费）', 'special'),
        _text(_purpose, '专项额度用途（有专项额度时必填）', 'specialPurpose'),
        _amount(_used, '已用', 'used'),
        _amount(_available, '银行可用（银行显示的数，可为负）', 'available'),
        SwitchListTile(
          title: const Text('银行可用已扣除预授权'),
          subtitle: const Text('打开：不再重复扣减；关闭：按下面的预授权金额扣减一次'),
          value: _includesHolds,
          onChanged: (value) => setState(() => _includesHolds = value),
        ),
        _amount(_holds, '预授权金额（可选）', 'holds'),
        const SectionTitle('来源与时点'),
        _padded(
          Wrap(
            spacing: CfSpace.xs,
            runSpacing: CfSpace.xs,
            children: <Widget>[
              for (final source in <SnapshotSource>[
                SnapshotSource.bankApp,
                SnapshotSource.statement,
                SnapshotSource.user,
              ])
                ChoiceChip(
                  label: Text(source.label),
                  selected: _source == source,
                  onSelected: (_) => setState(() => _source = source),
                ),
            ],
          ),
        ),
        _padded(
          DateField(
            label: '实际余额时点：日期（不晚于今天）',
            value: _asOfDate,
            first: LocalDate(2000, 1, 1),
            last: today,
            onChanged: (value) => setState(() => _asOfDate = value),
          ),
        ),
        _text(
          _time,
          '实际余额时点：时刻（HH:MM，${describeZone(widget.account.account.businessTz)}）',
          'time',
          keyboardType: TextInputType.datetime,
        ),
        if (_saveError != null)
          NoticeCard(
            icon: Icons.error_outline,
            tone: NoticeTone.danger,
            text: '没有保存：$_saveError',
          ),
        _padded(
          FilledButton(
            onPressed: _saving ? null : () => unawaited(_save()),
            child: Text(_saving ? '正在保存…' : '记录新快照'),
          ),
        ),
        const SectionTitle('历史'),
        if (history.isEmpty) _padded(Text('还没有额度快照。', style: secondary)),
        for (final row in history)
          MergeSemantics(
            child: ListTile(
              title: Wrap(
                spacing: CfSpace.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  const Text('银行可用'),
                  MoneyText(
                    minor: row.availableRawMinor,
                    currency: sub.currency,
                    negativeLabel: '超限',
                    textAlign: TextAlign.start,
                  ),
                ],
              ),
              subtitle: Text(
                '${row.balanceAsOf.substring(0, 16).replaceFirst('T', ' ')} · '
                '${SnapshotSource.of(row.sourceKind).label} · '
                '${ConfirmationLevel.of(row.confirmationLevel).label}'
                '${row.includesHolds ? '' : ' · 未含预授权'}',
              ),
            ),
          ),
      ],
    );
  }

  Widget _padded(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: CfSpace.md,
      vertical: CfSpace.xs,
    ),
    child: child,
  );

  Widget _amount(TextEditingController c, String label, String field) => _text(
    c,
    label,
    field,
    keyboardType: const TextInputType.numberWithOptions(
      signed: true,
      decimal: true,
    ),
  );

  Widget _text(
    TextEditingController c,
    String label,
    String field, {
    TextInputType keyboardType = TextInputType.text,
  }) => _padded(
    TextField(
      controller: c,
      keyboardType: keyboardType,
      autofillHints: null,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        errorText: _errors[field],
        errorMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}
