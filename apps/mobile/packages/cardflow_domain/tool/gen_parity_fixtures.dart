/// 生成随机 golden fixture，供跨语言一致性检查（protocol-parity 的第二步）：
///
/// ```text
/// dart run tool/gen_parity_fixtures.dart <输出目录> [--count N] [--seed S]
/// ```
///
/// 每个 fixture 的 `input` 是 `randomPlanInput`（Python 差分测试生成器的移植）生成的合法 v1 文档；
/// `expected` 只有 cycles 与 verify case（每份文档一个 cycles、三个随机分配的 verify），断言只检查
/// 输出的形状（cycles：每张卡一项；VerificationResult：三个成员），两个运行器都会通过。真正的比较是
/// 两个运行器 `--dump` 的输出逐字节相同：`diff -r`。
library;

import 'dart:convert';
import 'dart:io';

import 'package:cardflow_domain/testing.dart';

void main(List<String> args) {
  if (args.isEmpty || args.first.startsWith('-')) {
    stderr.writeln(
      'usage: dart run tool/gen_parity_fixtures.dart <dir> [--count N] [--seed S]',
    );
    exitCode = 2;
    return;
  }
  final out = Directory(args.first)..createSync(recursive: true);
  var count = 300;
  var seed = 20261018;
  for (var i = 1; i + 1 < args.length; i += 2) {
    switch (args[i]) {
      case '--count':
        count = int.parse(args[i + 1]);
      case '--seed':
        seed = int.parse(args[i + 1]);
      default:
        stderr.writeln('unknown option ${args[i]}');
        exitCode = 2;
        return;
    }
  }
  final rng = TestRandom(seed);
  var cases = 0;
  for (var i = 0; i < count; i++) {
    final input = randomPlanInput(rng);
    final cards = (input['cards']! as List<Object?>).length;
    final decision =
        (input['options']! as Map<String, Object?>)['decision_scenario'];
    final expected = <Object?>[
      <String, Object?>{
        'name': 'cycles',
        'kind': 'cycles',
        'assertions': <Object?>[
          <String, Object?>{'path': '', 'length': cards},
        ],
      },
      for (final (j, allocation) in randomAllocations(rng, input, 3).indexed)
        <String, Object?>{
          'name': 'verify_$j',
          'kind': 'verify',
          'allocation': protocolAllocation(allocation),
          'decision_scenario': decision,
          'assertions': <Object?>[
            <String, Object?>{'path': '', 'length': 3},
          ],
        },
    ];
    cases += expected.length;
    final fixture = <String, Object?>{
      'protocol_version': '1',
      'fixture_id': 'RANDOM-$seed-$i',
      'description': 'random parity fixture (seed $seed, #$i)',
      'input': input,
      'expected': expected,
    };
    File('${out.path}/random_${i.toString().padLeft(4, '0')}.v1.json')
        .writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(fixture)}\n',
        );
  }
  stdout.writeln(
    'wrote $count fixtures ($cases cases) to ${out.path} (seed $seed)',
  );
}
