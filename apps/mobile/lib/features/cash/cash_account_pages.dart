import 'dart:async';

import 'package:cardflow_domain/cardflow_domain.dart'
    show LocalDate, Timestamp, minorDigits;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/confirm_dialog.dart';
import '../../app/widgets/feedback.dart';
import '../../app/widgets/state_views.dart';
import '../../data/db/app_database.dart';
import '../../data/ids.dart';
import '../../data/mapping/cash_mapping.dart';
import '../../data/repositories/cash_account_repository.dart';
import '../../data/repositories/cash_models.dart';
import '../../data/repositories/cash_plan_reader.dart';
import '../../data/repositories/models.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/repository_errors.dart';
import '../../data/time/business_tz.dart';
import '../../data/time/clock.dart';
import '../../data/validation/text_rules.dart';
import '../cards/amount_input.dart';
import '../cards/card_dialogs.dart';
import '../cards/card_formatting.dart';
import 'cash_form_fields.dart';
import 'cash_formatting.dart';
import 'cash_page.dart';
import 'cash_providers.dart';

/// 保存后回到上一页（全屏页从根导航器弹出；没有上一页时回到现金与收支）。
void _close(BuildContext context, [String fallback = AppRoutes.cash]) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}

/// 现金时区里"现在"的 `HH:MM`。
String _nowHourMinute(WidgetRef ref) => timestampTextIn(
  ref.read(clockProvider).now(),
  cashTimeZone,
).substring(11, 16);

/// 现金时区里某天某时刻的时间戳。
Timestamp _cashTimestamp(LocalDate date, (int, int) time) => Timestamp.parse(
  timestampTextIn(
    instantAt(date, cashTimeZone, hour: time.$1, minute: time.$2),
    cashTimeZone,
  ),
);

/// P-08「添加账户」：名称、种类（理财/受限默认不可当日还款）、币种、可用于还款、可用日期、储备，以及可选
/// 的初始余额（余额 + 日期 + 实际时点；缺实际时点不可存，UF-1 步骤 4）。
class NewCashAccountPage extends ConsumerStatefulWidget {
  const NewCashAccountPage({super.key});

  static const String title = '添加现金账户';

  @override
  ConsumerState<NewCashAccountPage> createState() => _NewCashAccountPageState();
}

