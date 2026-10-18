import 'dart:io';

import 'package:cardflow/app/money/money_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// 服务端引擎的金额模块（相对 apps/mobile）。
const String serverMoneyPy =
    '../../services/api/cardflow/planner/engine/money.py';

/// 从 money.py 中解析 `MINOR_DIGITS: dict[str, int] = { ... }`。
Map<String, int> parseServerMinorDigits(String source) {
  final block = RegExp(r'MINOR_DIGITS[^=]*=\s*\{([^}]*)\}').firstMatch(source);
  if (block == null) {
    throw StateError('money.py 中找不到 MINOR_DIGITS');
  }
  return <String, int>{
    for (final m in RegExp(
      r'"([A-Z]{3})"\s*:\s*(\d+)',
    ).allMatches(block.group(1)!))
      m.group(1)!: int.parse(m.group(2)!),
  };
}

void main() {
  group('minorDigits 表', () {
    test('与服务端引擎 money.py 的 MINOR_DIGITS 完全一致', () {
      final file = File(serverMoneyPy);
      expect(file.existsSync(), isTrue, reason: '找不到 $serverMoneyPy');
      final server = parseServerMinorDigits(file.readAsStringSync());
      expect(server, hasLength(13));
      expect(minorDigits, equals(server));
    });

    test('覆盖 0、2、3 三种位数', () {
      expect(minorDigitsOf('CNY'), 2);
      expect(minorDigitsOf('JPY'), 0);
      expect(minorDigitsOf('KRW'), 0);
      expect(minorDigitsOf('VND'), 0);
      expect(minorDigitsOf('KWD'), 3);
      expect(minorDigitsOf('BHD'), 3);
      expect(minorDigitsOf('JOD'), 3);
    });

    test('未登记的币种直接报错，不猜小数位', () {
      expect(() => minorDigitsOf('XYZ'), throwsArgumentError);
      expect(() => formatMinorAbs(100, 'cny'), throwsArgumentError);
      expect(
        () => describeMoney(minor: 100, currency: 'BTC'),
        throwsArgumentError,
      );
    });

    test('每个币种都有读屏名称', () {
      expect(currencySpokenNames.keys.toSet(), minorDigits.keys.toSet());
    });
  });

  group('formatMinorAbs', () {
    test('2 位小数（CNY）', () {
      expect(formatMinorAbs(0, 'CNY'), '0.00');
      expect(formatMinorAbs(5, 'CNY'), '0.05');
      expect(formatMinorAbs(99, 'CNY'), '0.99');
      expect(formatMinorAbs(100, 'CNY'), '1.00');
      expect(formatMinorAbs(123456, 'CNY'), '1,234.56');
      expect(formatMinorAbs(100000000, 'CNY'), '1,000,000.00');
      expect(formatMinorAbs(-123456, 'CNY'), '1,234.56');
    });

    test('0 位小数（JPY、KRW、VND）', () {
      expect(formatMinorAbs(0, 'JPY'), '0');
      expect(formatMinorAbs(999, 'JPY'), '999');
      expect(formatMinorAbs(1235, 'JPY'), '1,235');
      expect(formatMinorAbs(1000000, 'KRW'), '1,000,000');
      expect(formatMinorAbs(-25000, 'VND'), '25,000');
    });

    test('3 位小数（KWD、BHD、JOD）', () {
      expect(formatMinorAbs(5, 'KWD'), '0.005');
      expect(formatMinorAbs(1235, 'KWD'), '1.235');
      expect(formatMinorAbs(1234567, 'BHD'), '1,234.567');
      expect(formatMinorAbs(-1000, 'JOD'), '1.000');
    });

    test('64 位整数的边界不溢出', () {
      expect(
        formatMinorAbs(9223372036854775807, 'CNY'),
        '92,233,720,368,547,758.07',
      );
      expect(
        formatMinorAbs(-9223372036854775807 - 1, 'CNY'),
        '92,233,720,368,547,758.08',
      );
    });
  });

  group('describeMoney', () {
    test('CNY 用 ¥，其他币种用 ISO 代码', () {
      expect(describeMoney(minor: 123456, currency: 'CNY').text, '¥1,234.56');
      expect(
        describeMoney(minor: 123456, currency: 'USD').text,
        'USD 1,234.56',
      );
      expect(describeMoney(minor: 1235, currency: 'JPY').text, 'JPY 1,235');
      expect(describeMoney(minor: 1235, currency: 'KWD').text, 'KWD 1.235');
    });

    test('零是真实的 0，不是空白', () {
      final zero = describeMoney(minor: 0, currency: 'CNY');
      expect(zero.text, '¥0.00');
      expect(zero.isNegative, isFalse);
    });

    test('没有金额时显示"—"，不显示 0', () {
      final none = describeMoney(minor: null, currency: 'CNY');
      expect(none.text, '—');
      expect(none.semanticsLabel, '暂无金额');
    });

    test('负数用"−"（U+2212）加语义词，读屏读语义词而不是负号', () {
      final gap = describeMoney(
        minor: -200000,
        currency: 'CNY',
        negativeLabel: '缺口',
      );
      expect(gap.text, '缺口 −¥2,000.00');
      expect(gap.text, isNot(contains('-')));
      expect(gap.isNegative, isTrue);
      expect(gap.semanticsLabel, '缺口 人民币 2,000.00 元');

      final credit = describeMoney(
        minor: -1235,
        currency: 'KWD',
        negativeLabel: '贷方余额',
      );
      expect(credit.text, '贷方余额 −KWD 1.235');
      expect(credit.semanticsLabel, '贷方余额 科威特第纳尔 1.235');
    });

    test('负数漏传语义词在 debug 下断言失败', () {
      expect(
        () => describeMoney(minor: -1, currency: 'CNY'),
        throwsA(isA<AssertionError>()),
      );
    });

    test('读屏带前缀：本期应还 人民币 8,000.00 元', () {
      final due = describeMoney(
        minor: 800000,
        currency: 'CNY',
        semanticsPrefix: '本期应还',
      );
      expect(due.semanticsLabel, '本期应还 人民币 8,000.00 元');
      expect(
        describeMoney(minor: 1250, currency: 'USD').semanticsLabel,
        '美元 12.50',
      );
    });

    test('金额隐藏：固定 4 个"•"，不随位数变化，不泄露数字', () {
      for (final minor in <int>[0, 7, 123456, 9223372036854775807]) {
        final hidden = describeMoney(
          minor: minor,
          currency: 'CNY',
          hidden: true,
        );
        expect(hidden.text, '••••');
        expect(hidden.semanticsLabel, '金额已隐藏');
        expect(RegExp(r'\d').hasMatch(hidden.text), isFalse);
      }
    });

    test('金额隐藏时负数仍保留语义词', () {
      final hidden = describeMoney(
        minor: -200000,
        currency: 'CNY',
        hidden: true,
        negativeLabel: '缺口',
        semanticsPrefix: '最低点',
      );
      expect(hidden.text, '缺口 ••••');
      expect(hidden.semanticsLabel, '最低点 缺口 金额已隐藏');
      expect(hidden.isNegative, isTrue);
    });
  });
}
