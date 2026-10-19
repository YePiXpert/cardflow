import 'dart:async';

import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate, Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/feedback.dart';
import '../../app/widgets/state_views.dart';
import '../../data/db/app_database.dart';
import '../../data/ids.dart';
import '../../data/mapping/cash_mapping.dart' show cashTimeZone;
import '../../data/mapping/ledger_mapping.dart' show StatementBalance;
import '../../data/repositories/cash_models.dart';
import '../../data/repositories/ledger_models.dart';
import '../../data/repositories/ledger_reader.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/repayment_repository.dart';
import '../../data/repositories/repository_errors.dart';
import '../../data/time/business_tz.dart';
import '../cards/amount_input.dart';
import '../cards/card_dialogs.dart';
import '../cash/cash_form_fields.dart';
import '../statements/ledger_formatting.dart';
import '../statements/statement_forms.dart';

/// P-06「登记还款」表单：账单（多期分配，实时合计）、金额、现金账户、方式、发起时间、预计扣款日、证据备注。
///
/// 校验（ui-spec P-06）：分配合计 ≠ 还款额时禁止保存（F-33）；超过所选账单的剩余应还时提示溢缴或分到他期；
/// 受限账户警告（R-CASH-01）；时点不晚于现在（G3）。保存后的文案是"已登记（待银行确认）"，没有"还款成功"。
class RepaymentFormPage extends ConsumerStatefulWidget {
  const RepaymentFormPage({
    super.key,
    this.accountId,
    this.statementId,
    this.currencyAccountId,
  });

  final String? accountId;
  final String? statementId;
  final String? currencyAccountId;

  static const String title = '登记还款';

  /// 保存后的轻提示（ui-spec §2"成功"）。
  static const String savedMessage = '已登记（待银行确认）';

  /// 分配合计与还款额不相等时的提示。
  static const String allocationMismatch = '分配合计须等于还款额（F-33），否则不能保存';

  @override
  ConsumerState<RepaymentFormPage> createState() => _RepaymentFormPageState();
}

