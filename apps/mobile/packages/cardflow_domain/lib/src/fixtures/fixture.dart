/// golden fixture 的严格读取与断言语义（`Fixture.schema.json`；Python `runner_py/run_fixtures.py`）。
///
/// Dart 端不带通用 JSON Schema 校验库（不在 architecture §11 版本表内）：Fixture 外壳由这里逐条
/// 检查（封闭对象、必填成员、CaseName/JsonPointer/Where 的 pattern、断言的两种形态），`input`
/// 交给协议适配层（[inputsFromProtocol]，它实现了 PlanInput 的全部规则）。断言语义与 Python
/// 运行器相同：RFC 6901 JSON Pointer、where/then、严格相等、length。
library;

import '../protocol/adapter.dart';
import '../protocol/json.dart';
import '../protocol/pointer.dart';
import '../pytext.dart';

/// Fixture 外壳不合格式（运行器退出码 2）。
final class FixtureFormatError implements Exception {
  /// 格式错误。
  const FixtureFormatError(this.path, this.message);

  /// JSON Pointer。
  final String path;

  /// 违反的规则。
  final String message;

  @override
  String toString() => '${path.isEmpty ? '<fixture>' : path}: $message';
}

/// 一条断言。
final class FixtureAssertion {
  FixtureAssertion._(this.raw);

  /// 原始断言对象。
  final Map<String, Object?> raw;

  /// JSON Pointer（`''` = 整个输出）。
  String get path => raw['path']! as String;

  /// where 条件（可无）。
  Map<String, Object?>? get where => raw['where'] as Map<String, Object?>?;

  /// 选中元素内的指针（默认 `''`）。
  String get then => (raw['then'] as String?) ?? '';

  /// 是否是 equals 断言（否则是 length 断言）。
  bool get isEquals => raw.containsKey('equals');

  /// 期望值。
  Object? get equals => raw['equals'];

  /// 期望长度。
  int get length => raw['length']! as int;

  /// 期望值的来源说明。
  String? get from => raw['from'] as String?;

  /// 给人看的描述（与 Python `describe` 同一写法）。
  String describe() {
    var text = path.isEmpty ? '<output>' : path;
    final w = where;
    if (w != null) {
      final keys = w.keys.toList()..sort(compareCodePoints);
      final cond = keys.map((k) => '$k=${displayJson(w[k])}').join(', ');
      text += '[$cond]$then';
    }
    return isEquals
        ? '$text == ${displayJson(equals)}'
        : 'len($text) == $length';
  }

  /// 在 [output] 上求值：（是否成立, 实际看到的内容）。
  (bool, String) check(Object? output) {
    Object? value;
    try {
      value = resolvePointer(output, path);
      final w = where;
      if (w != null) {
        if (value is! List<Object?>) {
          return (false, 'not an array: ${displayJson(value)}');
        }
        final matches = [
          for (final item in value)
            if (item is Map<String, Object?> &&
                w.entries.every(
                  (e) =>
                      item.containsKey(e.key) &&
                      jsonEquals(item[e.key], e.value),
                ))
              item,
        ];
        if (matches.length != 1) {
          return (false, '${matches.length} elements match');
        }
        value = resolvePointer(matches.single, then);
      }
    } on PointerLookupError catch (e) {
      return (false, 'missing ($e)');
    }
    if (isEquals) {
      return (jsonEquals(value, equals), displayJson(value));
    }
    if (value is List<Object?>) {
      return (value.length == length, 'length ${value.length}');
    }
    if (value is Map<String, Object?>) {
      return (value.length == length, 'length ${value.length}');
    }
    return (false, 'not an array/object: ${displayJson(value)}');
  }
}

/// case 的种类。
enum CaseKind {
  /// 每张卡的保守账期（`PlanOutcome.schema.json#/$defs/CardCycles`）。
  cycles,

  /// 独立验证器（`#/$defs/VerificationResult`）。
  verify,

  /// 完整运行（需要 CP-SAT；Dart 端报告为未运行）。
  plan,
}

/// 一个 case。
final class FixtureCase {
  FixtureCase._({
    required this.index,
    required this.name,
    required this.kind,
    required this.assertions,
    this.allocation,
    this.decisionScenario,
    this.profile,
  });

  /// 在 `expected` 中的位置。
  final int index;

  /// 名称。
  final String name;

  /// 种类。
  final CaseKind kind;

  /// 断言。
  final List<FixtureAssertion> assertions;

  /// verify：给定分配（原始 JSON，交给适配层）。
  final Object? allocation;

