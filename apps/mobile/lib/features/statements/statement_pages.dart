import 'dart:async';

import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/first_run_empty_state.dart';
import '../../app/widgets/money_text.dart';
import '../../app/widgets/state_views.dart';
import '../../data/db/app_database.dart';
import '../../data/mapping/ledger_mapping.dart';
import '../../data/repositories/ledger_models.dart';
import '../../data/repositories/ledger_reader.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/reconciliation_repository.dart';
import '../cards/card_formatting.dart';
import 'ledger_actions.dart';
import 'ledger_formatting.dart';

/// P-05 账单中心（列表，ui-spec P-05）：筛选（账户/有效状态/币种/月）；每行：剩余应还、到期、有效状态、确认层级、
/// 版本数、差异数；「录入正式账单」「记一笔」；列表下面是"不在已录账单里的交易"（未出账的、所在账期还没录入
/// 账单的），每笔可「删除」「补入账日」「转分期」（审查 R-16）。从 P-03「全部账单」进入时只看该账户（[accountId]）。
///
/// 四态：首次空白（"还没有正式账单"「录入正式账单」，导入在 I-3）、加载、错误（「重新加载」）、成功。
class StatementCenterPage extends ConsumerStatefulWidget {
  const StatementCenterPage({super.key, this.accountId});

  /// 所在的信用账户详情栈（为空 = 总览栈）。
  final String? accountId;

  static const String title = '账单中心';

  /// ui-spec P-05 九态"首次空白"。
  static const String firstRunMessage = '还没有正式账单';

  /// 不在已录账单里的交易（未出账的、所在账期还没录入账单的）一节的标题。
  static const String looseTitle = '不在已录账单里的交易';

  @override
  ConsumerState<StatementCenterPage> createState() =>
      _StatementCenterPageState();
}