class _RepaymentFormPageState extends ConsumerState<RepaymentFormPage> {
  final String _id = newUuidV4();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _time = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final Map<String, TextEditingController> _allocations =
      <String, TextEditingController>{};
  String? _sub;
  String? _cash;
  RepaymentMethod _method = RepaymentMethod.manual;
  LocalDate? _initDate;
  LocalDate? _expected;
  bool _prefilled = false;
  final Map<String, String> _errors = <String, String>{};
  String? _saveError;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in <TextEditingController>[
      _amount,
      _time,
      _note,
      ..._allocations.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _allocation(String statementId) =>
      _allocations.putIfAbsent(statementId, TextEditingController.new);

  void _prefill(LedgerData data) {
    if (_prefilled) {
      return;
    }
    _prefilled = true;
    final statement = widget.statementId == null
        ? null
        : data.statement(widget.statementId!);
    _sub =
        statement?.currencyAccountId ??
        widget.currencyAccountId ??
        CurrencyAccountField.choices(data, widget.accountId).firstOrNull?.id;
    if (statement != null) {
      final remaining = data.balances[statement.id]?.remaining ?? 0;
      if (remaining > 0) {
        final currency =
            data.currencyAccounts[statement.currencyAccountId]!.currency;
        _amount.text = amountText(remaining, currency);
        _allocation(statement.id).text = amountText(remaining, currency);
      }
    }
  }

  /// 还款额与分配（解析失败的项为 null）。
  ({int? amount, Map<String, int> allocations, bool allocationError}) _parse(
    String currency,
  ) {
    final (amount, _) = parseAmountMinor(_amount.text, currency);
    final allocations = <String, int>{};
    var error = false;
    for (final entry in _allocations.entries) {
      if (entry.value.text.trim().isEmpty) {
        continue;
      }
      final (value, e) = parseAmountMinor(entry.value.text, currency);
      if (e != null || value == null) {
        error = true;
      } else if (value > 0) {
        allocations[entry.key] = value;
      }
    }
    return (amount: amount, allocations: allocations, allocationError: error);
  }

  Future<void> _save(LedgerData data) async {
    final sub = _sub!;
    final currency = data.currencyAccounts[sub]!.currency;
    final errors = <String, String>{};
    final (amount, amountError) = parseAmountMinor(_amount.text, currency);
    if (amountError != null) {
      errors['amount'] = amountError;
    } else if (amount == 0) {
      errors['amount'] = '还款额须大于 0';
    }
    if (_cash == null) {
      errors['cashAccount'] = '请选择扣款的现金账户';
    }
    final (time, timeError) = parseHourMinute(_time.text);
    if (timeError != null) {
      errors['initiatedAt'] = timeError;
    }
    final parsed = _parse(currency);
    final sum = parsed.allocations.values.fold<int>(0, (a, b) => a + b);
    if (parsed.allocationError || amount == null || sum != amount) {
      errors['allocations'] = RepaymentFormPage.allocationMismatch;
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
    final initiated = time == null
        ? null
        : Timestamp.parse(
            timestampTextIn(
              instantAt(
                _initDate ?? data.cashToday,
                cashTimeZone,
                hour: time.$1,
                minute: time.$2,
              ),
              cashTimeZone,
            ),
          );
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(repaymentRepositoryProvider.future);
      final row = await repo.create(
        RepaymentDraft(
          currencyAccountId: sub,
          amountMinor: amount!,
          method: _method,
          allocations: parsed.allocations,
          cashAccountId: _cash,
          initiatedAt: initiated,
          expectedDebitOn: _expected ?? data.cashToday,
          evidenceNote: _note.text,
        ),
        id: _id,
      );
      showFeedback(messenger, RepaymentFormPage.savedMessage);
      if (mounted) {
        context.go(AppRoutes.repayment(row.id, accountId: widget.accountId));
      }
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
    final ledger = ref.watch(ledgerProvider);
    final cashPlan = ref.watch(cashPlanProvider);
    final guard = ledgerFormGuard(ref, ledger);
    final Widget body;
    if (guard != null) {
      body = guard;
    } else if (!cashPlan.hasValue) {
      body = cashPlan.hasError
          ? ErrorBlock(
              title: '读取失败',
              code: '${cashPlan.error.runtimeType}',
              onRetry: () => ref.invalidate(cashPlanProvider),
            )
          : const LoadingSkeleton();
    } else {
      final data = ledger.value!;
      _prefill(data);
      if (_sub == null) {
        body = const NoticeCard(
          icon: Icons.credit_card_off_outlined,
          text: '还没有信用账户：先在卡包里建卡。',
        );
      } else {
        body = _form(data, cashPlan.value!.activeAccounts);
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text(RepaymentFormPage.title)),
      body: body,
    );
  }

  Widget _form(LedgerData data, List<CashAccountRow> activeCash) {
    final sub = _sub!;
    final currency = data.currencyAccounts[sub]!.currency;
    final today = data.cashToday;
    final statements = <StatementBalance>[
      for (final s in data.statementsOf(sub))
        if (data.balances[s.id] case final b?)
          if (!b.status.isSettled) b,
    ];
    final cashChoices = <CashAccountRow>[
      for (final a in activeCash)
        if (a.currency == currency) a,
    ];
    final cash = cashChoices.where((a) => a.id == _cash).firstOrNull;
    final restricted =
        cash != null &&
        (CashAccountKind.of(cash.kind) == CashAccountKind.restricted ||
            !CashAvailability.of(cash).counted);
    final parsed = _parse(currency);
    final sum = parsed.allocations.values.fold<int>(0, (a, b) => a + b);
    final amount = parsed.amount;
    final mismatch = parsed.allocationError || amount == null || sum != amount;
    final remainingOfAllocated = <int>[
      for (final b in statements)
        if (parsed.allocations.containsKey(b.statement.id)) b.remaining,
    ].fold<int>(0, (a, b) => a + b);
    final over =
        amount != null &&
        parsed.allocations.isNotEmpty &&
        amount > remainingOfAllocated;
    return ListView(
      padding: const EdgeInsets.only(bottom: CfSpace.xl),
      children: <Widget>[
        CurrencyAccountField(
          data: data,
          value: _sub,
          creditAccountId: widget.accountId,
          onChanged: (v) => setState(() {
            _sub = v;
            _cash = null;
            for (final c in _allocations.values) {
              c.clear();
            }
          }),
        ),
        FormTextField(
          controller: _amount,
          label: '还款额',
          error: _errors['amount'],
          keyboardType: FormTextField.amountKeyboard,
          onChanged: (_) => setState(() {}),
        ),
        const SectionTitle('分配到账单'),
        if (statements.isEmpty)
          formPadded(const Text('这个账户还没有未结清的正式账单：先「录入正式账单」，再把还款分配到它。')),
        for (final b in statements) ...<Widget>[
          LedgerAmountRow(
            label:
                '${b.statement.statementDate} 账单 · 到期 ${b.statement.dueDate} · 剩余应还',
            minor: b.remaining,
            currency: currency,
          ),
          FormTextField(
            controller: _allocation(b.statement.id),
            label: '分到这期（${b.statement.statementDate}）',
            keyboardType: FormTextField.amountKeyboard,
            onChanged: (_) => setState(() {}),
          ),
        ],
        LedgerAmountRow(label: '分配合计', minor: sum, currency: currency),
        LedgerAmountRow(label: '还款额', minor: amount, currency: currency),
        if (mismatch)
          NoticeCard(
            icon: Icons.error_outline,
            tone: NoticeTone.danger,
            text:
                _errors['allocations'] ?? RepaymentFormPage.allocationMismatch,
          ),
        if (over)
          const NoticeCard(
            icon: Icons.info_outline,
            text: '还款额超过所选账单的剩余应还：多出的部分会成为溢缴款，或分到其他期。',
          ),
        ChoiceWrap<String>(
          label: '从哪个现金账户扣款（同币种）',
          values: <String>[for (final a in cashChoices) a.id],
          selected: _cash,
          labelOf: (id) {
            final a = cashChoices.firstWhere((x) => x.id == id);
            return '${a.name}（${a.currency}）';
          },
          onSelected: (v) => setState(() => _cash = v),
          error: _errors['cashAccount'],
        ),
        if (cashChoices.isEmpty)
          formPadded(const Text('没有同币种的现金账户：先在"现金与收支"里添加。')),
        if (restricted)
          const NoticeCard(
            icon: Icons.lock_outline,
            text: '这是受限资金或不可用于还款的账户：它不计入可用现金，资金日历不会用它承担这笔扣款（R-CASH-01）。',
          ),
        ChoiceWrap<RepaymentMethod>(
          label: '方式',
          values: RepaymentMethod.values,
          selected: _method,
          labelOf: (m) => m.label,
          onSelected: (m) => setState(() => _method = m),
        ),
        formPadded(
          DateField(
            label: '发起日期（${cashTimeZone.label}时间）',
            value: _initDate ?? today,
            first: today.addDays(-366),
            last: today,
            onChanged: (v) => setState(() => _initDate = v),
          ),
        ),
        FormTextField(
          controller: _time,
          label: '发起时刻（可选，HH:MM；空 = 还没发起）',
          error: _errors['initiatedAt'],
          keyboardType: TextInputType.datetime,
        ),
        formPadded(
          DateField(
            label: '预计扣款日（资金日历按它计划扣款）',
            value: _expected ?? today,
            first: today.addDays(-366),
            last: today.addDays(366),
            onChanged: (v) => setState(() => _expected = v),
          ),
        ),
        if (_errors['expectedDebitOn'] case final e?) formPadded(Text(e)),
        FormTextField(
          controller: _note,
          label: '证据备注（可选，≤200 字）',
          error: _errors['evidenceNote'],
        ),
        ledgerSaveError(_saveError),
        formPadded(
          FilledButton(
            onPressed: _saving || mismatch
                ? null
                : () => unawaited(_save(data)),
            child: Text(_saving ? '正在保存…' : '登记'),
          ),
        ),
        formPadded(const Text('登记后状态是"已登记（待银行确认）"：结清只由银行确认触发，"我已还款"不等于银行确认。')),
      ],
    );
  }
}