class _NewCashAccountPageState extends ConsumerState<NewCashAccountPage> {
  /// 预先生成：重试保存不重复建账户。
  final String _id = newUuidV4();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _reserve = TextEditingController();
  final TextEditingController _balance = TextEditingController();
  final TextEditingController _time = TextEditingController();
  CashAccountKind _kind = CashAccountKind.bank;
  String _currency = 'CNY';
  bool? _usable;
  LocalDate? _availableFrom;
  LocalDate? _balanceDate;
  final Map<String, String> _errors = <String, String>{};
  String? _saveError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _time.text = _nowHourMinute(ref);
  }

  @override
  void dispose() {
    for (final c in <TextEditingController>[_name, _reserve, _balance, _time]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _usableValue => _kind == CashAccountKind.restricted
      ? false
      : (_usable ?? _kind.usableByDefault);

  Future<void> _save() async {
    final errors = <String, String>{};
    final nameProblem = validateFreeText(
      _name.text,
      required: true,
      fieldName: '账户名称',
    );
    if (nameProblem != null) {
      errors['name'] = nameProblem;
    }
    final (reserve, reserveError) = parseAmountMinor(
      _reserve.text,
      _currency,
      required: false,
    );
    if (reserveError != null) {
      errors['reserveFloor'] = reserveError;
    }
    final (balance, balanceError) = parseAmountMinor(
      _balance.text,
      _currency,
      allowNegative: true,
      required: false,
    );
    if (balanceError != null) {
      errors['balance'] = balanceError;
    }
    final (time, timeError) = parseHourMinute(
      _time.text,
      required: balance != null,
    );
    if (balance != null && timeError != null) {
      errors['time'] = timeError;
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
    try {
      final today = ref.read(clockProvider).today(cashTimeZone);
      final accounts = await ref.read(cashAccountRepositoryProvider.future);
      final row = await accounts.create(
        NewCashAccount(
          id: _id,
          name: _name.text,
          kind: _kind,
          currency: _currency,
          usableForRepayment: _usableValue,
          availableFrom: _availableFrom,
          reserveFloorMinor: reserve ?? 0,
        ),
      );
      if (balance != null) {
        final date = _balanceDate ?? today;
        final snapshots = await ref.read(cashSnapshotRepositoryProvider.future);
        await snapshots.record(
          CashSnapshotDraft(
            cashAccountId: row.id,
            balanceMinor: balance,
            balanceAsOf: date,
            observedAt: _cashTimestamp(date, time!),
          ),
        );
      }
      showFeedback(messenger, CashPage.savedMessage);
      if (mounted) {
        _close(context);
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
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: colors.textSecondary,
    );
    final today = ref.watch(clockProvider).today(cashTimeZone);
    return Scaffold(
      appBar: AppBar(title: const Text(NewCashAccountPage.title)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: CfSpace.xl),
        children: <Widget>[
          FormTextField(
            controller: _name,
            label: '账户名称（≤20 字）',
            error: _errors['name'],
          ),
          ChoiceWrap<CashAccountKind>(
            label: '种类',
            values: CashAccountKind.values,
            selected: _kind,
            labelOf: (k) => k.label,
            onSelected: (k) => setState(() {
              _kind = k;
              _usable = null;
            }),
          ),
          ChoiceWrap<String>(
            label: '币种',
            values: minorDigits.keys.toList(),
            selected: _currency,
            labelOf: currencyLabel,
            onSelected: (value) => setState(() => _currency = value),
          ),
          SwitchListTile(
            title: const Text('可用于还款'),
            subtitle: Text(
              _kind == CashAccountKind.restricted
                  ? '受限资金不能直接用于还款；可以设置可用日期'
                  : '理财、受限资金默认不可当日用于还款',
            ),
            value: _usableValue,
            onChanged: _kind == CashAccountKind.restricted
                ? null
                : (value) => setState(() => _usable = value),
          ),
          formPadded(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                DateField(
                  label: '可用日期（可选：从这天起可用于还款）',
                  value: _availableFrom,
                  initial: today,
                  first: LocalDate(2000, 1, 1),
                  last: today.addDays(3650),
                  onChanged: (value) => setState(() => _availableFrom = value),
                ),
                if (_availableFrom != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () => setState(() => _availableFrom = null),
                      child: const Text('清除可用日期'),
                    ),
                  ),
              ],
            ),
          ),
          FormTextField(
            controller: _reserve,
            label: '最低储备（可选，不低于 0）',
            error: _errors['reserveFloor'],
            keyboardType: FormTextField.amountKeyboard,
            helper: '资金日历按它判断"距储备"的缺口',
          ),
          const SectionTitle('初始余额（可选）'),
          formPadded(Text('填了余额就必须填实际时点；之后可在账户详情里记录新快照。', style: secondary)),
          FormTextField(
            controller: _balance,
            label: '余额（可为负：透支）',
            error: _errors['balance'],
            keyboardType: FormTextField.amountKeyboard,
          ),
          formPadded(
            DateField(
              label: '余额日期（不晚于今天）',
              value: _balanceDate ?? today,
              first: LocalDate(2000, 1, 1),
              last: today,
              onChanged: (value) => setState(() => _balanceDate = value),
            ),
          ),
          FormTextField(
            controller: _time,
            label: '实际时点（HH:MM，${cashTimeZone.displayName}）',
            error: _errors['time'] ?? _errors['observedAt'],
            keyboardType: TextInputType.datetime,
          ),
          if (_saveError != null)
            NoticeCard(
              icon: Icons.error_outline,
              tone: NoticeTone.danger,
              text: '没有保存：$_saveError',
            ),
          formPadded(
            FilledButton(
              onPressed: _saving ? null : () => unawaited(_save()),
              child: Text(_saving ? '正在保存…' : '保存'),
            ),
          ),
        ],
      ),
    );
  }
}

