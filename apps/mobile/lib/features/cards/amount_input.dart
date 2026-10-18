import 'package:cardflow_domain/cardflow_domain.dart';

import '../../data/repositories/credit_pool_repository.dart'
    show maxAmountMinor;

/// 金额输入（G1）：按币种小数位输入，允许千分位逗号与空格；默认不小于 0，[allowNegative]
/// 时可负（银行可用额）。返回 (最小单位, 错误文案)：空输入且 [required] 为 false 时为 (null, null)。
///
/// 换算用领域包的 `toMinorText`（精确十进制，位数超过币种最小单位时拒绝，不取整）。
(int?, String?) parseAmountMinor(
  String text,
  String currency, {
  bool allowNegative = false,
  bool required = true,
}) {
  final cleaned = text.replaceAll(RegExp(r'[,\s，]'), '').replaceAll('−', '-');
  if (cleaned.isEmpty) {
    return required ? (null, '请填写金额') : (null, null);
  }
  if (!RegExp(r'^-?[0-9]+(\.[0-9]+)?$').hasMatch(cleaned)) {
    return (null, '金额格式不对');
  }
  final int minor;
  try {
    minor = toMinorText(cleaned, currency);
  } on RangeError {
    // RangeError 是 ArgumentError 的子类：先判断"超出 64 位"。
    return (null, '金额超出范围');
  } on ArgumentError {
    final digits = minorDigitsOf(currency);
    return (null, digits == 0 ? '$currency 不能有小数' : '最多 $digits 位小数');
  }
  if (minor < 0 && !allowNegative) {
    return (null, '金额不能为负');
  }
  if (minor.abs() > maxAmountMinor) {
    return (null, '金额超出范围');
  }
  return (minor, null);
}

/// 最小单位 → 输入框里的文字（不带千分位，币种小数位）。
String amountText(int minor, String currency) => fromMinorText(minor, currency);
