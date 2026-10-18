// 禁止二进制浮点的可执行检查（简报 I-0c §1；ADR-008；architecture §3）：扫描领域包 lib/、bin/、tool/
// 的 Dart 源码，去掉注释与字符串内容（字符串内插 `${...}` 仍算代码）后，出现以下任一即失败：
//   * `double` 类型、`num` 类型；
//   * `toDouble()` 以及 `roundToDouble()` 等 `*ToDouble` 调用；
//   * 小数或指数形式的数字字面量（`1.5`、`.5`、`1e3`）；
//   * 浮点除法 `/`（整数除法用 `~/`）。
// 注释（含文档注释）与字符串内容里出现这些写法是允许的。先用一组正反例自检扫描器本身。
import 'dart:io';

import 'package:test/test.dart';

/// 去掉注释与字符串内容，保留代码（含字符串内插中的表达式）与换行。
String codeOnly(String source) {
  final out = StringBuffer();
  final stack = <_Context>[_Code()];
  var i = 0;
  bool isIdent(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x5F ||
      c == 0x24;
  while (i < source.length) {
    final context = stack.last;
    final c = source.codeUnitAt(i);
    if (context is _Code) {
      if (source.startsWith('//', i)) {
        while (i < source.length && source.codeUnitAt(i) != 0x0A) {
          i++;
        }
        continue;
      }
      if (source.startsWith('/*', i)) {
        var depth = 0;
        while (i < source.length) {
          if (source.startsWith('/*', i)) {
            depth++;
            i += 2;
          } else if (source.startsWith('*/', i)) {
            depth--;
            i += 2;
            if (depth == 0) {
              break;
            }
          } else {
            if (source.codeUnitAt(i) == 0x0A) {
              out.write('\n');
            }
            i++;
          }
        }
        out.write(' ');
        continue;
      }
      var raw = false;
      var j = i;
      if ((c == 0x72 || c == 0x52) &&
          i + 1 < source.length &&
          (source[i + 1] == '"' || source[i + 1] == "'") &&
          (i == 0 || !isIdent(source.codeUnitAt(i - 1)))) {
        raw = true;
        j = i + 1;
      }
      final q = source[j];
      if (q == '"' || q == "'") {
        final triple = source.startsWith(q * 3, j);
        stack.add(_String(q, triple, raw));
        out.write(' ');
        i = j + (triple ? 3 : 1);
        continue;
      }
      if (c == 0x7B) {
        context.depth++;
      } else if (c == 0x7D) {
        if (context.depth == 0 && stack.length > 1) {
          stack.removeLast(); // 字符串内插结束，回到字符串
          out.write(' ');
          i++;
          continue;
        }
        context.depth--;
      }
      out.writeCharCode(c);
      i++;
      continue;
    }
    final s = context as _String;
    if (!s.raw && c == 0x5C) {
      out.write('  ');
      i += 2;
      continue;
    }
    if (s.triple ? source.startsWith(s.quote * 3, i) : source[i] == s.quote) {
      stack.removeLast();
      out.write(' ');
      i += s.triple ? 3 : 1;
      continue;
    }
    if (!s.raw && c == 0x24) {
      if (source.startsWith(r'${', i)) {
        stack.add(_Code());
        out.write(' ');
        i += 2;
        continue;
      }
      var j = i + 1;
      while (j < source.length &&
          isIdent(source.codeUnitAt(j)) &&
          source.codeUnitAt(j) != 0x24) {
        j++;
      }
      out
        ..write(' ')
        ..write(source.substring(i + 1, j));
      i = j;
      continue;
    }
    out.write(c == 0x0A ? '\n' : ' ');
    i++;
  }
  return out.toString();
}

sealed class _Context {}

final class _Code extends _Context {
  int depth = 0;
}

final class _String extends _Context {
  _String(this.quote, this.triple, this.raw);
  final String quote;
  final bool triple;
  final bool raw;
}

final List<(String, RegExp)> rules = [
  ('double type', RegExp(r'\bdouble\b')),
  ('num type', RegExp(r'\bnum\b')),
  ('toDouble call', RegExp(r'[tT]oDouble\b')),
  ('decimal literal', RegExp(r'(?<![\w$.])\d+\.\d+')),
  ('exponent literal', RegExp(r'(?<![\w$.])\d+(?:\.\d+)?[eE][+-]?\d+')),
  ('leading-dot literal', RegExp(r'(?<![\w$)\].])\.\d')),
  ('floating division', RegExp(r'(?<!~)/')),
];

/// 违规列表：（行号, 规则, 该行代码）。
List<(int, String, String)> findings(String source) {
  final lines = codeOnly(source).split('\n');
  return [
    for (final (index, line) in lines.indexed)
      for (final (name, pattern) in rules)
        if (pattern.hasMatch(line)) (index + 1, name, line.trim()),
  ];
}

void main() {
  group('the scanner flags floating point in code', () {
    const bad = <String, String>{
      'double type': 'double x = 1;',
      'num type': 'num y = 2;',
      'toDouble': 'final z = a.toDouble();',
      'roundToDouble': 'final r = a.roundToDouble();',
      'decimal literal': 'const k = 1.5;',
      'exponent literal': 'const e = 1e3;',
      'leading-dot literal': 'const f = .5;',
      'division': 'final q = a / b;',
      'division-assignment': 'a /= 2;',
      'division in an interpolation': r"final s = 'v=${a / b}';",
      'double in an interpolation': r'final s = "x ${double.parse(t)} y";',
      'decimal after a raw string': r"final p = RegExp(r'\d'); const g = 2.5;",
    };
    bad.forEach((name, code) {
      test(
        name,
        () => expect(findings(code), isNotEmpty, reason: codeOnly(code)),
      );
    });
  });

  group('the scanner allows comments, strings and integer arithmetic', () {
    const good = <String, String>{
      'line comment': '// double 1.5 a / b num',
      'doc comment': '/// 0.1 double toDouble() 1e9',
      'nested block comment': '/* nested /* 1.5 */ double */ final x = 1;',
      'string': "final s = '1.5 double a / b num';",
      'raw string regex': r"final p = RegExp(r'^\d+\.\d+$');",
      'triple-quoted string': "final t = '''\n2.5 / 3\n''';",
      'integer division': 'final q = a ~/ b;',
      'interpolated identifiers': r"final s = '$value/$other';",
      'interpolated integer division': r"final s = '${a ~/ b}.${a % b}';",
      'record field': r'final f = pair.$1 + pair.$2;',
      'hex literal': 'const h = 0x1E5;',
      'shift': 'final big = 1 << 53;',
      'version in a string': "const v = '1.1.0';",
      'Chinese text in a string': "final m = '按快照日计入，金额 1,234.56';",
    };
    good.forEach((name, code) {
      test(name, () => expect(findings(code), isEmpty, reason: codeOnly(code)));
    });
  });

  test('lib/, bin/ and tool/ contain no double, num, toDouble, decimal literal or `/` division', () {
    final files = [
      for (final dir in ['lib', 'bin', 'tool'])
        if (Directory(dir).existsSync())
          ...Directory(dir)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')),
    ]..sort((a, b) => a.path.compareTo(b.path));
    expect(files.length, greaterThan(20));
    final violations = <String>[];
    var lines = 0;
    for (final file in files) {
      final source = file.readAsStringSync();
      lines += '\n'.allMatches(source).length;
      for (final (line, rule, code) in findings(source)) {
        violations.add('${file.path}:$line: $rule: $code');
      }
    }
    // 证据：扫描范围（no-double-scan.txt）
    printOnFailure(violations.join('\n'));
    // ignore: avoid_print
    print(
      'no-double scan: ${files.length} files, $lines lines in lib/, bin/, tool/; '
      '${violations.length} violation(s)',
    );
    expect(violations, isEmpty);
  });
}
