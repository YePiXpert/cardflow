// 测试辅助 sensitive_text.dart 的自检（审查 R-03）：掩码后的日志、十进制字节列表、base64
// 都要能查出来；正常的日志与报告不能误报。
import 'dart:convert';

import 'package:cardflow/app/diagnostics/diagnostic_log.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/db/db_test_support.dart';
import 'sensitive_text.dart';

void main() {
  /// 把 [detail] 写进诊断日志后得到的报告行（数字被掩码）。
  String loggedLine(String detail) {
    final log = DiagnosticLog(clock: () => DateTime.utc(2026, 10, 18));
    addTearDown(log.dispose);
    log.error('db', 'open_failed', detail: detail);
    return log.entries.single.toReportText();
  }

  group('containsKeyMaterial', () {
    test('审查 R-03 的探针：进入诊断日志（数字已掩码）的原始密钥字面量能被发现', () {
      final line = loggedLine('PRAGMA key = "x\'$testKeyHex\'"');
      expect(line, contains("x'####################aabbccddeeff"));
      expect(containsKeyMaterial(line, testKeyHex), isTrue);
    });

    test('裸十六进制（encode() 的写法）进入日志也能发现', () {
      expect(containsKeyMaterial(loggedLine(otherKeyHex), otherKeyHex), isTrue);
      expect(
        containsKeyMaterial(
          loggedLine(testKeyHex.substring(16, 40)),
          testKeyHex,
        ),
        isTrue,
      );
    });

    test('原样、大写、部分泄露、base64、十进制字节列表', () {
      final bytes = <int>[
        for (var i = 0; i < 64; i += 2)
          int.parse(testKeyHex.substring(i, i + 2), radix: 16),
      ];
      for (final text in <String>[
        testKeyHex,
        testKeyHex.toUpperCase(),
        'key=${testKeyHex.substring(30, 38)}',
        base64Encode(bytes),
        base64Url.encode(bytes).substring(10, 20),
        bytes.toString(),
        bytes.join(','),
        'Uint8List ${bytes.sublist(8, 12).join(' ')}',
      ]) {
        expect(containsKeyMaterial(text, testKeyHex), isTrue, reason: text);
      }
    });

    test('普通日志与报告不误报（含掩码后的数字、日期与错误码）', () {
      for (final text in <String>[
        loggedLine('wrong_key'),
        loggedLine('sqlite 26 at 2026-10-18 10:00'),
        'DatabaseOpenException(wrong_key, sqlite 26)',
        '加密库状态：已启用（SQLite3 Multiple Ciphers 2.6.1，算法 chacha20）',
        'rows=500 write_ms=12 open_ms=40 count_ms=3 file_bytes=987654',
      ]) {
        expect(containsKeyMaterial(text, testKeyHex), isFalse, reason: text);
        expect(containsKeyMaterial(text, otherKeyHex), isFalse, reason: text);
      }
    });
  });

  group('金额、卡片数字、别名', () {
    test('金额：原样、千分位、掩码形态', () {
      expect(containsAmount('应还 12,345.67', 1234567, 'CNY'), isTrue);
      expect(containsAmount('amount=1234567', 1234567, 'CNY'), isTrue);
      expect(containsAmount(loggedLine('应还 12345.67'), 1234567, 'CNY'), isTrue);
      expect(
        containsAmount(loggedLine('应还 12,345.67'), 1234567, 'CNY'),
        isTrue,
      );
      expect(containsAmount(loggedLine('wrong_key'), 1234567, 'CNY'), isFalse);
      expect(containsAmount('route/changed /cards', 1234567, 'CNY'), isFalse);
    });

    test('卡片数字：完整卡号的任意 5 位窗口、日志里 5 位以上的掩码数字；只有末四位不算', () {
      const full = '6222020200112233445';
      expect(containsCardDigits('卡号 $full', full), isTrue);
      expect(containsCardDigits('…20011…', full), isTrue);
      expect(containsCardDigits(loggedLine('卡号 $full'), full), isTrue);
      expect(containsCardDigits('尾号 3445', full), isFalse);
      expect(containsCardDigits(loggedLine('尾号 3445'), full), isFalse);
    });

    test('别名：原样与含数字时的掩码形态', () {
      expect(containsUserText('别名 我的工资卡', '我的工资卡'), isTrue);
      expect(containsUserText(loggedLine('别名 工资卡2号'), '工资卡2号'), isTrue);
      expect(containsUserText(loggedLine('card/created'), '我的工资卡'), isFalse);
    });
  });
}
