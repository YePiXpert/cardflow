/// `dart run cardflow_domain:run_fixtures [--dump <dir>] [FIXTURE_OR_DIRECTORY ...]`
///
/// 运行规则协议 v1 golden fixture 的 cycles 与 verify case（plan case 需要 CP-SAT，报告为未运行）。
/// 退出码：0 全部一致，1 不一致，2 输入非法。详见 `lib/src/fixtures/runner.dart`。
library;

import 'dart:io';

import 'package:cardflow_domain/fixture_runner.dart';

void main(List<String> args) {
  exitCode = runFixturesCli(args, emit: stdout.writeln);
}
