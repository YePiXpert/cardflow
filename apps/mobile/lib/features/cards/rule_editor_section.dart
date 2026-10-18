import 'dart:async';

import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../app/widgets/feedback.dart';
import '../../app/widgets/state_views.dart';
import '../../data/db/app_database.dart';
import '../../data/mapping/domain_mapping.dart';
import '../../data/repositories/billing_rule_repository.dart';
import '../../data/repositories/card_wallet_reader.dart';
import '../../data/repositories/models.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/repository_errors.dart';
import '../../data/time/business_tz.dart';
import '../../data/validation/text_rules.dart';
import 'card_dialogs.dart';
import 'card_formatting.dart';

/// P-04 账期规则：编辑（来源、账单日、当天归属、到期类型、次月偏移、工作日/顺延、时区、入账延迟、
/// 截止时点）+ 3 期预览（领域包计算，与 F-12/F-16 一致）+ 版本历史。
///
/// 校验：到期须晚于账单日（阻止保存）；工作日与顺延需要已核验日历，本阶段没有，始终禁用并说明；
/// 时区默认 Asia/Shanghai，只能选固定偏移时区。保存 = 新版本，旧版封口（F-14）。
class RuleEditorSection extends ConsumerStatefulWidget {
  const RuleEditorSection({super.key, required this.account});

  final AccountView account;

  /// 首次空白。
  static const String noRuleMessage = '尚未设置账期规则';

  /// 保存成功的轻提示（"{m} 个方案需重算"在 I-2 有方案后再加）。
  static const String savedMessage = '已保存';

  @override
  ConsumerState<RuleEditorSection> createState() => _RuleEditorSectionState();
}

class _RuleEditorSectionState extends ConsumerState<RuleEditorSection> {
  late int _statementDay;
  late bool _inclusive;
  late DueKind _dueKind;
  late int _dueDay;
  late int _monthOffset;
  late int _dueDays;
  late int _delayMin;
  late int _delayMax;
  late String _zoneId;
  late bool _useCutoff;
  late final TextEditingController _cutoff;
  late final TextEditingController _exceptions;
  late bool _correction;
  late LocalDate _effectiveFrom;
  bool _saving = false;
  String? _saveError;

  BillingRuleVersionRow? get _current {
    final account = widget.account;
    if (account.currentRule != null) {
      return account.currentRule;
    }
    final open = account.ruleVersions.where(
      (r) => r.effectiveTo == null && !isEmptyRange(r),
    );
    return open.isEmpty ? null : open.last;
  }

  @override
  void initState() {
    super.initState();
    final current = _current;
    _statementDay = current?.statementDay ?? 10;
    _inclusive = current?.statementDayInclusive ?? true;
    _dueKind = current?.dueKind == DueKind.daysAfterStatement.code
        ? DueKind.daysAfterStatement
        : DueKind.fixedDay;
    _dueDay = current?.dueDay ?? 28;
    _monthOffset = current?.dueMonthOffset ?? 0;
    _dueDays = current?.dueDays ?? 20;
    _delayMin = current?.postingDelayMinDays ?? 0;
    _delayMax = current?.postingDelayMaxDays ?? 0;
    _zoneId = widget.account.account.businessTz;
    _useCutoff = current?.cutoffTime != null;
    _cutoff = TextEditingController(text: current?.cutoffTime ?? '');
    _exceptions = TextEditingController(text: current?.exceptions ?? '');
    _effectiveFrom = widget.account.today;
    final currentFrom = parseOptionalDate(current?.effectiveFrom);
    _correction = currentFrom != null && currentFrom >= widget.account.today;
  }

  @override
  void dispose() {
    _cutoff.dispose();
    _exceptions.dispose();
    super.dispose();
  }

