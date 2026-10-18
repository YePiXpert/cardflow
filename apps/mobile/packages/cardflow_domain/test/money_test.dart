// money 模块：minorDigits 与 money.py 逐项一致、toMinor/fromMinor（超精度拒绝、往返性质）、
// 显式取整模式（期望值取自 Python money.apply_rate 的实际输出）、decimalText（R3E-11）、Rational。
import 'dart:math';

import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:test/test.dart';

import 'support/repo.dart';

/// 从 money.py 中解析 `MINOR_DIGITS: dict[str, int] = { ... }`。
Map<String, int> parseServerMinorDigits(String source) {
  final block = RegExp(r'MINOR_DIGITS[^=]*=\s*\{([^}]*)\}').firstMatch(source);
  if (block == null) {
    throw StateError('MINOR_DIGITS not found in money.py');
  }
  return {
    for (final m in RegExp(
      r'"([A-Z]{3})"\s*:\s*(\d+)',
    ).allMatches(block.group(1)!))
      m.group(1)!: int.parse(m.group(2)!),
  };
}

Rational r(String text) => Rational.parseDecimal(text);

void main() {
  group('minorDigits', () {
    test('equals MINOR_DIGITS of the server engine money.py', () {
      final server = parseServerMinorDigits(engineSource('money.py'));
      expect(server, hasLength(13));
      expect(minorDigits, equals(server));
    });

    test('unknown currencies are an error, never a guessed digit count', () {
      expect(minorDigitsOf('CNY'), 2);
      expect(minorDigitsOf('JPY'), 0);
      expect(minorDigitsOf('KWD'), 3);
      expect(() => minorDigitsOf('XYZ'), throwsArgumentError);
      expect(() => minorDigitsOf('cny'), throwsArgumentError);
      expect(() => Money(1, 'BTC'), throwsArgumentError);
    });
  });

  group('toMinor / fromMinor', () {
    test('decimal text to minor units (Python to_minor)', () {
      expect(toMinorText('123.45', 'CNY'), 12345);
      expect(toMinorText('1E+2', 'CNY'), 10000);
      expect(toMinorText('-0.05', 'CNY'), -5);
      expect(toMinorText('1235', 'JPY'), 1235);
      expect(toMinorText('0.005', 'KWD'), 5);
    });

    test('more precision than the minor unit is rejected, never rounded', () {
      for (final (amount, currency) in [
        ('0.001', 'CNY'),
        ('1.5', 'JPY'),
        ('0.0005', 'KWD'),
      ]) {
        expect(
          () => toMinorText(amount, currency),
          throwsA(
            isA<ArgumentError>().having(
              (e) => '${e.message}',
              'message',
              'amount has more precision than the $currency minor unit',
            ),
          ),
        );
      }
      expect(
        () => toMinorText('99999999999999999999', 'CNY'),
        throwsRangeError,
      );
    });

    test('fixed-point text equals Python str(from_minor(...))', () {
      expect(fromMinorText(12345, 'CNY'), '123.45');
      expect(fromMinorText(5, 'CNY'), '0.05');
      expect(fromMinorText(-5, 'CNY'), '-0.05');
      expect(fromMinorText(0, 'CNY'), '0.00');
      expect(fromMinorText(1235, 'JPY'), '1235');
      expect(fromMinorText(5, 'KWD'), '0.005');
      expect(fromMinorText(-1234567, 'BHD'), '-1234.567');
      expect(Money(12345, 'CNY').toString(), 'CNY 123.45');
    });

    test('round trip to_minor(from_minor(n)) == n (seeded, 200 cases per currency)', () {
      final rng = Random(20261018);
      for (final currency in const ['CNY', 'JPY', 'KWD']) {
        for (var i = 0; i < 200; i++) {
          // 0..10^12（与 Python 性质测试相同的范围），两段随机数拼出 40 位
          final n =
              (rng.nextInt(1 << 20) * (1 << 20) + rng.nextInt(1 << 20)) %
              1000000000001;
          expect(toMinor(fromMinor(n, currency), currency), n);
          expect(toMinorText(fromMinorText(n, currency), currency), n);
        }
      }
    });
  });

  group('explicit rounding (values printed by Python money.apply_rate)', () {
    const cases = [
      (1001, '0.006'),
      (1001, '0.5'),
      (-1001, '0.5'),
      (1003, '0.5'),
      (-1003, '0.5'),
      (7, '0.33333'),
      (-7, '0.33333'),
    ];
    final expected = <RoundingMode, List<int>>{
      RoundingMode.halfUp: [6, 501, -501, 502, -502, 2, -2],
      RoundingMode.down: [6, 500, -500, 501, -501, 2, -2],
      RoundingMode.halfEven: [6, 500, -500, 502, -502, 2, -2],
      // money.py: "UP" = ROUND_CEILING（朝正无穷；负数朝零）
      RoundingMode.up: [7, 501, -500, 502, -501, 3, -2],
    };
    for (final MapEntry(key: mode, value: values) in expected.entries) {
      test(mode.code, () {
        expect([
          for (final (x, rate) in cases) applyRate(x, r(rate), mode),
        ], values);
      });
    }
  });

  group('decimalText (canonical rate text, R3E-11)', () {
    test('equals Python money.decimal_text', () {
      const vectors = {
        '0.0060000000': '0.006',
        '0E-10': '0',
        '1.0000000000': '1',
        '0.12345': '0.12345',
        '6E-3': '0.006',
        '-0.50': '-0.5',
        '1E+1': '10',
        '100': '100',
        '-0': '0',
      };
      vectors.forEach(
        (stored, text) => expect(decimalText(r(stored)), text, reason: stored),
      );
    });

    test('a non-terminating value has no decimal text', () {
      expect(() => decimalText(Rational.fromInt(1, 3)), throwsArgumentError);
    });
  });

  group('Rational', () {
    test('parse, normalise, compare', () {
      expect(r('0.50'), Rational.fromInt(1, 2));
      expect(r('-1.5e1'), Rational.fromInt(-15));
      expect(r('.5'), Rational.fromInt(1, 2));
      expect(r('3'), Rational.fromInt(6, 2));
      expect(Rational.fromInt(1, -2), Rational.fromInt(-1, 2));
      expect(Rational.fromInt(1, 3) < Rational.fromInt(1, 2), isTrue);
      expect(() => r('1,5'), throwsFormatException);
      expect(() => r('NaN'), throwsFormatException);
      expect(() => r('1e100000'), throwsFormatException);
      expect(() => Rational.fromInt(1, 0), throwsArgumentError);
    });

    test('floor, ceil, truncate and every rounding mode on halves', () {
      final x = Rational.fromInt(-5, 2); // -2.5
      expect(x.floor(), BigInt.from(-3));
      expect(x.ceil(), BigInt.from(-2));
      expect(x.truncate(), BigInt.from(-2));
      expect(x.round(RoundingMode.halfUp), BigInt.from(-3));
      expect(x.round(RoundingMode.halfEven), BigInt.from(-2));
      expect(x.round(RoundingMode.down), BigInt.from(-2));
      expect(x.round(RoundingMode.up), BigInt.from(-2));
      expect(
        Rational.fromInt(7, 2).round(RoundingMode.halfEven),
        BigInt.from(4),
      );
      expect(
        () => Rational(BigInt.two.pow(70)).roundToInt(RoundingMode.down),
        throwsRangeError,
      );
    });

    test('arithmetic is exact', () {
      final a = r('0.1');
      final b = r('0.2');
      expect(a + b, r('0.3'));
      expect((a * b).dividedBy(b), a);
      expect(r('0.33333').timesInt(3), r('0.99999'));
      expect(-(a - b), a);
    });
  });
}
