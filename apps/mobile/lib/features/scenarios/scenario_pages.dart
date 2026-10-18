import 'dart:async';

import 'package:cardflow_domain/cardflow_domain.dart'
    show LocalDate, Rational, decimalText;
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
import '../../app/widgets/workspace_badges.dart';
import '../../data/db/app_database.dart';
import '../../data/ids.dart';
import '../../data/mapping/cash_mapping.dart';
import '../../data/repositories/cash_forecast_reader.dart';
import '../../data/repositories/cash_models.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/repository_errors.dart';
import '../../data/repositories/scenario_repository.dart';
import '../../data/time/clock.dart';
import '../cards/amount_input.dart';
import '../cards/card_dialogs.dart';
import '../cards/card_formatting.dart';
import '../cash/cash_form_fields.dart';
import '../cash/cash_formatting.dart';
import '../planner/planner_segments.dart';

/// 情景参数的一句话说明。
String describeScenario(ScenarioView s) {
  final p = s.params;
  return switch (s.kind) {
    ScenarioKind.builtinConfirmed => '只算确定的收支（排除全部预计收入）',
    ScenarioKind.builtinBaseline => '预计收支按期发生',
    ScenarioKind.userStress => <String>[
      '收入延迟 ${p.incomeDelayDays} 天',
      '收入 ${_percent(p.incomeScale)}%',
      '生活支出 ${_percent(p.expenseScale)}%',
      p.sameDayOrder == SameDayOrderChoice.timestamp ? '同日按时刻' : '同日先支出后收入',
      if (p.eventOverrides.isNotEmpty) '覆盖 ${p.eventOverrides.length} 笔收支',
      if (p.limitChanges.isNotEmpty) '额度变化 ${p.limitChanges.length} 项（I-2 使用）',
    ].join(' · '),
  };
}

String _percent(String scale) =>
    decimalText(Rational.parseDecimal(scale) * Rational.fromInt(100));

/// 计算版本的一句话：最低现金（逐账户最差者）、日期、缺口数。
String _runLine(ScenarioRunRow run, CashRunResult result) {
  final computed = run.computedAt.substring(0, 16).replaceFirst('T', ' ');
  return 'v${run.versionNo} · 计算于 $computed · 缺口 ${result.gapCount} 个';
}

RunAccountResult? _worst(CashRunResult result) {
  RunAccountResult? worst;
  for (final a in result.accounts) {
    if (worst == null || a.minBalance < worst.minBalance) {
      worst = a;
    }
  }
  return worst;
}

/// P-09 情景与假设对比（ui-spec P-09）：内置"已确认""基准预期"不可修改；用户压力情景带参数、最近一次
/// 计算与状态（"已过期"）；「重算」生成新版本（旧版保留）；「对比」两情景或两版本并排。
///
/// 四态：首次空白"只有内置口径"「新建」、加载（骨架；重算时"正在重算 {n} 个情景"）、错误（「重新计算」）、
/// 成功（"已保存 v{n}"）。
class ScenariosPage extends ConsumerStatefulWidget {
  const ScenariosPage({super.key});

  static const String title = '情景';

  /// ui-spec P-09 九态"首次空白"。
  static const String firstRunMessage = '只有内置口径';

  /// 版本过期的徽标文字。
  static const String staleLabel = '已过期';

  @override
  ConsumerState<ScenariosPage> createState() => _ScenariosPageState();
}

class _ScenariosPageState extends ConsumerState<ScenariosPage> {
  int _recomputing = 0;
  String? _error;

