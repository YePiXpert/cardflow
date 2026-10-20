import 'dart:async';

import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/feedback.dart';
import '../../app/widgets/money_text.dart';
import '../../app/widgets/state_views.dart';
import '../../app/widgets/workspace_bound_form.dart';
import '../../data/db/app_database.dart';
import '../../data/ids.dart';
import '../../data/mapping/domain_mapping.dart';
import '../../data/mapping/ledger_mapping.dart';
import '../../data/repositories/installment_repository.dart';
import '../../data/repositories/ledger_models.dart';
import '../../data/repositories/ledger_reader.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/repository_errors.dart';
import '../../data/repositories/statement_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../data/time/business_tz.dart';
import '../cards/amount_input.dart';
import '../cards/card_dialogs.dart';
import '../cards/card_formatting.dart';
import '../cash/cash_form_fields.dart';
import 'installment_cost.dart';
import 'ledger_formatting.dart';
import 'statement_pages.dart' show InstallmentPlanCard;

/// 关闭全屏表单：能返回就返回，否则回到 [fallback]。
void closeLedgerForm(BuildContext context, String fallback) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}

/// 保存失败的提示（表单保留，ui-spec §2"错误"）。
Widget ledgerSaveError(String? error) => error == null
    ? const SizedBox.shrink()
    : NoticeCard(
        icon: Icons.error_outline,
        tone: NoticeTone.danger,
        text: '没有保存：$error',
      );

/// 表单通用的读取失败 / 加载态。
Widget? ledgerFormGuard(WidgetRef ref, AsyncValue<LedgerData> ledger) =>
    switch (ledger) {
      AsyncError(:final error) => ErrorBlock(
        title: '读取失败',
        code: '${error.runtimeType}',
        onRetry: () => ref.invalidate(ledgerProvider),
      ),
      AsyncData() => null,
      _ => const LoadingSkeleton(),
    };

/// 币种子账户的选择（"卡 A · CNY"）。
class CurrencyAccountField extends StatelessWidget {
  const CurrencyAccountField({
    super.key,
    required this.data,
    required this.value,
    required this.onChanged,
    this.creditAccountId,
    this.error,
  });

  final LedgerData data;
  final String? value;
  final ValueChanged<String> onChanged;

  /// 只列这个信用账户的子账户（从 P-03 进入时）。
  final String? creditAccountId;
  final String? error;

  /// 可选的子账户（未删除的信用账户的全部子账户）。
  static List<CurrencyAccountRow> choices(
    LedgerData data, [
    String? creditAccountId,
  ]) => <CurrencyAccountRow>[
    for (final account in data.wallet.accounts)
      if (creditAccountId == null || account.id == creditAccountId)
        for (final c in account.currencies) c.row,
  ];

  @override
  Widget build(BuildContext context) {
    final options = choices(data, creditAccountId);
    return ChoiceWrap<String>(
      label: '账户',
      values: <String>[for (final c in options) c.id],
      selected: value,
      labelOf: (id) =>
          '${data.accountName(id)}（${data.currencyAccounts[id]!.currency}）',
      onSelected: onChanged,
      error: error,
    );
  }
}

/// 一组金额输入的控制器（账单要素）。
final class _FigureFields {
  _FigureFields();

  final TextEditingController newBalance = TextEditingController();
  final TextEditingController minDue = TextEditingController();
  final TextEditingController previous = TextEditingController();
  final TextEditingController payments = TextEditingController();
  final TextEditingController credits = TextEditingController();
  final TextEditingController fees = TextEditingController();
  final TextEditingController interest = TextEditingController();
  final TextEditingController installment = TextEditingController();
  final TextEditingController creditBalance = TextEditingController();

  List<TextEditingController> get all => <TextEditingController>[
    newBalance,
    minDue,
    previous,
    payments,
    credits,
    fees,
    interest,
    installment,
    creditBalance,
  ];

  void dispose() {
    for (final c in all) {
      c.dispose();
    }
  }

