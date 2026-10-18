/// 精确有理数与显式取整（不使用二进制浮点）。
///
/// 利率、情景系数、加权缓冲天数等非整数量一律用 [Rational]（BigInt 分子/分母）表示；
/// 金额永远是 `int` 最小单位。取整只通过 [RoundingMode] 显式进行，语义与
/// `services/api/cardflow/planner/engine/money.py` 的 `ROUNDING` 表一致。
library;

/// 取整模式（money.py `ROUNDING` 的四个键）。
enum RoundingMode {
  /// `HALF_UP`：取最近值，恰在一半时远离零（四舍五入；Python `ROUND_HALF_UP`）。
  halfUp('HALF_UP'),

  /// `DOWN`：朝零截断（如银联活动"取小数点后两位，不作四舍五入"；Python `ROUND_DOWN`）。
  down('DOWN'),

  /// `HALF_EVEN`：取最近值，恰在一半时取偶数（Python `ROUND_HALF_EVEN`）。
  halfEven('HALF_EVEN'),

  /// `UP`：朝正无穷（费用的保守口径）。与 money.py 一致，`UP` 映射到 `ROUND_CEILING`，
  /// 因此对负数是朝零方向（-1.5 → -1）。
  up('UP');

  const RoundingMode(this.code);

  /// money.py 中的名称。
  final String code;
}

/// 精确有理数：分母恒为正，分子分母互素。
final class Rational implements Comparable<Rational> {
  Rational._(this.numerator, this.denominator);

  /// `numerator / denominator`，自动约分；分母为 0 抛 [ArgumentError]。
  factory Rational(BigInt numerator, [BigInt? denominator]) {
    var n = numerator;
    var d = denominator ?? BigInt.one;
    if (d == BigInt.zero) {
      throw ArgumentError('zero denominator');
    }
    if (d.isNegative) {
      n = -n;
      d = -d;
    }
    if (n == BigInt.zero) {
      return Rational._(BigInt.zero, BigInt.one);
    }
    final g = n.gcd(d);
    if (g != BigInt.one) {
      n = n ~/ g;
      d = d ~/ g;
    }
    return Rational._(n, d);
  }

  /// 整数（可带整数分母）。
  factory Rational.fromInt(int numerator, [int denominator = 1]) =>
      Rational(BigInt.from(numerator), BigInt.from(denominator));

  /// 0。
  static final Rational zero = Rational._(BigInt.zero, BigInt.one);

  /// 1。
  static final Rational one = Rational._(BigInt.one, BigInt.one);

  static final RegExp _decimal = RegExp(
    r'^([+-]?)([0-9]*)(?:\.([0-9]*))?(?:[eE]([+-]?[0-9]+))?$',
  );

  /// 解析十进制文本（`-0.006`、`1.5E-3`、`12`），得到精确值；不接受空白、NaN、无穷。
  ///
  /// 与 Python `Decimal(text)` 对有限十进制数的取值一致（不取整）。指数的绝对值超过
  /// 10000 视为不支持（[FormatException]），以免构造出巨大的整数。
  static Rational parseDecimal(String text) {
    final m = _decimal.firstMatch(text);
    if (m == null) {
      throw const FormatException('not a decimal number');
    }
    final intDigits = m.group(2)!;
    final fracDigits = m.group(3) ?? '';
    if (intDigits.isEmpty && fracDigits.isEmpty) {
      throw const FormatException('not a decimal number');
    }
    final expText = m.group(4);
    var exponent = 0;
    if (expText != null) {
      final digits = expText.replaceFirst(RegExp(r'^[+-]'), '');
      if (digits.length > 5 || int.parse(digits) > 10000) {
        throw const FormatException(
          'decimal exponent out of the supported range',
        );
      }
      exponent = int.parse(expText);
    }
    var n = BigInt.parse(
      '$intDigits$fracDigits'.isEmpty ? '0' : '$intDigits$fracDigits',
    );
    if (m.group(1) == '-') {
      n = -n;
    }
    final scale = exponent - fracDigits.length;
    if (scale >= 0) {
      return Rational(n * BigInt.from(10).pow(scale));
    }
    return Rational(n, BigInt.from(10).pow(-scale));
  }