/// P-08 现金账户详情：概况（种类、可用性、储备、最新余额与"{n} 天前"）、快照历史（含已包含的事件）、
/// 本账户的收支与周期事项；「记录新快照」「修改」「停用/恢复使用」。
class CashAccountDetailPage extends ConsumerWidget {
  const CashAccountDetailPage({super.key, required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(cashAccountDetailProvider(accountId));
    return Scaffold(
      appBar: AppBar(title: Text(detail.value?.summary.row.name ?? '现金账户')),
      body: switch (detail) {
        AsyncData(:final value) => _AccountDetail(view: value),
        AsyncError(:final error) when error is NotFoundException => ErrorBlock(
          title: '已不存在',
          detail: '这个现金账户不在当前空间里（可能已切换空间）。',
          onRetry: () => context.go(AppRoutes.cash),
          retryLabel: '回到现金与收支',
        ),
        AsyncError(:final error) => ErrorBlock(
          title: '读取失败',
          code: '${error.runtimeType}',
          detail: '本机数据没有改动。',
          onRetry: () => ref.invalidate(cashAccountDetailProvider(accountId)),
        ),
        _ => const LoadingSkeleton(rows: 4),
      },
    );
  }
}

class _AccountDetail extends ConsumerWidget {
  const _AccountDetail({required this.view});

