/// 金额：整数最小单位 + 币种（ADR-008）。
///
/// 与 `services/api/cardflow/planner/engine/money.py` 同义：最小单位位数表 [minorDigits]、
/// [toMinor]（超精度拒绝，不取整）、[fromMinor]、显式取整的 [applyRate]、
/// 规范十进制文本 [decimalText]（去尾零，与 Python `money.decimal_text` 一致）。
library;

import 'rational.dart';

/// 每种币种的最小单位位数（ISO 4217）。不假设"全局 2 位小数"。
///
/// 必须与 money.py 的 `MINOR_DIGITS` 完全一致（测试读取 money.py 逐项比对）；
/// App 的金额展示（`MoneyText`）引用的就是这张表。
const Map<String, int> minorDigits = <String, int>{
  'CNY': 2,
  'USD': 2,
  'EUR': 2,
  'HKD': 2,
  'GBP': 2,
  'MOP': 2,
  'TWD': 2,
  'JPY': 0,
  'KRW': 0,
  'VND': 0,
  'KWD': 3,
  'BHD': 3,
  'JOD': 3,
};

/// 币种的最小单位位数；未登记的币种抛 [ArgumentError]（宁可报错，也不猜小数位）。
int minorDigitsOf(String currency) {
  final digits = minorDigits[currency];
  if (digits == null) {
    throw ArgumentError.value(currency, 'currency', '未登记最小单位位数的币种');
  }
  return digits;
}

BigInt _pow10(int n) => BigInt.from(10).pow(n);

/// 十进制金额 → 整数最小单位：`123.45` CNY → 12345。
///
/// 位数超过币种最小单位时抛 [ArgumentError]，绝不静默取整；结果超出 64 位整数抛 [RangeError]。
int toMinor(Rational amount, String currency) {
  final scaled = amount * Rational(_pow10(minorDigitsOf(currency)));
  if (!scaled.isInteger) {
    throw ArgumentError(
      'amount has more precision than the $currency minor unit',
    );
  }
  return checkedInt(scaled.numerator);
}

/// [toMinor] 的文本版：`toMinorText('123.45', 'CNY') == 12345`。
int toMinorText(String amount, String currency) =>
    toMinor(Rational.parseDecimal(amount), currency);

/// 整数最小单位 → 精确十进制值：12345 CNY → 123.45。
Rational fromMinor(int minor, String currency) =>
    Rational(BigInt.from(minor), _pow10(minorDigitsOf(currency)));

/// 整数最小单位 → 定点文本，位数等于币种最小单位位数（与 Python
/// `str(money.from_minor(minor, currency))` 相同）：12345 CNY → `123.45`，5 CNY → `0.05`，
/// 1235 JPY → `1235`，5 KWD → `0.005`。
String fromMinorText(int minor, String currency) {
  final digits = minorDigitsOf(currency);
  final negative = minor < 0;
  final abs = BigInt.from(minor).abs().toString().padLeft(digits + 1, '0');
  final text = digits == 0
      ? abs
      : '${abs.substring(0, abs.length - digits)}.${abs.substring(abs.length - digits)}';
  return negative ? '-$text' : text;
}

/// `minor × rate`，按 [rounding] 显式取整（money.py `apply_rate`）。
int applyRate(int minor, Rational rate, RoundingMode rounding) =>
    (Rational.fromInt(minor) * rate).roundToInt(rounding);

/// 规范十进制文本：普通记数法、无多余尾零、所有零都写 `"0"`（money.py `decimal_text`）。
///
/// 数据库读出的 `NUMERIC(20,10)`（如 0.0060000000）与 0.006 得到同一文本，因此同一利率只有一种
/// 写法、一个 input_hash（R3E-11）。不是有限小数（如 1/3）时抛 [ArgumentError]。
String decimalText(Rational value) {
  if (value.isZero) {
    return '0';
  }
  var rest = value.denominator;
  var twos = 0;
  var fives = 0;
  final two = BigInt.two;
  final five = BigInt.from(5);
  while (rest % two == BigInt.zero) {
    rest = rest ~/ two;
    twos++;
  }
  while (rest % five == BigInt.zero) {
    rest = rest ~/ five;
    fives++;
  }
  if (rest != BigInt.one) {
    throw ArgumentError('not a terminating decimal');
  }
  final places = twos > fives ? twos : fives;
  final scaled = value.numerator * _pow10(places) ~/ value.denominator;
  final negative = scaled.isNegative;
  var digits = scaled.abs().toString();
  if (places > 0) {
    digits = digits.padLeft(places + 1, '0');
    var fraction = digits.substring(digits.length - places);
    fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
    final integer = digits.substring(0, digits.length - places);
    digits = fraction.isEmpty ? integer : '$integer.$fraction';
  }
  return negative ? '-$digits' : digits;
}

/// 金额值对象：整数最小单位 + ISO 4217 币种（architecture §3 的 `Money{minor, currency}`）。
final class Money implements Comparable<Money> {
  /// 币种必须在 [minorDigits] 中登记，否则抛 [ArgumentError]。
  Money(this.minor, this.currency) {
    minorDigitsOf(currency);
  }

  /// 整数最小单位（CNY 为分、JPY 为元、KWD 为 1/1000）。
  final int minor;

  /// ISO 4217 币种代码。
  final String currency;

  void _sameCurrency(Money other) {
    if (other.currency != currency) {
      throw ArgumentError('currency mismatch: $currency vs ${other.currency}');
    }
  }

  /// 同币种相加。
  Money operator +(Money other) {
    _sameCurrency(other);
    return Money(minor + other.minor, currency);
  }

  /// 同币种相减。
  Money operator -(Money other) {
    _sameCurrency(other);
    return Money(minor - other.minor, currency);
  }

  /// 是否为负。
  bool get isNegative => minor < 0;

  /// 精确十进制值。
  Rational get decimal => fromMinor(minor, currency);

  @override
  int compareTo(Money other) {
    _sameCurrency(other);
    return minor.compareTo(other.minor);
  }

  @override
  bool operator ==(Object other) =>
      other is Money && other.minor == minor && other.currency == currency;

  @override
  int get hashCode => Object.hash(minor, currency);

  @override
  String toString() => '$currency ${fromMinorText(minor, currency)}';
}
