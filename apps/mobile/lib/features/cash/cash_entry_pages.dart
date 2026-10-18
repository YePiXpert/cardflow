import 'dart:async';

import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate, Timestamp;
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
import '../../data/repositories/cash_event_repository.dart';
import '../../data/repositories/cash_models.dart';
import '../../data/repositories/cash_plan_reader.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/recurring_item_repository.dart';
import '../../data/repositories/repository_errors.dart';
import '../../data/time/business_tz.dart';
import '../../data/time/clock.dart';
import '../cards/amount_input.dart';
import '../cards/card_dialogs.dart';
import '../cards/card_formatting.dart';
import 'cash_form_fields.dart';
import 'cash_formatting.dart';
import 'cash_page.dart';
import 'cash_providers.dart';

void _close(BuildContext context, [String fallback = AppRoutes.cash]) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}

/// 现金时区里某天某时刻的时间戳；[time] 为空时为 null（只知道日期）。
Timestamp? _timestampOn(LocalDate date, (int, int)? time) => time == null
    ? null
    : Timestamp.parse(
        timestampTextIn(
          instantAt(date, cashTimeZone, hour: time.$1, minute: time.$2),
          cashTimeZone,
        ),
      );

/// 日期选择的范围：今天往前一年到往后十年（[current] 更早时从它开始，避免已有的日期落在范围外）。
LocalDate _firstDate(LocalDate today, [LocalDate? current]) {
  final first = today.addDays(-366);
  return current != null && current < first ? current : first;
}

LocalDate _lastDate(LocalDate today) => today.addDays(3650);

/// 账户选择（可换行的单选标签：文字放大到 3 倍也不截断）。
class _AccountField extends StatelessWidget {
  const _AccountField({
    required this.label,
    required this.accounts,
    required this.value,
    required this.onChanged,
    this.error,
  });

  final String label;
  final List<CashAccountRow> accounts;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? error;

  @override
  Widget build(BuildContext context) => ChoiceWrap<String>(
    key: ValueKey<String>('account-field-$label'),
    label: label,
    values: <String>[for (final a in accounts) a.id],
    selected: value,
    labelOf: (id) {
      final a = accounts.firstWhere((x) => x.id == id);
      return '${a.name}（${a.currency}）';
    },
    onSelected: onChanged,
    error: error,
  );
}

Widget _saveErrorCard(String? error) => error == null
    ? const SizedBox.shrink()
    : NoticeCard(
        icon: Icons.error_outline,
        tone: NoticeTone.danger,
        text: '没有保存：$error',
      );

/// P-08「新增收支」/修改收支：类型（收入、固定生活支出、其他债务、一次性支出）、账户、层级（必选：确定/预计，
/// 没有概率字段）、日期、时刻（可选）、金额、名称。修改时另有「标记已发生」（G3）与「删除」。
class CashEventFormPage extends ConsumerStatefulWidget {
  const CashEventFormPage({super.key, this.eventId, this.initialType});

  /// 为空 = 新增。
  final String? eventId;
  final CashPlanType? initialType;

  static const String newTitle = '新增收支';
  static const String editTitle = '修改收支';

  @override
  ConsumerState<CashEventFormPage> createState() => _CashEventFormPageState();
}

class _CashEventFormPageState extends ConsumerState<CashEventFormPage> {
  final String _id = newUuidV4();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _time = TextEditingController();
  final TextEditingController _label = TextEditingController();
  late CashPlanType _type = widget.initialType ?? CashPlanType.income;
  String? _accountId;
  CashEventClass? _cls;
  LocalDate? _date;
  bool _loaded = false;
  final Map<String, String> _errors = <String, String>{};
  String? _saveError;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in <TextEditingController>[_amount, _time, _label]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(CashEventEntry entry) {
    if (_loaded) {
      return;
    }
    _loaded = true;
    final row = entry.row;
    _type = CashPlanType.ofEvent(row) ?? CashPlanType.oneOff;
    _accountId = row.cashAccountId;
    _cls = CashEventClass.of(row.cls);
    _date = LocalDate.parse(row.eventOn);
    _amount.text = amountText(row.amountMinor.abs(), entry.account.currency);
    _time.text = row.eventAt?.substring(11, 16) ?? '';
    _label.text = row.label ?? '';
  }

