import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate;
import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../data/validation/text_rules.dart';
import 'card_formatting.dart';

/// 换卡/补卡的输入。
typedef ReplacementInput = ({String last4, LocalDate effectiveFrom});

/// [LocalDate] → 日期选择器用的 [DateTime]（当地午夜，只用年月日）。
DateTime pickerDate(LocalDate date) =>
    DateTime(date.year, date.month, date.day);

/// 日期选择器结果 → [LocalDate]。
LocalDate fromPicker(DateTime value) =>
    LocalDate(value.year, value.month, value.day);

/// 日期字段：显示当前日期（[value] 为空时显示"未选择"），点按打开系统日期选择器。
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.first,
    required this.last,
    required this.onChanged,
    this.initial,
  });

  final String label;
  final LocalDate? value;
  final LocalDate first;
  final LocalDate last;
  final ValueChanged<LocalDate> onChanged;

  /// [value] 为空时选择器打开在哪一天（默认 [last]）。
  final LocalDate? initial;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: pickerDate(value ?? initial ?? last),
          firstDate: pickerDate(first),
          lastDate: pickerDate(last),
        );
        if (picked != null) {
          onChanged(fromPicker(picked));
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(value == null ? '未选择' : formatDate(value!)),
      ),
    );
  }
}

/// 换卡/补卡对话框：新末四位 + 生效日（P-03 字段校验）。取消返回 null。
Future<ReplacementInput?> showReplaceCardDialog(
  BuildContext context, {
  required String oldTail,
  required LocalDate today,
}) => showDialog<ReplacementInput>(
  context: context,
  builder: (_) => _ReplaceCardDialog(oldTail: oldTail, today: today),
);

class _ReplaceCardDialog extends StatefulWidget {
  const _ReplaceCardDialog({required this.oldTail, required this.today});

  final String oldTail;
  final LocalDate today;

  @override
  State<_ReplaceCardDialog> createState() => _ReplaceCardDialogState();
}

class _ReplaceCardDialogState extends State<_ReplaceCardDialog> {
  final TextEditingController _last4 = TextEditingController();
  late LocalDate _effective = widget.today;
  String? _error;

  @override
  void dispose() {
    _last4.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('换卡/补卡'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('旧卡 ${widget.oldTail} 将标为"已换卡"；新卡挂在同一信用账户，账户、子账户与历史数据不变。'),
            const SizedBox(height: CfSpace.md),
            TextField(
              controller: _last4,
              keyboardType: TextInputType.number,
              autofillHints: null,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              onChanged: (value) => setState(
                () => _error = looksLikeFullCardNumber(value)
                    ? fullCardNumberMessage
                    : null,
              ),
              decoration: InputDecoration(
                labelText: '新卡末四位',
                errorText: _error,
                errorMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: CfSpace.md),
            DateField(
              label: '新卡生效日',
              value: _effective,
              first: LocalDate(2000, 1, 1),
              last: widget.today.addDays(366),
              onChanged: (value) => setState(() => _effective = value),
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
            final problem = validateLast4(_last4.text);
            if (problem != null) {
              setState(() => _error = problem);
              return;
            }
            Navigator.of(context)
                .pop((last4: _last4.text, effectiveFrom: _effective));
          },
          child: const Text('确认换卡'),
        ),
      ],
    );
  }
}

/// 销卡对话框：销卡日（不晚于今天）+ 影响说明（ui-spec §4.5）。取消返回 null。
Future<LocalDate?> showCloseCardDialog(
  BuildContext context, {
  required String tail,
  required LocalDate today,
}) => showDialog<LocalDate>(
  context: context,
  builder: (_) => _CloseCardDialog(tail: tail, today: today),
);

class _CloseCardDialog extends StatefulWidget {
  const _CloseCardDialog({required this.tail, required this.today});

  final String tail;
  final LocalDate today;

  @override
  State<_CloseCardDialog> createState() => _CloseCardDialogState();
}

class _CloseCardDialogState extends State<_CloseCardDialog> {
  late LocalDate _closedOn = widget.today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('销卡 ${widget.tail}？'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              '影响：这 1 张卡将标为"已销卡"，不能再恢复；信用账户、币种子账户与历史数据都保留。'
              '如有欠款，销卡后欠款仍显示（账单、交易与还款都不迁移）。',
            ),
            const SizedBox(height: CfSpace.md),
            DateField(
              label: '销卡日（不晚于今天）',
              value: _closedOn,
              first: LocalDate(2000, 1, 1),
              last: widget.today,
              onChanged: (value) => setState(() => _closedOn = value),
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
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(_closedOn),
          child: const Text('确认销卡'),
        ),
      ],
    );
  }
}