class _StatementCenterPageState extends ConsumerState<StatementCenterPage> {
  String? _account;
  EffectiveStatementStatus? _status;
  String? _currency;
  String? _month;

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(ledgerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(StatementCenterPage.title),
        actions: <Widget>[
          IconButton(
            tooltip: '记一笔',
            icon: const Icon(Icons.edit_note),
            onPressed: () => context.go(
              AppRoutes.newTransaction(accountId: widget.accountId),
            ),
          ),
          IconButton(
            tooltip: '录入正式账单',
            icon: const Icon(Icons.post_add),
            onPressed: () =>
                context.go(AppRoutes.newStatement(accountId: widget.accountId)),
          ),
        ],
      ),
      body: switch (ledger) {
        AsyncData(:final value) => _body(context, value),
        AsyncError(:final error) => ErrorBlock(
          title: '账单读取失败',
          code: '${error.runtimeType}',
          detail: '本机数据没有改动。',
          onRetry: () => ref.invalidate(ledgerProvider),
          retryLabel: '重新加载',
        ),
        _ => const LoadingSkeleton(rows: 4),
      },
    );
  }

  Widget _body(BuildContext context, LedgerData data) {
    final fixedAccount = widget.accountId;
    final all = <StatementRow>[
      for (final s in data.statements)
        if (fixedAccount == null ||
            data.currencyAccounts[s.currencyAccountId]?.creditAccountId ==
                fixedAccount)
          s,
    ];
    final loose = data.looseTransactions(creditAccountId: fixedAccount);
    if (all.isEmpty && loose.isEmpty) {
      return FirstRunEmptyState(
        icon: Icons.receipt_long_outlined,
        message: StatementCenterPage.firstRunMessage,
        purpose: '跨账户查看账单要素、版本、交易、分期、还款与差异。',
        actions: <EmptyStateAction>[
          EmptyStateAction(
            label: '录入正式账单',
            onPressed: () =>
                context.go(AppRoutes.newStatement(accountId: fixedAccount)),
          ),
          EmptyStateAction(
            label: '记一笔',
            onPressed: () =>
                context.go(AppRoutes.newTransaction(accountId: fixedAccount)),
          ),
          const EmptyStateAction(label: '导入', stage: '后续版本提供'),
        ],
      );
    }
    final accounts = <String>{
      for (final s in all)
        data.currencyAccounts[s.currencyAccountId]!.creditAccountId,
    }.toList();
    final currencies = <String>{
      for (final s in all) data.currencyAccounts[s.currencyAccountId]!.currency,
    }.toList();
    final months = <String>{
      for (final s in all) s.statementDate.substring(0, 7),
    }.toList()..sort((a, b) => b.compareTo(a));
    final shown = <StatementRow>[
      for (final s in all)
        if ((_account == null ||
                data.currencyAccounts[s.currencyAccountId]!.creditAccountId ==
                    _account) &&
            (_status == null || data.statusOf(s.id) == _status) &&
            (_currency == null ||
                data.currencyAccounts[s.currencyAccountId]!.currency ==
                    _currency) &&
            (_month == null || s.statementDate.startsWith(_month!)))
          s,
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: CfSpace.xl),
      children: <Widget>[
        if (fixedAccount == null && accounts.length > 1)
          _FilterChips<String>(
            label: '账户',
            values: accounts,
            selected: _account,
            labelOf: (id) => data.wallet.account(id)?.displayName ?? '账户',
            onSelected: (v) => setState(() => _account = v),
          ),
        _FilterChips<EffectiveStatementStatus>(
          label: '状态',
          values: <EffectiveStatementStatus>[
            for (final status in EffectiveStatementStatus.values)
              if (all.any((s) => data.statusOf(s.id) == status)) status,
          ],
          selected: _status,
          labelOf: (s) => s.label,
          onSelected: (v) => setState(() => _status = v),
        ),
        if (currencies.length > 1)
          _FilterChips<String>(
            label: '币种',
            values: currencies,
            selected: _currency,
            labelOf: currencyLabel,
            onSelected: (v) => setState(() => _currency = v),
          ),
        _FilterChips<String>(
          label: '月份',
          values: months,
          selected: _month,
          labelOf: (m) => m,
          onSelected: (v) => setState(() => _month = v),
        ),
        if (all.isEmpty)
          const Padding(
            padding: EdgeInsets.all(CfSpace.md),
            child: Text(StatementCenterPage.firstRunMessage),
          )
        else if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.all(CfSpace.md),
            child: Text('没有符合筛选条件的账单。'),
          ),
        for (final s in shown)
          _StatementTile(data: data, statement: s, accountId: fixedAccount),
        if (loose.isNotEmpty) ...<Widget>[
          SectionTitle('${StatementCenterPage.looseTitle}（${loose.length}）'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: Text(
              '未出账的交易，以及所在账期还没有录入正式账单的交易；录错的可以在这里删除或补入账日。',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: CardFlowColors.of(context).textSecondary),
            ),
          ),
          for (final (txn, cycle) in loose)
            TransactionTile(
              data: data,
              txn: txn,
              cycle: cycle,
              today: data.todayByCurrencyAccount[txn.currencyAccountId]!,
              accountId: fixedAccount,
            ),
        ],
      ],
    );
  }
}