  Future<void> _save(String currency, LocalDate today) async {
    final errors = <String, String>{};
    if (_accountId == null) {
      errors['account'] = '请选择账户';
    }
    if (_cls == null) {
      errors['cls'] = CashClassField.missing;
    }
    final (amount, amountError) = parseAmountMinor(_amount.text, currency);
    if (amountError != null) {
      errors['amount'] = amountError;
    } else if (amount == 0) {
      errors['amount'] = '金额须大于 0';
    }
    final (time, timeError) = parseHourMinute(_time.text);
    if (timeError != null) {
      errors['at'] = timeError;
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
    final date = _date ?? today;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(cashEventRepositoryProvider.future);
      final eventId = widget.eventId;
      if (eventId == null) {
        await repo.create(
          CashEventDraft(
            cashAccountId: _accountId!,
            type: _type,
            cls: _cls!,
            on: date,
            at: _timestampOn(date, time),
            amountMinor: amount!,
            label: _label.text,
          ),
          id: _id,
        );
      } else {
        await repo.update(
          eventId,
          on: date,
          at: _timestampOn(date, time),
          clearAt: time == null,
          amountMinor: amount,
          cls: _cls,
          label: _label.text,
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

  Future<void> _markPosted(String eventId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(cashEventRepositoryProvider.future);
      await repo.markPosted(eventId);
      showFeedback(messenger, '已标记为已发生（确定）');
    } on RepositoryException catch (error) {
      if (mounted) {
        setState(() => _saveError = error.message);
      }
    }
  }

  Future<void> _delete(String eventId) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await confirmAction(
      context,
      title: '删除这笔收支？',
      message: '影响：这 1 笔收支从资金日历中移除；已经包含它的余额快照不受影响。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed) {
      return;
    }
    try {
      final repo = await ref.read(cashEventRepositoryProvider.future);
      await repo.delete(eventId);
      showFeedback(messenger, CashPage.savedMessage);
      if (mounted) {
        _close(context);
      }
    } on RepositoryException catch (error) {
      if (mounted) {
        setState(() => _saveError = error.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventId = widget.eventId;
    final plan = ref.watch(cashPlanProvider);
    final entry = eventId == null
        ? null
        : ref.watch(cashEventEntryProvider(eventId));
    final today = ref.watch(clockProvider).today(cashTimeZone);
    final title = eventId == null
        ? CashEventFormPage.newTitle
        : CashEventFormPage.editTitle;
    final Widget body;
    if (entry case AsyncError(:final error)) {
      body = ErrorBlock(
        title: error is NotFoundException ? '已不存在' : '读取失败',
        detail: '这笔收支不在当前空间里，或已删除。',
        onRetry: () => context.go(AppRoutes.cash),
        retryLabel: '回到现金与收支',
      );
    } else if (plan is AsyncError) {
      body = ErrorBlock(
        title: '读取失败',
        code: '${plan.error.runtimeType}',
        onRetry: () => ref.invalidate(cashPlanProvider),
      );
    } else if (!plan.hasValue || (entry != null && !entry.hasValue)) {
      body = const LoadingSkeleton();
    } else {
      if (entry != null) {
        _fill(entry.value!);
      }
      final accounts = plan.value!.activeAccounts;
      _accountId ??= accounts.isEmpty ? null : accounts.first.id;
      final account =
          accounts.where((a) => a.id == _accountId).firstOrNull ??
          entry?.value?.account;
      final row = entry?.value?.row;
      body = ListView(
        padding: const EdgeInsets.only(bottom: CfSpace.xl),
        children: <Widget>[
          if (eventId == null)
            ChoiceWrap<CashPlanType>(
              label: '类型',
              values: CashPlanType.values,
              selected: _type,
              labelOf: (t) => t.label,
              onSelected: (t) => setState(() => _type = t),
            )
          else
            formPadded(Text('类型：${_type.label} · 账户：${account?.name ?? ''}')),
          if (eventId == null)
            _AccountField(
              label: '账户',
              accounts: accounts,
              value: _accountId,
              error: _errors['account'],
              onChanged: (v) => setState(() => _accountId = v),
            ),
          CashClassField(
            selected: _cls,
            error: _errors['cls'],
            onSelected: (c) => setState(() => _cls = c),
          ),
          formPadded(
            DateField(
              label: '日期',
              value: _date ?? today,
              first: _firstDate(today, _date),
              last: _lastDate(today),
              onChanged: (v) => setState(() => _date = v),
            ),
          ),
          FormTextField(
            controller: _time,
            label: '时刻（可选，HH:MM；同日按时刻排序时需要）',
            error: _errors['at'],
            keyboardType: TextInputType.datetime,
          ),
          FormTextField(
            controller: _amount,
            label: '金额（${_type.sign < 0 ? '支出' : '收入'}，填正数）',
            error: _errors['amount'],
            keyboardType: FormTextField.amountKeyboard,
          ),
          FormTextField(
            controller: _label,
            label: '名称（可选，≤20 字）',
            error: _errors['label'],
          ),
          _saveErrorCard(_saveError),
          formPadded(
            FilledButton(
              onPressed: _saving || account == null
                  ? null
                  : () => unawaited(_save(account.currency, today)),
              child: Text(_saving ? '正在保存…' : '保存'),
            ),
          ),
          if (row != null) ...<Widget>[
            if (row.postingStatus == PostingStatus.planned.code)
              formPadded(
                OutlinedButton(
                  onPressed: LocalDate.parse(row.eventOn) > today
                      ? null
                      : () => unawaited(_markPosted(row.id)),
                  child: const Text('标记已发生'),
                ),
              ),
            if (row.postingStatus == PostingStatus.planned.code &&
                LocalDate.parse(row.eventOn) > today)
              formPadded(const Text('还没到这一天：到期后才能标记已发生。')),
            formPadded(
              OutlinedButton(
                onPressed: () => unawaited(_delete(row.id)),
                child: const Text('删除'),
              ),
            ),
          ],
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: body,
    );
  }
}

/// P-08「新增调拨」：转出与到账两端（不同账户、同币种），到账日不早于转出日；层级必选。
class TransferFormPage extends ConsumerStatefulWidget {
  const TransferFormPage({super.key});

  static const String title = '新增调拨';

  @override
  ConsumerState<TransferFormPage> createState() => _TransferFormPageState();
}

class _TransferFormPageState extends ConsumerState<TransferFormPage> {
  final String _group = newUuidV4();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _outTime = TextEditingController();
  final TextEditingController _inTime = TextEditingController();
  final TextEditingController _label = TextEditingController();
  String? _from;
  String? _to;
  LocalDate? _outOn;
  LocalDate? _inOn;
  CashEventClass? _cls;
  final Map<String, String> _errors = <String, String>{};
  String? _saveError;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in <TextEditingController>[
      _amount,
      _outTime,
      _inTime,
      _label,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(List<CashAccountRow> accounts, LocalDate today) async {
    final errors = <String, String>{};
    final from = accounts.where((a) => a.id == _from).firstOrNull;
    if (from == null) {
      errors['fromAccount'] = '请选择转出账户';
    }
    if (_to == null) {
      errors['toAccount'] = '请选择转入账户';
    }
    if (_cls == null) {
      errors['cls'] = CashClassField.missing;
    }
    final (amount, amountError) = parseAmountMinor(
      _amount.text,
      from?.currency ?? 'CNY',
    );
    if (amountError != null) {
      errors['amount'] = amountError;
    } else if (amount == 0) {
      errors['amount'] = '金额须大于 0';
    }
    final (outTime, outError) = parseHourMinute(_outTime.text);
    if (outError != null) {
      errors['outAt'] = outError;
    }
    final (inTime, inError) = parseHourMinute(_inTime.text);
    if (inError != null) {
      errors['inAt'] = inError;
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
    final outOn = _outOn ?? today;
    final inOn = _inOn ?? outOn;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(cashEventRepositoryProvider.future);
      await repo.createTransfer(
        TransferDraft(
          fromAccountId: _from!,
          toAccountId: _to!,
          amountMinor: amount!,
          outOn: outOn,
          inOn: inOn,
          outAt: _timestampOn(outOn, outTime),
          inAt: _timestampOn(inOn, inTime),
          cls: _cls!,
          label: _label.text,
        ),
        groupId: _group,
      );
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
    final plan = ref.watch(cashPlanProvider);
    final today = ref.watch(clockProvider).today(cashTimeZone);
    return Scaffold(
      appBar: AppBar(title: const Text(TransferFormPage.title)),
      body: switch (plan) {
        AsyncData(:final value) => _form(value.activeAccounts, today),
        AsyncError(:final error) => ErrorBlock(
          title: '读取失败',
          code: '${error.runtimeType}',
          onRetry: () => ref.invalidate(cashPlanProvider),
        ),
        _ => const LoadingSkeleton(),
      },
    );
  }

  Widget _form(List<CashAccountRow> accounts, LocalDate today) {
    final outOn = _outOn ?? today;
    return ListView(
      padding: const EdgeInsets.only(bottom: CfSpace.xl),
      children: <Widget>[
        _AccountField(
          label: '转出账户',
          accounts: accounts,
          value: _from,
          error: _errors['fromAccount'],
          onChanged: (v) => setState(() => _from = v),
        ),
        _AccountField(
          label: '转入账户（与转出不同、币种相同）',
          accounts: accounts,
          value: _to,
          error: _errors['toAccount'],
          onChanged: (v) => setState(() => _to = v),
        ),
        FormTextField(
          controller: _amount,
          label: '金额（填正数）',
          error: _errors['amount'],
          keyboardType: FormTextField.amountKeyboard,
        ),
        formPadded(
          DateField(
            label: '转出日期',
            value: outOn,
            first: _firstDate(today),
            last: _lastDate(today),
            onChanged: (v) => setState(() => _outOn = v),
          ),
        ),
        FormTextField(
          controller: _outTime,
          label: '转出时刻（可选，HH:MM）',
          error: _errors['outAt'],
          keyboardType: TextInputType.datetime,
        ),
        formPadded(
          DateField(
            label: '到账日期（不早于转出日）',
            value: _inOn ?? outOn,
            first: _firstDate(today),
            last: _lastDate(today),
            onChanged: (v) => setState(() => _inOn = v),
          ),
        ),
        if (_errors['inOn'] != null)
          formPadded(
            Text(
              _errors['inOn']!,
              style: TextStyle(color: CardFlowColors.of(context).danger.fg),
            ),
          ),
        FormTextField(
          controller: _inTime,
          label: '到账时刻（可选，HH:MM）',
          error: _errors['inAt'],
          keyboardType: TextInputType.datetime,
        ),
        CashClassField(
          selected: _cls,
          error: _errors['cls'],
          onSelected: (c) => setState(() => _cls = c),
        ),
        FormTextField(
          controller: _label,
          label: '名称（可选，≤20 字）',
          error: _errors['label'],
        ),
        _saveErrorCard(_saveError),
        formPadded(
          FilledButton(
            onPressed: _saving ? null : () => unawaited(_save(accounts, today)),
            child: Text(_saving ? '正在保存…' : '保存调拨'),
          ),
        ),
      ],
    );
  }
}

/// P-08「新增周期事项」/修改周期事项：账户、类型、层级（必选）、名称、金额、频率、第一期、日规则（每月/每年）、
/// 结束日（可选）。修改周期规则会重新生成今天之后的各期（单期例外随之清除）。
class RecurringFormPage extends ConsumerStatefulWidget {
  const RecurringFormPage({super.key, this.itemId});

  /// 为空 = 新增。
  final String? itemId;

  static const String newTitle = '新增周期事项';
  static const String editTitle = '修改周期事项';

  @override
  ConsumerState<RecurringFormPage> createState() => _RecurringFormPageState();
}

class _RecurringFormPageState extends ConsumerState<RecurringFormPage> {
  final String _id = newUuidV4();
  final TextEditingController _label = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  String? _accountId;
  CashPlanType _type = CashPlanType.living;
  CashEventClass? _cls;
  RecurringFrequency _frequency = RecurringFrequency.monthly;
  DayRule _dayRule = DayRule.anchorDay;
  LocalDate? _start;
  LocalDate? _end;
  bool _loaded = false;
  final Map<String, String> _errors = <String, String>{};
  String? _saveError;
  bool _saving = false;

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _fill(RecurringDetailView view) {
    if (_loaded) {
      return;
    }
    _loaded = true;
    final row = view.row;
    _accountId = row.cashAccountId;
    _label.text = row.label;
    _amount.text = amountText(row.amountMinor.abs(), view.account.currency);
    _type = switch (CashCategory.of(row.category)) {
      CashCategory.income => CashPlanType.income,
      CashCategory.living => CashPlanType.living,
      CashCategory.bill => CashPlanType.debt,
      _ => row.amountMinor < 0 ? CashPlanType.oneOff : CashPlanType.income,
    };
    _cls = CashEventClass.of(row.cls);
    _frequency = RecurringFrequency.of(row.frequency);
    _dayRule = DayRule.of(row.dayRule);
    _start = LocalDate.parse(row.startOn);
    _end = row.endOn == null ? null : LocalDate.parse(row.endOn!);
  }

  Future<void> _save(String currency, LocalDate today) async {
    final errors = <String, String>{};
    if (_accountId == null) {
      errors['account'] = '请选择账户';
    }
    if (_cls == null) {
      errors['cls'] = CashClassField.missing;
    }
    final (amount, amountError) = parseAmountMinor(_amount.text, currency);
    if (amountError != null) {
      errors['amount'] = amountError;
    } else if (amount == 0) {
      errors['amount'] = '金额须大于 0';
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
    final draft = RecurringItemDraft(
      cashAccountId: _accountId!,
      label: _label.text,
      type: _type,
      cls: _cls!,
      amountMinor: amount!,
      frequency: _frequency,
      startOn: _start ?? today,
      dayRule: _frequency.allowsMonthEnd ? _dayRule : DayRule.anchorDay,
      endOn: _end,
    );
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(recurringItemRepositoryProvider.future);
      final itemId = widget.itemId;
      if (itemId == null) {
        await repo.create(draft, id: _id);
      } else {
        await repo.update(itemId, draft);
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
    final itemId = widget.itemId;
    final plan = ref.watch(cashPlanProvider);
    final detail = itemId == null
        ? null
        : ref.watch(recurringDetailProvider(itemId));
    final today = ref.watch(clockProvider).today(cashTimeZone);
    final title = itemId == null
        ? RecurringFormPage.newTitle
        : RecurringFormPage.editTitle;
    final Widget body;
    if (detail is AsyncError || plan is AsyncError) {
      body = ErrorBlock(
        title: '读取失败',
        detail: '这个周期事项不在当前空间里，或已删除。',
        onRetry: () => context.go(AppRoutes.cash),
        retryLabel: '回到现金与收支',
      );
    } else if (!plan.hasValue || (detail != null && !detail.hasValue)) {
      body = const LoadingSkeleton();
    } else {
      if (detail != null) {
        _fill(detail.value!);
      }
      final accounts = plan.value!.activeAccounts;
      _accountId ??= accounts.isEmpty ? null : accounts.first.id;
      final account =
          accounts.where((a) => a.id == _accountId).firstOrNull ??
          detail?.value?.account;
      body = ListView(
        padding: const EdgeInsets.only(bottom: CfSpace.xl),
        children: <Widget>[
          if (itemId != null)
            const NoticeCard(
              icon: Icons.info_outline,
              tone: NoticeTone.neutral,
              text:
                  '修改周期规则（频率、第一期、日规则、结束日）会重新生成今天之后的各期，这些期的单期覆盖与跳过将被清除；'
                  '只改金额、名称或层级时，今天之后尚未发生的各期就地更新。',
            ),
          if (itemId == null)
            _AccountField(
              label: '账户',
              accounts: accounts,
              value: _accountId,
              error: _errors['account'],
              onChanged: (v) => setState(() => _accountId = v),
            )
          else
            formPadded(Text('账户：${account?.name ?? ''}')),
          ChoiceWrap<CashPlanType>(
            label: '类型',
            values: CashPlanType.values,
            selected: _type,
            labelOf: (t) => t.label,
            onSelected: (t) => setState(() => _type = t),
          ),
          CashClassField(
            selected: _cls,
            error: _errors['cls'],
            onSelected: (c) => setState(() => _cls = c),
          ),
          FormTextField(
            controller: _label,
            label: '名称（必填，≤20 字）',
            error: _errors['label'],
          ),
          FormTextField(
            controller: _amount,
            label: '每期金额（填正数）',
            error: _errors['amount'],
            keyboardType: FormTextField.amountKeyboard,
          ),
          ChoiceWrap<RecurringFrequency>(
            label: '频率',
            values: RecurringFrequency.values,
            selected: _frequency,
            labelOf: (f) => f.label,
            onSelected: (f) => setState(() => _frequency = f),
          ),
          formPadded(
            DateField(
              label: '第一期',
              value: _start ?? today,
              first: _firstDate(today, _start),
              last: _lastDate(today),
              onChanged: (v) => setState(() => _start = v),
            ),
          ),
          if (_frequency.allowsMonthEnd)
            ChoiceWrap<DayRule>(
              label: '日规则（不支持工作日规则：本阶段没有已核验的节假日日历）',
              values: DayRule.values,
              selected: _dayRule,
              labelOf: (r) => r.label,
              onSelected: (r) => setState(() => _dayRule = r),
              error: _errors['dayRule'],
            ),
          formPadded(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                DateField(
                  label: '结束日（可选）',
                  value: _end,
                  initial: today.addDays(365),
                  first: _firstDate(today, _end),
                  last: _lastDate(today),
                  onChanged: (v) => setState(() => _end = v),
                ),
                if (_errors['endOn'] != null)
                  Text(
                    _errors['endOn']!,
                    style: TextStyle(
                      color: CardFlowColors.of(context).danger.fg,
                    ),
                  ),
                if (_end != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () => setState(() => _end = null),
                      child: const Text('清除结束日'),
                    ),
                  ),
              ],
            ),
          ),
          _saveErrorCard(_saveError),
          formPadded(
            FilledButton(
              onPressed: _saving || account == null
                  ? null
                  : () => unawaited(_save(account.currency, today)),
              child: Text(_saving ? '正在保存…' : '保存'),
            ),
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: body,
    );
  }
}

/// P-08 周期事项详情：每一期可单独覆盖（金额/日期/时刻）、跳过或恢复，不影响其他各期（R-CASH-02）；
/// 已发生的期不能再改。「修改」「停用/启用」。
class RecurringDetailPage extends ConsumerWidget {
  const RecurringDetailPage({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(recurringDetailProvider(itemId));
    return Scaffold(
      appBar: AppBar(title: Text(detail.value?.row.label ?? '周期事项')),
      body: switch (detail) {
        AsyncData(:final value) => _RecurringDetail(view: value),
        AsyncError(:final error) when error is NotFoundException => ErrorBlock(
          title: '已不存在',
          detail: '这个周期事项不在当前空间里（可能已切换空间）。',
          onRetry: () => context.go(AppRoutes.cash),
          retryLabel: '回到现金与收支',
        ),
        AsyncError(:final error) => ErrorBlock(
          title: '读取失败',
          code: '${error.runtimeType}',
          detail: '本机数据没有改动。',
          onRetry: () => ref.invalidate(recurringDetailProvider(itemId)),
        ),
        _ => const LoadingSkeleton(rows: 4),
      },
    );
  }
}

class _RecurringDetail extends ConsumerWidget {
  const _RecurringDetail({required this.view});

  final RecurringDetailView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final row = view.row;
    final currency = view.account.currency;
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: CardFlowColors.of(context).textSecondary,
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: CfSpace.xl),
      children: <Widget>[
        formPadded(
          Text(
            '${view.account.name} · ${RecurringFrequency.of(row.frequency).label}'
            '${row.frequency == 'monthly' || row.frequency == 'yearly' ? '（${DayRule.of(row.dayRule).label}）' : ''} · '
            '第一期 ${row.startOn}${row.endOn == null ? '' : ' · 截至 ${row.endOn}'} · '
            '${CashEventClass.of(row.cls).label}${row.active ? '' : ' · 已停用'}',
          ),
        ),
        LabeledValue(
          label: '每期',
          value: CashFlowLabel(
            amountMinor: row.amountMinor,
            currency: currency,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(CfSpace.md),
          child: Wrap(
            spacing: CfSpace.xs,
            runSpacing: CfSpace.xs,
            children: <Widget>[
              OutlinedButton(
                onPressed: () => context.go(AppRoutes.editRecurring(row.id)),
                child: const Text('修改'),
              ),
              OutlinedButton(
                onPressed: () => unawaited(_toggle(context, ref)),
                child: Text(row.active ? '停用' : '启用'),
              ),
            ],
          ),
        ),
        const SectionTitle('各期（展开到今天之后 180 天）'),
        formPadded(Text('每一期可单独覆盖或跳过，不影响其他各期；已发生的期不能再改。', style: secondary)),
        if (view.occurrences.isEmpty)
          formPadded(Text('还没有展开的期。', style: secondary)),
        for (final o in view.occurrences)
          _OccurrenceTile(view: view, occurrence: o, currency: currency),
      ],
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final stopping = view.row.active;
    final confirmed = await confirmAction(
      context,
      title: stopping ? '停用这个周期事项？' : '启用这个周期事项？',
      message: stopping
          ? '影响：今天之后尚未发生的各期从资金日历中移除；已发生的期保留。'
          : '启用后按周期规则重新展开到今天之后 180 天。',
      confirmLabel: stopping ? '停用' : '启用',
    );
    if (!confirmed) {
      return;
    }
    final repo = await ref.read(recurringItemRepositoryProvider.future);
    await repo.setActive(view.row.id, !stopping);
    showFeedback(messenger, CashPage.savedMessage);
  }
}

class _OccurrenceTile extends ConsumerWidget {
  const _OccurrenceTile({
    required this.view,
    required this.occurrence,
    required this.currency,
  });

  final RecurringDetailView view;
  final RecurringOccurrence occurrence;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = occurrence;
    final event = o.event;
    final key = o.key;
    final status = o.skipped
        ? '已跳过'
        : o.posted
        ? '已发生'
        : o.overridden
        ? '已覆盖'
        : '按周期';
    final moved = event != null && event.eventOn != key.toString()
        ? ' → ${event.eventOn}'
        : '';
    return ListTile(
      title: Text('${formatShortDate(key, view.today)}$moved · $status'),
      subtitle: Wrap(
        spacing: CfSpace.xs,
        runSpacing: CfSpace.xxs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          if (event != null)
            CashFlowLabel(amountMinor: event.amountMinor, currency: currency),
          if (!o.posted && !o.skipped)
            TextButton(
              onPressed: () => unawaited(_override(context, ref)),
              child: const Text('覆盖'),
            ),
          if (!o.posted && !o.skipped)
            TextButton(
              onPressed: () => unawaited(
                _run(context, ref, (repo) => repo.skip(view.row.id, key)),
              ),
              child: const Text('跳过'),
            ),
          if (!o.posted && (o.skipped || o.overridden))
            TextButton(
              onPressed: () => unawaited(
                _run(context, ref, (repo) => repo.restore(view.row.id, key)),
              ),
              child: const Text('恢复'),
            ),
        ],
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(RecurringItemRepository repo) action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(await ref.read(recurringItemRepositoryProvider.future));
      showFeedback(messenger, CashPage.savedMessage);
    } on RepositoryException catch (error) {
      showFeedback(messenger, '没有保存：${error.message}');
    }
  }

  Future<void> _override(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_OverrideInput>(
      context: context,
      builder: (_) => _OverrideDialog(
        occurrence: occurrence,
        currency: currency,
        today: view.today,
      ),
    );
    if (result == null || !context.mounted) {
      return;
    }
    await _run(
      context,
      ref,
      (repo) => repo.overrideOccurrence(
        view.row.id,
        occurrence.key,
        amountMinor: result.amount,
        on: result.on,
        at: result.at,
      ),
    );
  }
}

typedef _OverrideInput = ({int? amount, LocalDate? on, Timestamp? at});

class _OverrideDialog extends StatefulWidget {
  const _OverrideDialog({
    required this.occurrence,
    required this.currency,
    required this.today,
  });

  final RecurringOccurrence occurrence;
  final String currency;
  final LocalDate today;

  @override
  State<_OverrideDialog> createState() => _OverrideDialogState();
}

class _OverrideDialogState extends State<_OverrideDialog> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _time = TextEditingController();
  LocalDate? _on;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('覆盖 ${widget.occurrence.key} 这一期'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('只改这一期：填新金额和/或新日期（其他各期不变）。'),
            const SizedBox(height: CfSpace.sm),
            TextField(
              controller: _amount,
              autofillHints: null,
              keyboardType: FormTextField.amountKeyboard,
              decoration: const InputDecoration(
                labelText: '新金额（可选，填正数）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: CfSpace.sm),
            DateField(
              label: '新日期（可选）',
              value: _on,
              initial: widget.occurrence.key,
              first: widget.today.addDays(-366),
              last: widget.today.addDays(3650),
              onChanged: (v) => setState(() => _on = v),
            ),
            const SizedBox(height: CfSpace.sm),
            TextField(
              controller: _time,
              autofillHints: null,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: '时刻（可选，HH:MM）',
                border: OutlineInputBorder(),
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
            final (amount, amountError) = parseAmountMinor(
              _amount.text,
              widget.currency,
              required: false,
            );
            final (time, timeError) = parseHourMinute(_time.text);
            final problem = amountError ?? timeError;
            if (problem != null ||
                (amount == null && _on == null && time == null)) {
              setState(() => _error = problem ?? '请填写新金额或新日期');
              return;
            }
            final on = _on ?? (time == null ? null : widget.occurrence.key);
            Navigator.of(context).pop((
              amount: amount,
              on: on,
              at: on == null ? null : _timestampOn(on, time),
            ));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
