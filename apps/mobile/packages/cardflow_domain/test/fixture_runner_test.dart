// Dart fixture 运行器（tests/protocol/test_runner.py 的对应）：退出码 0/1/2（2 优先）、plan case 报告
// 为未运行、断言语义（JSON Pointer、where/then、严格相等、length）、--dump 的文件名与内容。
import 'dart:convert';
import 'dart:io';

import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:cardflow_domain/fixture_runner.dart';
import 'package:cardflow_domain/testing.dart';
import 'package:test/test.dart';

import 'support/repo.dart';

typedef Doc = Map<String, Object?>;

(int, String) run(List<String> args) {
  final lines = <String>[];
  final status = runFixturesCli(args, emit: lines.add);
  return (status, lines.join('\n'));
}

late Directory tmp;

File write(Doc doc, [String name = 'case.v1.json']) {
  final file = File('${tmp.path}/$name');
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(_plain(doc))}\n',
  );
  return file;
}

/// 测试里的浮点记号写成 JSON 时保留原记号（JsonEncoder 不认识 JsonFloat）。
Object? _plain(Object? value) => switch (value) {
  JsonFloat() => _Raw(value.toString()),
  List<Object?>() => [for (final v in value) _plain(v)],
  Map<String, Object?>() => {
    for (final MapEntry(:key, :value) in value.entries) key: _plain(value),
  },
  _ => value,
};

final class _Raw {
  _Raw(this.text);
  final String text;
  // JsonEncoder 调用 toJson；返回 double，写出的仍是浮点记号（1000000.0、1.5）。测试代码允许 double，
  // 禁止 double 的扫描只针对 lib/、bin/、tool/。
  Object toJson() => double.parse(text);
}

Doc fixture() => deepCopyJson(f18Fixture())! as Doc;

