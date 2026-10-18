/// Dart golden fixture 运行器（读写文件，依赖 dart:io）。
///
/// 用法（在 `apps/mobile/packages/cardflow_domain` 下）：
///
/// ```text
/// dart run cardflow_domain:run_fixtures [--dump <dir>] [FIXTURE_OR_DIRECTORY ...]
/// ```
///
/// 默认运行仓库 `packages/rules-protocol/fixtures/*.v1.json`（从当前目录向上查找仓库根）；给出目录
/// 时运行其中的 `*.v1.json`。每个 fixture：严格 JSON → 严格 Fixture 外壳 → 除 `time_limit_s` 外
/// 不得有浮点数 → 协议适配层 → 逐个 case：`cycles`（账期）、`verify`（独立验证器，无求解器）计算并
/// 检查全部断言；`plan` 需要 CP-SAT，报告为"未运行"，不算通过也不算失败。
///
/// `--dump <dir>`：把每个 cycles/verify case 的输出写成规范化 JSON（加换行），路径
/// `<dir>/<fixture 文件名去掉 .v1.json>/<两位序号>-<case 名>.<kind>.json`；Python 运行器的
/// `--dump` 写同样命名的参考输出，两个目录逐字节比较（protocol-parity）。
///
/// 退出码：0 全部断言成立；1 有断言不成立；2 输入非法（读不了、不是严格 JSON、外壳或协议违规）——
/// 2 优先于 1。
library;

import 'dart:convert';
import 'dart:io';

import '../../cardflow_domain.dart';
import 'fixture.dart';

/// 全部断言成立。
const int fixturesPassed = 0;

/// 有断言不成立。
const int fixturesMismatch = 1;

/// 输入非法。
const int fixturesInvalid = 2;

const String _usage = '''
usage: dart run cardflow_domain:run_fixtures [--dump <dir>] [FIXTURE_OR_DIRECTORY ...]

Runs the cycles and verify cases of rules-protocol v1 golden fixtures with the Dart domain
layer (plan cases need CP-SAT and are reported as not run). Default: every
packages/rules-protocol/fixtures/*.v1.json of the repository.

  --dump <dir>   write every cycles/verify output as canonical JSON to
                 <dir>/<fixture>/<NN>-<case>.<kind>.json

Exit status: 0 every assertion holds; 1 a mismatch; 2 invalid input.''';

/// 从 [start] 向上查找含 `packages/rules-protocol/fixtures` 的仓库根。
Directory? findRepositoryRoot([Directory? start]) {
  var dir = (start ?? Directory.current).absolute;
  while (true) {
    if (Directory('${dir.path}/packages/rules-protocol/fixtures')
        .existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      return null;
    }
    dir = parent;
  }
}

/// fixture 文件对应的 dump 子目录名（去掉 `.v1.json` 或 `.json`）。
String fixtureStem(String path) {
  final name = path.split(Platform.pathSeparator).last.split('/').last;
  if (name.endsWith('.v1.json')) {
    return name.substring(0, name.length - '.v1.json'.length);
  }
  return name.endsWith('.json') ? name.substring(0, name.length - 5) : name;
}

/// dump 文件名：`<两位序号>-<case 名>.<kind>.json`。
String dumpFileName(int index, String caseName, String kind) =>
    '${index.toString().padLeft(2, '0')}-$caseName.$kind.json';

/// 运行器入口（`bin/run_fixtures.dart` 调用）；返回退出码。
int runFixturesCli(List<String> args, {required void Function(String) emit}) {
  String? dump;
  final targets = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--dump') {
      if (i + 1 >= args.length) {
        emit(_usage);
        return fixturesInvalid;
      }
      dump = args[++i];
    } else if (arg.startsWith('--dump=')) {
      dump = arg.substring('--dump='.length);
    } else if (arg.startsWith('-')) {
      emit(_usage);
      return fixturesInvalid;
    } else {
      targets.add(arg);
    }
  }
  emit(
    'rules-protocol runner (Dart): protocol v$protocolVersion, cardflow_domain '
    '(engine model $engineModelVersion semantics, no solver)',
  );
  final root = findRepositoryRoot();
  final files = <File>[];
  if (targets.isEmpty) {
    if (root == null) {
      emit('repository root (packages/rules-protocol/fixtures) not found');
      return fixturesInvalid;
    }
    files.addAll(
      _v1Files(Directory('${root.path}/packages/rules-protocol/fixtures')),
    );
  } else {
    for (final t in targets) {
      final dir = Directory(t);
      files.addAll(dir.existsSync() ? _v1Files(dir) : <File>[File(t)]);
    }
  }
  if (files.isEmpty) {
    emit('no *.v1.json fixtures found');
    return fixturesInvalid;
  }
  final results = [
    for (final f in files)
      _runFixture(f, root, dump == null ? null : Directory(dump), emit),
  ];
  final status = results.fold<int>(0, (a, b) => a > b ? a : b);
  emit(
    'summary: ${results.length} fixture(s): '
    '${results.where((r) => r == fixturesPassed).length} passed, '
    '${results.where((r) => r == fixturesMismatch).length} failed, '
    '${results.where((r) => r == fixturesInvalid).length} invalid -> exit $status',
  );
  return status;
}