  final CashAccountDetailView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: colors.textSecondary,
    );
    final summary = view.summary;
    final row = summary.row;
    final snapshot = summary.latestSnapshot;
    final today = ref.watch(clockProvider).today(cashTimeZone);
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
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text('${summary.kind.label} · ${currencyLabel(row.currency)}'),
              AvailabilityBadge(summary.availability),
              if (!summary.active)
                const StatusBadge(
                  label: '已停用',
                  icon: Icons.pause_circle_outline,
                ),
              if (summary.stale) StaleBadge(ageDays: summary.ageDays!),
            ],
          ),
        ),
        LabeledValue(
          label: '最新余额',
          value: snapshot == null
              ? const Text('—')
              : BalanceText(
                  minor: snapshot.balanceMinor,
                  currency: row.currency,
                  semanticsPrefix: '最新余额',
                ),
        ),
        if (snapshot != null)
          LabeledValue(
            label: '余额日期',
            value: Text(
              '${snapshot.balanceAsOf}（${ageText(summary.ageDays!)}）',
            ),
          ),
        LabeledValue(
          label: '最低储备',
          value: BalanceText(
            minor: row.reserveFloorMinor,
            currency: row.currency,
            semanticsPrefix: '最低储备',
          ),
        ),
        if (summary.missingSnapshot)
          NoticeCard(
            icon: Icons.checklist,
            text: '数据不全：还没有余额快照，资金日历未计入这个账户（不补零）。',
            action: OutlinedButton(
              onPressed: () => context.go(AppRoutes.recordCashSnapshot(row.id)),
              child: const Text('记录新快照'),
            ),
          ),
        if (summary.stale)
          NoticeCard(
            icon: Icons.access_time,
            text: '余额快照已是 ${ageText(summary.ageDays!)}，依赖它的结果是"假设分析"。',
            action: OutlinedButton(
              onPressed: () => context.go(AppRoutes.recordCashSnapshot(row.id)),
              child: const Text('记录新快照'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(CfSpace.md),
          child: Wrap(
            spacing: CfSpace.xs,
            runSpacing: CfSpace.xs,
            children: <Widget>[
              if (summary.active)
                FilledButton(
                  onPressed: () =>
                      context.go(AppRoutes.recordCashSnapshot(row.id)),
                  child: const Text('记录新快照'),
                ),
              OutlinedButton(
                onPressed: () => unawaited(_edit(context, ref, row)),
                child: const Text('修改账户'),
              ),
              OutlinedButton(
                onPressed: () => unawaited(_toggleStatus(context, ref, row)),
                child: Text(summary.active ? '停用' : '恢复使用'),
              ),
            ],
          ),
        ),
        const SectionTitle('快照历史'),
        if (view.snapshots.isEmpty)
          formPadded(Text('还没有余额快照。', style: secondary)),
        for (final entry in view.snapshots)
          ListTile(
            title: Wrap(
              spacing: CfSpace.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(entry.row.balanceAsOf),
                BalanceText(
                  minor: entry.row.balanceMinor,
                  currency: row.currency,
                  semanticsPrefix: '余额',
                  textAlign: TextAlign.start,
                ),
              ],
            ),
            subtitle: Text(
              '实际时点 ${entry.row.observedAt.substring(0, 16).replaceFirst('T', ' ')} · '
              '${SnapshotSource.of(entry.row.sourceKind).label} · '
              '${ConfirmationLevel.of(entry.row.confirmationLevel).label}\n'
              '${entry.included.isEmpty ? '余额未包含当天的任何收支' : '余额已包含：${entry.included.map(cashEventTitle).join('、')}'}',
            ),
          ),
        const SectionTitle('本账户的收支'),
        if (view.events.isEmpty) formPadded(Text('最近没有收支。', style: secondary)),
        for (final e in view.events)
          ListTile(
            onTap: e.transferGroupId == null && e.recurringItemId == null
                ? () => context.go(AppRoutes.cashEvent(e.id))
                : e.recurringItemId != null
                ? () => context.go(AppRoutes.recurring(e.recurringItemId!))
                : null,
            title: Text(cashEventTitle(e)),
            subtitle: Text(cashEventSubtitle(e, today)),
            trailing: CashFlowLabel(
              amountMinor: e.amountMinor,
              currency: row.currency,
            ),
          ),
        if (view.recurring.isNotEmpty) ...<Widget>[
          const SectionTitle('周期事项'),
          for (final item in view.recurring)
            ListTile(
              onTap: () => context.go(AppRoutes.recurring(item.id)),
              title: Text(item.label),
              subtitle: Text(
                '${RecurringFrequency.of(item.frequency).label} · ${item.active ? '启用' : '已停用'}',
              ),
              trailing: CashFlowLabel(
                amountMinor: item.amountMinor,
                currency: row.currency,
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _toggleStatus(
    BuildContext context,
    WidgetRef ref,
    CashAccountRow row,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final closing = row.status == CashAccountStatus.active.code;
    final confirmed = await confirmAction(
      context,
      title: closing ? '停用这个现金账户？' : '恢复使用这个现金账户？',
      message: closing
          ? '影响：这 1 个账户不再进入资金日历与可用现金；快照、收支与周期事项都保留，可以恢复。'
          : '恢复后重新进入资金日历。',
      confirmLabel: closing ? '停用' : '恢复使用',
    );
    if (!confirmed) {
      return;
    }
    final repo = await ref.read(cashAccountRepositoryProvider.future);
    await repo.setStatus(
      row.id,
      closing ? CashAccountStatus.closed : CashAccountStatus.active,
    );
    showFeedback(messenger, CashPage.savedMessage);
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    CashAccountRow row,
  ) async {
    final result = await showDialog<_AccountEdit>(
      context: context,
      builder: (_) => _EditAccountDialog(row: row),
    );
    if (result == null || !context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(cashAccountRepositoryProvider.future);
      await repo.update(
        row.id,
        name: result.name,
        usableForRepayment: result.usable,
        reserveFloorMinor: result.reserve,
        availableFrom: result.availableFrom,
        clearAvailableFrom: result.availableFrom == null,
      );
      showFeedback(messenger, CashPage.savedMessage);
    } on RepositoryException catch (error) {
      showFeedback(messenger, '没有保存：${error.message}');
    }
  }
}

typedef _AccountEdit = ({
  String name,
  bool usable,
  int reserve,
  LocalDate? availableFrom,
});

class _EditAccountDialog extends StatefulWidget {
  const _EditAccountDialog({required this.row});

  final CashAccountRow row;

  @override
  State<_EditAccountDialog> createState() => _EditAccountDialogState();
}

class _EditAccountDialogState extends State<_EditAccountDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.row.name,
  );
  late final TextEditingController _reserve = TextEditingController(
    text: amountText(widget.row.reserveFloorMinor, widget.row.currency),
  );
  late bool _usable = widget.row.usableForRepayment;
  late LocalDate? _availableFrom = widget.row.availableFrom == null
      ? null
      : LocalDate.parse(widget.row.availableFrom!);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _reserve.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final restricted = widget.row.kind == CashAccountKind.restricted.code;
    return AlertDialog(
      title: const Text('修改现金账户'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _name,
              autofillHints: null,
              decoration: const InputDecoration(
                labelText: '账户名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: CfSpace.sm),
            TextField(
              controller: _reserve,
              autofillHints: null,
              keyboardType: FormTextField.amountKeyboard,
              decoration: const InputDecoration(
                labelText: '最低储备',
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('可用于还款'),
              value: !restricted && _usable,
              onChanged: restricted ? null : (v) => setState(() => _usable = v),
            ),
            DateField(
              label: '可用日期（可选）',
              value: _availableFrom,
              first: LocalDate(2000, 1, 1),
              last: LocalDate(2099, 12, 31),
              initial: LocalDate(2026, 1, 1),
              onChanged: (v) => setState(() => _availableFrom = v),
            ),
            if (_availableFrom != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => setState(() => _availableFrom = null),
                  child: const Text('清除可用日期'),
                ),
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: CardFlowColors.of(context).danger.fg),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final (reserve, error) = parseAmountMinor(
              _reserve.text,
              widget.row.currency,
            );
            final nameProblem = validateFreeText(
              _name.text,
              required: true,
              fieldName: '账户名称',
            );
            if (error != null || nameProblem != null) {
              setState(() => _error = nameProblem ?? error);
              return;
            }
            Navigator.of(context).pop((
              name: _name.text,
              usable: !restricted && _usable,
              reserve: reserve!,
              availableFrom: _availableFrom,
            ));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// P-08「记录新快照」：余额、余额日期（不晚于今天）、实际时点（必填，缺实际时点不可存）、来源、确认层级；
/// 当天已有收支时逐条询问"余额是否已包含 {事件}"（R-CASH-06），全部回答后才能保存。
class RecordCashSnapshotPage extends ConsumerStatefulWidget {
  const RecordCashSnapshotPage({super.key, required this.accountId});

  final String accountId;

  static const String title = '记录新快照';

  @override
  ConsumerState<RecordCashSnapshotPage> createState() =>
      _RecordCashSnapshotPageState();
}

class _RecordCashSnapshotPageState
    extends ConsumerState<RecordCashSnapshotPage> {
  final TextEditingController _balance = TextEditingController();
  final TextEditingController _time = TextEditingController();
  LocalDate? _date;
  SnapshotSource _source = SnapshotSource.bankApp;
  ConfirmationLevel _level = ConfirmationLevel.userConfirmed;
  final Map<String, bool> _answers = <String, bool>{};
  final Map<String, String> _errors = <String, String>{};
  String? _saveError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _time.text = _nowHourMinute(ref);
  }

  @override
  void dispose() {
    _balance.dispose();
    _time.dispose();
    super.dispose();
  }

  Future<void> _save(
    CashAccountRow account,
    LocalDate date,
    List<CashEventRow> sameDay,
  ) async {
    final errors = <String, String>{};
    final (balance, balanceError) = parseAmountMinor(
      _balance.text,
      account.currency,
      allowNegative: true,
    );
    if (balanceError != null) {
      errors['balance'] = balanceError;
    }
    final (time, timeError) = parseHourMinute(_time.text, required: true);
    if (timeError != null) {
      errors['time'] = timeError;
    }
    if (sameDay.any((e) => !_answers.containsKey(e.id))) {
      errors['includes'] = '请逐条回答：余额是否已包含当天的这些收支';
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
    try {
      final repo = await ref.read(cashSnapshotRepositoryProvider.future);
      await repo.record(
        CashSnapshotDraft(
          cashAccountId: account.id,
          balanceMinor: balance!,
          balanceAsOf: date,
          observedAt: _cashTimestamp(date, time!),
          source: _source,
          confirmationLevel: _level,
          sameDayAnswers: <String, bool>{
            for (final e in sameDay) e.id: _answers[e.id]!,
          },
        ),
      );
      showFeedback(messenger, CashPage.savedMessage);
      if (mounted) {
        _close(context, AppRoutes.cashAccount(account.id));
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
    final detail = ref.watch(cashAccountDetailProvider(widget.accountId));
    final today = ref.watch(clockProvider).today(cashTimeZone);
    final date = _date ?? today;
    final sameDay = ref.watch(
      sameDayCashEventsProvider(widget.accountId, date.toString()),
    );
    return Scaffold(
      appBar: AppBar(title: const Text(RecordCashSnapshotPage.title)),
      body: switch (detail) {
        AsyncData(:final value) => _form(
          context,
          value.summary.row,
          today,
          date,
          sameDay,
        ),
        AsyncError(:final error) when error is NotFoundException => ErrorBlock(
          title: '已不存在',
          detail: '这个现金账户不在当前空间里。',
          onRetry: () => context.go(AppRoutes.cash),
          retryLabel: '回到现金与收支',
        ),
        AsyncError(:final error) => ErrorBlock(
          title: '读取失败',
          code: '${error.runtimeType}',
          onRetry: () =>
              ref.invalidate(cashAccountDetailProvider(widget.accountId)),
        ),
        _ => const LoadingSkeleton(),
      },
    );
  }

  Widget _form(
    BuildContext context,
    CashAccountRow account,
    LocalDate today,
    LocalDate date,
    AsyncValue<SameDayEvents> sameDay,
  ) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: colors.textSecondary,
    );
    final events = sameDay.value?.events ?? const <CashEventRow>[];
    return ListView(
      padding: const EdgeInsets.only(bottom: CfSpace.xl),
      children: <Widget>[
        formPadded(
          Text(
            '${account.name} · ${currencyLabel(account.currency)}',
            style: theme.textTheme.titleMedium,
          ),
        ),
        FormTextField(
          controller: _balance,
          label: '余额（可为负：透支）',
          error: _errors['balance'],
          keyboardType: FormTextField.amountKeyboard,
        ),
        formPadded(
          DateField(
            label: '余额日期（不晚于今天）',
            value: date,
            first: LocalDate(2000, 1, 1),
            last: today,
            onChanged: (value) => setState(() {
              _date = value;
              _answers.clear();
            }),
          ),
        ),
        FormTextField(
          controller: _time,
          label: '实际时点（HH:MM，必填，${cashTimeZone.displayName}）',
          error:
              _errors['time'] ??
              _errors['observedAt'] ??
              _errors['balanceAsOf'],
          keyboardType: TextInputType.datetime,
        ),
        ChoiceWrap<SnapshotSource>(
          label: '来源',
          values: const <SnapshotSource>[
            SnapshotSource.bankApp,
            SnapshotSource.statement,
            SnapshotSource.user,
          ],
          selected: _source,
          labelOf: (s) => s.label,
          onSelected: (s) => setState(() => _source = s),
        ),
        ChoiceWrap<ConfirmationLevel>(
          label: '确认层级',
          values: const <ConfirmationLevel>[
            ConfirmationLevel.userConfirmed,
            ConfirmationLevel.bankConfirmed,
          ],
          selected: _level,
          labelOf: (l) => l.label,
          onSelected: (l) => setState(() => _level = l),
        ),
        if (events.isNotEmpty) ...<Widget>[
          const SectionTitle('当天已登记的收支'),
          formPadded(
            Text(
              '余额日期当天已有 ${events.length} 笔收支。请逐条回答余额是否已包含它：已包含的不再重复计入，未包含的计入当天。',
              style: secondary,
            ),
          ),
          for (final e in events)
            ChoiceWrap<bool>(
              label:
                  '余额是否已包含「${cashEventTitle(e)}」'
                  '${e.eventAt == null ? '' : '（${e.eventAt!.substring(11, 16)}）'}'
                  '：${e.amountMinor < 0 ? '支出' : '收入'} ${amountText(e.amountMinor.abs(), account.currency)}？',
              values: const <bool>[true, false],
              selected: _answers[e.id],
              labelOf: (v) => v ? '已包含' : '未包含',
              onSelected: (v) => setState(() => _answers[e.id] = v),
            ),
          if (_errors['includes'] != null)
            NoticeCard(
              icon: Icons.error_outline,
              tone: NoticeTone.danger,
              text: _errors['includes']!,
            ),
        ],
        if (_saveError != null)
          NoticeCard(
            icon: Icons.error_outline,
            tone: NoticeTone.danger,
            text: '没有保存：$_saveError',
          ),
        formPadded(
          FilledButton(
            onPressed: _saving || !sameDay.hasValue
                ? null
                : () => unawaited(_save(account, date, events)),
            child: Text(_saving ? '正在保存…' : '保存快照'),
          ),
        ),
      ],
    );
  }
}