  void fill(StatementFigures f, String currency) {
    String text(int? v) => v == null ? '' : amountText(v, currency);
    newBalance.text = text(f.newBalanceMinor);
    minDue.text = text(f.minDueMinor);
    previous.text = text(f.previousBalanceMinor);
    payments.text = text(f.paymentsMinor);
    credits.text = text(f.creditsMinor);
    fees.text = text(f.feesMinor);
    interest.text = text(f.interestMinor);
    installment.text = text(f.installmentDueMinor);
    creditBalance.text = text(f.creditBalanceMinor);
  }

  /// 解析；有错时写进 [errors] 并返回 null。
  StatementFigures? parse(String currency, Map<String, String> errors) {
    int? read(
      TextEditingController c,
      String field, {
      bool required = false,
      bool signed = false,
    }) {
      final (value, error) = parseAmountMinor(
        c.text,
        currency,
        allowNegative: signed,
        required: required,
      );
      if (error != null) {
        errors[field] = error;
      }
      return value;
    }

    final figures = (
      newBalance: read(newBalance, 'newBalance', required: true, signed: true),
      minDue: read(minDue, 'minDue'),
      previous: read(previous, 'previousBalance', signed: true),
      payments: read(payments, 'payments'),
      credits: read(credits, 'credits'),
      fees: read(fees, 'fees'),
      interest: read(interest, 'interest'),
      installment: read(installment, 'installmentDue'),
      creditBalance: read(creditBalance, 'creditBalance'),
    );
    if (errors.isNotEmpty || figures.newBalance == null) {
      return null;
    }
    return StatementFigures(
      newBalanceMinor: figures.newBalance!,
      minDueMinor: figures.minDue,
      previousBalanceMinor: figures.previous,
      paymentsMinor: figures.payments,
      creditsMinor: figures.credits,
      feesMinor: figures.fees,
      interestMinor: figures.interest,
      installmentDueMinor: figures.installment,
      creditBalanceMinor: figures.creditBalance,
    );
  }

  List<Widget> widgets(Map<String, String> errors) => <Widget>[
    FormTextField(
      controller: newBalance,
      label: '本期应还（新余额，必填；溢缴时填负数）',
      error: errors['newBalance'],
      keyboardType: FormTextField.amountKeyboard,
    ),
    FormTextField(
      controller: minDue,
      label: '最低还款额（来源未含时留空）',
      error: errors['minDue'],
      keyboardType: FormTextField.amountKeyboard,
    ),
    FormTextField(
      controller: previous,
      label: '上期余额（可负）',
      error: errors['previousBalance'],
      keyboardType: FormTextField.amountKeyboard,
    ),
    FormTextField(
      controller: payments,
      label: '本期还款',
      error: errors['payments'],
      keyboardType: FormTextField.amountKeyboard,
    ),
    FormTextField(
      controller: credits,
      label: '退款与贷记',
      error: errors['credits'],
      keyboardType: FormTextField.amountKeyboard,
    ),
    FormTextField(
      controller: fees,
      label: '费用（含年费）',
      error: errors['fees'],
      keyboardType: FormTextField.amountKeyboard,
    ),
    FormTextField(
      controller: interest,
      label: '利息',
      error: errors['interest'],
      keyboardType: FormTextField.amountKeyboard,
    ),
    FormTextField(
      controller: installment,
      label: '分期应还（本期本金 + 手续费）',
      error: errors['installmentDue'],
      keyboardType: FormTextField.amountKeyboard,
    ),
    FormTextField(
      controller: creditBalance,
      label: '贷方余额（溢缴款）',
      error: errors['creditBalance'],
      keyboardType: FormTextField.amountKeyboard,
    ),
    formPadded(const Text('留空 = 来源未含此项（不当 0）。')),
  ];
}

/// P-05「录入正式账单」：手工录入要素作为 v1（账单日不晚于今天、到期晚于账单日；同一账户同一账单日只有
/// 一份，F-21）。
class StatementEntryPage extends ConsumerStatefulWidget {
  const StatementEntryPage({super.key, this.accountId, this.currencyAccountId});

  final String? accountId;
  final String? currencyAccountId;

  static const String title = '录入正式账单';

