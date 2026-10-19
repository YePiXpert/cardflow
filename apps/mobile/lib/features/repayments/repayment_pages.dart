import 'dart:async';

import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate, Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/confirm_dialog.dart';
import '../../app/widgets/feedback.dart';
import '../../app/widgets/first_run_empty_state.dart';
import '../../app/widgets/money_text.dart';
import '../../app/widgets/state_views.dart';
import '../../data/db/app_database.dart';
import '../../data/mapping/cash_mapping.dart' show cashTimeZone;
import '../../data/repositories/cash_models.dart';
import '../../data/repositories/ledger_models.dart';
import '../../data/repositories/ledger_reader.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/reconciliation_repository.dart';
import '../../data/repositories/repayment_repository.dart';
import '../../data/repositories/repository_errors.dart';
import '../../data/time/business_tz.dart';
import '../cards/amount_input.dart';
import '../cards/card_dialogs.dart';
import '../cards/card_formatting.dart';
import '../cash/cash_form_fields.dart';
import '../statements/ledger_formatting.dart';
import '../statements/statement_pages.dart' show ReconciliationSummaryTile;

/// 还款的一行：金额、状态、方式、账户、分配到的账单。
class RepaymentTile extends StatelessWidget {
  const RepaymentTile({
    super.key,
    required this.data,
    required this.repayment,
    this.accountId,
  });

  final LedgerData data;
  final RepaymentRow repayment;
  final String? accountId;

  @override
  Widget build(BuildContext context) {
    final status = RepaymentStatus.of(repayment.status);
    final today = data.todayByCurrencyAccount[repayment.currencyAccountId];
    final statements = <String>[
      for (final a in data.allocationsOf(repayment.id))
        if (data.statement(a.statementId) case final s?)
          today == null
              ? s.statementDate
              : formatShortDate(LocalDate.parse(s.statementDate), today),
    ];
    return ListTile(
      title: Wrap(
        spacing: CfSpace.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(data.accountName(repayment.currencyAccountId)),
          MoneyText(
            minor: repayment.amountMinor,
            currency: repayment.currency,
            semanticsPrefix: '还款',
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: CfSpace.xxs),
        child: Wrap(
          spacing: CfSpace.xs,
          runSpacing: CfSpace.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            repaymentStatusBadge(status),
            Text(RepaymentMethod.of(repayment.method).label),
            if (statements.isNotEmpty) Text('分到 ${statements.join('、')} 账单'),
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () =>
          context.go(AppRoutes.repayment(repayment.id, accountId: accountId)),
    );
  }
}

/// P-06 还款与核对（列表）：待核对的还款、差异清单（疑似重复、金额不符、未匹配、退款待核对，逐项处理）、
/// 全部还款、已处理的差异（结果与处理者，R-STMT-09）。
///
/// 四态：首次空白（"本期还没有还款记录"「登记还款」）、加载、错误（「重新加载」）、成功。
class RepaymentCenterPage extends ConsumerWidget {
  const RepaymentCenterPage({super.key, this.accountId});

  final String? accountId;

  static const String title = '还款与核对';

  /// ui-spec P-06 九态"首次空白"。
  static const String firstRunMessage = '本期还没有还款记录';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(ledgerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(title),
        actions: <Widget>[
          IconButton(
            tooltip: '登记还款',
            icon: const Icon(Icons.add),
            onPressed: () =>
                context.go(AppRoutes.newRepayment(accountId: accountId)),
          ),
        ],
      ),
      body: switch (ledger) {
        AsyncData(:final value) => _body(context, ref, value),
        AsyncError(:final error) => ErrorBlock(
          title: '还款读取失败',
          code: '${error.runtimeType}',
          detail: '本机数据没有改动。',
          onRetry: () => ref.invalidate(ledgerProvider),
          retryLabel: '重新加载',
        ),
        _ => const LoadingSkeleton(rows: 4),
      },
    );
  }

  bool _mine(LedgerData data, String currencyAccountId) =>
      accountId == null ||
      data.currencyAccounts[currencyAccountId]?.creditAccountId == accountId;

