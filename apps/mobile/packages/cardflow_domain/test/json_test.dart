// 严格 JSON 读取（tests/protocol/test_adapter.py 的 test_parse_json_is_strict、
// test_parse_json_keeps_integers_exact；test_review_wave3_protocol.py 的 R3E-12 不回显）与
// 运行器的严格相等语义。
import 'dart:convert';

import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:test/test.dart';

Matcher throwsProtocolError([Object? messageMatcher]) => throwsA(
  isA<ProtocolError>().having(
    (e) => e.message,
    'message',
    messageMatcher ?? anything,
  ),
);

void main() {
  group('parseJson is strict', () {
    final cases = <String, List<int>>{
      'duplicate key': utf8.encode('{"a": 1, "a": 2}'),
      'NaN': utf8.encode('{"a": NaN}'),
      'Infinity': utf8.encode('{"a": Infinity}'),
      '-Infinity': utf8.encode('{"a": -Infinity}'),
      'overflow 1e400': utf8.encode('{"a": 1e400}'),
      'overflow 1e309': utf8.encode('[1e309]'),
      'BOM': [0xEF, 0xBB, 0xBF, ...utf8.encode('{"a": 1}')],
      'not UTF-8': [...utf8.encode('{"a": "'), 0xFF, ...utf8.encode('"}')],
      'EOF': utf8.encode('{"a": 1'),
      'integer literal too long': utf8.encode('{"a": ${'9' * 5000}}'),
      'nested too deeply': utf8.encode('${'[' * 100000}${']' * 100000}'),
      'trailing comma': utf8.encode('[1,]'),
      'leading zero': utf8.encode('[01]'),
      'bare fraction': utf8.encode('[.5]'),
      'control character in a string': utf8.encode('["a\tb"]'),
      'bad escape': utf8.encode(r'["\x"]'),
      'extra data': utf8.encode('{} {}'),
      'single quotes': utf8.encode("{'a': 1}"),
    };
    cases.forEach((name, bytes) {
      test(name, () => expect(() => parseJson(bytes), throwsProtocolError()));
    });
  });

  test('integers stay exact; integer and float tokens are distinct', () {
    final doc =
        parseJson(
              utf8.encode(
                '{"a": 9223372036854775807, "b": -1, "c": 9223372036854775808, '
                '"d": 1.0, "e": 1e2, "f": -0}',
              ),
            )!
            as Map<String, Object?>;
    expect(doc['a'], 9223372036854775807);
    expect(doc['b'], -1);
    expect(doc['c'], BigInt.parse('9223372036854775808'));
    expect(doc['d'], isA<JsonFloat>());
    expect(doc['e'], isA<JsonFloat>());
    expect(doc['f'], 0);
    expect(jsonKind(doc['d']), 'a float');
    expect(jsonKind(doc['c']), 'an integer');
    expect(jsonKind(true), 'a boolean');
  });

  test('escapes and surrogate pairs decode like Python json', () {
    final text =
        parseJson(utf8.encode(r'["\"\\\/\b\f\n\r\t\u00e9\ud83d\ude00\ud800"]'))!
            as List<Object?>;
    expect(text.single, '"\\/\b\f\n\r\t\u00e9\ud83d\ude00\ud800');
  });

  group('errors never echo the offending content (R3E-12)', () {
    final cases = <String, (List<int>, String)>{
      'duplicate-key': (
        utf8.encode('{"6222021234567890": 1, "6222021234567890": 2}'),
        '6222021234567890',
      ),
      'not-utf8': (
        [...utf8.encode('{"a": "'), 0xFF, 0xFE, ...utf8.encode('9876"}')],
        '9876',
      ),
      'overflow': (utf8.encode('{"a": 1e999999}'), '999999'),
    };
    cases.forEach((name, value) {
      final (bytes, secret) = value;
      test(name, () {
        try {
          parseJson(bytes);
          fail('expected a ProtocolError');
        } on ProtocolError catch (e) {
          expect('$e', isNot(contains(secret)));
        }
      });
    });
  });

  group('jsonEquals is strict (runner assertion semantics)', () {
    test('booleans are not numbers, integers are not floats', () {
      expect(jsonEquals(true, true), isTrue);
      expect(jsonEquals(true, 1), isFalse);
      expect(jsonEquals(1, parseJsonText('1.0')), isFalse);
      expect(jsonEquals(1, BigInt.one), isTrue);
      expect(jsonEquals(parseJsonText('0.0'), parseJsonText('-0.0')), isTrue);
      expect(jsonEquals(null, <String, Object?>{}), isFalse);
      expect(
        jsonEquals(
          <String, Object?>{
            'a': <Object?>[1, 'x'],
          },
          <String, Object?>{
            'a': <Object?>[1, 'x'],
          },
        ),
        isTrue,
      );
      expect(
        jsonEquals(
          <String, Object?>{'a': 1},
          <String, Object?>{'a': 1, 'b': 2},
        ),
        isFalse,
      );
    });
  });
}