  @override
  ConsumerState<StatementEntryPage> createState() => _StatementEntryPageState();
}

class _StatementEntryPageState extends ConsumerState<StatementEntryPage>
    with WorkspaceBoundForm {
  final String _id = newUuidV4();
  final _FigureFields _fields = _FigureFields();
  late String? _sub = widget.currencyAccountId;
  LocalDate? _statementDate;
  LocalDate? _dueDate;
  final Map<String, String> _errors = <String, String>{};
  String? _saveError;
  bool _saving = false;

  @override
  void dispose() {
    _fields.dispose();
    super.dispose();
  }

  Future<void> _save(LedgerData data) async {
    final errors = <String, String>{};
    final sub = _sub;
    if (sub == null) {
      errors['account'] = '请选择账户';
    }
    if (_statementDate == null) {
      errors['statementDate'] = '请选择账单日';
    }
    if (_dueDate == null) {
      errors['dueDate'] = '请选择到期还款日';
    }
    final currency = sub == null ? 'CNY' : data.currencyAccounts[sub]!.currency;
    final figures = _fields.parse(currency, errors);
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
      _saveError = null;
    });
    if (errors.isNotEmpty || figures == null) {
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await boundRepository(statementRepositoryProvider.future);
      final row = await repo.recordIssued(
        StatementEntryDraft(
          currencyAccountId: sub!,
          statementDate: _statementDate!,
          dueDate: _dueDate!,
          figures: figures,
        ),
        id: _id,
      );
      showFeedback(messenger, '已录入 v1（你已确认）');
      if (mounted) {
        context.go(AppRoutes.statement(row.id, accountId: widget.accountId));
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
    final guard = ledgerFormGuard(ref, ledger);
    final Widget body;
    if (guard != null) {
      body = guard;
    } else {
      final data = ledger.value!;
      final options = CurrencyAccountField.choices(data, widget.accountId);
      if (options.isEmpty) {
        body = const NoticeCard(
          icon: Icons.credit_card_off_outlined,
          text: '还没有信用账户：先在卡包里建卡。',
        );
      } else {
        _sub ??= options.first.id;
        final today = data.todayByCurrencyAccount[_sub] ?? data.cashToday;
        body = ListView(
          padding: const EdgeInsets.only(bottom: CfSpace.xl),
          children: <Widget>[
            CurrencyAccountField(
              data: data,
              value: _sub,
              creditAccountId: widget.accountId,
              error: _errors['account'],
              onChanged: (v) => setState(() => _sub = v),
            ),
            formPadded(
              DateField(
                label: '账单日（不晚于今天）',
                value: _statementDate,
                first: today.addDays(-731),
                last: today,
                onChanged: (v) => setState(() => _statementDate = v),
              ),
            ),
            if (_errors['statementDate'] case final e?) formPadded(Text(e)),
            formPadded(
              DateField(
                label: '到期还款日（晚于账单日）',
                value: _dueDate,
                first: (_statementDate ?? today.addDays(-731)).addDays(1),
                last: today.addDays(366),
                initial: _statementDate?.addDays(20),
                onChanged: (v) => setState(() => _dueDate = v),
              ),
            ),
            if (_errors['dueDate'] case final e?) formPadded(Text(e)),
            ..._fields.widgets(_errors),
            ledgerSaveError(_saveError),
            formPadded(
              FilledButton(
                onPressed: _saving ? null : () => unawaited(_save(data)),
                child: Text(_saving ? '正在保存…' : '保存为 v1'),
              ),
            ),
          ],
        );
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text(StatementEntryPage.title)),
      body: body,
    );
  }
}

/// P-05「人工修正」：新版本（来源"人工修正"），理由必填，原值保留可查（R-STMT-07）。
class StatementCorrectionPage extends ConsumerStatefulWidget {
  const StatementCorrectionPage({
    super.key,
    required this.statementId,
    this.accountId,
  });

  final String statementId;
  final String? accountId;

  static const String title = '人工修正';

  @override
  ConsumerState<StatementCorrectionPage> createState() =>
      _StatementCorrectionPageState();
}