  Future<void> _recompute(List<ScenarioView> scenarios) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _recomputing = scenarios.length;
      _error = null;
    });
    try {
      final scope = await ref.read(workspaceScopeProvider.future);
      final reader = CashForecastReader(scope);
      ScenarioRunRow? last;
      for (final s in scenarios) {
        last = await reader.recompute(s.key);
      }
      showFeedback(
        messenger,
        scenarios.length == 1
            ? '已保存 v${last!.versionNo}'
            : '已重算 ${scenarios.length} 个情景',
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = '${error.runtimeType}');
      }
    } finally {
      if (mounted) {
        setState(() => _recomputing = 0);
      }
    }
  }

  Future<void> _delete(ScenarioBoardItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await confirmAction(
      context,
      title: '删除情景「${item.scenario.name}」？',
      message: '影响：这个情景与它的 ${item.runs.length} 个计算版本都将删除；内置口径不受影响。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed) {
      return;
    }
    try {
      final repo = await ref.read(scenarioRepositoryProvider.future);
      await repo.delete(item.scenario.row!.id);
      showFeedback(messenger, '已删除');
    } on RepositoryException catch (error) {
      showFeedback(messenger, error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(scenarioBoardProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(ScenariosPage.title)),
      body: switch (board) {
        AsyncData(:final value) => _list(context, value),
        AsyncError(:final error) => ErrorBlock(
          title: '情景读取失败',
          code: '${error.runtimeType}',
          detail: '上一次的计算版本都保留着。',
          onRetry: () => ref.invalidate(scenarioBoardProvider),
          retryLabel: '重新计算',
        ),
        _ => const LoadingSkeleton(),
      },
    );
  }

  Widget _list(BuildContext context, ScenarioBoard board) {
    final secondary = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: CardFlowColors.of(context).textSecondary);
    return ListView(
      padding: const EdgeInsets.only(bottom: CfSpace.xl),
      children: <Widget>[
        const PlannerSegmentBar(current: PlannerSegment.scenarios),
        const RootPageBadges(),
        if (_recomputing > 0)
          Padding(
            padding: const EdgeInsets.all(CfSpace.md),
            child: Text('正在重算 $_recomputing 个情景…'),
          ),
        if (_error != null)
          NoticeCard(
            icon: Icons.error_outline,
            tone: NoticeTone.danger,
            text: '重算失败（$_error），上一版保留。',
          ),
        Padding(
          padding: const EdgeInsets.all(CfSpace.md),
          child: Text(
            '内置"已确认""基准预期"不可修改。压力情景只允许变差：收入延迟、收入减少、生活支出增加；'
            '「重算」生成新版本，旧版本保留用于对比；数据或参数变了，版本标"已过期"。',
            style: secondary,
          ),
        ),
        if (board.stressItems.isEmpty)
          FirstRunEmptyState(
            icon: Icons.tune,
            message: ScenariosPage.firstRunMessage,
            purpose: '建立命名的压力情景，重算并与历史版本对比。',
            actions: <EmptyStateAction>[
              EmptyStateAction(
                label: '新建',
                onPressed: () => context.go(AppRoutes.newScenario),
              ),
            ],
            scrollable: false,
          ),
        for (final item in board.items)
          _ScenarioCard(
            item: item,
            busy: _recomputing > 0,
            onRecompute: () =>
                unawaited(_recompute(<ScenarioView>[item.scenario])),
            onDelete: () => unawaited(_delete(item)),
          ),
        Padding(
          padding: const EdgeInsets.all(CfSpace.md),
          child: Wrap(
            spacing: CfSpace.xs,
            runSpacing: CfSpace.xs,
            children: <Widget>[
              FilledButton(
                onPressed: () => context.go(AppRoutes.newScenario),
                child: const Text('新建情景'),
              ),
              OutlinedButton(
                onPressed: _recomputing > 0
                    ? null
                    : () => unawaited(
                        _recompute(<ScenarioView>[
                          for (final i in board.items) i.scenario,
                        ]),
                      ),
                child: const Text('全部重算'),
              ),
              OutlinedButton(
                onPressed: () => context.go(AppRoutes.scenarioCompare()),
                child: const Text('对比'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScenarioCard extends StatelessWidget {
  const _ScenarioCard({
    required this.item,
    required this.busy,
    required this.onRecompute,
    required this.onDelete,
  });

  final ScenarioBoardItem item;
  final bool busy;
  final VoidCallback onRecompute;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final s = item.scenario;
    final latest = item.latest;
    final result = item.latestResult;
    final worst = result == null ? null : _worst(result);
    // 用 Material 当卡片底：卡片里的 ExpansionTile/ListTile 的底色与水波纹画在它上面。
    return Padding(
      key: ValueKey<String>('scenario-${s.name}'),
      padding: const EdgeInsets.symmetric(
        horizontal: CfSpace.md,
        vertical: CfSpace.xs,
      ),
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CfRadius.lg),
          side: BorderSide(color: colors.borderInput, width: CfStroke.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(CfSpace.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: CfSpace.xs,
                runSpacing: CfSpace.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Semantics(
                    header: true,
                    child: Text(s.name, style: theme.textTheme.titleMedium),
                  ),
                  StatusBadge(
                    label: s.isBuiltin ? '内置（不可修改）' : '压力情景',
                    icon: s.isBuiltin ? Icons.lock_outline : Icons.tune,
                    tone: NoticeTone.neutral,
                  ),
                  if (item.stale)
                    const StatusBadge(
                      label: ScenariosPage.staleLabel,
                      icon: Icons.update,
                      tone: NoticeTone.attention,
                    ),
                  if (result?.assumptionAnalysis ?? false)
                    const AssumptionBadge(),
                ],
              ),
              const SizedBox(height: CfSpace.xxs),
              Text(describeScenario(s)),
              const SizedBox(height: CfSpace.xxs),
              if (latest == null || result == null)
                const Text('尚未计算')
              else ...<Widget>[
                Text(_runLine(latest, result)),
                if (worst != null)
                  Wrap(
                    spacing: CfSpace.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      const Text('最低现金'),
                      MoneyText(
                        minor: worst.minBalance,
                        currency: worst.currency,
                        negativeLabel: '缺口',
                        semanticsPrefix: '最低现金',
                        textAlign: TextAlign.start,
                      ),
                      Text('${worst.minOn} · ${worst.name}'),
                    ],
                  ),
                if (result.missingSnapshot.isNotEmpty)
                  Text('数据不全：${result.missingSnapshot.join('、')}缺快照，未计入'),
                if (result.inactiveOverrides.isNotEmpty)
                  Text('覆盖的收支已删除：${result.inactiveOverrides.length} 项未生效'),
              ],
              Wrap(
                spacing: CfSpace.xs,
                runSpacing: CfSpace.xs,
                children: <Widget>[
                  TextButton(
                    onPressed: busy ? null : onRecompute,
                    child: const Text('重算'),
                  ),
                  if (!s.isBuiltin) ...<Widget>[
                    TextButton(
                      onPressed: () =>
                          context.go(AppRoutes.editScenario(s.row!.id)),
                      child: const Text('编辑'),
                    ),
                    TextButton(onPressed: onDelete, child: const Text('删除')),
                  ],
                  TextButton(
                    onPressed: () => context.go(
                      AppRoutes.cashCalendarWith(
                        basis: switch (s.kind) {
                          ScenarioKind.builtinConfirmed =>
                            CashBasis.confirmed.code,
                          ScenarioKind.builtinBaseline =>
                            CashBasis.baseline.code,
                          ScenarioKind.userStress => CashBasis.stress.code,
                        },
                        scenario: s.isBuiltin ? null : s.key,
                      ),
                    ),
                    child: const Text('看资金日历'),
                  ),
                ],
              ),
              const Text('设为决策情景：I-2 提供'),
              if (item.runs.length > 1)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('历史版本（${item.runs.length}）'),
                  children: <Widget>[
                    for (var i = 0; i < item.runs.length; i++)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          _runLine(
                            item.runs[i],
                            CashRunResult.parse(item.runs[i].result),
                          ),
                        ),
                        trailing: i + 1 < item.runs.length
                            ? TextButton(
                                onPressed: () => context.go(
                                  AppRoutes.scenarioCompare(
                                    a: item.runs[i + 1].id,
                                    b: item.runs[i].id,
                                  ),
                                ),
                                child: const Text('与上一版对比'),
                              )
                            : null,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// P-09 编辑器：名称、收入延迟（0–180 天）、收入比例（0–100%）、生活支出比例（100%–1000%）、同日顺序
/// （按时刻须所有收支有时刻）、事件覆盖、额度变化（占位：账户 + 日期，I-2 使用）。
class ScenarioEditorPage extends ConsumerStatefulWidget {
  const ScenarioEditorPage({super.key, this.scenarioId});

  final String? scenarioId;

  static const String newTitle = '新建情景';
  static const String editTitle = '编辑情景';

  @override
  ConsumerState<ScenarioEditorPage> createState() => _ScenarioEditorPageState();
}

class _ScenarioEditorPageState extends ConsumerState<ScenarioEditorPage> {
  final String _id = newUuidV4();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _delay = TextEditingController(text: '0');
  final TextEditingController _income = TextEditingController(text: '100');
  final TextEditingController _expense = TextEditingController(text: '100');
  SameDayOrderChoice _order = SameDayOrderChoice.conservative;
  List<EventOverrideSpec> _overrides = <EventOverrideSpec>[];
  List<LimitChangeSpec> _limits = <LimitChangeSpec>[];
  bool _loaded = false;
  final Map<String, String> _errors = <String, String>{};
  String? _saveError;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in <TextEditingController>[_name, _delay, _income, _expense]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(ScenarioView view) {
    if (_loaded) {
      return;
    }
    _loaded = true;
    final p = view.params;
    _name.text = view.name;
    _delay.text = '${p.incomeDelayDays}';
    _income.text = _percent(p.incomeScale);
    _expense.text = _percent(p.expenseScale);
    _order = p.sameDayOrder;
    _overrides = List<EventOverrideSpec>.of(p.eventOverrides);
    _limits = List<LimitChangeSpec>.of(p.limitChanges);
  }

  /// 百分比文本 → 系数（至多 8 位小数的百分数）。
  (Rational?, String?) _scale(String text) {
    final value = text.trim().replaceAll('%', '');
    if (!RegExp(r'^[0-9]{1,4}(\.[0-9]{1,8})?$').hasMatch(value)) {
      return (null, '请填写百分比，如 100 或 50.5');
    }
    return (
      Rational.parseDecimal(value).dividedBy(Rational.fromInt(100)),
      null,
    );
  }

  Future<void> _save() async {
    final errors = <String, String>{};
    final delay = int.tryParse(_delay.text.trim());
    if (delay == null) {
      errors['incomeDelayDays'] = '请填写 0–180 的整数';
    }
    final (income, incomeError) = _scale(_income.text);
    if (incomeError != null) {
      errors['incomeScale'] = incomeError;
    }
    final (expense, expenseError) = _scale(_expense.text);
    if (expenseError != null) {
      errors['expenseScale'] = expenseError;
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
    final draft = ScenarioDraft(
      name: _name.text,
      incomeDelayDays: delay!,
      incomeScale: income,
      expenseScale: expense,
      sameDayOrder: _order,
      eventOverrides: _overrides,
      limitChanges: _limits,
    );
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await ref.read(scenarioRepositoryProvider.future);
      final id = widget.scenarioId;
      if (id == null) {
        await repo.create(draft, id: _id);
      } else {
        await repo.update(id, draft);
      }
      showFeedback(messenger, '已保存；「重算」后生成新版本');
      if (mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(AppRoutes.scenarios);
        }
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
    final id = widget.scenarioId;
    final board = ref.watch(scenarioBoardProvider);
    final wallet = ref.watch(walletProvider);
    final today = ref.watch(clockProvider).today(cashTimeZone);
    final title = id == null
        ? ScenarioEditorPage.newTitle
        : ScenarioEditorPage.editTitle;
    final Widget body;
    if (board case AsyncError(:final error)) {
      body = ErrorBlock(
        title: '读取失败',
        code: '${error.runtimeType}',
        onRetry: () => ref.invalidate(scenarioBoardProvider),
      );
    } else if (!board.hasValue) {
      body = const LoadingSkeleton();
    } else {
      final value = board.value!;
      final existing = id == null ? null : value.item(id)?.scenario;
      if (id != null && existing == null) {
        body = ErrorBlock(
          title: '已不存在',
          detail: '这个情景不在当前空间里，或已删除。',
          onRetry: () => context.go(AppRoutes.scenarios),
          retryLabel: '回到情景',
        );
      } else if (existing != null && existing.isBuiltin) {
        body = ErrorBlock(
          title: '内置情景不可修改',
          onRetry: () => context.go(AppRoutes.scenarios),
          retryLabel: '回到情景',
        );
      } else {
        if (existing != null) {
          _fill(existing);
        }
        body = _form(
          context,
          value,
          wallet.value?.accounts
                  .map((a) => (a.id, a.displayName, a.primaryCurrency.currency))
                  .toList() ??
              const <(String, String, String)>[],
          today,
        );
      }
    }
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: body,
    );
  }

  Widget _form(
    BuildContext context,
    ScenarioBoard board,
    List<(String, String, String)> creditAccounts,
    LocalDate today,
  ) {
    final rows = board.inputs.eventRows;
    final accounts = {for (final a in board.inputs.accountRows) a.id: a};
    String currencyOfEvent(String id) {
      final row = rows[id];
      return row == null
          ? 'CNY'
          : accounts[row.cashAccountId]?.currency ?? 'CNY';
    }

    String eventLabel(String id) {
      final row = rows[id];
      if (row == null) {
        return '（已删除，未生效）';
      }
      final currency = accounts[row.cashAccountId]?.currency ?? 'CNY';
      return '${formatShortDate(LocalDate.parse(row.eventOn), today)} ${cashEventTitle(row)} '
          '${row.amountMinor < 0 ? '支出' : '收入'} ${amountText(row.amountMinor.abs(), currency)}';
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: CfSpace.xl),
      children: <Widget>[
        FormTextField(
          controller: _name,
          label: '名称（必填，≤20 字，不能与内置同名）',
          error: _errors['name'],
        ),
        FormTextField(
          controller: _delay,
          label: '收入延迟（天，0–180）',
          error: _errors['incomeDelayDays'],
          keyboardType: TextInputType.number,
        ),
        FormTextField(
          controller: _income,
          label: '收入比例（%，0–100）',
          error: _errors['incomeScale'],
          keyboardType: FormTextField.amountKeyboard,
          helper: '预计收入按这个比例到账（四舍五入到分）',
        ),
        FormTextField(
          controller: _expense,
          label: '生活支出比例（%，100–1000）',
          error: _errors['expenseScale'],
          keyboardType: FormTextField.amountKeyboard,
          helper: '生活类支出按这个比例增加',
        ),
        ChoiceWrap<SameDayOrderChoice>(
          label: '同日顺序',
          values: SameDayOrderChoice.values,
          selected: _order,
          labelOf: (o) => o.label,
          onSelected: (o) => setState(() => _order = o),
          error: _errors['sameDayOrder'],
        ),
        SectionTitle(
          '事件覆盖（${_overrides.length}）',
          trailing: TextButton(
            onPressed: rows.isEmpty
                ? null
                : () => unawaited(_addOverride(board, today, eventLabel)),
            child: const Text('添加覆盖'),
          ),
        ),
        if (_errors['eventOverrides'] != null)
          NoticeCard(
            icon: Icons.error_outline,
            tone: NoticeTone.danger,
            text: _errors['eventOverrides']!,
          ),
        for (final o in _overrides)
          ListTile(
            title: Text(eventLabel(o.eventId)),
            subtitle: Text(
              <String>[
                if (o.on != null) '改到 ${o.on}',
                if (o.amountMinor != null)
                  '金额改为 ${amountText(o.amountMinor!.abs(), currencyOfEvent(o.eventId))}',
              ].join(' · '),
            ),
            trailing: IconButton(
              tooltip: '移除这项覆盖',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _overrides.remove(o)),
            ),
          ),
        SectionTitle(
          '额度变化（${_limits.length}，I-2 使用）',
          trailing: TextButton(
            onPressed: creditAccounts.isEmpty
                ? null
                : () => unawaited(_addLimit(creditAccounts, today)),
            child: const Text('添加额度变化'),
          ),
        ),
        if (_errors['limitChanges'] != null)
          NoticeCard(
            icon: Icons.error_outline,
            tone: NoticeTone.danger,
            text: _errors['limitChanges']!,
          ),
        for (final c in _limits)
          ListTile(
            title: Text(
              creditAccounts
                      .where((a) => a.$1 == c.creditAccountId)
                      .firstOrNull
                      ?.$2 ??
                  c.creditAccountId,
            ),
            subtitle: Text(
              '${c.on} 起 · ${c.changeMinor < 0 ? '降额' : '提额'} '
              '${amountText(c.changeMinor.abs(), creditAccounts.where((a) => a.$1 == c.creditAccountId).firstOrNull?.$3 ?? 'CNY')}',
            ),
            trailing: IconButton(
              tooltip: '移除这项额度变化',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _limits.remove(c)),
            ),
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
            child: Text(_saving ? '正在保存…' : '保存情景'),
          ),
        ),
      ],
    );
  }

  Future<void> _addOverride(
    ScenarioBoard board,
    LocalDate today,
    String Function(String id) eventLabel,
  ) async {
    final from = today.addDays(-31);
    final candidates = <String>[
      for (final e in board.inputs.events)
        if (e.on >= from && !_overrides.any((o) => o.eventId == e.id)) e.id,
    ];
    final result = await showDialog<EventOverrideSpec>(
      context: context,
      builder: (_) => _OverrideDialog(
        candidates: candidates,
        labelOf: eventLabel,
        today: today,
        rows: board.inputs.eventRows,
        currencyOf: (id) {
          final row = board.inputs.eventRows[id];
          return row == null
              ? 'CNY'
              : board.inputs.accountRow(row.cashAccountId)?.currency ?? 'CNY';
        },
      ),
    );
    if (result != null) {
      setState(() => _overrides = <EventOverrideSpec>[..._overrides, result]);
    }
  }

  Future<void> _addLimit(
    List<(String, String, String)> accounts,
    LocalDate today,
  ) async {
    final result = await showDialog<LimitChangeSpec>(
      context: context,
      builder: (_) => _LimitDialog(accounts: accounts, today: today),
    );
    if (result != null) {
      setState(() => _limits = <LimitChangeSpec>[..._limits, result]);
    }
  }
}

class _OverrideDialog extends StatefulWidget {
  const _OverrideDialog({
    required this.candidates,
    required this.labelOf,
    required this.today,
    required this.rows,
    required this.currencyOf,
  });

  final List<String> candidates;
  final String Function(String id) labelOf;
  final String Function(String id) currencyOf;
  final LocalDate today;
  final Map<String, CashEventRow> rows;

  @override
  State<_OverrideDialog> createState() => _OverrideDialogState();
}

class _OverrideDialogState extends State<_OverrideDialog> {
  String? _eventId;
  LocalDate? _on;
  final TextEditingController _amount = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('覆盖一笔收支'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('只在这个情景里改它的日期和/或金额。'),
            RadioGroup<String>(
              groupValue: _eventId,
              onChanged: (v) => setState(() => _eventId = v),
              child: Column(
                children: <Widget>[
                  for (final id in widget.candidates)
                    RadioListTile<String>(
                      value: id,
                      title: Text(widget.labelOf(id)),
                    ),
                ],
              ),
            ),
            DateField(
              label: '新日期（可选）',
              value: _on,
              initial: widget.today,
              first: widget.today.addDays(-366),
              last: widget.today.addDays(3650),
              onChanged: (v) => setState(() => _on = v),
            ),
            const SizedBox(height: CfSpace.sm),
            TextField(
              controller: _amount,
              autofillHints: null,
              keyboardType: FormTextField.amountKeyboard,
              decoration: const InputDecoration(
                labelText: '新金额（可选，填正数；0 = 这笔不发生）',
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
            final id = _eventId;
            if (id == null) {
              setState(() => _error = '请选择一笔收支');
              return;
            }
            final row = widget.rows[id]!;
            final (amount, amountError) = parseAmountMinor(
              _amount.text,
              widget.currencyOf(id),
              required: false,
            );
            if (amountError != null || (amount == null && _on == null)) {
              setState(() => _error = amountError ?? '请填写新日期或新金额');
              return;
            }
            Navigator.of(context).pop(
              EventOverrideSpec(
                eventId: id,
                on: _on,
                amountMinor: amount == null
                    ? null
                    : (row.amountMinor < 0 ? -amount : amount),
              ),
            );
          },
          child: const Text('添加'),
        ),
      ],
    );
  }
}

class _LimitDialog extends StatefulWidget {
  const _LimitDialog({required this.accounts, required this.today});

  /// （信用账户 id，名称，主子账户币种）。
  final List<(String, String, String)> accounts;
  final LocalDate today;

  @override
  State<_LimitDialog> createState() => _LimitDialogState();
}

class _LimitDialogState extends State<_LimitDialog> {
  String? _accountId;
  LocalDate? _on;
  final TextEditingController _change = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _change.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('额度变化（I-2 使用）'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            RadioGroup<String>(
              groupValue: _accountId,
              onChanged: (v) => setState(() => _accountId = v),
              child: Column(
                children: <Widget>[
                  for (final (id, name, _) in widget.accounts)
                    RadioListTile<String>(value: id, title: Text(name)),
                ],
              ),
            ),
            DateField(
              label: '生效日期',
              value: _on,
              initial: widget.today,
              first: widget.today.addDays(-366),
              last: widget.today.addDays(3650),
              onChanged: (v) => setState(() => _on = v),
            ),
            const SizedBox(height: CfSpace.sm),
            TextField(
              controller: _change,
              autofillHints: null,
              keyboardType: FormTextField.amountKeyboard,
              decoration: const InputDecoration(
                labelText: '变化额（负数 = 降额）',
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
            final currency =
                widget.accounts
                    .where((a) => a.$1 == _accountId)
                    .firstOrNull
                    ?.$3 ??
                'CNY';
            final (change, error) = parseAmountMinor(
              _change.text,
              currency,
              allowNegative: true,
            );
            if (_accountId == null ||
                _on == null ||
                error != null ||
                change == 0) {
              setState(() => _error = error ?? '额度变化须选择账户与日期，变化额不为 0');
              return;
            }
            Navigator.of(context).pop(
              LimitChangeSpec(
                creditAccountId: _accountId!,
                on: _on!,
                changeMinor: change!,
              ),
            );
          },
          child: const Text('添加'),
        ),
      ],
    );
  }
}

