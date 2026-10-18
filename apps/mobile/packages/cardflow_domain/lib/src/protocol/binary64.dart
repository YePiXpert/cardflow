/// IEEE 754 binary64 的精确整数表示，只用于 JSON 中的非整数数字（协议 v1 只有
/// `options.time_limit_s`）。
///
/// 领域层不使用 `double`（ADR-008），但规范化 JSON 要按 ECMAScript `Number.prototype.toString`
/// 写出非整数（RFC 8785 §3.2.2.3，README"规范化 JSON 与 input_hash"第 6 条），这取决于数字
/// 舍入到 binary64 之后的值。这里用 BigInt 精确地完成两步：十进制记号 → 最近的 binary64
/// （就近舍入、恰在一半取偶，与 Python `float(text)` 相同），binary64 → 最短往返十进制
/// （与 Python `repr(float)` / ECMAScript 相同：位数最少，其中最接近者，再相同取偶）。
library;

import '../rational.dart';

/// binary64 值：`(-1)^negative × significand × 2^exponent`。
///
/// 规格化数 `2^52 <= significand < 2^53`；次正规数 `exponent == -1074`；零的 significand 为 0。
final class Binary64 {
  Binary64._(this.negative, this.significand, this.exponent);

  static final BigInt _two52 = BigInt.one << 52;
  static final BigInt _two53 = BigInt.one << 53;
  static final BigInt _ten = BigInt.from(10);
  static const int _minExponent = -1074;
  static const int _maxExponent = 971;

  /// 正零或负零。
  static Binary64 zero({bool negative = false}) =>
      Binary64._(negative, BigInt.zero, 0);

  /// 非负有理数 `numerator / denominator` 最近的 binary64（就近舍入，恰在一半取偶）；
  /// 超出 binary64 的有限范围（会舍入成无穷）时返回 null。
  static Binary64? nearest(
    BigInt numerator,
    BigInt denominator, {
    bool negative = false,
  }) {
    if (numerator.isNegative || denominator <= BigInt.zero) {
      throw ArgumentError(
        'expects a non-negative numerator and a positive denominator',
      );
    }
    if (numerator == BigInt.zero) {
      return zero(negative: negative);
    }
    var e = numerator.bitLength - denominator.bitLength - 53;
    BigInt n;
    BigInt d;
    BigInt q;
    while (true) {
      n = e >= 0 ? numerator : numerator << -e;
      d = e >= 0 ? denominator << e : denominator;
      q = n ~/ d;
      if (q >= _two53) {
        e++;
      } else if (q < _two52) {
        e--;
      } else {
        break;
      }
    }
    if (e < _minExponent) {
      e = _minExponent;
      n = numerator << -e;
      d = denominator;
      q = n ~/ d;
    }
    final twiceRemainder = (n - q * d) << 1;
    final cmp = twiceRemainder.compareTo(d);
    if (cmp > 0 || (cmp == 0 && q.isOdd)) {
      q += BigInt.one;
    }
    if (q == _two53) {
      q = _two52;
      e++;
    }
    if (e > _maxExponent) {
      return null;
    }
    if (q == BigInt.zero) {
      return zero(negative: negative);
    }
    return Binary64._(negative, q, e);
  }

  static final RegExp _number = RegExp(
    r'^(-?)(0|[1-9][0-9]*)(?:\.([0-9]+))?(?:[eE]([+-]?)([0-9]+))?$',
  );

  /// JSON 数字记号最近的 binary64；记号不合语法时抛 [FormatException]，舍入成无穷时返回 null
  /// （Python `float("1e400")` 是 inf，协议读取器据此拒绝）。
  static Binary64? parseJsonNumber(String token) {
    final m = _number.firstMatch(token);
    if (m == null) {
      throw const FormatException('not a JSON number');
    }
    final negative = m.group(1) == '-';
    final fraction = m.group(3) ?? '';
    final digits = '${m.group(2)}$fraction'.replaceFirst(RegExp(r'^0+'), '');
    if (digits.isEmpty) {
      return zero(negative: negative);
    }
    final expDigits = (m.group(5) ?? '0').replaceFirst(RegExp(r'^0+(?=.)'), '');
    final expNegative = m.group(4) == '-';
    // 指数的位数远超 binary64 范围时直接判定（不构造巨大的整数）。
    if (expDigits.length > 7) {
      return expNegative ? zero(negative: negative) : null;
    }
    final exp10 =
        (expNegative ? -1 : 1) * int.parse(expDigits) - fraction.length;
    final adjusted = digits.length - 1 + exp10; // 首位有效数字的十进制位置
    if (adjusted > 309) {
      return null; // >= 10^309 > 最大有限值
    }
    if (adjusted < -400) {
      return zero(negative: negative); // < 10^-399，小于最小次正规数的一半
    }
    final significand = BigInt.parse(digits);
    if (exp10 >= 0) {
      return nearest(
        significand * _ten.pow(exp10),
        BigInt.one,
        negative: negative,
      );
    }
    return nearest(significand, _ten.pow(-exp10), negative: negative);
  }