List<File> _v1Files(Directory dir) {
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.v1.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}

String _relative(File file, Directory? root) {
  final path = file.absolute.path;
  if (root != null && path.startsWith('${root.path}/')) {
    return path.substring(root.path.length + 1);
  }
  return file.path;
}

int _runFixture(
  File file,
  Directory? root,
  Directory? dump,
  void Function(String) emit,
) {
  emit('== ${_relative(file, root)}');
  final Fixture fixture;
  try {
    final List<int> bytes;
    try {
      bytes = file.readAsBytesSync();
    } on FileSystemException catch (e) {
      emit('   INVALID: cannot read: ${e.message}');
      return fixturesInvalid;
    }
    final Object? document;
    try {
      document = parseJson(bytes);
    } on ProtocolError catch (e) {
      emit('   INVALID: not strict JSON: $e');
      return fixturesInvalid;
    }
    try {
      fixture = readFixture(document);
    } on FixtureFormatError catch (e) {
      emit('   INVALID: fixture format: $e');
      return fixturesInvalid;
    }
    final floats = findFloats(document);
    if (floats.isNotEmpty) {
      emit('   INVALID: JSON floats outside time_limit_s: $floats');
      return fixturesInvalid;
    }
    inputsFromProtocol(fixture.input);
  } on ProtocolError catch (e) {
    emit('   INVALID: protocol violation in input: $e');
    return fixturesInvalid;
  }
  emit(
    '   fixture ${fixture.fixtureId}: strict fixture reader OK (Dart); '
    'input_hash ${protocolInputHash(fixture.input)}',
  );
  final parsed = inputsFromProtocol(fixture.input);
  var total = 0;
  var failed = 0;
  var notRun = 0;
  for (final c in fixture.cases) {
    final Object? output;
    final String label;
    try {
      switch (c.kind) {
        case CaseKind.plan:
          emit(
            '   case ${c.name} [plan ${c.profile} / ${c.decisionScenario}]: '
            'NOT RUN (needs CP-SAT; not counted as pass or fail)',
          );
          notRun++;
          continue;
        case CaseKind.cycles:
          output = cardCyclesToProtocol(parsed.inputs);
          label = 'cycles';
        case CaseKind.verify:
          output = verifyFromProtocol(
            fixture.input,
            c.allocation,
            c.decisionScenario,
          );
          final items = (c.allocation! as List<Object?>)
              .cast<Map<String, Object?>>();
          final parts = items
              .map((a) => '${a['card_id']}=${a['amount_minor']}')
              .join(', ');
          label = 'verify $parts / ${c.decisionScenario}';
      }
    } on ProtocolError catch (e) {
      emit('   case ${c.name}: INVALID: $e');
      return fixturesInvalid;
    }
    emit('   case ${c.name} [$label]');
    if (dump != null) {
      final target = File(
        '${dump.path}/${fixtureStem(file.path)}/'
        '${dumpFileName(c.index, c.name, c.kind.name)}',
      );
      target.parent.createSync(recursive: true);
      target.writeAsBytesSync(<int>[...canonicalJson(output), 0x0A]);
      emit('     dumped ${target.path}');
    }
    for (final a in c.assertions) {
      total++;
      final (holds, found) = a.check(output);
      final source = a.from == null ? '' : '  <- ${a.from}';
      if (holds) {
        emit('     PASS ${a.describe()}$source');
      } else {
        failed++;
        emit('     FAIL ${a.describe()}; found $found$source');
      }
    }
  }
  final ok = failed == 0;
  emit(
    '   result: ${ok ? 'PASS' : 'FAIL'} (${total - failed}/$total assertions hold; '
    '$notRun plan case(s) not run: need CP-SAT)',
  );
  return ok ? fixturesPassed : fixturesMismatch;
}

/// 把 [value] 写成给人看的 JSON（调试用）。
String prettyJson(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(_plain(value));

Object? _plain(Object? value) => switch (value) {
  JsonFloat() || BigInt() => value.toString(),
  List<Object?>() => [for (final v in value) _plain(v)],
  Map<String, Object?>() => {
    for (final MapEntry(:key, :value) in value.entries) key: _plain(value),
  },
  _ => value,
};