  Widget _body(BuildContext context, WidgetRef ref, LedgerData data) {
    final repayments = <RepaymentRow>[
      for (final r in data.repayments)
        if (_mine(data, r.currencyAccountId)) r,
    ];
    final items = <ReconciliationItemRow>[
      for (final item in data.items)
        if (accountId == null || _itemIsMine(data, item)) item,
    ];
    if (repayments.isEmpty && items.isEmpty) {
      return FirstRunEmptyState(
        icon: Icons.payments_outlined,
        message: firstRunMessage,
        purpose: '登记还款的双侧时间与证据，跟踪到银行确认；核对疑似重复、金额不符与未匹配的还款。',
        actions: <EmptyStateAction>[
          EmptyStateAction(
            label: '登记还款',
            onPressed: () =>
                context.go(AppRoutes.newRepayment(accountId: accountId)),
          ),
        ],
      );
    }
    final awaiting = <RepaymentRow>[
      for (final r in repayments)
        if (RepaymentStatus.of(r.status).awaitsEvidence) r,
    ];
    final open = <ReconciliationItemRow>[
      for (final i in items)
        if (i.status == ReconciliationStatus.open.code) i,
    ];
    final closed = <ReconciliationItemRow>[
      for (final i in items)
        if (i.status != ReconciliationStatus.open.code) i,
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: CfSpace.xl),
      children: <Widget>[
        SectionTitle('待核对的还款（${awaiting.length}）'),
        if (awaiting.isEmpty) formPadded(const Text('没有等待银行证据的还款。')),
        for (final r in awaiting)
          RepaymentTile(data: data, repayment: r, accountId: accountId),
        SectionTitle('差异清单（${open.length}）'),
        if (open.isEmpty) formPadded(const Text('没有待处理的差异。')),
        for (final item in open)
          _OpenItemCard(data: data, item: item, accountId: accountId),
        SectionTitle('全部还款（${repayments.length}）'),
        for (final r in repayments)
          RepaymentTile(data: data, repayment: r, accountId: accountId),
        if (closed.isNotEmpty) ...<Widget>[
          SectionTitle('已处理的差异（${closed.length}）'),
          for (final item in closed) ReconciliationSummaryTile(item: item),
        ],
      ],
    );
  }

  bool _itemIsMine(LedgerData data, ReconciliationItemRow item) {
    for (final r in referencedRepayments(item)) {
      final row = data.repayment(r);
      if (row != null && _mine(data, row.currencyAccountId)) {
        return true;
      }
    }
    final txnId = referencedTransaction(item);
    final txn = txnId == null ? null : data.transaction(txnId);
    return txn != null && _mine(data, txn.currencyAccountId);
  }
}

/// 一个待处理的差异项与它的处理动作（R-STMT-09：类型、来源、建议动作；处理结果与处理者在处理后显示）。
class _OpenItemCard extends ConsumerWidget {
  const _OpenItemCard({
    required this.data,
    required this.item,
    required this.accountId,
  });

  final LedgerData data;
  final ReconciliationItemRow item;
  final String? accountId;