  /// 是否为负号位（含负零）。
  final bool negative;

  /// 有效数（零为 0）。
  final BigInt significand;

  /// 二进制指数。
  final int exponent;

  /// 是否为零（正零或负零）。
  bool get isZero => significand == BigInt.zero;

  /// 精确值。
  Rational get value {
    if (isZero) {
      return Rational.zero;
    }
    final signed = negative ? -significand : significand;
    return exponent >= 0
        ? Rational(signed << exponent)
        : Rational(signed, BigInt.one << -exponent);
  }

  /// ECMAScript `Number::toString`（RFC 8785 §3.2.2.3）：`10.0 → 10`、`0.5 → 0.5`、
  /// `1e-7 → 1e-7`、`1e21 → 1e+21`、负零 → `0`。
  String toEcmaScript() {
    if (isZero) {
      return '0';
    }
    final (digits, n) = _shortest();
    final k = digits.length;
    String text;
    if (k <= n && n <= 21) {
      text = digits + '0' * (n - k);
    } else if (0 < n && n <= 21) {
      text = '${digits.substring(0, n)}.${digits.substring(n)}';
    } else if (-6 < n && n <= 0) {
      text = '0.${'0' * -n}$digits';
    } else {
      final e = n - 1;
      final mantissa = k == 1 ? digits : '${digits[0]}.${digits.substring(1)}';
      text = '${mantissa}e${e >= 0 ? '+' : '-'}${e.abs()}';
    }
    return negative ? '-$text' : text;
  }

  static int _floorDiv(int a, int b) {
    final q = a ~/ b;
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q;
  }

  /// 最短往返十进制：返回（数字串 d1…dk，n），值 = 0.d1…dk × 10^n。
  (String, int) _shortest() {
    final q = significand;
    final m = q << 2;
    final high = m + BigInt.two;
    final low = (q == _two52 && exponent > _minExponent)
        ? m - BigInt.one
        : m - BigInt.two;
    final inclusive = q.isEven; // 恰在边界上的十进制值按"取偶"读回本值
    final s2 = exponent - 2; // 值(X) = X × 2^s2
    // 从一个保证 10^p 大于上边界的 p 开始（log10(2) ≈ 0.30103，多留一位余量），逐位下降；
    // 第一个有候选的 p 给出最少的位数。
    var p = _floorDiv((high.bitLength + s2) * 30103, 100000) + 2;
    while (true) {
      var numScale = BigInt.one;
      var den = BigInt.one;
      if (s2 >= 0) {
        numScale = BigInt.one << s2;
      } else {
        den = BigInt.one << -s2;
      }
      if (p >= 0) {
        den *= _ten.pow(p);
      } else {
        numScale *= _ten.pow(-p);
      }
      final lowNum = low * numScale;
      final highNum = high * numScale;
      final sMin = inclusive
          ? (lowNum + den - BigInt.one) ~/ den
          : lowNum ~/ den + BigInt.one;
      var sMax = highNum ~/ den;
      if (!inclusive && highNum % den == BigInt.zero) {
        sMax -= BigInt.one;
      }
      if (sMin <= sMax) {
        final valueNum = m * numScale;
        var s = valueNum ~/ den;
        final twiceRemainder = (valueNum - s * den) << 1;
        final cmp = twiceRemainder.compareTo(den);
        if (cmp > 0 || (cmp == 0 && s.isOdd)) {
          s += BigInt.one;
        }
        if (s < sMin) {
          s = sMin;
        } else if (s > sMax) {
          s = sMax;
        }
        final digits = s.toString();
        return (digits, p + digits.length);
      }
      p--;
    }
  }

  /// 同一 binary64 值即相等；正零等于负零（与 Python `0.0 == -0.0` 相同）。
  @override
  bool operator ==(Object other) {
    if (other is! Binary64) {
      return false;
    }
    if (isZero || other.isZero) {
      return isZero && other.isZero;
    }
    return negative == other.negative &&
        significand == other.significand &&
        exponent == other.exponent;
  }

  @override
  int get hashCode => isZero ? 0 : Object.hash(negative, significand, exponent);

  @override
  String toString() => toEcmaScript();
}