/// P-09「对比」：两个计算版本（两情景或同一情景的两版本）并排——逐账户的最低现金、日期、缺口数与差异。
class ScenarioComparePage extends ConsumerStatefulWidget {
  const ScenarioComparePage({super.key, this.a, this.b});

  final String? a;
  final String? b;

  static const String title = '情景对比';

  /// 少于两个版本时（UF-5 "无历史版本 → 先保存"）。
  static const String needTwoRuns = '至少需要两个计算版本才能对比：先在情景列表里「重算」。';

  @override
  ConsumerState<ScenarioComparePage> createState() =>
      _ScenarioComparePageState();
}

class _ScenarioComparePageState extends ConsumerState<ScenarioComparePage> {
  late String? _a = widget.a;
  late String? _b = widget.b;

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(scenarioBoardProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(ScenarioComparePage.title)),
      body: switch (board) {
        AsyncData(:final value) => _body(context, value),
        AsyncError(:final error) => ErrorBlock(
          title: '读取失败',
          code: '${error.runtimeType}',
          onRetry: () => ref.invalidate(scenarioBoardProvider),
        ),
        _ => const LoadingSkeleton(),
      },
    );
  }

  Widget _body(BuildContext context, ScenarioBoard board) {
    final runs = board.allRuns;
    if (runs.length < 2) {
      return ListView(
        children: const <Widget>[
          NoticeCard(
            icon: Icons.info_outline,
            tone: NoticeTone.neutral,
            text: ScenarioComparePage.needTwoRuns,
          ),
        ],
      );
    }
    final byId = {for (final (item, run) in runs) run.id: (item, run)};
    _b ??= runs.first.$2.id;
    _a ??= runs.firstWhere((r) => r.$2.id != _b).$2.id;
    String label((ScenarioBoardItem, ScenarioRunRow) entry) =>
        '${entry.$1.scenario.name} v${entry.$2.versionNo}';
    final a = byId[_a];
    final b = byId[_b];
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: CfSpace.xl),
      children: <Widget>[
        ChoiceWrap<String>(
          key: const ValueKey<String>('compare-a'),
          label: 'A',
          values: <String>[for (final (_, r) in runs) r.id],
          selected: _a,
          labelOf: (id) => label(byId[id]!),
          onSelected: (id) => setState(() => _a = id),
        ),
        ChoiceWrap<String>(
          key: const ValueKey<String>('compare-b'),
          label: 'B',
          values: <String>[for (final (_, r) in runs) r.id],
          selected: _b,
          labelOf: (id) => label(byId[id]!),
          onSelected: (id) => setState(() => _b = id),
        ),
        if (a != null && b != null) ...<Widget>[
          SectionTitle('${label(a)} 与 ${label(b)}'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: Text(
              'A 计算于 ${a.$2.computedAt.substring(0, 16).replaceFirst('T', ' ')}，'
              'B 计算于 ${b.$2.computedAt.substring(0, 16).replaceFirst('T', ' ')}；差异 = B − A。',
            ),
          ),
          for (final row in compareRuns(
            CashRunResult.parse(a.$2.result),
            CashRunResult.parse(b.$2.result),
          ))
            Container(
              margin: const EdgeInsets.all(CfSpace.md),
              padding: const EdgeInsets.all(CfSpace.sm),
              decoration: BoxDecoration(
                color: CardFlowColors.of(context).surface,
                borderRadius: BorderRadius.circular(CfRadius.lg),
                border: Border.all(
                  color: CardFlowColors.of(context).borderInput,
                  width: CfStroke.hairline,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Semantics(
                    header: true,
                    child: Text(row.name, style: theme.textTheme.titleMedium),
                  ),
                  _compareMoney('最低现金 A', row.a?.minBalance, row.currency),
                  _compareMoney('最低现金 B', row.b?.minBalance, row.currency),
                  _compareMoney(
                    '最低现金差异',
                    row.minDelta,
                    row.currency,
                    negativeLabel: '减少',
                  ),
                  Text(
                    '最低日期：A ${row.a?.minOn ?? '—'} · B ${row.b?.minOn ?? '—'}',
                  ),
                  Text(
                    '缺口点：A ${row.a?.breaches.length ?? '—'} · B ${row.b?.breaches.length ?? '—'}'
                    '${row.gapDelta == null ? '' : ' · 差异 ${row.gapDelta! > 0 ? '+' : ''}${row.gapDelta}'}',
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _compareMoney(
    String label,
    int? minor,
    String currency, {
    String negativeLabel = '缺口',
  }) => Wrap(
    spacing: CfSpace.xs,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: <Widget>[
      ExcludeSemantics(child: Text(label)),
      MoneyText(
        minor: minor,
        currency: currency,
        negativeLabel: negativeLabel,
        semanticsPrefix: label,
        textAlign: TextAlign.start,
      ),
    ],
  );
}