  Future<void> _run(
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final kind = ReconciliationKind.of(item.kind);
    final refs = reconciliationRefsOf(item);
    final repayments = <RepaymentRow>[
      for (final id in referencedRepayments(item)) ?data.repayment(id),
    ];
    final txnId = referencedTransaction(item);
    final txn = txnId == null ? null : data.transaction(txnId);
    Future<ReconciliationRepository> items() =>
        ref.read(reconciliationRepositoryProvider.future);
    Future<RepaymentRepository> repo() =>
        ref.read(repaymentRepositoryProvider.future);
    final actions = <Widget>[
      if (kind == ReconciliationKind.duplicateRepayment) ...<Widget>[
        FilledButton(
          onPressed: () => unawaited(
            _run(
              context,
              () async => (await repo()).resolveDuplicate(item.id),
              '已标记：确为两笔还款',
            ),
          ),
          child: const Text('确为两笔'),
        ),
        for (final r in repayments)
          OutlinedButton(
            onPressed: () => unawaited(
              _run(
                context,
                () async => (await repo()).resolveDuplicate(
                  item.id,
                  voidRepaymentId: r.id,
                ),
                '已作废重复的登记',
              ),
            ),
            child: Text('同一笔：作废"${RepaymentMethod.of(r.method).label}"那笔'),
          ),
      ],
      if (kind == ReconciliationKind.refundPending) ...<Widget>[
        FilledButton(
          onPressed: () => unawaited(
            _run(
              context,
              () async => (await items()).resolve(
                item.id,
                ReconciliationResolution.offset,
              ),
              '已标记：退款已冲抵应还',
            ),
          ),
          child: const Text('已冲抵应还'),
        ),
        OutlinedButton(
          onPressed: () => unawaited(
            _run(
              context,
              () async => (await items()).resolve(
                item.id,
                ReconciliationResolution.notOffset,
              ),
              '已标记：退款未冲抵本期应还',
            ),
          ),
          child: const Text('未冲抵本期应还'),
        ),
      ],
      if (kind == ReconciliationKind.amountMismatch)
        FilledButton(
          onPressed: () => unawaited(
            _run(
              context,
              () async => (await items()).resolve(
                item.id,
                ReconciliationResolution.acknowledged,
              ),
              '已核对',
            ),
          ),
          child: const Text('已核对'),
        ),
      if (kind == ReconciliationKind.unmatchedRepayment) ...<Widget>[
        FilledButton(
          onPressed: () => context.go(
            AppRoutes.newRepayment(
              accountId: accountId,
              currencyAccountId: txn?.currencyAccountId,
            ),
          ),
          child: const Text('去登记还款'),
        ),
        OutlinedButton(
          onPressed: () => unawaited(
            _run(
              context,
              () async => (await items()).resolve(
                item.id,
                ReconciliationResolution.registered,
              ),
              '已标记：已登记对应还款',
            ),
          ),
          child: const Text('已登记对应还款'),
        ),
      ],
      TextButton(
        onPressed: () => unawaited(
          _run(context, () async => (await items()).dismiss(item.id), '已忽略'),
        ),
        child: const Text('忽略'),
      ),
    ];
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
              Wrap(
                spacing: CfSpace.xs,
                runSpacing: CfSpace.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(kind.label, style: theme.textTheme.bodyLarge),
                  reconciliationBadge(ReconciliationStatus.open),
                ],
              ),
              Text('来源：${kind.source}'),
              Text('建议：${kind.suggestion}'),
              for (final r in repayments)
                RepaymentTile(data: data, repayment: r, accountId: accountId),
              if (txn != null)
                LedgerAmountRow(
                  label:
                      '${TxnType.of(txn.txnType).label} · ${txn.merchant ?? data.accountName(txn.currencyAccountId)} · ${timestampText(txn.txnAt)}',
                  minor: txn.amountMinor,
                  currency: txn.currency,
                  negativeLabel: '贷记',
                ),
              if (kind == ReconciliationKind.amountMismatch &&
                  repayments.isNotEmpty) ...<Widget>[
                LedgerAmountRow(
                  label: '登记金额',
                  minor: refs['expected_minor'] as int?,
                  currency: repayments.first.currency,
                ),
                LedgerAmountRow(
                  label: refs['side'] == 'cash' ? '实际扣款' : '银行入账',
                  minor: refs['actual_minor'] as int?,
                  currency: repayments.first.currency,
                ),
              ],
              const SizedBox(height: CfSpace.xs),
              Wrap(
                spacing: CfSpace.xs,
                runSpacing: CfSpace.xs,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 时点输入（日期 + HH:MM），可选带金额；用于「标记已发起」「确认扣款」「上传入账证据」「银行确认」。
final class TimePointInput {
  const TimePointInput(this.at, {this.amountMinor, this.debitedAt});

  final Timestamp at;
  final int? amountMinor;
  final Timestamp? debitedAt;
}

Future<TimePointInput?> showTimePointDialog(
  BuildContext context, {
  required String title,
  required String label,
  required LocalDate today,
  required BusinessTimeZone zone,
  String? amountLabel,
  String? currency,
  String? debitLabel,
}) => showDialog<TimePointInput>(
  context: context,
  builder: (_) => _TimePointDialog(
    title: title,
    label: label,
    today: today,
    zone: zone,
    amountLabel: amountLabel,
    currency: currency,
    debitLabel: debitLabel,
  ),
);

class _TimePointDialog extends StatefulWidget {
  const _TimePointDialog({
    required this.title,
    required this.label,
    required this.today,
    required this.zone,
    this.amountLabel,
    this.currency,
    this.debitLabel,
  });

  final String title;
  final String label;
  final LocalDate today;
  final BusinessTimeZone zone;
  final String? amountLabel;
  final String? currency;
  final String? debitLabel;

  @override
  State<_TimePointDialog> createState() => _TimePointDialogState();
}

class _TimePointDialogState extends State<_TimePointDialog> {
  late LocalDate _date = widget.today;
  late LocalDate _debitDate = widget.today;
  final TextEditingController _time = TextEditingController();
  final TextEditingController _debitTime = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _time.dispose();
    _debitTime.dispose();
    _amount.dispose();
    super.dispose();
  }

  Timestamp _at(LocalDate date, (int, int) time) => Timestamp.parse(
    timestampTextIn(
      instantAt(date, widget.zone, hour: time.$1, minute: time.$2),
      widget.zone,
    ),
  );

  void _submit() {
    final (time, timeError) = parseHourMinute(_time.text, required: true);
    if (timeError != null) {
      setState(() => _error = timeError);
      return;
    }
    Timestamp? debited;
    if (widget.debitLabel != null) {
      final (dt, debitError) = parseHourMinute(_debitTime.text, required: true);
      if (debitError != null) {
        setState(() => _error = '扣款时刻：$debitError');
        return;
      }
      debited = _at(_debitDate, dt!);
    }
    int? amount;
    if (widget.amountLabel != null && _amount.text.trim().isNotEmpty) {
      final (value, amountError) = parseAmountMinor(
        _amount.text,
        widget.currency!,
      );
      if (amountError != null || value == 0) {
        setState(() => _error = amountError ?? '金额须大于 0');
        return;
      }
      amount = value;
    }
    Navigator.of(context).pop(
      TimePointInput(
        _at(_date, time!),
        amountMinor: amount,
        debitedAt: debited,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (widget.debitLabel != null) ...<Widget>[
              DateField(
                label: '${widget.debitLabel}日期',
                value: _debitDate,
                first: widget.today.addDays(-366),
                last: widget.today,
                onChanged: (v) => setState(() => _debitDate = v),
              ),
              const SizedBox(height: CfSpace.sm),
              TextField(
                controller: _debitTime,
                keyboardType: TextInputType.datetime,
                autofillHints: null,
                decoration: InputDecoration(
                  labelText: '${widget.debitLabel}时刻（HH:MM）',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: CfSpace.sm),
            ],
            DateField(
              label: '${widget.label}日期（${widget.zone.label}时间）',
              value: _date,
              first: widget.today.addDays(-366),
              last: widget.today,
              onChanged: (v) => setState(() => _date = v),
            ),
            const SizedBox(height: CfSpace.sm),
            TextField(
              controller: _time,
              keyboardType: TextInputType.datetime,
              autofillHints: null,
              decoration: InputDecoration(
                labelText: '${widget.label}时刻（HH:MM，不晚于现在）',
                border: const OutlineInputBorder(),
              ),
            ),
            if (widget.amountLabel != null) ...<Widget>[
              const SizedBox(height: CfSpace.sm),
              TextField(
                controller: _amount,
                keyboardType: FormTextField.amountKeyboard,
                autofillHints: null,
                decoration: InputDecoration(
                  labelText: widget.amountLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: CfSpace.xs),
                child: Text(
                  _error!,
                  style: TextStyle(color: CardFlowColors.of(context).danger.fg),
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
}

/// P-06 还款详情：时间线（已登记 › 处理中 › 现金已扣 › 银行已入账 › 银行确认；失败；用户已标记；待核对；
/// 已冲正）、双侧时间、分配、现金时间线上的那条扣款、差异项、证据备注与按状态给出的动作。
///
/// 文案："已登记（待银行确认）"；不出现"还款成功"，不用绿色勾。
class RepaymentDetailPage extends ConsumerWidget {
  const RepaymentDetailPage({
    super.key,
    required this.repaymentId,
    this.accountId,
  });

  final String repaymentId;
  final String? accountId;

  static const String title = '还款';

  Future<void> _run(
    BuildContext context,
    Future<void> Function(RepaymentRepository repo) action,
    String success,
    WidgetRef ref,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(repaymentRepositoryProvider.future);
      await action(repo);
      showFeedback(messenger, success);
    } on RepositoryException catch (error) {
      showFeedback(messenger, error.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(ledgerProvider);
    final row = ledger.value?.repayment(repaymentId);
    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: switch (ledger) {
        AsyncData() when row == null => ErrorBlock(
          title: '已不存在',
          detail: '这笔还款不在当前空间里，或已作废。',
          onRetry: () => context.go(AppRoutes.repayments(accountId: accountId)),
          retryLabel: '回到还款与核对',
        ),
        AsyncData(:final value) => _detail(context, ref, value, row!),
        AsyncError(:final error) => ErrorBlock(
          title: '还款读取失败',
          code: '${error.runtimeType}',
          detail: '本机数据没有改动。',
          onRetry: () => ref.invalidate(ledgerProvider),
          retryLabel: '重新加载',
        ),
        _ => const LoadingSkeleton(rows: 4),
      },
    );
  }

  Widget _detail(
    BuildContext context,
    WidgetRef ref,
    LedgerData data,
    RepaymentRow r,
  ) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final status = RepaymentStatus.of(r.status);
    final account = data.accountOf(r.currencyAccountId)!;
    final cash = r.cashAccountId == null
        ? null
        : data.cashAccounts[r.cashAccountId];
    final event = data.repaymentEvents[r.id];
    final today = data.todayByCurrencyAccount[r.currencyAccountId]!;
    final cashToday = data.cashToday;
    final steps = <(String, String?, bool)>[
      ('已登记', r.createdAt, true),
      ('处理中', r.paymentInitiatedAt, r.paymentInitiatedAt != null),
      ('现金已扣', r.cashDebitedAt, r.cashDebitedAt != null),
      ('银行已入账', r.creditPostedAt, r.creditPostedAt != null),
      ('银行确认', r.bankConfirmedAt, r.bankConfirmedAt != null),
    ];
    Future<void> time({
      required String title,
      required String label,
      required BusinessTimeZone zone,
      required LocalDate day,
      required Future<void> Function(RepaymentRepository, TimePointInput)
      action,
      required String success,
      String? amountLabel,
      String? debitLabel,
    }) async {
      final input = await showTimePointDialog(
        context,
        title: title,
        label: label,
        today: day,
        zone: zone,
        amountLabel: amountLabel,
        currency: r.currency,
        debitLabel: debitLabel,
      );
      if (input == null || !context.mounted) {
        return;
      }
      await _run(context, (repo) => action(repo, input), success, ref);
    }

    final actions = <Widget>[
      if (status == RepaymentStatus.recorded)
        OutlinedButton(
          onPressed: () => unawaited(
            time(
              title: '标记已发起',
              label: '发起',
              zone: cashTimeZone,
              day: cashToday,
              action: (repo, i) => repo.markInitiated(r.id, i.at),
              success: '已标记发起（处理中，待银行确认）',
            ),
          ),
          child: const Text('标记已发起'),
        ),
      if (status == RepaymentStatus.recorded ||
          status == RepaymentStatus.processing)
        FilledButton(
          onPressed: () => unawaited(
            time(
              title: '确认扣款',
              label: '扣款',
              zone: cashTimeZone,
              day: cashToday,
              amountLabel: '实际扣款金额（可选；与登记不同时生成"金额不符"）',
              action: (repo, i) => repo.confirmDebit(
                r.id,
                i.at,
                actualAmountMinor: i.amountMinor,
              ),
              success: '已记录现金扣款（待银行入账）',
            ),
          ),
          child: const Text('确认扣款'),
        ),
      if (status == RepaymentStatus.processing)
        OutlinedButton(
          onPressed: () => unawaited(
            _run(
              context,
              (repo) => repo.markFailed(r.id),
              '已标记失败：计划扣款已撤下',
              ref,
            ),
          ),
          child: const Text('标记失败'),
        ),
      if (status == RepaymentStatus.recorded)
        OutlinedButton(
          onPressed: () async {
            final ok = await confirmAction(
              context,
              title: '标记"我已还款"？',
              message: '这只是你的确认，不是银行确认：账单不会结清、负债不会核销，到期后仍无证据会变为"待核对"。',
              confirmLabel: '我已还款',
            );
            if (ok && context.mounted) {
              await _run(
                context,
                (repo) => repo.markUserPaid(r.id),
                '已记录：你已确认（待银行确认）',
                ref,
              );
            }
          },
          child: const Text('我已还款'),
        ),
      if (status == RepaymentStatus.cashDebited)
        FilledButton(
          onPressed: () => unawaited(
            time(
              title: '上传入账证据',
              label: '银行入账',
              zone: account.zone,
              day: today,
              amountLabel: '入账金额（可选；与登记不同时生成"金额不符"）',
              action: (repo, i) => repo.markCreditPosted(
                r.id,
                i.at,
                creditedAmountMinor: i.amountMinor,
              ),
              success: '已记录银行入账（待银行确认）',
            ),
          ),
          child: const Text('上传入账证据'),
        ),
      if (status == RepaymentStatus.creditPosted)
        FilledButton(
          onPressed: () => unawaited(
            time(
              title: '银行确认',
              label: '确认',
              zone: account.zone,
              day: today,
              action: (repo, i) => repo.confirmByBank(r.id, i.at),
              success: '已记录银行确认',
            ),
          ),
          child: const Text('银行确认'),
        ),
      if (status == RepaymentStatus.userMarkedPaid ||
          status == RepaymentStatus.needsReview)
        FilledButton(
          onPressed: () => unawaited(
            time(
              title: '银行确认（取得证据）',
              label: '确认',
              zone: account.zone,
              day: today,
              debitLabel: '实际扣款',
              action: (repo, i) =>
                  repo.confirmByBank(r.id, i.at, debitedAt: i.debitedAt),
              success: '已记录银行确认',
            ),
          ),
          child: const Text('银行确认（取得证据）'),
        ),
      if (status == RepaymentStatus.failed)
        FilledButton(
          onPressed: () => unawaited(
            _run(context, (repo) => repo.retry(r.id), '已重新登记（待银行确认）', ref),
          ),
          child: const Text('重试登记'),
        ),
      if (status == RepaymentStatus.bankConfirmed)
        OutlinedButton(
          onPressed: () async {
            final ok = await confirmAction(
              context,
              title: '银行冲正了这笔还款？',
              message: '冲正后这笔还款不再核销负债；已结清的账单状态不变，剩余应还按实际重新计算。',
              confirmLabel: '冲正',
              destructive: true,
            );
            if (ok && context.mounted) {
              await _run(context, (repo) => repo.reverse(r.id), '已记录冲正', ref);
            }
          },
          child: const Text('冲正'),
        ),
      if (const <RepaymentStatus>{
        RepaymentStatus.recorded,
        RepaymentStatus.failed,
        RepaymentStatus.userMarkedPaid,
        RepaymentStatus.needsReview,
      }.contains(status))
        TextButton(
          onPressed: () async {
            final ok = await confirmAction(
              context,
              title: '作废这笔登记？',
              message: '影响：这 1 笔还款登记与它在资金日历里的计划扣款一并作废，不可撤销。',
              confirmLabel: '作废',
              destructive: true,
            );
            if (ok && context.mounted) {
              await _run(context, (repo) => repo.delete(r.id), '已作废登记', ref);
            }
          },
          child: const Text('作废登记'),
        ),
    ];
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                data.accountName(r.currencyAccountId),
                style: theme.textTheme.titleMedium,
              ),
              MoneyText(
                minor: r.amountMinor,
                currency: r.currency,
                semanticsPrefix: '还款',
                textAlign: TextAlign.start,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: CfSpace.xxs),
              Wrap(
                spacing: CfSpace.xs,
                runSpacing: CfSpace.xxs,
                children: <Widget>[
                  repaymentStatusBadge(status),
                  Text(RepaymentMethod.of(r.method).label),
                ],
              ),
            ],
          ),
        ),
        if (status == RepaymentStatus.needsReview)
          const NoticeCard(
            icon: Icons.help_outline,
            text: '已过到期日仍没有银行证据：待核对（提醒不会消失，提醒降级在后续版本提供）。',
          ),
        if (status == RepaymentStatus.userMarkedPaid)
          const NoticeCard(
            icon: Icons.how_to_reg_outlined,
            tone: NoticeTone.unknown,
            text: '"我已还款"只是你的确认：账单不结清、负债不核销，等待银行入账证据。',
          ),
        if (cash != null &&
            CashAccountKind.of(cash.kind) == CashAccountKind.restricted)
          const NoticeCard(
            icon: Icons.lock_outline,
            text: '扣款账户是受限资金：它不计入可用现金（R-CASH-01）。',
          ),
        const SectionTitle('操作'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
          child: Wrap(
            spacing: CfSpace.xs,
            runSpacing: CfSpace.xs,
            children: actions,
          ),
        ),
        const SectionTitle('时间线'),
        for (final (label, at, reached) in steps)
          ListTile(
            dense: true,
            leading: ExcludeSemantics(
              child: Icon(
                reached
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: colors.textSecondary,
              ),
            ),
            title: Text(label),
            subtitle: Text(
              at == null ? (reached ? '' : '未到这一步') : timestampText(at),
            ),
          ),
        if (status == RepaymentStatus.failed ||
            status == RepaymentStatus.reversed)
          ListTile(
            dense: true,
            leading: ExcludeSemantics(
              child: Icon(Icons.error_outline, color: colors.danger.fg),
            ),
            title: Text(status.label),
          ),
        const SectionTitle('双侧时间'),
        LabeledValue(label: '预计扣款日', value: Text(r.expectedDebitOn ?? '未填写')),
        LabeledValue(
          label: '现金账户',
          value: Text(cash == null ? '未指定' : '${cash.name}（${cash.currency}）'),
        ),
        LabeledValue(
          label: '现金时间线',
          value: Text(
            event == null
                ? '没有扣款事件'
                : '${event.eventOn} ${PostingStatus.of(event.postingStatus) == PostingStatus.posted ? '已扣（确定）' : '计划扣款'}',
          ),
        ),
        LabeledValue(
          label: '负债核销日',
          value: Text(data.creditDates[r.id]?.toString() ?? '银行入账后才核销'),
        ),
        const SectionTitle('分配'),
        for (final a in data.allocationsOf(r.id))
          if (data.statement(a.statementId) case final s?)
            ListTile(
              title: Text(statementTitle(data, s)),
              subtitle: moneyRow('分配', a.amountMinor, r.currency),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  context.go(AppRoutes.statement(s.id, accountId: accountId)),
            ),
        if (data.itemsOfRepayment(r.id) case final items
            when items.isNotEmpty) ...<Widget>[
          const SectionTitle('差异'),
          for (final item in items)
            ReconciliationSummaryTile(
              item: item,
              onTap: () =>
                  context.go(AppRoutes.repayments(accountId: accountId)),
            ),
        ],
        const SectionTitle('证据'),
        LabeledValue(label: '证据备注', value: Text(r.evidenceNote ?? '未填写')),
        formPadded(const Text('附件（截图、账单文件，≤25 MB）随后续版本的导入功能提供；现在可以写备注。')),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: TextButton(
              onPressed: () async {
                final note = await showDialog<String>(
                  context: context,
                  builder: (_) => _NoteDialog(initial: r.evidenceNote ?? ''),
                );
                if (note == null || !context.mounted) {
                  return;
                }
                await _run(
                  context,
                  (repo) => repo.setEvidenceNote(r.id, note),
                  '已保存证据备注',
                  ref,
                );
              },
              child: const Text('编辑证据备注'),
            ),
          ),
        ),
      ],
    );
  }
}

/// 金额的一行（标签 + MoneyText）。
Widget moneyRow(String label, int? minor, String currency) => Wrap(
  spacing: CfSpace.sm,
  crossAxisAlignment: WrapCrossAlignment.center,
  children: <Widget>[
    Text(label),
    MoneyText(minor: minor, currency: currency, semanticsPrefix: label),
  ],
);

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.initial});

  final String initial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final TextEditingController _note = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('证据备注'),
    content: TextField(
      controller: _note,
      autofillHints: null,
      maxLines: 3,
      decoration: const InputDecoration(
        labelText: '≤200 字，不含完整卡号',
        border: OutlineInputBorder(),
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_note.text),
        child: const Text('保存'),
      ),
    ],
  );
}