void main() {
  setUp(() => tmp = Directory.systemTemp.createTempSync('cardflow_runner_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('F-18 passes with exit 0; plan cases are reported as not run', () {
    final (status, out) = run([f18File().path]);
    expect(status, fixturesPassed, reason: out);
    expect(out, contains('input_hash $f18InputHash'));
    expect(
      out,
      contains(
        'result: PASS (14/14 assertions hold; 3 plan case(s) not run: need CP-SAT)',
      ),
    );
    expect(
      out,
      contains(
        'case cash_safety_optimum [plan cash_safety / baseline]: NOT RUN (needs CP-SAT',
      ),
    );
    expect(out, isNot(contains('FAIL')));
    expect(
      out.trimRight(),
      endsWith('1 passed, 0 failed, 0 invalid -> exit 0'),
    );
  });

  test('the default target is every v1 fixture of the repository', () {
    final (status, out) = run([]);
    expect(status, fixturesPassed, reason: out);
    expect(out, contains('regression_2026-10-16_10000.v1.json'));
  });

  test('a tampered expected value fails with exit 1', () {
    final doc = fixture();
    final verify = obj(arr(doc['expected'])[1]);
    obj(arr(verify['assertions'])[1])['equals'] = '42.5';
    final (status, out) = run([write(doc).path]);
    expect(status, fixturesMismatch, reason: out);
    expect(
      out,
      contains(
        '     FAIL /verification/weighted_buffer_days == "42.5"; found "42.4"'
        '  <- plan_A8000_C2000.weighted_buffer_days',
      ),
    );
    expect(out, contains('result: FAIL (13/14 assertions hold'));
  });

  final invalid = <(String, void Function(Doc), String)>[
    (
      'float-amount',
      (d) => obj(obj(d['input'])['request'])['amount_minor'] = parseJsonText(
        '1000000.0',
      ),
      'JSON floats',
    ),
    (
      'duplicate-card',
      (d) => obj(arr(obj(d['input'])['cards'])[1])['card_id'] = 'A',
      'duplicate card_id',
    ),
    (
      'bad-case-kind',
      (d) => obj(arr(d['expected'])[0])['kind'] = 'other',
      'fixture format',
    ),
    (
      'unknown-verify-scenario',
      (d) => obj(arr(d['expected'])[1])['decision_scenario'] = 'nope',
      'unknown scenario',
    ),
    (
      'float-in-expected',
      (d) => obj(arr(obj(arr(d['expected'])[0])['assertions'])[0])['equals'] =
          parseJsonText('1.5'),
      'JSON floats',
    ),
    ('unknown-member', (d) => d['extra'] = 1, 'fixture format'),
    (
      'both-equals-and-length',
      (d) =>
          obj(arr(obj(arr(d['expected'])[0])['assertions'])[0])['length'] = 1,
      'fixture format',
    ),
    (
      'then-without-where',
      (d) =>
          obj(arr(obj(arr(d['expected'])[0])['assertions'])[0])['then'] = '/x',
      'fixture format',
    ),
  ];
  for (final (name, mutate, message) in invalid) {
    test('invalid input exits 2 ($name)', () {
      final doc = fixture();
      mutate(doc);
      final (status, out) = run([write(doc).path]);
      expect(status, fixturesInvalid, reason: out);
      expect(out, contains(message));
    });
  }

  test('invalid JSON exits 2 and 2 wins over 0', () {
    final broken = File('${tmp.path}/broken.v1.json')
      ..writeAsStringSync('{"protocol_version": "1", "protocol_version": "1"}');
    final (status, out) = run([broken.path, f18File().path]);
    expect(status, fixturesInvalid, reason: out);
    expect(out, contains('INVALID: not strict JSON'));
  });

  test('unknown options print the usage and exit 2', () {
    final (status, out) = run(['--frobnicate']);
    expect(status, fixturesInvalid);
    expect(out, contains('usage: dart run cardflow_domain:run_fixtures'));
    expect(run(['--dump']).$1, fixturesInvalid);
  });

  test('--dump writes every cycles/verify output as canonical JSON, named like the Python runner', () {
    final dump = Directory('${tmp.path}/dump');
    final (status, out) = run(['--dump', dump.path, f18File().path]);
    expect(status, fixturesPassed, reason: out);
    final dir = Directory('${dump.path}/regression_2026-10-16_10000');
    final names = [for (final f in dir.listSync()) f.uri.pathSegments.last]
      ..sort();
    expect(names, [
      '00-cycles.cycles.json',
      '01-plan_A8000_C2000.verify.json',
      '02-plan_B10000.verify.json',
    ]);
    final parsed = f18();
    final cycles = File('${dir.path}/00-cycles.cycles.json').readAsBytesSync();
    expect(cycles, [
      ...canonicalJson(cardCyclesToProtocol(parsed.inputs)),
      0x0A,
    ]);
    final verify = File('${dir.path}/01-plan_A8000_C2000.verify.json')
        .readAsBytesSync();
    expect(verify, [
      ...canonicalJson(
        verifyFromProtocol(
          f18Input(),
          protocolAllocation({'A': 800000, 'C': 200000}),
          'baseline',
        ),
      ),
      0x0A,
    ]);
    expect(fixtureStem('x/regression.v1.json'), 'regression');
    expect(dumpFileName(3, 'case', 'verify'), '03-case.verify.json');
  });

  group('assertion semantics (test_runner.py)', () {
    final output = <String, Object?>{
      'allocation': <Object?>[
        <String, Object?>{'card_id': 'A', 'amount_minor': 5},
        <String, Object?>{'card_id': 'C', 'amount_minor': 7},
      ],
      'flags': <String, Object?>{'ok': true, 'n': 1},
      'a/b': <String, Object?>{'~x': 3},
    };
    final cases = <(Doc, bool)>[
      ({'path': '/flags/ok', 'equals': true}, true),
      ({'path': '/flags/ok', 'equals': 1}, false), // 布尔不是数字
      ({'path': '/flags/n', 'equals': true}, false),
      ({'path': '/flags/n', 'equals': parseJsonText('1.0')}, false), // 整数不是浮点
      ({'path': '/a~1b/~0x', 'equals': 3}, true), // RFC 6901 转义
      ({'path': '/allocation/1/card_id', 'equals': 'C'}, true),
      ({'path': '/allocation/01/card_id', 'equals': 'C'}, false), // 下标无前导零
      ({'path': '/allocation/2', 'equals': null}, false), // 不存在不是 null
      ({'path': '/allocation', 'length': 2}, true),
      ({'path': '/flags', 'length': 2}, true),
      (
        {
          'path': '/allocation',
          'where': {'card_id': 'C'},
          'then': '/amount_minor',
          'equals': 7,
        },
        true,
      ),
      (
        {
          'path': '/allocation',
          'where': {'card_id': 'Z'},
          'equals': <String, Object?>{},
        },
        false,
      ),
      (
        {
          'path': '/allocation',
          'where': {'amount_minor': 5},
          'equals': arr(output['allocation'])[0],
        },
        true,
      ),
      (
        {
          'path': '/flags',
          'where': {'ok': true},
          'equals': <String, Object?>{},
        },
        false,
      ), // 不是数组
    ];
    for (final (i, (assertion, holds)) in cases.indexed) {
      test('#$i ${FixtureAssertion.parse(assertion).describe()}', () {
        expect(FixtureAssertion.parse(assertion).check(output).$1, holds);
      });
    }

    test('where must select exactly one element', () {
      final rows = <String, Object?>{
        'rows': <Object?>[
          <String, Object?>{'k': 1},
          <String, Object?>{'k': 1},
        ],
      };
      final a = FixtureAssertion.parse({
        'path': '/rows',
        'where': {'k': 1},
        'equals': {'k': 1},
      });
      expect(a.check(rows), (false, '2 elements match'));
    });
  });
}
