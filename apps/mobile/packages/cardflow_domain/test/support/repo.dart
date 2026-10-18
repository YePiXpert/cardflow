/// 测试用：定位仓库根、读取 golden fixture 与 Python 源码（比对用）。
library;

import 'dart:io';

import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:cardflow_domain/fixture_runner.dart';
import 'package:cardflow_domain/testing.dart';

/// 仓库根（含 packages/rules-protocol/fixtures）。
Directory repoRoot() {
  final root = findRepositoryRoot();
  if (root == null) {
    throw StateError(
      'repository root not found from ${Directory.current.path}',
    );
  }
  return root;
}

/// 仓库根下的文件。
File repoFile(String relative) => File('${repoRoot().path}/$relative');

/// F-18 v1 fixture 文件。
File f18File() => repoFile(
  'packages/rules-protocol/fixtures/regression_2026-10-16_10000.v1.json',
);

/// F-18 fixture 文档（每次新解析）。
Map<String, Object?> f18Fixture() =>
    parseJson(f18File().readAsBytesSync())! as Map<String, Object?>;

/// F-18 的 PlanInput 文档（可修改的新副本）。
Map<String, Object?> f18Input() =>
    deepCopyJson(f18Fixture()['input'])! as Map<String, Object?>;

/// F-18 读成领域对象。
ParsedPlanInput f18() => inputsFromProtocol(f18Input());

/// Python 引擎源码（`services/api/cardflow/planner/engine/<name>`）。
String engineSource(String name) =>
    repoFile('services/api/cardflow/planner/engine/$name').readAsStringSync();

/// F-18 的 `protocol_input_hash`（README 与 Python 测试钉住的值）。
const String f18InputHash =
    'ea990327f08b42d476fa157d9bb8ddff6a1d8eb4e41ff60b1e498c5861a91ee8';

/// 取 JSON 文档中的成员（测试里改写文档用）。
Map<String, Object?> obj(Object? value) => value! as Map<String, Object?>;

/// 取 JSON 数组。
List<Object?> arr(Object? value) => value! as List<Object?>;
