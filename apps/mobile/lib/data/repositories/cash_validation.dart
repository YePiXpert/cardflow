/// 现金仓库共用的字段校验（P-08/P-09、G1/G3/G4/G5）：文案可直接显示、不含用户数据。
library;

import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate, Timestamp;

import '../mapping/cash_mapping.dart';
import '../time/business_tz.dart';
import '../validation/text_rules.dart';
import 'cash_models.dart';
import 'credit_pool_repository.dart' show maxAmountMinor;
import 'repository_errors.dart';

/// 现金日期是否在规则协议 v1 支持的范围（1970–2999 年）。
bool isSupportedCashDate(LocalDate date) =>
    date.year >= 1970 && date.year <= 2999;

/// 用户登记的收支只能选确定或预计（R-CASH-03：须选层级，没有概率字段）。
void checkUserCashClass(CashEventClass cls) {
  if (!CashEventClass.userChoices.contains(cls)) {
    throw const ValidationException('cls', '请选择层级：确定或预计');
  }
}

/// 金额（正数，最小单位）不超过 10^13（G1）。
void checkCashMagnitude(int amount, {String field = 'amount'}) {
  if (amount <= 0) {
    throw ValidationException(field, '金额须大于 0');
  }
  if (amount > maxAmountMinor) {
    throw ValidationException(field, '金额超出范围');
  }
}

/// 日期在支持范围内。
void checkCashDate(String field, LocalDate date) {
  if (!isSupportedCashDate(date)) {
    throw ValidationException(field, '日期超出支持的范围');
  }
}

/// 时刻 → 存库文本：换算到现金时区写出（按自身偏移取的日期就是业务日期），日期必须等于 [on]
/// （规则协议 v1 的交叉规则：`at` 按自身偏移的日期等于 `on`）。
String? cashAtText(Timestamp? at, LocalDate on, {String field = 'at'}) {
  if (at == null) {
    return null;
  }
  final text = timestampTextIn(
    DateTime.fromMicrosecondsSinceEpoch(at.utcMicros, isUtc: true),
    cashTimeZone,
  );
  if (Timestamp.parse(text).date != on) {
    throw ValidationException(field, '时刻须在所选日期当天');
  }
  return text;
}

/// 可选的名称（G2/G5）：空白为 null。
String? optionalCashLabel(String? text, {String field = 'label'}) {
  final value = text?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  final problem = validateFreeText(value, fieldName: '名称');
  if (problem != null) {
    throw ValidationException(field, problem);
  }
  return value;
}

/// 必填的名称（G2/G5）。
String requiredCashLabel(String? text, {String field = 'label'}) {
  final value = text?.trim() ?? '';
  final problem = validateFreeText(value, required: true, fieldName: '名称');
  if (problem != null) {
    throw ValidationException(field, problem);
  }
  return value;
}