  BillingRuleDraft get _draft => BillingRuleDraft(
    statementDay: _statementDay,
    due: _dueKind == DueKind.fixedDay
        ? DueRule.fixedDay(day: _dueDay, monthOffset: _monthOffset)
        : DueRule.daysAfterStatement(days: _dueDays),
    statementDayInclusive: _inclusive,
    cutoffTime: _useCutoff ? _cutoff.text.trim() : null,
    postingDelayMinDays: _delayMin,
    postingDelayMaxDays: _delayMax,
    exceptions: _exceptions.text,
  );

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final rules = await ref.read(billingRuleRepositoryProvider.future);
      await rules.saveVersion(
        RuleSubject.creditAccount(widget.account.id),
        _draft,
        effect: _current == null || _correction
            ? const RuleCorrection()
            : RuleEffectiveFrom(_effectiveFrom),
      );
      if (_zoneId != widget.account.account.businessTz) {
        final accounts = await ref.read(creditAccountRepositoryProvider.future);
        await accounts.updateDetails(widget.account.id, businessTz: _zoneId);
      }
      showFeedback(messenger, RuleEditorSection.savedMessage);
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
    final today = widget.account.today;
    final problem = billingRuleDraftProblem(_draft);
    final preview = problem == null
        ? previewCycles(_draft.toDomain(), today)
        : const <Cycle>[];
    final current = _current;
    final currentFrom = parseOptionalDate(current?.effectiveFrom);
    final effectiveProblem =
        current != null &&
            !_correction &&
            currentFrom != null &&
            _effectiveFrom <= currentFrom
        ? '生效日须晚于当前版本的生效日（$currentFrom）'
        : null;
    final versions = widget.account.ruleVersions.reversed.toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: CfSpace.xl),
      children: <Widget>[
        if (current == null)
          const NoticeCard(
            icon: Icons.checklist,
            text: '${RuleEditorSection.noRuleMessage}：按银行账单核对后保存，保存后才能预测账期。',
          ),
        const SectionTitle('来源'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
          child: Wrap(
            spacing: CfSpace.xs,
            runSpacing: CfSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              const StatusBadge(
                label: '用户声明',
                icon: Icons.person_outline,
                tone: NoticeTone.unknown,
              ),
              const OutlinedButton(onPressed: null, child: Text('采用官方模板')),
              Text('官方模板需要连接服务器，后续提供。', style: secondary),
            ],
          ),
        ),
        const SectionTitle('账单日'),
        _padded(
          DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: _statementDay,
            decoration: const InputDecoration(
              labelText: '每月账单日',
              border: OutlineInputBorder(),
            ),
            items: <DropdownMenuItem<int>>[
              for (var day = 1; day <= 31; day++)
                DropdownMenuItem<int>(value: day, child: Text('$day 日')),
            ],
            onChanged: (value) => setState(() => _statementDay = value!),
          ),
        ),
        if (_statementDay >= 29)
          const NoticeCard(
            icon: Icons.info_outline,
            tone: NoticeTone.unknown,
            text: '29–31 日在小月按月末计算（月末截断），例如 31 日在 4 月是 30 日、在 2 月是 28 或 29 日。',
          ),
        SwitchListTile(
          title: const Text('账单日当天入账计入本期'),
          subtitle: const Text('关闭则账单日当天入账算下一期（银行差异项，请按账单核对）'),
          value: _inclusive,
          onChanged: (value) => setState(() => _inclusive = value),
        ),
        const SectionTitle('到期'),
        _padded(
          Wrap(
            spacing: CfSpace.xs,
            runSpacing: CfSpace.xs,
            children: <Widget>[
              ChoiceChip(
                label: const Text('固定日'),
                selected: _dueKind == DueKind.fixedDay,
                onSelected: (_) => setState(() => _dueKind = DueKind.fixedDay),
              ),
              ChoiceChip(
                label: const Text('账单后 N 天'),
                selected: _dueKind == DueKind.daysAfterStatement,
                onSelected: (_) =>
                    setState(() => _dueKind = DueKind.daysAfterStatement),
              ),
            ],
          ),
        ),
        if (_dueKind == DueKind.fixedDay) ...<Widget>[
          _padded(
            Wrap(
              spacing: CfSpace.xs,
              runSpacing: CfSpace.xs,
              children: <Widget>[
                for (final (offset, label) in <(int, String)>[
                  (0, '当月'),
                  (1, '次月'),
                  (2, '再下月'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _monthOffset == offset,
                    onSelected: (_) => setState(() => _monthOffset = offset),
                  ),
              ],
            ),
          ),
          _padded(
            DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: _dueDay,
              decoration: const InputDecoration(
                labelText: '到期日',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<int>>[
                for (var day = 1; day <= 31; day++)
                  DropdownMenuItem<int>(value: day, child: Text('$day 日')),
              ],
              onChanged: (value) => setState(() => _dueDay = value!),
            ),
          ),
        ] else ...<Widget>[
          _padded(
            DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: _dueDays,
              decoration: const InputDecoration(
                labelText: '账单日后天数（自然日）',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<int>>[
                for (var days = 1; days <= 60; days++)
                  DropdownMenuItem<int>(value: days, child: Text('$days 天')),
              ],
              onChanged: (value) => setState(() => _dueDays = value!),
            ),
          ),
          const SwitchListTile(
            title: Text('按工作日计算'),
            subtitle: Text('需要已核验的工作日日历，本阶段不可用。'),
            value: false,
            onChanged: null,
          ),
        ],
        const SwitchListTile(
          title: Text('到期日遇节假日顺延'),
          subtitle: Text('需要已核验的工作日日历，本阶段不可用；不顺延。'),
          value: false,
          onChanged: null,
        ),
        const SectionTitle('时区与入账'),
        _padded(
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _zoneId,
            decoration: const InputDecoration(
              labelText: '业务时区（账期按它计算，与手机时区无关）',
              border: OutlineInputBorder(),
            ),
            items: <DropdownMenuItem<String>>[
              for (final zone in supportedBusinessTimeZones)
                DropdownMenuItem<String>(
                  value: zone.id,
                  child: Text(
                    zone.displayName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              for (final id in laterSupportedTimeZoneIds)
                DropdownMenuItem<String>(
                  value: id,
                  enabled: false,
                  child: Text('$id · 后续支持', overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) => setState(() => _zoneId = value!),
          ),
        ),
        _padded(
          Wrap(
            spacing: CfSpace.sm,
            runSpacing: CfSpace.sm,
            children: <Widget>[
              for (final (label, isMin) in <(String, bool)>[
                ('入账延迟最少（天）', true),
                ('入账延迟最多（天）', false),
              ])
                SizedBox(
                  width: double.infinity,
                  child: DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: isMin ? _delayMin : _delayMax,
                    decoration: InputDecoration(
                      labelText: label,
                      border: const OutlineInputBorder(),
                    ),
                    items: <DropdownMenuItem<int>>[
                      for (var d = 0; d <= maxPostingDelayDays; d++)
                        DropdownMenuItem<int>(value: d, child: Text('$d 天')),
                    ],
                    onChanged: (value) => setState(() {
                      if (isMin) {
                        _delayMin = value!;
                      } else {
                        _delayMax = value!;
                      }
                    }),
                  ),
                ),
            ],
          ),
        ),
        SwitchListTile(
          title: const Text('设置截止时点'),
          subtitle: const Text('晚于这个时刻入账的算次日（按业务时区）'),
          value: _useCutoff,
          onChanged: (value) => setState(() => _useCutoff = value),
        ),
        if (_useCutoff)
          _padded(
            TextField(
              controller: _cutoff,
              keyboardType: TextInputType.datetime,
              autofillHints: null,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '截止时点（HH:MM）',
                hintText: '如 17:00',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        _padded(
          TextField(
            controller: _exceptions,
            autofillHints: null,
            maxLines: null,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '例外说明（可选，≤$maxNoteLength 字）',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        if (current != null) ...<Widget>[
          const SectionTitle('生效'),
          _padded(
            Wrap(
              spacing: CfSpace.xs,
              runSpacing: CfSpace.xs,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('更正当前规则（适用于全部历史）'),
                  selected: _correction,
                  onSelected: (_) => setState(() => _correction = true),
                ),
                ChoiceChip(
                  label: const Text('从某日起按新规则'),
                  selected: !_correction,
                  onSelected: (_) => setState(() => _correction = false),
                ),
              ],
            ),
          ),
          if (!_correction)
            _padded(
              DateField(
                label: '新规则生效日（入账日）',
                value: _effectiveFrom,
                first: LocalDate(2000, 1, 1),
                last: today.addDays(366),
                onChanged: (value) => setState(() => _effectiveFrom = value),
              ),
            ),
          if (effectiveProblem != null)
            NoticeCard(
              icon: Icons.error_outline,
              tone: NoticeTone.danger,
              text: effectiveProblem,
            ),
        ],
        const SectionTitle('3 期预览'),
        if (problem != null)
          NoticeCard(
            icon: Icons.error_outline,
            tone: NoticeTone.danger,
            text: '$problem（不能保存）',
          )
        else
          for (var i = 0; i < preview.length; i++)
            LabeledValue(
              label: '第 ${i + 1} 期',
              value: Text(
                '账单日 ${formatDate(preview[i].statementDate)} → 到期 ${formatDate(preview[i].dueDate)}',
              ),
            ),
        if (_saveError != null)
          NoticeCard(
            icon: Icons.error_outline,
            tone: NoticeTone.danger,
            text: '保存失败：$_saveError',
          ),
        _padded(
          FilledButton(
            onPressed: _saving || problem != null || effectiveProblem != null
                ? null
                : () => unawaited(_save()),
            child: Text(_saving ? '正在保存…' : '保存为用户声明'),
          ),
        ),
        const SectionTitle('规则版本历史'),
        if (versions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CfSpace.md),
            child: Text('还没有版本。', style: secondary),
          ),
        for (final version in versions)
          ListTile(
            title: Text(
              '第 ${version.version} 版 · ${ReviewStatus.of(version.reviewStatus).label} · ${RuleSource.of(version.source).label}',
            ),
            subtitle: Text(
              '${describeStatementDay(version.statementDay)}，${describeDue(dueOf(version))}；${describeEffectiveRange(version)}',
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
}
