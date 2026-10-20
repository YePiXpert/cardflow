import 'dart:async';

import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate, Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/confirm_dialog.dart';
import '../../app/widgets/feedback.dart';
import '../../app/widgets/money_text.dart';
import '../../app/widgets/state_views.dart';
import '../../app/widgets/workspace_bound_form.dart';
import '../../data/db/app_database.dart';
import '../../data/mapping/cash_mapping.dart' show cashTimeZone;
import '../../data/repositories/cash_models.dart';
import '../../data/repositories/ledger_home.dart';
import '../../data/repositories/ledger_models.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/repayment_repository.dart';
import '../../data/repositories/repository_errors.dart';
import '../../data/time/clock.dart';
import '../cards/amount_input.dart';
import '../cash/cash_form_fields.dart';

/// "还清本期"（简报 U-1 §3 快捷）：预填金额 = 剩余应还、分配 = 本期账单、方式手工、发起时间 = 现在、预计扣款日 =
/// 今天、扣款账户 = 唯一可用于还款的现金账户（多个时让用户选），生成"已登记（待银行确认）"的还款；之后在详情与
/// 卡账行上一步推进"银行已入账""银行确认"。状态机与文案规则不变（不出现"还款成功"）。
Future<void> showQuickPaySheet(BuildContext context, CardLedgerRow row) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => QuickPaySheet(row: row),
    );

/// "还清本期"的弹层。
class QuickPaySheet extends ConsumerStatefulWidget {
  const QuickPaySheet({super.key, required this.row});

  final CardLedgerRow row;

  /// 弹层标题。
  static const String title = '还清本期';

  /// 保存后的轻提示（带确认层级）。
  static const String savedMessage = '已登记（待银行确认）';

  @override
  ConsumerState<QuickPaySheet> createState() => _QuickPaySheetState();
}

class _QuickPaySheetState extends ConsumerState<QuickPaySheet>
    with WorkspaceBoundForm<QuickPaySheet> {
  final TextEditingController _amount = TextEditingController();
  String? _cash;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final remaining = widget.row.remaining ?? 0;
    if (remaining > 0) {
      _amount.text = amountText(remaining, widget.row.currency);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// 可用于还款的现金账户：同币种、未停用、今天可用于还款（受限、不可用于还款的不列）。
  List<CashAccountRow> _choices(
    List<CashAccountRow> accounts,
    LocalDate today,
  ) => <CashAccountRow>[
    for (final a in accounts)
      if (a.currency == widget.row.currency &&
          a.status == CashAccountStatus.active.code &&
          CashAvailability.of(a).usableOn(today))
        a,
  ];

  Future<void> _save(List<CashAccountRow> choices) async {
    final row = widget.row;
    final current = row.current!;
    final (amount, amountError) = parseAmountMinor(_amount.text, row.currency);
    if (amountError != null || amount == null || amount == 0) {
      setState(() => _error = amountError ?? '还款额须大于 0');
      return;
    }
    final cash = choices.length == 1 ? choices.single.id : _cash;
    if (cash == null) {
      setState(() => _error = '请选择扣款的现金账户');
      return;
    }
    if (amount > current.remaining) {
      final confirmed = await confirmAction(
        context,
        title: '比剩余应还多？',
        message: '多出的部分会成为贷方余额（溢缴款），抵扣以后的账单。确认这笔就是要多还，再登记。',
        confirmLabel: '仍要登记',
      );
      if (!confirmed || !mounted) {
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final clock = ref.read(clockProvider);
      final repo = await boundRepository(repaymentRepositoryProvider.future);
      await repo.create(
        RepaymentDraft(
          currencyAccountId: row.currencyAccountId,
          amountMinor: amount,
          method: RepaymentMethod.manual,
          allocations: <String, int>{current.statement.id: amount},
          cashAccountId: cash,
          initiatedAt: Timestamp.parse(clock.nowText(cashTimeZone)),
          expectedDebitOn: clock.today(cashTimeZone),
        ),
      );
      navigator.pop();
      showFeedback(messenger, QuickPaySheet.savedMessage);
    } on RepositoryException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
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
    final colors = CardFlowColors.of(context);
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: colors.textSecondary,
    );
    final plan = ref.watch(cashPlanProvider);
    final row = widget.row;
    final current = row.current;
    final view = plan.value;
    final choices = view == null
        ? const <CashAccountRow>[]
        : _choices(<CashAccountRow>[
            for (final a in view.accounts) a.row,
          ], view.today);
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
                    '${QuickPaySheet.title} · ${row.title}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
              if (current != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CfSpace.md,
                    CfSpace.xxs,
                    CfSpace.md,
                    0,
                  ),
                  child: Wrap(
                    spacing: CfSpace.xxs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text('剩余应还', style: secondary),
                      MoneyText(
                        minor: current.remaining,
                        currency: row.currency,
                        semanticsPrefix: '剩余应还',
                        textAlign: TextAlign.start,
                        style: secondary,
                      ),
                      Text(
                        '· 分配到 ${current.statement.statementDate} 账单',
                        style: secondary,
                      ),
                    ],
                  ),
                ),
              if (row.pending != null)
                const NoticeCard(
                  icon: Icons.help_outline,
                  text: '这期已有登记的还款还没入账：确认不是同一笔再登记，避免重复。',
                ),
              FormTextField(
                controller: _amount,
                label: '还款额',
                keyboardType: FormTextField.amountKeyboard,
              ),
              if (view != null && choices.isEmpty)
                NoticeCard(
                  icon: Icons.account_balance_wallet_outlined,
                  text: '还没有可用于还款的现金账户：先添加一个，扣款才会进资金日历。',
                  action: OutlinedButton(
                    onPressed: () {
                      final router = GoRouter.of(context);
                      Navigator.of(context).pop();
                      router.go(AppRoutes.newCashAccount);
                    },
                    child: const Text('添加现金账户'),
                  ),
                )
              else if (choices.length > 1)
                ChoiceWrap<String>(
                  label: '从哪个现金账户扣款',
                  values: <String>[for (final a in choices) a.id],
                  selected: _cash,
                  labelOf: (id) => choices.firstWhere((a) => a.id == id).name,
                  onSelected: (id) => setState(() => _cash = id),
                )
              else if (choices.length == 1)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CfSpace.md,
                    vertical: CfSpace.xs,
                  ),
                  child: Text(
                    '从「${choices.single.name}」扣款 · 今天 · 手动还款',
                    style: secondary,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
                child: Text(
                  '登记后是"已登记（待银行确认）"：不是还清。银行入账、核对一致后在卡账或详情上一步记"银行已入账""银行确认"。',
                  style: secondary,
                ),
              ),
              if (_error != null)
                NoticeCard(
                  icon: Icons.error_outline,
                  tone: NoticeTone.danger,
                  text: _error!,
                ),
              Padding(
                padding: const EdgeInsets.all(CfSpace.md),
                child: Wrap(
                  spacing: CfSpace.xs,
                  runSpacing: CfSpace.xs,
                  children: <Widget>[
                    FilledButton(
                      onPressed: _saving || current == null || choices.isEmpty
                          ? null
                          : () => unawaited(_save(choices)),
                      child: Text(_saving ? '登记中…' : '登记还款'),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        final router = GoRouter.of(context);
                        Navigator.of(context).pop();
                        router.go(
                          AppRoutes.newRepayment(
                            accountId: row.creditAccountId,
                            statementId: current?.statement.id,
                            currencyAccountId: row.currencyAccountId,
                          ),
                        );
                      },
                      child: const Text('完整登记'),
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
