import 'dart:async';

import 'package:cardflow_domain/cardflow_domain.dart'
    show BillingRuleError, LocalDate, dueDateForStatement, selectRule;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/feedback.dart';
import '../../app/widgets/state_views.dart';
import '../../app/widgets/workspace_bound_form.dart';
import '../../data/mapping/domain_mapping.dart';
import '../../data/repositories/card_wallet_reader.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/repository_errors.dart';
import '../../data/repositories/statement_repository.dart';
import '../cards/amount_input.dart';
import '../cards/card_dialogs.dart';
import '../cash/cash_form_fields.dart';

/// "记本期账单"（简报 U-1 §3 快捷）：底部弹层，字段 = 账单日（默认今天及以前最近的预测账单日）、新增账单金额
/// （必填）、最低还款（可选）、到期日（默认预测值，可改）。用现有仓库生成 v1 手工账单（`recordIssued`），其余要素
/// 按"来源未含此项"保存。原"录入正式账单"完整表单保留为「完整录入」。
Future<void> showQuickStatementSheet(
  BuildContext context, {
  required AccountView account,
  required CurrencyAccountView sub,
}) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  builder: (_) => QuickStatementSheet(account: account, sub: sub),
);

/// "记本期账单"的弹层。
class QuickStatementSheet extends ConsumerStatefulWidget {
  const QuickStatementSheet({
    super.key,
    required this.account,
    required this.sub,
  });

  final AccountView account;
  final CurrencyAccountView sub;

  /// 弹层标题。
  static const String title = '记本期账单';

  /// 保存后的轻提示（带确认层级）。
  static const String savedMessage = '已记本期账单（你已确认）';

  /// 账单日最早可选到今天前多少天。
  static const int lookbackDays = 120;

  @override
  ConsumerState<QuickStatementSheet> createState() =>
      _QuickStatementSheetState();
}

class _QuickStatementSheetState extends ConsumerState<QuickStatementSheet>
    with WorkspaceBoundForm<QuickStatementSheet> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _minDue = TextEditingController();
  late LocalDate _statementDate;
  LocalDate? _dueDate;
  bool _dueEdited = false;
  final Map<String, String> _errors = <String, String>{};
  String? _saveError;
  bool _saving = false;

  LocalDate get _today => widget.account.today;

  @override
  void initState() {
    super.initState();
    final recent = recentStatementCycle(widget.sub.ruleVersions, _today);
    _statementDate = recent?.statementDate ?? _today;
    _dueDate = recent?.dueDate;
  }

  @override
  void dispose() {
    _amount.dispose();
    _minDue.dispose();
    super.dispose();
  }

  /// 账单日 [date] 的预测到期日（规则给不出时为 null）。
  LocalDate? _predictedDue(LocalDate date) {
    final versions = widget.sub.ruleVersions;
    if (versions.isEmpty) {
      return null;
    }
    try {
      final rule = selectRule(versions.map(billingRuleFromRow).toList(), date);
      return dueDateForStatement(rule, date);
    } on BillingRuleError {
      return null;
    }
  }

  Future<void> _save() async {
    final currency = widget.sub.currency;
    final errors = <String, String>{};
    final (amount, amountError) = parseAmountMinor(_amount.text, currency);
    if (amountError != null) {
      errors['newBalance'] = amountError;
    }
    final (minDue, minError) = parseAmountMinor(
      _minDue.text,
      currency,
      required: false,
    );
    if (minError != null) {
      errors['minDue'] = minError;
    }
    if (_dueDate == null) {
      errors['dueDate'] = '请选择到期还款日';
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
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final repo = await boundRepository(statementRepositoryProvider.future);
      await repo.recordIssued(
        StatementEntryDraft(
          currencyAccountId: widget.sub.row.id,
          statementDate: _statementDate,
          dueDate: _dueDate!,
          figures: StatementFigures(
            newBalanceMinor: amount!,
            minDueMinor: minDue,
          ),
        ),
      );
      navigator.pop();
      showFeedback(messenger, QuickStatementSheet.savedMessage);
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
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: CardFlowColors.of(context).textSecondary,
    );
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
                child: Semantics(
                  header: true,
                  child: Text(
                    QuickStatementSheet.title,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CfSpace.md,
                  CfSpace.xxs,
                  CfSpace.md,
                  0,
                ),
                child: Text(
                  '按账单上的数填：新增账单金额必填，其余要素记为"来源未含此项"，之后可在账单详情里人工修正。',
                  style: secondary,
                ),
              ),
              formPadded(
                DateField(
                  label: '账单日',
                  value: _statementDate,
                  first: _today.addDays(-QuickStatementSheet.lookbackDays),
                  last: _today,
                  onChanged: (v) => setState(() {
                    _statementDate = v;
                    if (!_dueEdited) {
                      _dueDate = _predictedDue(v);
                    }
                  }),
                ),
              ),
              FormTextField(
                controller: _amount,
                label: '新增账单金额（必填）',
                error: _errors['newBalance'],
                keyboardType: FormTextField.amountKeyboard,
              ),
              FormTextField(
                controller: _minDue,
                label: '最低还款（可选）',
                error: _errors['minDue'],
                keyboardType: FormTextField.amountKeyboard,
              ),
              formPadded(
                DateField(
                  label: _dueEdited || _dueDate == null
                      ? '到期还款日'
                      : '到期还款日（按账期规则预测，可改）',
                  value: _dueDate,
                  first: _statementDate.addDays(1),
                  last: _statementDate.addDays(90),
                  onChanged: (v) => setState(() {
                    _dueDate = v;
                    _dueEdited = true;
                  }),
                ),
              ),
              if (_errors['dueDate'] case final error?)
                NoticeCard(
                  icon: Icons.error_outline,
                  tone: NoticeTone.danger,
                  text: error,
                ),
              if (_saveError != null && _errors['dueDate'] == null)
                NoticeCard(
                  icon: Icons.error_outline,
                  tone: NoticeTone.danger,
                  text: _saveError!,
                ),
              Padding(
                padding: const EdgeInsets.all(CfSpace.md),
                child: Wrap(
                  spacing: CfSpace.xs,
                  runSpacing: CfSpace.xs,
                  children: <Widget>[
                    FilledButton(
                      onPressed: _saving ? null : () => unawaited(_save()),
                      child: Text(_saving ? '保存中…' : '保存'),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        final router = GoRouter.of(context);
                        Navigator.of(context).pop();
                        router.go(
                          AppRoutes.newStatement(
                            accountId: widget.account.id,
                            currencyAccountId: widget.sub.row.id,
                          ),
                        );
                      },
                      child: const Text('完整录入'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