class _StatementCorrectionPageState
    extends ConsumerState<StatementCorrectionPage>
    with WorkspaceBoundForm {
  final _FigureFields _fields = _FigureFields();
  final TextEditingController _reason = TextEditingController();
  LocalDate? _dueDate;
  bool _filled = false;
  final Map<String, String> _errors = <String, String>{};
  String? _saveError;
  bool _saving = false;

  @override
  void dispose() {
    _fields.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save(String currency) async {
    final errors = <String, String>{};
    final figures = _fields.parse(currency, errors);
    if (_reason.text.trim().isEmpty) {
      errors['reason'] = '请填写修正理由';
    }
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
      _saveError = null;
    });
    if (errors.isNotEmpty || figures == null) {
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await boundRepository(statementRepositoryProvider.future);
      final version = await repo.correct(
        widget.statementId,
        figures: figures,
        reason: _reason.text,
        dueDate: _dueDate,
      );
      showFeedback(messenger, '已生成 v${version.versionNo}，原值保留');
      if (mounted) {
        closeLedgerForm(
          context,
          AppRoutes.statement(widget.statementId, accountId: widget.accountId),
        );
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
    final guard = ledgerFormGuard(ref, ledger);
    final Widget body;
    if (guard != null) {
      body = guard;
    } else {
      final data = ledger.value!;
      final s = data.statement(widget.statementId);
      if (s == null) {
        body = ErrorBlock(
          title: '已不存在',
          detail: '这期账单不在当前空间里。',
          onRetry: () =>
              context.go(AppRoutes.statements(accountId: widget.accountId)),
          retryLabel: '回到账单中心',
        );
      } else {
        final current = data.versions[s.id]!.last;
        final currency = data.currencyAccounts[s.currencyAccountId]!.currency;
        if (!_filled) {
          _filled = true;
          _fields.fill(StatementFigures.of(current), currency);
          _dueDate = LocalDate.parse(s.dueDate);
        }
        final today = data.todayByCurrencyAccount[s.currencyAccountId]!;
        body = ListView(
          padding: const EdgeInsets.only(bottom: CfSpace.xl),
          children: <Widget>[
            NoticeCard(
              icon: Icons.history,
              tone: NoticeTone.unknown,
              text:
                  '${statementTitle(data, s)}：当前是 v${current.versionNo}。修正会生成 v${current.versionNo + 1}，原值保留可查。',
            ),
            formPadded(
              DateField(
                label: '到期还款日',
                value: _dueDate,
                first: LocalDate.parse(s.statementDate).addDays(1),
                last: today.addDays(366),
                onChanged: (v) => setState(() => _dueDate = v),
              ),
            ),
            ..._fields.widgets(_errors),
            FormTextField(
              controller: _reason,
              label: '修正理由（必填，≤200 字）',
              error: _errors['reason'],
            ),
            ledgerSaveError(_saveError),
            formPadded(
              FilledButton(
                onPressed: _saving ? null : () => unawaited(_save(currency)),
                child: Text(_saving ? '正在保存…' : '生成新版本'),
              ),
            ),
          ],
        );
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text(StatementCorrectionPage.title)),
      body: body,
    );
  }
}

/// P-05「记一笔」：账户、类型、金额、交易时间与精度（时刻可空）、入账日（可空：按入账延迟给出可能账期）、
/// 卡片、商户、分类（G1~G3）。退款进入"退款待核对"。
class TransactionFormPage extends ConsumerStatefulWidget {
  const TransactionFormPage({
    super.key,
    this.accountId,
    this.currencyAccountId,
  });

  final String? accountId;
  final String? currencyAccountId;

  static const String title = '记一笔';

  @override
  ConsumerState<TransactionFormPage> createState() =>
      _TransactionFormPageState();
}

class _TransactionFormPageState extends ConsumerState<TransactionFormPage>
    with WorkspaceBoundForm {
  final String _id = newUuidV4();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _time = TextEditingController();
  final TextEditingController _merchant = TextEditingController();
  final TextEditingController _category = TextEditingController();
  late String? _sub = widget.currencyAccountId;
  TxnType _type = TxnType.purchase;

  /// 转账/取现与调整的方向：true = 增加欠款。
  bool _increase = true;
  LocalDate? _date;
  bool _postedKnown = true;
  LocalDate? _posted;
  String? _card;
  final Map<String, String> _errors = <String, String>{};
  String? _saveError;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in <TextEditingController>[
      _amount,
      _time,
      _merchant,
      _category,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(LedgerData data) async {
    final errors = <String, String>{};
    final sub = _sub;
    if (sub == null) {
      errors['account'] = '请选择账户';
    }
    final currency = sub == null ? 'CNY' : data.currencyAccounts[sub]!.currency;
    final (amount, amountError) = parseAmountMinor(_amount.text, currency);
    if (amountError != null) {
      errors['amount'] = amountError;
    } else if (amount == 0) {
      errors['amount'] = '金额须大于 0';
    }
    final (time, timeError) = parseHourMinute(_time.text);
    if (timeError != null) {
      errors['txnAt'] = timeError;
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
    final zone = data.accountOf(sub!)!.zone;
    final today = data.todayByCurrencyAccount[sub]!;
    final date = _date ?? today;
    final sign = switch (_type.sign) {
      0 => _increase ? 1 : -1,
      final s => s,
    };
    final at = Timestamp.parse(
      timestampTextIn(
        instantAt(date, zone, hour: time?.$1 ?? 0, minute: time?.$2 ?? 0),
        zone,
      ),
    );
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await boundRepository(transactionRepositoryProvider.future);
      await repo.create(
        TransactionDraft(
          currencyAccountId: sub,
          type: _type,
          amountMinor: sign * amount!,
          txnAt: at,
          precision: time == null
              ? TxnTimePrecision.date
              : TxnTimePrecision.datetime,
          postedOn: _postedKnown ? (_posted ?? date) : null,
          cardId: _card,
          merchant: _merchant.text,
          category: _category.text,
        ),
        id: _id,
      );
      showFeedback(
        messenger,
        _type == TxnType.refund ? '已记一笔：退款待核对（应还不变）' : '已记一笔（你已确认）',
      );
      if (mounted) {
        closeLedgerForm(
          context,
          AppRoutes.statements(accountId: widget.accountId),
        );
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
    final guard = ledgerFormGuard(ref, ledger);
    final Widget body;
    if (guard != null) {
      body = guard;
    } else {
      final data = ledger.value!;
      final options = CurrencyAccountField.choices(data, widget.accountId);
      if (options.isEmpty) {
        body = const NoticeCard(
          icon: Icons.credit_card_off_outlined,
          text: '还没有信用账户：先在卡包里建卡。',
        );
      } else {
        _sub ??= options.first.id;
        final account = data.accountOf(_sub!)!;
        final today = data.todayByCurrencyAccount[_sub]!;
        final cards = account.cards;
        body = ListView(
          padding: const EdgeInsets.only(bottom: CfSpace.xl),
          children: <Widget>[
            CurrencyAccountField(
              data: data,
              value: _sub,
              creditAccountId: widget.accountId,
              error: _errors['account'],
              onChanged: (v) => setState(() {
                _sub = v;
                _card = null;
              }),
            ),
            ChoiceWrap<TxnType>(
              label: '类型',
              values: TxnType.manualChoices,
              selected: _type,
              labelOf: (t) => t.label,
              onSelected: (t) => setState(() => _type = t),
            ),
            if (_type.sign == 0)
              ChoiceWrap<bool>(
                label: '方向',
                values: const <bool>[true, false],
                selected: _increase,
                labelOf: (v) => v ? '增加欠款' : '减少欠款（贷记）',
                onSelected: (v) => setState(() => _increase = v),
              ),
            if (_type == TxnType.repayment)
              formPadded(
                const Text('还款入账只用于核对银行记录：负债按「登记还款」核销，没有对应登记时生成"未匹配的还款"。'),
              ),
            FormTextField(
              controller: _amount,
              label: '金额（填正数）',
              error: _errors['amount'],
              keyboardType: FormTextField.amountKeyboard,
            ),
            formPadded(
              DateField(
                label: '交易日期（${account.zone.label}时间，不晚于今天）',
                value: _date ?? today,
                first: today.addDays(-731),
                last: today,
                onChanged: (v) => setState(() => _date = v),
              ),
            ),
            FormTextField(
              controller: _time,
              label: '交易时刻（可选，HH:MM；空 = 只知道日期）',
              error: _errors['txnAt'],
              keyboardType: TextInputType.datetime,
            ),
            ChoiceWrap<bool>(
              label: '入账日',
              values: const <bool>[true, false],
              selected: _postedKnown,
              labelOf: (v) => v ? '已知' : '未知（按入账延迟给出可能账期）',
              onSelected: (v) => setState(() => _postedKnown = v),
            ),
            if (_postedKnown)
              formPadded(
                DateField(
                  label: '入账日（不早于交易日、不晚于今天）',
                  value: _posted ?? _date ?? today,
                  first: _date ?? today.addDays(-731),
                  last: today,
                  onChanged: (v) => setState(() => _posted = v),
                ),
              ),
            if (_errors['postedOn'] case final e?) formPadded(Text(e)),
            ChoiceWrap<String>(
              label: '卡片（可选）',
              values: <String>['', for (final c in cards) c.id],
              selected: _card ?? '',
              labelOf: (id) => id.isEmpty
                  ? '不指定'
                  : cardSummary(cards.firstWhere((c) => c.id == id)),
              onSelected: (v) => setState(() => _card = v.isEmpty ? null : v),
              error: _errors['card'],
            ),
            FormTextField(
              controller: _merchant,
              label: '商户（可选，≤20 字）',
              error: _errors['merchant'],
            ),
            FormTextField(
              controller: _category,
              label: '分类（可选，≤20 字）',
              error: _errors['category'],
            ),
            ledgerSaveError(_saveError),
            formPadded(
              FilledButton(
                onPressed: _saving ? null : () => unawaited(_save(data)),
                child: Text(_saving ? '正在保存…' : '保存'),
              ),
            ),
          ],
        );
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text(TransactionFormPage.title)),
      body: body,
    );
  }
}

/// 转分期（R-STMT-10）：期数、每期费率（%）、收费方式、尾差策略、首期账单日；预览每期本金与费用、名义与实际
/// 年化（F-36/F-37，领域包 installment.dart）。拆分与名义年化当场算；实际年化（有理数 IRR）改动停下
/// [installmentCostDebounce] 之后在后台 isolate 里算（审查 R-04：界面线程上不做 IRR），算好之前显示"计算中"。
class InstallmentFormPage extends ConsumerStatefulWidget {
  const InstallmentFormPage({
    super.key,
    required this.transactionId,
    this.accountId,
  });

  final String transactionId;
  final String? accountId;

  static const String title = '转分期';

  @override
  ConsumerState<InstallmentFormPage> createState() =>
      _InstallmentFormPageState();
}

class _InstallmentFormPageState extends ConsumerState<InstallmentFormPage>
    with WorkspaceBoundForm {
  final String _id = newUuidV4();
  final TextEditingController _periods = TextEditingController(text: '12');
  final TextEditingController _rate = TextEditingController();
  InstallmentFeeMode _feeMode = InstallmentFeeMode.perPeriod;
  RemainderTo _remainder = RemainderTo.last;
  LocalDate? _first;
  final Map<String, String> _errors = <String, String>{};
  String? _saveError;
  bool _saving = false;

  /// 实际年化的去抖计时器与最近一次请求（只认最后一次请求的结果）。
  Timer? _costTimer;
  int _costRequest = 0;

  /// 算好的成本与它对应的条款（[_termsKey]）；条款变了就不再显示旧结果。
  InstallmentCost? _cost;
  String? _costKey;
  bool _costFailed = false;

  @override
  void dispose() {
    _costTimer?.cancel();
    _periods.dispose();
    _rate.dispose();
    super.dispose();
  }

  /// 条款的签名（期数、费率原文、收费方式、尾差）。
  String _termsKey() =>
      '${_periods.text.trim()}|${_rate.text.trim()}|${_feeMode.code}|${_remainder.code}';

  /// 条款变了：预览当场重画；实际年化等停下 [installmentCostDebounce] 之后再算。
  void _termsChanged() {
    setState(() {});
    _costTimer?.cancel();
    _costTimer = Timer(
      installmentCostDebounce,
      () => unawaited(_computeCost()),
    );
  }

  Future<void> _computeCost() async {
    final txn = ref
        .read(ledgerProvider)
        .value
        ?.transaction(widget.transactionId);
    final terms = _terms();
    if (txn == null || terms == null) {
      return;
    }
    final key = _termsKey();
    final request = ++_costRequest;
    final input = InstallmentCostInput(
      principalMinor: txn.amountMinor,
      perPeriodRate: terms.$2,
      periods: installmentPeriodsOf(
        principalMinor: txn.amountMinor,
        periods: terms.$1,
        perPeriodRate: terms.$2,
        feeMode: _feeMode,
        remainderTo: _remainder,
      ),
    );
    try {
      final cost = await ref.read(installmentCostRunnerProvider)(input);
      if (mounted && request == _costRequest) {
        setState(() {
          _cost = cost;
          _costKey = key;
          _costFailed = false;
        });
      }
    } on Object {
      if (mounted && request == _costRequest) {
        setState(() {
          _cost = null;
          _costKey = key;
          _costFailed = true;
        });
      }
    }
  }

  /// 期数与每期费率（%）；不合格时为 null。
  (int, Rational)? _terms() {
    final periods = int.tryParse(_periods.text.trim());
    if (periods == null || periods < 1 || periods > 60) {
      return null;
    }
    final text = _rate.text.trim().replaceAll('%', '');
    if (!RegExp(r'^[0-9]+(\.[0-9]+)?$').hasMatch(text)) {
      return null;
    }
    final rate = Rational.parseDecimal(text).dividedBy(Rational.fromInt(100));
    return rate >= Rational.one ? null : (periods, rate);
  }

  Future<void> _save() async {
    final terms = _terms();
    setState(() {
      _errors.clear();
      _saveError = null;
      if (terms == null) {
        _errors['terms'] = '期数须为 1–60，每期费率填百分数（如 0.6 表示 0.6%）';
      }
    });
    if (terms == null) {
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await boundRepository(installmentRepositoryProvider.future);
      await repo.create(
        InstallmentDraft(
          transactionId: widget.transactionId,
          periods: terms.$1,
          perPeriodRate: terms.$2,
          feeMode: _feeMode,
          remainderTo: _remainder,
          firstStatementOn: _first,
        ),
        id: _id,
      );
      showFeedback(messenger, '已转分期（你已确认）');
      if (mounted) {
        closeLedgerForm(
          context,
          AppRoutes.statements(accountId: widget.accountId),
        );
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

  /// 首期账单日的候选：交易本身的账期起连续 3 期（规则给不出时为空，由仓库按默认推出）。
  List<LocalDate> _candidates(LedgerData data, CardTransactionRow txn) {
    final account = data.accountOf(txn.currencyAccountId);
    if (account == null) {
      return const <LocalDate>[];
    }
    final versions = <BillingRuleVersionRow>[
      for (final c in account.currencies)
        if (c.row.id == txn.currencyAccountId) ...c.ruleVersions,
    ];
    final base = txn.postedOn == null
        ? txnDateOf(txn, account.zone)
        : LocalDate.parse(txn.postedOn!);
    try {
      final rule = selectRule(versions.map(billingRuleFromRow).toList(), base);
      return previewCycles(rule, base).map((c) => c.statementDate).toList();
    } on BillingRuleError {
      return const <LocalDate>[];
    }
  }

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(ledgerProvider);
    final guard = ledgerFormGuard(ref, ledger);
    final Widget body;
    if (guard != null) {
      body = guard;
    } else {
      final data = ledger.value!;
      final txn = data.transaction(widget.transactionId);
      if (txn == null) {
        body = ErrorBlock(
          title: '已不存在',
          detail: '这笔交易不在当前空间里，或已删除。',
          onRetry: () =>
              context.go(AppRoutes.statements(accountId: widget.accountId)),
          retryLabel: '回到账单中心',
        );
      } else {
        final terms = _terms();
        final candidates = _candidates(data, txn);
        final preview = terms == null
            ? null
            : installmentPeriodsOf(
                principalMinor: txn.amountMinor,
                periods: terms.$1,
                perPeriodRate: terms.$2,
                feeMode: _feeMode,
                remainderTo: _remainder,
              );
        final costText = _costKey != _termsKey()
            ? InstallmentPlanCard.computingText
            : _costFailed || _cost == null
            ? '暂时算不出'
            : percentText(_cost!.effective);
        final today = data.todayByCurrencyAccount[txn.currencyAccountId]!;
        body = ListView(
          padding: const EdgeInsets.only(bottom: CfSpace.xl),
          children: <Widget>[
            LedgerAmountRow(
              label:
                  '${txn.merchant ?? TxnType.of(txn.txnType).label} · ${timestampText(txn.txnAt)}',
              minor: txn.amountMinor,
              currency: txn.currency,
            ),
            FormTextField(
              controller: _periods,
              label: '期数（1–60）',
              error: _errors['terms'],
              keyboardType: TextInputType.number,
              onChanged: (_) => _termsChanged(),
            ),
            FormTextField(
              controller: _rate,
              label: '每期费率（%，如 0.6）',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => _termsChanged(),
            ),
            ChoiceWrap<InstallmentFeeMode>(
              label: '手续费',
              values: InstallmentFeeMode.values,
              selected: _feeMode,
              labelOf: (m) => m.label,
              onSelected: (m) {
                _feeMode = m;
                _termsChanged();
              },
            ),
            ChoiceWrap<RemainderTo>(
              label: '尾差（各期四舍五入后的差额）',
              values: RemainderTo.values,
              selected: _remainder,
              labelOf: (r) => r == RemainderTo.last ? '加到末期' : '加到首期',
              onSelected: (r) {
                _remainder = r;
                _termsChanged();
              },
            ),
            if (candidates.isNotEmpty)
              ChoiceWrap<LocalDate?>(
                label: '第 1 期所在账单',
                values: <LocalDate?>[null, ...candidates],
                selected: _first,
                labelOf: (d) => d == null
                    ? '默认（入账日与今天中较晚者所在账期）'
                    : '${formatShortDate(d, today)} 出账',
                onSelected: (d) => setState(() => _first = d),
              ),
            if (terms != null && preview != null) ...<Widget>[
              const SectionTitle('预览'),
              LedgerAmountRow(
                label: '第 1 期（本金 + 费用）',
                minor: preview.first.principal + preview.first.fee,
                currency: txn.currency,
              ),
              LedgerAmountRow(
                label: '第 ${preview.last.periodNo} 期（本金 + 费用）',
                minor: preview.last.principal + preview.last.fee,
                currency: txn.currency,
              ),
              LedgerAmountRow(
                label: '手续费合计',
                minor: preview.fold<int>(0, (a, p) => a + p.fee),
                currency: txn.currency,
              ),
              LabeledValue(
                label: '名义年化（每期费率 × 12，不是实际成本）',
                value: Text(percentText(terms.$2.timesInt(12))),
              ),
              LabeledValue(label: '实际年化（复利，按各期现金流 IRR）', value: Text(costText)),
            ],
            ledgerSaveError(_saveError),
            formPadded(
              FilledButton(
                onPressed: _saving ? null : () => unawaited(_save()),
                child: Text(_saving ? '正在保存…' : '转分期'),
              ),
            ),
          ],
        );
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text(InstallmentFormPage.title)),
      body: body,
    );
  }
}

/// 金额（MoneyText）的一行，供还款页复用。
Widget moneyLine(String label, int? minor, String currency) => Wrap(
  spacing: CfSpace.sm,
  crossAxisAlignment: WrapCrossAlignment.center,
  children: <Widget>[
    Text(label),
    MoneyText(minor: minor, currency: currency, semanticsPrefix: label),
  ],
);