  /// verify / plan：决策情景。
  final String? decisionScenario;

  /// plan：画像。
  final String? profile;
}

/// 一个 golden fixture。
final class Fixture {
  Fixture._(this.fixtureId, this.input, this.cases);

  /// fixture ID。
  final String fixtureId;

  /// PlanInput（原始 JSON）。
  final Object? input;

  /// case。
  final List<FixtureCase> cases;
}

final RegExp _id = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$');
final RegExp _caseName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$');
final RegExp _pointer = RegExp(r'^(/([^~/]|~[01])*)*$');
final RegExp _whereKey = RegExp(r'^[a-z][a-z0-9_]*$');
final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');

Map<String, Object?> _object(
  Object? value,
  String path,
  List<String> allowed,
  List<String> required,
) {
  if (value is! Map<String, Object?>) {
    throw FixtureFormatError(
      path,
      'expected an object, got ${jsonKind(value)}',
    );
  }
  for (final key in value.keys) {
    if (!allowed.contains(key)) {
      throw FixtureFormatError(childPointer(path, key), 'unknown member');
    }
  }
  for (final key in required) {
    if (!value.containsKey(key)) {
      throw FixtureFormatError(path, 'missing required member ${pyRepr(key)}');
    }
  }
  return value;
}

String _string(Object? value, String path, {RegExp? pattern, int? maxLength}) {
  if (value is! String) {
    throw FixtureFormatError(path, 'expected a string, got ${jsonKind(value)}');
  }
  if (pattern != null && !pattern.hasMatch(value)) {
    throw FixtureFormatError(path, 'does not match ${pattern.pattern}');
  }
  if (maxLength != null && value.runes.length > maxLength) {
    throw FixtureFormatError(path, 'longer than $maxLength characters');
  }
  return value;
}

List<Object?> _array(Object? value, String path, {int minItems = 0}) {
  if (value is! List<Object?>) {
    throw FixtureFormatError(path, 'expected an array, got ${jsonKind(value)}');
  }
  if (value.length < minItems) {
    throw FixtureFormatError(path, 'needs at least $minItems item(s)');
  }
  return value;
}

FixtureAssertion _assertion(Object? value, String path) {
  final o = _object(
    value,
    path,
    const <String>['path', 'where', 'then', 'equals', 'length', 'from'],
    const <String>['path'],
  );
  final hasEquals = o.containsKey('equals');
  final hasLength = o.containsKey('length');
  if (hasEquals == hasLength) {
    throw FixtureFormatError(
      path,
      "needs exactly one of 'equals' and 'length'",
    );
  }
  _string(o['path'], childPointer(path, 'path'), pattern: _pointer);
  if (o.containsKey('where')) {
    final wherePath = childPointer(path, 'where');
    final where = o['where'];
    if (where is! Map<String, Object?> || where.isEmpty) {
      throw FixtureFormatError(wherePath, 'expected a non-empty object');
    }
    for (final MapEntry(:key, :value) in where.entries) {
      if (!_whereKey.hasMatch(key)) {
        throw FixtureFormatError(
          childPointer(wherePath, key),
          'invalid member name',
        );
      }
      if (value is! String && value is! bool && !isJsonInteger(value)) {
        throw FixtureFormatError(
          childPointer(wherePath, key),
          'expected a string, an integer or a boolean',
        );
      }
    }
  }
  if (o.containsKey('then')) {
    if (!o.containsKey('where')) {
      throw FixtureFormatError(path, "'then' requires 'where'");
    }
    _string(o['then'], childPointer(path, 'then'), pattern: _pointer);
  }
  if (hasLength) {
    final length = o['length'];
    if (length is! int || length < 0 || length > int32Max) {
      throw FixtureFormatError(
        childPointer(path, 'length'),
        'expected a count',
      );
    }
  }
  if (o.containsKey('from')) {
    _string(o['from'], childPointer(path, 'from'), maxLength: textMaxLength);
  }
  return FixtureAssertion._(o);
}