/// 一组可取消的筛选标签（"全部"即不筛选）。
class _FilterChips<T> extends StatelessWidget {
  const _FilterChips({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final String label;
  final List<T> values;
  final T? selected;
  final String Function(T value) labelOf;
  final ValueChanged<T?> onSelected;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(CfSpace.md, CfSpace.xs, CfSpace.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: CfSpace.xxs),
          Wrap(
            spacing: CfSpace.xs,
            runSpacing: CfSpace.xs,
            children: <Widget>[
              ChoiceChip(
                label: const Text('全部'),
                selected: selected == null,
                onSelected: (_) => onSelected(null),
              ),
              for (final v in values)
                ChoiceChip(
                  label: Text(labelOf(v)),
                  selected: v == selected,
                  onSelected: (_) => onSelected(v),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 列表的一行：剩余应还、到期、状态、确认层级、版本数、差异数。
class _StatementTile extends StatelessWidget {
  const _StatementTile({
    required this.data,
    required this.statement,
    required this.accountId,
  });

  final LedgerData data;
  final StatementRow statement;
  final String? accountId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final balance = data.balances[statement.id];
    final currency =
        data.currencyAccounts[statement.currencyAccountId]!.currency;
    final versions = data.versions[statement.id]?.length ?? 0;
    final items = data.openItemsOf(statement.id).length;
    final today = data.todayByCurrencyAccount[statement.currencyAccountId]!;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CfSpace.md,
        vertical: CfSpace.xxs,
      ),
      child: Card(
        child: InkWell(
          onTap: () => context.go(
            AppRoutes.statement(statement.id, accountId: accountId),
          ),
          child: Padding(
            padding: const EdgeInsets.all(CfSpace.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  statementTitle(data, statement),
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: CfSpace.xxs),
                Wrap(
                  spacing: CfSpace.sm,
                  runSpacing: CfSpace.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    const Text('剩余应还'),
                    MoneyText(
                      minor: balance?.remaining,
                      currency: currency,
                      semanticsPrefix: '剩余应还',
                    ),
                    Text(
                      '到期 ${formatShortDate(LocalDate.parse(statement.dueDate), today)}',
                    ),
                  ],
                ),
                if ((balance?.creditBalance ?? 0) > 0)
                  Wrap(
                    spacing: CfSpace.sm,
                    children: <Widget>[
                      const Text('贷方余额'),
                      MoneyText(
                        minor: balance!.creditBalance,
                        currency: currency,
                        semanticsPrefix: '贷方余额',
                      ),
                    ],
                  ),
                const SizedBox(height: CfSpace.xxs),
                Wrap(
                  spacing: CfSpace.xs,
                  runSpacing: CfSpace.xxs,
                  children: <Widget>[
                    if (balance != null) effectiveStatusBadge(balance),
                    confirmationBadge(data.confirmationOf(statement.id)),
                    StatusBadge(
                      label: '$versions 个版本',
                      icon: Icons.layers_outlined,
                    ),
                    if (items > 0)
                      StatusBadge(
                        label: '差异 $items',
                        icon: Icons.rule,
                        tone: NoticeTone.attention,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// P-05 账单详情：版本切换 › 要素（R-STMT-01 全项，带来源与版本；来源未含的项显示"来源未含此项"）›
/// 负债四分法 › 交易（含退款待核对、可能账期）› 分期（每期本金/费用、尾差、名义与实际年化并列）› 还款分配 ›
/// 差异清单；「登记还款」「人工修正」「记一笔」。
class StatementDetailPage extends ConsumerStatefulWidget {
  const StatementDetailPage({
    super.key,
    required this.statementId,
    this.accountId,
  });

  final String statementId;
  final String? accountId;

  @override
  ConsumerState<StatementDetailPage> createState() =>
      _StatementDetailPageState();
}

class _StatementDetailPageState extends ConsumerState<StatementDetailPage> {
  int? _versionNo;

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(ledgerProvider);
    final data = ledger.value;
    final statement = data?.statement(widget.statementId);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          statement == null ? '账单' : statementTitle(data!, statement),
        ),
      ),
      body: switch (ledger) {
        AsyncData() when statement == null => ErrorBlock(
          title: '已不存在',
          detail: '这期账单不在当前空间里（可能已切换空间）。',
          onRetry: () =>
              context.go(AppRoutes.statements(accountId: widget.accountId)),
          retryLabel: '回到账单中心',
        ),
        AsyncData(:final value) => _detail(context, value, statement!),
        AsyncError(:final error) => ErrorBlock(
          title: '账单读取失败',
          code: '${error.runtimeType}',
          detail: '本机数据没有改动。',
          onRetry: () => ref.invalidate(ledgerProvider),
          retryLabel: '重新加载',
        ),
        _ => const LoadingSkeleton(rows: 5),
      },
    );
  }

  Widget _detail(BuildContext context, LedgerData data, StatementRow s) {
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: CardFlowColors.of(context).textSecondary,
    );
    final versions = data.versions[s.id]!;
    final current = versions.last;
    final selected = versions.firstWhere(
      (v) => v.versionNo == (_versionNo ?? current.versionNo),
      orElse: () => current,
    );
    final balance = data.balances[s.id]!;
    final currency = data.currencyAccounts[s.currencyAccountId]!.currency;
    final liability = data.liabilities[s.currencyAccountId];
    final today = data.todayByCurrencyAccount[s.currencyAccountId]!;
    final source = StatementSource.of(selected.sourceKind);
    final sourceText =
        '来源：${source.label} · v${selected.versionNo}'
        '${selected.reason == null ? '' : '（理由：${selected.reason}）'}';
    // 还款只分配到本期（更早的已并入下一期）；有效状态"已还清"的不能再修正（PRD §6.2 裁决段）。
    final canRegister = balance.isCurrent;
    final canCorrect = balance.status != EffectiveStatementStatus.paid;
    final transactions = data.transactionsOf(s.id);
    final plans = data.plansOf(s.currencyAccountId);
    final repayments = data.repaymentsOn(s.id);
    final items = <ReconciliationItemRow>[
      for (final item in data.items)
        if (data.statementsOfItem(item).contains(s.id)) item,
    ];
    final futureDue = <int>[
      for (final p in plans)
        if (p.status == InstallmentPlanStatus.active.code)
          for (final period
              in data.periods[p.id] ?? const <InstallmentScheduleRow>[])
            if (period.status == InstallmentPeriodStatus.scheduled.code)
              period.principalMinor + period.feeMinor,
    ].fold<int>(0, (a, b) => a + b);
    return ListView(
      padding: const EdgeInsets.only(bottom: CfSpace.xl),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CfSpace.md,
            CfSpace.sm,
            CfSpace.md,
            0,
          ),
          child: Wrap(
            spacing: CfSpace.xs,
            runSpacing: CfSpace.xxs,
            children: <Widget>[
              effectiveStatusBadge(balance),
              confirmationBadge(data.confirmationOf(s.id)),
            ],
          ),
        ),
        LabeledValue(label: '账单日', value: Text(s.statementDate)),
        LabeledValue(label: '到期还款日', value: Text(s.dueDate)),
        if (balance.creditBalance > 0)
          NoticeCard(
            icon: Icons.savings_outlined,
            tone: NoticeTone.unknown,
            text: '这期有贷方余额（溢缴款），本期应还为 0。',
          ),
        Padding(
          padding: const EdgeInsets.all(CfSpace.md),
          child: Wrap(
            spacing: CfSpace.xs,
            runSpacing: CfSpace.xs,
            children: <Widget>[
              if (canRegister)
                FilledButton(
                  onPressed: () => context.go(
                    AppRoutes.newRepayment(
                      accountId: widget.accountId,
                      statementId: s.id,
                    ),
                  ),
                  child: const Text('登记还款'),
                ),
              if (canCorrect)
                OutlinedButton(
                  onPressed: () => context.go(
                    AppRoutes.correctStatement(
                      s.id,
                      accountId: widget.accountId,
                    ),
                  ),
                  child: const Text('人工修正'),
                ),
              OutlinedButton(
                onPressed: () => context.go(
                  AppRoutes.newTransaction(
                    accountId: widget.accountId,
                    currencyAccountId: s.currencyAccountId,
                  ),
                ),
                child: const Text('记一笔'),
              ),
            ],
          ),
        ),
        if (!canCorrect)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: Text('已还清的账单不能再修正；银行另有调整时请录入下一期账单。', style: secondary),
          ),
        SectionTitle('账单要素（v${selected.versionNo}）'),
        if (versions.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: Wrap(
              spacing: CfSpace.xs,
              runSpacing: CfSpace.xs,
              children: <Widget>[
                for (final v in versions)
                  ChoiceChip(
                    label: Text(
                      'v${v.versionNo} ${StatementSource.of(v.sourceKind).label}'
                      '${v.id == current.id ? '（当前）' : ''}',
                    ),
                    selected: v.id == selected.id,
                    onSelected: (_) => setState(() => _versionNo = v.versionNo),
                  ),
              ],
            ),
          ),
        if (versions.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CfSpace.md,
              vertical: CfSpace.xxs,
            ),
            child: Text('修正只生成新版本，原值保留可查。', style: secondary),
          ),
        LedgerAmountRow(
          label: '上期余额',
          minor: selected.previousBalanceMinor,
          currency: currency,
          source: sourceText,
          negativeLabel: '贷方',
        ),
        LedgerAmountRow(
          label: '本期应还（新余额）',
          minor: selected.newBalanceMinor,
          currency: currency,
          source: sourceText,
          negativeLabel: '贷方余额',
        ),
        LedgerAmountRow(
          label: '最低还款额',
          minor: selected.minDueMinor,
          currency: currency,
          source: sourceText,
        ),
        LedgerAmountRow(
          label: '本期还款',
          minor: selected.paymentsMinor,
          currency: currency,
          source: sourceText,
        ),
        LedgerAmountRow(
          label: '退款与贷记',
          minor: selected.creditsMinor,
          currency: currency,
          source: sourceText,
        ),
        LedgerAmountRow(
          label: '费用（含年费）',
          minor: selected.feesMinor,
          currency: currency,
          source: sourceText,
        ),
        LedgerAmountRow(
          label: '利息',
          minor: selected.interestMinor,
          currency: currency,
          source: sourceText,
        ),
        LedgerAmountRow(
          label: '分期应还（本期）',
          minor: selected.installmentDueMinor,
          currency: currency,
          source: sourceText,
        ),
        LedgerAmountRow(
          label: '贷方余额（溢缴款）',
          minor: selected.creditBalanceMinor,
          currency: currency,
          source: sourceText,
        ),
        for (final label in <String>['历史逾期', '撤销', '预授权释放'])
          LedgerAmountRow(
            label: label,
            minor: null,
            currency: currency,
            source: sourceText,
          ),
        if (!balance.isCurrent)
          NoticeCard(
            icon: Icons.merge_type,
            tone: NoticeTone.unknown,
            text:
                '${effectiveStatusText(balance)}：这期没还的部分已计入下一期的新增账单，'
                '不再单独计入负债、近期到期与逾期，也不再接受还款分配。',
          )
        else ...<Widget>[
          if (balance.paidAfter > 0)
            LedgerAmountRow(
              label: '账单日之后银行入账的还款',
              minor: balance.paidAfter,
              currency: currency,
              source: '不论分配到哪一期；账单日及以前入账的已反映在新增账单里',
            ),
          for (final a in balance.adjustments)
            LedgerAmountRow(
              label:
                  '转分期调整（${data.transaction(a.plan.transactionId)?.merchant ?? '消费'}）',
              minor: a.amountMinor,
              currency: currency,
              negativeLabel: '减',
              source: '这笔已出账的消费在本版本录入后才转分期：减去分期本金，加上本期这一期的本金与手续费',
            ),
          LedgerAmountRow(
            label: '本期剩余应还',
            minor: balance.remaining,
            currency: currency,
            source:
                '系统估计：新增账单减去账单日之后银行入账的还款'
                '${balance.adjustments.isEmpty ? '' : '，加上转分期调整'}（"我已还款"不扣减）',
          ),
          if (balance.creditBalance > 0 && balance.basis >= 0)
            LedgerAmountRow(
              label: '贷方余额（多还的部分）',
              minor: balance.creditBalance,
              currency: currency,
            ),
        ],
        if (liability != null)
          LedgerAmountRow(
            label: '未出账',
            minor: liability.unbilled,
            currency: currency,
            source: '系统估计：最近一期账单之后的交易',
          ),
        LedgerAmountRow(
          label: '未来分期还款（本金 + 费用）',
          minor: futureDue,
          currency: currency,
          source: '系统估计：尚未出账的各期',
        ),
        if (liability != null) ...<Widget>[
          const SectionTitle('负债四分法'),
          LiabilitySection.of(liability),
        ],
        SectionTitle('本期交易（${transactions.length}）'),
        if (transactions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: Text('没有落在这期账单里的交易记录。', style: secondary),
          ),
        for (final (txn, cycle) in transactions)
          TransactionTile(
            data: data,
            txn: txn,
            cycle: cycle,
            today: today,
            accountId: widget.accountId,
          ),
        SectionTitle('分期（${plans.length}）'),
        if (plans.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: Text('这个账户没有分期。消费可以在交易里「转分期」。', style: secondary),
          ),
        for (final plan in plans)
          InstallmentPlanCard(
            data: data,
            plan: plan,
            highlight: LocalDate.parse(s.statementDate),
          ),
        SectionTitle('还款分配（${repayments.length}）'),
        if (repayments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: Text('本期还没有还款记录。', style: secondary),
          ),
        for (final (repayment, amount) in repayments)
          ListTile(
            title: Wrap(
              spacing: CfSpace.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                const Text('分到本期'),
                MoneyText(
                  minor: amount,
                  currency: currency,
                  semanticsPrefix: '分到本期',
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: CfSpace.xxs),
              child: Wrap(
                spacing: CfSpace.xs,
                runSpacing: CfSpace.xxs,
                children: <Widget>[
                  repaymentStatusBadge(data.repaymentStatusOf(repayment)),
                  Text(RepaymentMethod.of(repayment.method).label),
                ],
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(
              AppRoutes.repayment(repayment.id, accountId: widget.accountId),
            ),
          ),
        SectionTitle('差异清单（${items.length}）'),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: Text('没有差异项。', style: secondary),
          ),
        for (final item in items)
          ReconciliationSummaryTile(
            item: item,
            systemReason: data.systemCloseReason(item),
            onTap: () =>
                context.go(AppRoutes.repayments(accountId: widget.accountId)),
          ),
      ],
    );
  }
}

/// 一笔交易：类型、金额、商户、账期归属（可能账期）、退款待核对；消费可「转分期」；「补入账日」（入账日未知时）
/// 与「删除」（已转分期的先提示作废分期，审查 R-16）。入账日未知、可能账期跨过本期账单日的标"可能已出账，
/// 请补入账日"（Q-3：负债按未出账计，偏大）。
class TransactionTile extends ConsumerWidget {
  const TransactionTile({
    super.key,
    required this.data,
    required this.txn,
    required this.cycle,
    required this.today,
    required this.accountId,
  });

  final LedgerData data;
  final CardTransactionRow txn;
  final TxnCycle cycle;
  final LocalDate today;
  final String? accountId;

  /// 可能已出账的提示（Q-3）。
  static const String mayBeBilledText = '可能已出账，请补入账日（入账日未知时按未出账计，负债可能偏大）';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = TxnType.of(txn.txnType);
    final item = data.itemOfTransaction(txn.id);
    final plan = livePlanOf(data.plans, txn.id);
    final converted = plan != null;
    final canConvert = type == TxnType.purchase && !converted;
    return ListTile(
      title: Wrap(
        spacing: CfSpace.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(<String>[type.label, ?txn.merchant].join(' · ')),
          MoneyText(
            minor: txn.amountMinor,
            currency: txn.currency,
            negativeLabel: '贷记',
            negativeTone: MoneyTone.neutral,
            semanticsPrefix: type.label,
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${timestampText(txn.txnAt)} · ${txn.postedOn == null ? '入账日未知' : '入账 ${txn.postedOn}'}',
          ),
          Text(cycleText(cycle, today)),
          if (data.mayBeBilled(txn))
            Padding(
              padding: const EdgeInsets.only(top: CfSpace.xxs),
              child: StatusBadge(
                label: mayBeBilledText,
                icon: Icons.event_note_outlined,
                tone: NoticeTone.attention,
              ),
            ),
          if (converted) const Text('已转分期（本金按各期出账）'),
          if (item != null &&
              item.status == ReconciliationStatus.open.code &&
              type == TxnType.refund)
            const Text('退款待核对：应还不变、不计入收入'),
          Wrap(
            spacing: CfSpace.xs,
            children: <Widget>[
              if (canConvert)
                TextButton(
                  onPressed: () => context.go(
                    AppRoutes.newInstallment(txn.id, accountId: accountId),
                  ),
                  child: const Text('转分期'),
                ),
              if (txn.postedOn == null)
                TextButton(
                  onPressed: () => unawaited(
                    fillPostedOn(context, ref, txn: txn, today: today),
                  ),
                  child: const Text('补入账日'),
                ),
              TextButton(
                onPressed: () => unawaited(
                  deleteTransaction(context, ref, txn: txn, plan: plan),
                ),
                child: const Text('删除'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 一个分期计划：本金、期数、每期费率、收费方式与尾差；每期本金/费用表（[highlight] 账单日的那一期标"本期"）；
/// 成本：名义年化（每期费率 × 12，不是实际成本）与实际年化（复利，按各期现金流 IRR）并列（F-37）；各期都还没
/// 出账的进行中计划可「作废（录错了）」（审查 R-16）。
class InstallmentPlanCard extends ConsumerWidget {
  const InstallmentPlanCard({
    super.key,
    required this.data,
    required this.plan,
    this.highlight,
  });

  final LedgerData data;
  final InstallmentPlanRow plan;
  final LocalDate? highlight;

  /// 作废入口的文案（录错了的分期）。
  static const String cancelLabel = '作废（录错了）';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final txn = data.transaction(plan.transactionId);
    final currency = data.currencyAccounts[plan.currencyAccountId]!.currency;
    final periods = data.periods[plan.id] ?? const <InstallmentScheduleRow>[];
    final cost = data.costOf(plan);
    final status = InstallmentPlanStatus.of(plan.status);
    final remainderPeriod = plan.remainderPolicy == 'last'
        ? periods.lastOrNull
        : periods.firstOrNull;
    final regular = periods.length > 1
        ? (plan.remainderPolicy == 'last' ? periods.first : periods.last)
        : remainderPeriod;
    final remainder = remainderPeriod == null || regular == null
        ? 0
        : remainderPeriod.principalMinor - regular.principalMinor;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CfSpace.md,
        vertical: CfSpace.xxs,
      ),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(CfSpace.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '${txn?.merchant ?? '分期'} · ${plan.periods} 期 · ${status.label}',
                style: theme.textTheme.bodyLarge,
              ),
              LedgerAmountRow(
                label: '分期本金',
                minor: plan.principalMinor,
                currency: currency,
              ),
              LabeledValue(
                label: '每期费率',
                value: Text(
                  '${percentText(cost.perPeriodRate)}（${InstallmentFeeMode.of(plan.feeMode).label}，取整 ${plan.rounding}）',
                ),
              ),
              if (remainder == 0)
                const LabeledValue(label: '尾差', value: Text('各期相等'))
              else
                LedgerAmountRow(
                  label:
                      '尾差（${plan.remainderPolicy == 'last' ? '末期' : '首期'}${remainder > 0 ? '多' : '少'}）',
                  minor: remainder.abs(),
                  currency: currency,
                ),
              LabeledValue(
                label: '名义年化（每期费率 × 12，不是实际成本）',
                value: Text(percentText(cost.nominal)),
              ),
              LabeledValue(
                label: '实际年化（复利，按各期现金流 IRR）',
                value: Text(percentText(cost.effective)),
              ),
              LabeledValue(
                label: '月 IRR',
                value: Text(percentText(cost.monthlyIrr)),
              ),
              ExpansionTile(
                title: Text('每期本金与费用（${periods.length} 期）'),
                children: <Widget>[
                  for (final p in periods)
                    ListTile(
                      dense: true,
                      title: Wrap(
                        spacing: CfSpace.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          Text(
                            '第 ${p.periodNo} 期${highlight != null && p.statementDate == highlight.toString() ? '（本期）' : ''}',
                          ),
                          MoneyText(
                            minor: p.principalMinor,
                            currency: currency,
                            semanticsPrefix: '本金',
                          ),
                          const Text('+'),
                          MoneyText(
                            minor: p.feeMinor,
                            currency: currency,
                            semanticsPrefix: '费用',
                          ),
                        ],
                      ),
                      subtitle: Text(
                        '账单 ${p.statementDate} · 到期 ${p.dueDate} · ${InstallmentPeriodStatus.of(p.status).label}',
                      ),
                    ),
                ],
              ),
              if (canCancelPlan(plan, periods))
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: () =>
                        unawaited(cancelPlan(context, ref, plan: plan)),
                    child: const Text(InstallmentPlanCard.cancelLabel),
                  ),
                )
              else if (status == InstallmentPlanStatus.active)
                Text(
                  '已有出账的期次，不能作废（提前结清在后续版本提供）',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: CardFlowColors.of(context).textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 差异项的摘要行：类型、来源、建议动作、状态、处理结果与处理者（R-STMT-09）。系统处理的（引用的交易被删除、
/// 还款登记被作废，审查 R-07）写明原因 [systemReason]。
class ReconciliationSummaryTile extends StatelessWidget {
  const ReconciliationSummaryTile({
    super.key,
    required this.item,
    this.onTap,
    this.systemReason,
  });

  final ReconciliationItemRow item;
  final VoidCallback? onTap;

  /// 系统处理的原因（`LedgerData.systemCloseReason`）。
  final String? systemReason;

  @override
  Widget build(BuildContext context) {
    final kind = ReconciliationKind.of(item.kind);
    final status = ReconciliationStatus.of(item.status);
    return ListTile(
      onTap: onTap,
      title: Text(kind.label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('来源：${kind.source}'),
          if (status == ReconciliationStatus.open)
            Text('建议：${kind.suggestion}')
          else
            Text(
              '结果：${systemReason == null ? ReconciliationResolution.of(item.resolution!).label : '系统处理（$systemReason）'}'
              ' · 处理者：${ResolvedBy.of(item.resolvedBy!).label} · ${timestampText(item.resolvedAt!)}',
            ),
          Padding(
            padding: const EdgeInsets.only(top: CfSpace.xxs),
            child: reconciliationBadge(status),
          ),
        ],
      ),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
    );
  }
}

/// 差异项引用的还款（界面显示用）。
List<String> itemRepayments(ReconciliationItemRow item) =>
    referencedRepayments(item);
