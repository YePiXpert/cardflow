// 公测版 0.0.1 的界面约束（简报 I1-c2 §2；版本号按用户要求为 0.0.1）。
//
// 公测说明与「关于」：P-22 首次使用页底部（最后一节）与"我的 › 关于卡序"显示同一段公测说明（原文逐字断言；
// 说明里的版本号只来自 PublicBeta.version，测试读取 pubspec.yaml 断言它与版本名相同）；「关于」显示名称"卡序 CardFlow"、
// "公测版"标识、版本与构建号（与诊断页同一来源 package_info_plus，测试用与常量不同的版本号证明来源，含读取中/读取失败）、
// 源码地址（可选中的纯文本 + 复制，不打开浏览器）、反馈方式。
//
// 阶段代号防回归：用户可见的文字里不出现内部阶段代号（"I-3 提供""I-2 使用"一类，正则 `I-\d`），
// 未开放的功能一律写"后续版本提供"一类说法。两道检查：
// 1. 扫描 lib/ 下全部 Dart 源码的字符串字面量（去掉注释；内插表达式里的字符串也算），先用正反例自检扫描器；
// 2. 逐页打开 App（演示空间的全部页面、真实空间的首次空白页、没有工作空间时的 P-22），每页从顶滚到底，
//    检查渲染出来的全部文字（RichText 与输入框内容）。
import 'dart:async';
import 'dart:io';

import 'package:cardflow/app/routes.dart';
import 'package:cardflow/features/diagnostics/app_diagnostics.dart';
import 'package:cardflow/features/diagnostics/diagnostics_page.dart';
import 'package:cardflow/features/onboarding/welcome_page.dart';
import 'package:cardflow/features/settings/about_page.dart';
import 'package:cardflow/features/settings/public_beta.dart';
import 'package:cardflow/features/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

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