FixtureCase _case(Object? value, String path, int index) {
  final kindValue = value is Map<String, Object?> ? value['kind'] : null;
  final kind = switch (kindValue) {
    'cycles' => CaseKind.cycles,
    'verify' => CaseKind.verify,
    'plan' => CaseKind.plan,
    _ => throw FixtureFormatError(
      path,
      "'kind' must be one of cycles, verify, plan",
    ),
  };
  final members = switch (kind) {
    CaseKind.cycles => const <String>['name', 'kind', 'assertions'],
    CaseKind.verify => const <String>[
      'name',
      'kind',
      'allocation',
      'decision_scenario',
      'assertions',
    ],
    CaseKind.plan => const <String>[
      'name',
      'kind',
      'profile',
      'decision_scenario',
      'assertions',
    ],
  };
  final o = _object(value, path, members, members);
  final name = _string(
    o['name'],
    childPointer(path, 'name'),
    pattern: _caseName,
  );
  String? decision;
  String? profile;
  if (kind != CaseKind.cycles) {
    decision = _string(
      o['decision_scenario'],
      childPointer(path, 'decision_scenario'),
      pattern: _id,
    );
  }
  if (kind == CaseKind.verify) {
    final items = _array(
      o['allocation'],
      childPointer(path, 'allocation'),
      minItems: 1,
    );
    for (var i = 0; i < items.length; i++) {
      final itemPath = '${childPointer(path, 'allocation')}/$i';
      final item = _object(
        items[i],
        itemPath,
        const <String>['card_id', 'amount_minor'],
        const <String>['card_id', 'amount_minor'],
      );
      _string(item['card_id'], childPointer(itemPath, 'card_id'), pattern: _id);
      final amount = item['amount_minor'];
      if (amount is! int || amount < 1 || amount > moneyLimit) {
        throw FixtureFormatError(
          childPointer(itemPath, 'amount_minor'),
          'expected an integer in [1, $moneyLimit]',
        );
      }
    }
  }
  if (kind == CaseKind.plan) {
    final p = o['profile'];
    if (p is! String || !profiles.contains(p)) {
      throw FixtureFormatError(
        childPointer(path, 'profile'),
        'must be one of ${pyListRepr(profiles)}',
      );
    }
    profile = p;
  }
  final assertionsPath = childPointer(path, 'assertions');
  final raw = _array(o['assertions'], assertionsPath, minItems: 1);
  return FixtureCase._(
    index: index,
    name: name,
    kind: kind,
    assertions: [
      for (var i = 0; i < raw.length; i++)
        _assertion(raw[i], '$assertionsPath/$i'),
    ],
    allocation: o['allocation'],
    decisionScenario: decision,
    profile: profile,
  );
}

/// 严格读取 Fixture 外壳；不合格式抛 [FixtureFormatError]。`input` 的内容由调用方交给
/// [inputsFromProtocol] 校验。
Fixture readFixture(Object? document) {
  final o = _object(
    document,
    '',
    const <String>[
      'protocol_version',
      'fixture_id',
      'description',
      'source',
      'input',
      'expected',
    ],
    const <String>['protocol_version', 'fixture_id', 'input', 'expected'],
  );
  if (o['protocol_version'] != protocolVersion) {
    throw FixtureFormatError(
      '/protocol_version',
      'unsupported protocol_version (expected ${pyRepr(protocolVersion)})',
    );
  }
  final fixtureId = _string(o['fixture_id'], '/fixture_id', pattern: _id);
  if (o.containsKey('description')) {
    _string(o['description'], '/description', maxLength: textMaxLength);
  }
  if (o.containsKey('source')) {
    final s = _object(
      o['source'],
      '/source',
      const <String>['path', 'sha256', 'converter'],
      const <String>['path', 'sha256', 'converter'],
    );
    for (final key in const <String>['path', 'converter']) {
      final text = _string(s[key], '/source/$key', maxLength: 256);
      if (text.isEmpty) {
        throw FixtureFormatError('/source/$key', 'must not be empty');
      }
    }
    _string(s['sha256'], '/source/sha256', pattern: _sha256);
  }
  final expected = _array(o['expected'], '/expected', minItems: 1);
  return Fixture._(fixtureId, o['input'], [
    for (var i = 0; i < expected.length; i++)
      _case(expected[i], '/expected/$i', i),
  ]);
}

/// [value] 中除 [allowed] 外每个浮点数的 JSON Pointer（期望值与输入中都不得有浮点数）。
List<String> findFloats(
  Object? value, {
  String path = '',
  Set<String> allowed = const <String>{'/input/options/time_limit_s'},
}) {
  if (value is JsonFloat) {
    return allowed.contains(path) ? const <String>[] : <String>[path];
  }
  if (value is Map<String, Object?>) {
    return [
      for (final MapEntry(:key, :value) in value.entries)
        ...findFloats(value, path: childPointer(path, key), allowed: allowed),
    ];
  }
  if (value is List<Object?>) {
    return [
      for (var i = 0; i < value.length; i++)
        ...findFloats(value[i], path: '$path/$i', allowed: allowed),
    ];
  }
  return const <String>[];
}
