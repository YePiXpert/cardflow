/// 现金表单共用的输入组件：文本/金额输入、层级选择（没有默认值，须选）、时刻输入。
library;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../data/repositories/cash_models.dart';

/// 表单行的统一内边距。
Widget formPadded(Widget child) => Padding(
  padding: const EdgeInsets.symmetric(
    horizontal: CfSpace.md,
    vertical: CfSpace.xs,
  ),
  child: child,
);

/// 文本输入（关闭系统自动填充，避免卡号填充）。
class FormTextField extends StatelessWidget {
  const FormTextField({
    super.key,
    required this.controller,
    required this.label,
    this.error,
    this.keyboardType = TextInputType.text,
    this.helper,
  });

  final TextEditingController controller;
  final String label;
  final String? error;
  final String? helper;
  final TextInputType keyboardType;

  /// 金额输入的键盘。
  static const TextInputType amountKeyboard = TextInputType.numberWithOptions(
    signed: true,
    decimal: true,
  );

  @override
  Widget build(BuildContext context) => formPadded(
    TextField(
      controller: controller,
      keyboardType: keyboardType,
      autofillHints: null,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 3,
        errorText: error,
        errorMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}

/// 一组单选标签（可换行）。
class ChoiceWrap<T> extends StatelessWidget {
  const ChoiceWrap({
    super.key,
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.error,
  });

  final String label;
  final List<T> values;
  final T? selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onSelected;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    return formPadded(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: theme.textTheme.bodyMedium),
          const SizedBox(height: CfSpace.xxs),
          Wrap(
            spacing: CfSpace.xs,
            runSpacing: CfSpace.xs,
            children: <Widget>[
              for (final value in values)
                ChoiceChip(
                  label: Text(labelOf(value)),
                  selected: value == selected,
                  onSelected: (_) => onSelected(value),
                ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: CfSpace.xxs),
              child: Text(
                error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.danger.fg,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 层级选择（R-CASH-03）：确定 / 预计，没有默认值、没有概率字段。
class CashClassField extends StatelessWidget {
  const CashClassField({
    super.key,
    required this.selected,
    required this.onSelected,
    this.error,
  });

  final CashEventClass? selected;
  final ValueChanged<CashEventClass> onSelected;
  final String? error;

  /// 没选层级时的文案。
  static const String missing = '请选择层级：确定或预计';

  @override
  Widget build(BuildContext context) => ChoiceWrap<CashEventClass>(
    label: '层级（必选；不设概率）',
    values: CashEventClass.userChoices,
    selected: selected,
    labelOf: (c) => c == CashEventClass.confirmed ? '确定（合同、已约定）' : '预计（可能变动）',
    onSelected: onSelected,
    error: error,
  );
}

/// 解析 `HH:MM`；空白返回 (null, null)，格式不对返回 (null, 错误)。
((int, int)?, String?) parseHourMinute(String text, {bool required = false}) {
  final value = text.trim();
  if (value.isEmpty) {
    return (null, required ? '请填写时刻（HH:MM）' : null);
  }
  final m = RegExp(r'^([01][0-9]|2[0-3]):([0-5][0-9])$').firstMatch(value);
  if (m == null) {
    return (null, '时刻格式应为 HH:MM');
  }
  return ((int.parse(m.group(1)!), int.parse(m.group(2)!)), null);
}
