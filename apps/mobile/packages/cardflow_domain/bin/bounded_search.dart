/// 本地有限搜索的命令行入口（调试与验收证据用）：
///
/// ```text
/// dart run cardflow_domain:bounded_search [选项] FILE_OR_DIRECTORY ...
///   --max-cards K     用卡数上限 1–3（默认 3；实际取它与请求的 K 中较小者）
///   --budget-ms N     时间预算（毫秒，默认 2000）
///   --decision ID     决策情景（默认取文档 options）
///   --profile P       画像（默认取文档 options）
///   --json            每个文件输出一行 JSON（结果的 toJson()，另加 file 与 input_hash）
/// ```
///
/// 文件可以是 PlanInput 文档，也可以是 golden fixture（取其 `input`）；目录取其中的 `*.json`。
/// 退出码：0 正常（不论是否找到），2 输入非法。
library;

import 'dart:convert';
import 'dart:io';

import 'package:cardflow_domain/cardflow_domain.dart';

void main(List<String> args) {
  var maxCards = 3;
  var budgetMs = 2000;
  String? decision;
  String? profile;
  var asJson = false;
  final targets = <String>[];
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--max-cards':
        maxCards = int.parse(args[++i]);
      case '--budget-ms':
        budgetMs = int.parse(args[++i]);
      case '--decision':
        decision = args[++i];
      case '--profile':
        profile = args[++i];
      case '--json':
        asJson = true;
      default:
        if (args[i].startsWith('-')) {
          stderr.writeln('unknown option ${args[i]}');
          exitCode = 2;
          return;
        }
        targets.add(args[i]);
    }
  }
  final files = <File>[];
  for (final t in targets) {
    final dir = Directory(t);
    if (dir.existsSync()) {
      files.addAll(
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path)),
      );
    } else {
      files.add(File(t));
    }
  }
  if (files.isEmpty) {
    stderr.writeln(
      'usage: dart run cardflow_domain:bounded_search [options] FILE_OR_DIRECTORY ...',
    );
    exitCode = 2;
    return;
  }
  final options = BoundedSearchOptions(
    maxCards: maxCards,
    budget: Duration(milliseconds: budgetMs),
  );
  for (final file in files) {
    final Object? input;
    final BoundedSearchResult result;
    try {
      final document = parseJson(file.readAsBytesSync());
      input =
          document is Map<String, Object?> && document.containsKey('expected')
          ? document['input']
          : document;
      result = boundedSearchFromProtocol(
        input,
        decisionScenario: decision,
        profile: profile,
        options: options,
      );
    } on ProtocolError catch (e) {
      stderr.writeln('${file.path}: INVALID: $e');
      exitCode = 2;
      return;
    }
    if (asJson) {
      stdout.writeln(
        jsonEncode(
          _plain(<String, Object?>{
            'file': file.path,
            'input_hash': protocolInputHash(input),
            ...result.toJson(),
          }),
        ),
      );
      continue;
    }
    final ms = (result.elapsedMicros + 500) ~/ 1000;
    stdout
      ..writeln('== ${file.path}')
      ..writeln('   input_hash ${protocolInputHash(input)}')
      ..writeln(
        '   decision ${result.decisionScenario}, profile ${result.profile}, '
        'K <= ${result.maxCards}, budget ${budgetMs}ms',
      )
      ..writeln(
        '   outcome ${result.outcome.name}: ${result.message} (proven: ${result.proven})',
      );
    if (result.allocation.isNotEmpty) {
      final parts = result.allocation.entries
          .map((e) => '${e.key}=${e.value}')
          .join(', ');
      final v = result.verification!;
      stdout
        ..writeln('   allocation $parts')
        ..writeln(
          '   verification ok ${v.ok}; weighted buffer ${v.weightedBufferDays} days; '
          'fees ${v.fees}; failing scenarios ${result.failingScenarios.isEmpty ? '-' : result.failingScenarios.join(',')}',
        )
        ..writeln('   objectives ${result.objectives}');
      for (final line in v.lines) {
        stdout.writeln(
          '     ${line.card}: ${line.amount} statement ${line.statementDate} due ${line.dueDate} '
          'repay ${line.repayOn} from ${line.repayFrom} (buffer ${line.bufferDays} days, fee ${line.fee})',
        );
      }
    }
    for (final issue in result.dataIssues) {
      stdout.writeln('   data issue ${issue.code}');
    }
    for (final MapEntry(key: cardId, value: e) in result.exclusions.entries) {
      stdout.writeln(
        '   excluded $cardId: ${e.code}${e.detail == null ? '' : ' (${e.detail})'}',
      );
    }
    stdout.writeln(
      '   candidates ${result.candidates}, verifier calls ${result.verifierCalls}, '
      'exhausted ${result.exhausted}, timed out ${result.timedOut}, elapsed ${ms}ms',
    );
  }
}

Object? _plain(Object? value) => switch (value) {
  JsonFloat() || BigInt() => value.toString(),
  List<Object?>() => [for (final v in value) _plain(v)],
  Map<String, Object?>() => {
    for (final MapEntry(:key, :value) in value.entries) key: _plain(value),
  },
  _ => value,
};