  /// 分子（符号在分子上）。
  final BigInt numerator;

  /// 分母（恒为正）。
  final BigInt denominator;

  /// 是否为 0。
  bool get isZero => numerator == BigInt.zero;

  /// 是否小于 0。
  bool get isNegative => numerator.isNegative;

  /// 是否为整数。
  bool get isInteger => denominator == BigInt.one;

  /// 和。
  Rational operator +(Rational other) => Rational(
    numerator * other.denominator + other.numerator * denominator,
    denominator * other.denominator,
  );

  /// 差。
  Rational operator -(Rational other) => Rational(
    numerator * other.denominator - other.numerator * denominator,
    denominator * other.denominator,
  );

  /// 积。
  Rational operator *(Rational other) =>
      Rational(numerator * other.numerator, denominator * other.denominator);

  /// 相反数。
  Rational operator -() => Rational._(-numerator, denominator);

  /// 商（除数为 0 抛 [ArgumentError]）。不提供 `/` 运算符：领域层源码不出现 `/`。
  Rational dividedBy(Rational other) =>
      Rational(numerator * other.denominator, denominator * other.numerator);

  /// 与整数的积。
  Rational timesInt(int factor) =>
      Rational(numerator * BigInt.from(factor), denominator);

  /// 绝对值。
  Rational abs() => isNegative ? -this : this;

  /// 朝负无穷取整。
  BigInt floor() {
    final r = numerator % denominator; // Euclidean：0 <= r < denominator
    return (numerator - r) ~/ denominator;
  }

  /// 朝正无穷取整。
  BigInt ceil() => -((-this).floor());

  /// 朝零取整。
  BigInt truncate() => isNegative ? ceil() : floor();

  /// 按 [mode] 取整到整数。
  BigInt round(RoundingMode mode) {
    switch (mode) {
      case RoundingMode.down:
        return truncate();
      case RoundingMode.up:
        return ceil();
      case RoundingMode.halfUp:
      case RoundingMode.halfEven:
        final magnitude = abs();
        final q = magnitude.floor();
        final twiceRemainder =
            (magnitude.numerator - q * magnitude.denominator) * BigInt.two;
        final cmp = twiceRemainder.compareTo(magnitude.denominator);
        var r = q;
        if (cmp > 0 || (cmp == 0 && (mode == RoundingMode.halfUp || q.isOdd))) {
          r = q + BigInt.one;
        }
        return isNegative ? -r : r;
    }
  }

  /// 按 [mode] 取整到 64 位整数；超出 int 范围抛 [RangeError]（不截断）。
  int roundToInt(RoundingMode mode) => checkedInt(round(mode));

  /// 精确的整数值（不是整数时抛 [StateError]）。
  BigInt toBigInt() {
    if (!isInteger) {
      throw StateError('not an integer');
    }
    return numerator;
  }

  @override
  int compareTo(Rational other) =>
      (numerator * other.denominator).compareTo(other.numerator * denominator);

  /// 小于。
  bool operator <(Rational other) => compareTo(other) < 0;

  /// 小于等于。
  bool operator <=(Rational other) => compareTo(other) <= 0;

  /// 大于。
  bool operator >(Rational other) => compareTo(other) > 0;

  /// 大于等于。
  bool operator >=(Rational other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is Rational &&
      other.numerator == numerator &&
      other.denominator == denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  String toString() =>
      isInteger ? numerator.toString() : '$numerator/$denominator';
}

/// BigInt → int；超出 64 位范围抛 [RangeError]（绝不静默截断）。
int checkedInt(BigInt value) {
  if (!value.isValidInt) {
    throw RangeError('integer out of the 64-bit range');
  }
  return value.toInt();
}