/// 在页面的主滚动区里滚到 [finder]（「关于」页的可选中文本自带一个滚动区，不能用默认的 Scrollable 查找）。
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
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

  group('公测说明与「关于」', () {
    /// 简报 I1-c2 §2 第 2 条给出的说明原文（版本号按用户要求改为 0.0.1）。
    const briefNote =
        '公测版 0.0.1：数据只保存在这台 iPhone 的加密数据库里，不上传任何服务器。'
        '删除 App 或「重置本地数据」会永久删除全部数据；目前还没有备份与导出，后续版本提供。';

    test(
      '说明原文（公测版 0.0.1）；说明里的版本号就是 PublicBeta.version，且与 pubspec.yaml 的版本名相同',
      () {
        expect(PublicBeta.note, briefNote);
        expect(PublicBeta.version, '0.0.1');
        expect(PublicBeta.note, startsWith('公测版 ${PublicBeta.version}：'));
        final pubspec = File('pubspec.yaml').readAsStringSync();
        final version = RegExp(
          r'^version:\s*(\d+\.\d+\.\d+)\+\d+\s*$',
          multiLine: true,
        ).firstMatch(pubspec);
        expect(version, isNotNull, reason: 'pubspec.yaml 的 version 行');
        expect(PublicBeta.version, version!.group(1));
        expect(PublicBeta.appName, '卡序 CardFlow');
        expect(PublicBeta.sourceAddress, 'github.com/YePiXpert/cardflow');
        expect(
          PublicBeta.feedback,
          '我的 › 诊断信息 › 复制诊断信息，附上问题描述发到 GitHub Issues',
        );
      },
    );

    testWidgets('P-22 首次使用页（没有工作空间）：底部最后一节是公测说明', (tester) async {
      await pumpCardFlowApp(tester, workspace: TestWorkspace.none);
      expect(appBarTitle(WelcomePage.title), findsOneWidget);
      final list = tester.widget<ListView>(
        find.descendant(
          of: find.byType(WelcomePage),
          matching: find.byType(ListView),
        ),
      );
      final children =
          (list.childrenDelegate as SliverChildListDelegate).children;
      expect(children.last, isA<PublicBetaNotice>(), reason: '说明在最底部');
      await _scrollTo(tester, find.text(PublicBeta.note));
      expect(find.text(PublicBeta.noteTitle), findsOneWidget);
      expect(find.text(PublicBeta.note), findsOneWidget);
    });

    testWidgets('从"我的"进入的欢迎页同样在底部显示公测说明', (tester) async {
      await pumpCardFlowApp(tester);
      await goTo(tester, AppRoutes.welcome);
      await _scrollTo(tester, find.text(PublicBeta.note));
      expect(find.text(PublicBeta.note), findsOneWidget);
    });

    testWidgets('「关于」：我的 › 关于卡序；名称、公测版标识、版本与构建号（与诊断页同一来源）、公测说明、'
        '源码地址可选中并可复制、反馈方式与「打开诊断信息」', (tester) async {
      final copied = captureClipboard(tester);
      await pumpCardFlowApp(tester);
      // 版本与构建号必须来自 package_info_plus（与诊断页同一来源），不是 PublicBeta.version：模拟一个不同的版本。
      PackageInfo.setMockInitialValues(
        appName: '卡序',
        packageName: 'li.yep.cardflow',
        version: '9.8.7',
        buildNumber: '65',
        buildSignature: '',
      );
      await goTo(tester, AppRoutes.settings);
      await tester.tap(find.text(AboutPage.title));
      await tester.pumpAndSettle();
      expect(appBarTitle(AboutPage.title), findsOneWidget);
      expect(
        appRouter(tester).routerDelegate.currentConfiguration.uri.path,
        AppRoutes.about,
      );
      expect(find.text(PublicBeta.appName), findsOneWidget);
      expect(find.text(PublicBeta.badge), findsOneWidget);
      expect(find.text('9.8.7（构建 65）'), findsOneWidget);
      expect(find.text(PublicBeta.noteTitle), findsOneWidget);
      expect(find.text(PublicBeta.note), findsOneWidget);
      final source = find.byType(SelectableText);
      await _scrollTo(tester, source);
      expect(
        tester.widget<SelectableText>(source).data,
        'github.com/YePiXpert/cardflow',
      );
      await _scrollTo(tester, find.text('复制源码地址'));
      await tester.tap(find.text('复制源码地址'));
      await tester.pumpAndSettle();
      expect(copied, <String>['github.com/YePiXpert/cardflow']);
      expect(find.text(AboutPage.copiedMessage), findsOneWidget);
      await _scrollTo(tester, find.text(PublicBeta.feedback));
      expect(find.text(PublicBeta.feedback), findsOneWidget);
      await _scrollTo(tester, find.text('打开诊断信息'));
      await tester.tap(find.text('打开诊断信息'));
      await tester.pumpAndSettle();
      expect(appBarTitle(DiagnosticsPage.title), findsOneWidget);
      // 诊断页显示同一个版本与构建号。
      expect(find.text('9.8.7（构建 65）'), findsOneWidget);
    });

    testWidgets('「关于」的版本读取中：显示"读取中…"，公测说明照常显示', (tester) async {
      final pending = Completer<AppDiagnostics>();
      await pumpCardFlowApp(
        tester,
        overrides: <Override>[
          appDiagnosticsProvider.overrideWith((ref) => pending.future),
        ],
      );
      await goTo(tester, AppRoutes.about);
      expect(find.text('读取中…'), findsOneWidget);
      expect(find.text(PublicBeta.note), findsOneWidget, reason: '说明不依赖版本读取');
    });

    testWidgets('「关于」的版本读取失败：显示错误类型', (tester) async {
      await pumpCardFlowApp(
        tester,
        overrides: <Override>[
          appDiagnosticsProvider.overrideWith(
            (ref) => Future<AppDiagnostics>.error(StateError('x')),
          ),
        ],
      );
      await goTo(tester, AppRoutes.about);
      expect(find.text('读取失败（StateError）'), findsOneWidget);
    });

    testWidgets('"我的"页有「关于卡序」入口', (tester) async {
      await pumpCardFlowApp(tester);
      await goTo(tester, AppRoutes.settings);
      expect(appBarTitle(SettingsPage.title), findsOneWidget);
      expect(find.text(AboutPage.title), findsOneWidget);
      expect(find.text('版本、公测说明、源码与反馈'), findsOneWidget);
    });
  });
}
