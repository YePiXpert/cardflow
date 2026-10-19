// 公测版（0.1.0 beta 1）的界面约束（简报 I1-c2 §2）。
//
// 阶段代号防回归：用户可见的文字里不出现内部阶段代号（"I-3 提供""I-2 使用"一类，正则 `I-\d`），
// 未开放的功能一律写"后续版本提供"一类说法。两道检查：
// 1. 扫描 lib/ 下全部 Dart 源码的字符串字面量（去掉注释；内插表达式里的字符串也算），先用正反例自检扫描器；
// 2. 逐页打开 App（演示空间的全部页面、真实空间的首次空白页、没有工作空间时的 P-22），每页从顶滚到底，
//    检查渲染出来的全部文字（RichText 与输入框内容）。
import 'dart:io';

import 'package:cardflow/app/routes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/forbidden_ui.dart';
import '../test_helpers.dart';
import 'accessibility_test.dart' show allPages;

/// 内部阶段代号（I-0 … I-9 及其后缀，如 I-1c）。
final RegExp stageCode = RegExp(r'I-\d');

/// Dart 源码里字符串字面量的内容（注释里的不算）：（起始行号, 内容）。内插 `${…}`、`$name` 在内容里记为
/// `…`；内插表达式里的字符串字面量另记一条。支持单/双引号、三引号、原始字符串与嵌套的块注释。
List<(int, String)> stringLiterals(String source) {
  final found = <(int, String)>[];
  final stack = <_Context>[_Code()];
  var i = 0;
  var line = 1;
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
              line++;
            }
            i++;
          }
        }
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
        stack.add(_String(q, triple, raw, line));
        i = j + (triple ? 3 : 1);
        continue;
      }
      if (c == 0x7B) {
        context.depth++;
      } else if (c == 0x7D) {
        if (context.depth == 0 && stack.length > 1) {
          stack.removeLast(); // 内插结束，回到字符串
          i++;
          continue;
        }
        context.depth--;
      } else if (c == 0x0A) {
        line++;
      }
      i++;
      continue;
    }
    final s = context as _String;
    if (!s.raw && c == 0x5C && i + 1 < source.length) {
      s.text.write(source.substring(i, i + 2));
      if (source.codeUnitAt(i + 1) == 0x0A) {
        line++;
      }
      i += 2;
      continue;
    }
    if (s.triple ? source.startsWith(s.quote * 3, i) : source[i] == s.quote) {
      found.add((s.line, s.text.toString()));
      stack.removeLast();
      i += s.triple ? 3 : 1;
      continue;
    }
    if (!s.raw && c == 0x24) {
      s.text.write('…');
      if (source.startsWith(r'${', i)) {
        stack.add(_Code());
        i += 2;
        continue;
      }
      var j = i + 1;
      while (j < source.length &&
          isIdent(source.codeUnitAt(j)) &&
          source.codeUnitAt(j) != 0x24) {
        j++;
      }
      i = j;
      continue;
    }
    if (c == 0x0A) {
      line++;
    }
    s.text.writeCharCode(c);
    i++;
  }
  return found;
}

sealed class _Context {}

final class _Code extends _Context {
  int depth = 0;
}

final class _String extends _Context {
  _String(this.quote, this.triple, this.raw, this.line);
  final String quote;
  final bool triple;
  final bool raw;
  final int line;
  final StringBuffer text = StringBuffer();
}

/// 含阶段代号的字面量：（行号, 内容）。
List<(int, String)> stageCodeLiterals(String source) => <(int, String)>[
  for (final literal in stringLiterals(source))
    if (stageCode.hasMatch(literal.$2)) literal,
];

/// 渲染出来的文字里含阶段代号的。
List<String> stageCodeTexts(WidgetTester tester) => <String>[
  for (final text in visibleTexts(tester))
    if (stageCode.hasMatch(text)) text,
];

Future<void> _expectNoStageCodeOnPages(
  WidgetTester tester,
  Iterable<String> pages,
) async {
  for (final page in pages) {
    await goTo(tester, page);
    await forEachScreen(tester, () {
      expect(stageCodeTexts(tester), isEmpty, reason: page);
    });
  }
}

void main() {
  group('阶段代号防回归：扫描器自检', () {
    const flagged = <String, String>{
      '单引号': "const a = '从备份恢复：I-4 提供';",
      '双引号': 'const b = "额度变化（I-2 使用）";',
      '三引号跨行': "const c = '''\n导入在\nI-3 提供\n''';",
      '原始字符串': "const d = r'I-1c';",
      '内插里的字符串': r"final e = '额度 ${n > 0 ? 'I-2 使用' : ''} 项';",
      '内插之后的文字': r"final f = '${label}：I-3 提供';",
      '紧跟在注释后的字符串': "// 说明\nconst g = 'I-4';",
    };
    flagged.forEach((name, code) {
      test(name, () => expect(stageCodeLiterals(code), isNotEmpty));
    });

    const clean = <String, String>{
      '行注释': "// I-3 提供 'I-4'",
      '文档注释': '/// 给 I-1c 的接口',
      '嵌套块注释': "/* I-2 /* 'I-3' */ I-4 */ const x = '后续版本提供';",
      '注释在代码行尾': "const y = '后续版本提供'; // I-3",
      '内插的变量名': r"final z = '${stage}：$label';",
      '原始字符串里的正则': r"final p = RegExp(r'I-\d');",
    };
    clean.forEach((name, code) {
      test(name, () => expect(stageCodeLiterals(code), isEmpty, reason: code));
    });

    test('行号与内容', () {
      const code = "// 第一行\nconst a = '甲';\nconst b = \"乙\${'丙'}丁\";\n";
      expect(stringLiterals(code), <(int, String)>[
        (2, '甲'),
        (3, '丙'),
        (3, '乙…丁'),
      ]);
    });
  });

  test('lib/ 全部 Dart 源码的字符串字面量（注释除外）都不含阶段代号 I-数字', () {
    final files =
        Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(files.length, greaterThan(100), reason: '应在 apps/mobile 下运行');
    final hits = <String>[
      for (final file in files)
        for (final (line, text) in stageCodeLiterals(file.readAsStringSync()))
          '${file.path}:$line  $text',
    ];
    expect(hits, isEmpty, reason: hits.join('\n'));
    // ignore: avoid_print
    print('扫描了 ${files.length} 个文件，含阶段代号的字符串字面量：${hits.length} 处');
  });

  testWidgets('演示空间的全部页面（每页滚到底）没有文字匹配 I-数字', (tester) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.demo);
    final pages = await allPages(tester);
    await _expectNoStageCodeOnPages(tester, pages);
    // ignore: avoid_print
    print('检查了演示空间的 ${pages.length} 个页面');
  });

  testWidgets('真实空间的首次空白页与"我的"各页没有文字匹配 I-数字', (tester) async {
    await pumpCardFlowApp(tester);
    await _expectNoStageCodeOnPages(tester, <String>[
      AppRoutes.overview,
      AppRoutes.cards,
      AppRoutes.planner,
      AppRoutes.cashCalendar,
      AppRoutes.cash,
      AppRoutes.scenarios,
      AppRoutes.statements(),
      AppRoutes.repayments(),
      AppRoutes.discover,
      AppRoutes.settings,
      AppRoutes.diagnostics,
      AppRoutes.welcome,
    ]);
  });

  testWidgets('P-22 首次使用页（没有工作空间）没有文字匹配 I-数字', (tester) async {
    await pumpCardFlowApp(tester, workspace: TestWorkspace.none);
    await forEachScreen(tester, () {
      expect(stageCodeTexts(tester), isEmpty);
    });
  });
}
