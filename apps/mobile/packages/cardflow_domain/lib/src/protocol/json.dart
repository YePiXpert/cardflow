/// 严格 JSON 读取与 JSON 值工具（Python `protocol.parse_json` 与运行器的 `json_equal`）。
///
/// 读取结果的 Dart 类型：`null`、`bool`、`int`（64 位内的整数记号）、`BigInt`（超出 64 位的整数
/// 记号）、[JsonFloat]（带小数点或指数的数字记号）、`String`、`List<Object?>`、
/// `Map<String, Object?>`（保持成员顺序）。整数记号与浮点记号严格区分：`1.0` 是浮点，不是整数。
library;

import 'dart:convert';

import 'binary64.dart';
import 'errors.dart';

/// 带小数点或指数的 JSON 数字（协议 v1 只允许出现在 `options.time_limit_s`）。
///
/// 按 Python `float(text)` 舍入到 binary64 后保存（精确整数表示，不经过 `double`）。
final class JsonFloat {
  /// 由 binary64 值构造。
  const JsonFloat(this.binary64);

  /// 解析数字记号；记号不合 JSON 语法时抛 [FormatException]，超出 binary64 有限范围时返回 null。
  static JsonFloat? parse(String token) {
    final value = Binary64.parseJsonNumber(token);
    return value == null ? null : JsonFloat(value);
  }

  /// binary64 值。
  final Binary64 binary64;

  /// ECMAScript 写法（规范化 JSON 用）。
  @override
  String toString() => binary64.toEcmaScript();

  @override
  bool operator ==(Object other) =>
      other is JsonFloat && other.binary64 == binary64;

  @override
  int get hashCode => binary64.hashCode;
}

/// 嵌套深度上限（Python 的 json 在约 1000 层时因递归上限报错；协议文档只有个位数层）。
const int maxJsonDepth = 512;

/// Python `int(str)` 的位数上限（`sys.int_info.str_digits_check_threshold` 默认 4300）。
const int maxIntegerDigits = 4300;

/// 严格读取 UTF-8 JSON：拒绝 BOM、非 UTF-8、重复键、NaN/Infinity（含溢出的数字字面量，
/// 如 `1e400`）、超长整数记号与过深嵌套。错误只给规则与位置，不回显内容（R3E-12）。
Object? parseJson(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    throw const ProtocolError('', 'a UTF-8 byte order mark is not allowed');
  }
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException catch (e) {
    throw ProtocolError('', 'not UTF-8 (invalid byte at offset ${e.offset})');
  }
  return parseJsonText(text);
}

/// 严格读取已解码的 JSON 文本（规则同 [parseJson]）。
Object? parseJsonText(String text) {
  final parser = _Parser(text);
  if (text.startsWith('\uFEFF')) {
    throw parser._error('Unexpected UTF-8 BOM (decode using utf-8-sig)', 0);
  }
  parser._skipWhitespace();
  final value = parser._value(0);
  parser._skipWhitespace();
  if (parser._pos < text.length) {
    throw parser._error('Extra data', parser._pos);
  }
  return value;
}

final RegExp _numberToken = RegExp(
  r'-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][-+]?[0-9]+)?',
);

final class _Parser {
  _Parser(this._text);

  final String _text;
  int _pos = 0;

  ProtocolError _error(String rule, int at) {
    var line = 1;
    var lineStart = 0;
    for (var i = 0; i < at && i < _text.length; i++) {
      if (_text.codeUnitAt(i) == 0x0A) {
        line++;
        lineStart = i + 1;
      }
    }
    return ProtocolError(
      '',
      'invalid JSON: $rule (line $line, column ${at - lineStart + 1})',
    );
  }

  void _skipWhitespace() {
    while (_pos < _text.length) {
      final c = _text.codeUnitAt(_pos);
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
        _pos++;
      } else {
        break;
      }
    }
  }

  bool _startsWith(String literal) => _text.startsWith(literal, _pos);

  Object? _value(int depth) {
    if (_pos >= _text.length) {
      throw _error('Expecting value', _pos);
    }
    final c = _text.codeUnitAt(_pos);
    switch (c) {
      case 0x7B: // {
        return _object(depth + 1);
      case 0x5B: // [
        return _array(depth + 1);
      case 0x22: // "
        return _string();
    }
    if (_startsWith('true')) {
      _pos += 4;
      return true;
    }
    if (_startsWith('false')) {
      _pos += 5;
      return false;
    }
    if (_startsWith('null')) {
      _pos += 4;
      return null;
    }
    final match = _numberToken.matchAsPrefix(_text, _pos);
    if (match != null) {
      _pos = match.end;
      return _number(match[0]!);
    }
    for (final constant in const <String>['NaN', 'Infinity', '-Infinity']) {
      if (_startsWith(constant)) {
        throw ProtocolError('', '$constant is not a JSON number');
      }
    }
    throw _error('Expecting value', _pos);
  }

  Object _number(String token) {
    final isInteger =
        !token.contains('.') && !token.contains('e') && !token.contains('E');
    if (isInteger) {
      final digits = token.startsWith('-') ? token.length - 1 : token.length;
      if (digits > maxIntegerDigits) {
        throw const ProtocolError(
          '',
          'invalid JSON: an integer literal is too long',
        );
      }
      return int.tryParse(token) ?? BigInt.parse(token);
    }
    final value = JsonFloat.parse(token);
    if (value == null) {
      throw const ProtocolError('', 'a number is out of the double range');
    }
    return value;
  }

  String _string() {
    final start = _pos;
    _pos++; // opening quote
    final buffer = StringBuffer();
    while (true) {
      if (_pos >= _text.length) {
        throw _error('Unterminated string starting at', start);
      }
      final c = _text.codeUnitAt(_pos);
      if (c == 0x22) {
        _pos++;
        return buffer.toString();
      }
      if (c == 0x5C) {
        if (_pos + 1 >= _text.length) {
          throw _error('Unterminated string starting at', start);
        }
        final e = _text.codeUnitAt(_pos + 1);
        switch (e) {
          case 0x22:
            buffer.writeCharCode(0x22);
          case 0x5C:
            buffer.writeCharCode(0x5C);
          case 0x2F:
            buffer.writeCharCode(0x2F);
          case 0x62: // b
            buffer.writeCharCode(0x08);
          case 0x66: // f
            buffer.writeCharCode(0x0C);
          case 0x6E: // n
            buffer.writeCharCode(0x0A);
          case 0x72: // r
            buffer.writeCharCode(0x0D);
          case 0x74: // t
            buffer.writeCharCode(0x09);
          case 0x75: // u
            final hex = _pos + 6 <= _text.length
                ? _text.substring(_pos + 2, _pos + 6)
                : '';
            if (!RegExp(r'^[0-9A-Fa-f]{4}$').hasMatch(hex)) {
              throw _error(r'Invalid \uXXXX escape', _pos);
            }
            buffer.writeCharCode(int.parse(hex, radix: 16));
            _pos += 6;
            continue;
          default:
            throw _error(r'Invalid \escape', _pos);
        }
        _pos += 2;
        continue;
      }
      if (c < 0x20) {
        throw _error('Invalid control character at', _pos);
      }
      buffer.writeCharCode(c);
      _pos++;
    }
  }

  void _checkDepth(int depth) {
    if (depth > maxJsonDepth) {
      throw const ProtocolError('', 'invalid JSON: nested too deeply');
    }
  }

  Map<String, Object?> _object(int depth) {
    _checkDepth(depth);
    _pos++; // {
    final out = <String, Object?>{};
    _skipWhitespace();
    if (_pos < _text.length && _text.codeUnitAt(_pos) == 0x7D) {
      _pos++;
      return out;
    }
    while (true) {
      _skipWhitespace();
      if (_pos >= _text.length || _text.codeUnitAt(_pos) != 0x22) {
        throw _error('Expecting property name enclosed in double quotes', _pos);
      }
      final key = _string();
      _skipWhitespace();
      if (_pos >= _text.length || _text.codeUnitAt(_pos) != 0x3A) {
        throw _error("Expecting ':' delimiter", _pos);
      }
      _pos++;
      _skipWhitespace();
      final value = _value(depth);
      if (out.containsKey(key)) {
        throw const ProtocolError('', 'duplicate object key');
      }
      out[key] = value;
      _skipWhitespace();
      if (_pos < _text.length && _text.codeUnitAt(_pos) == 0x2C) {
        _pos++;
        continue;
      }
      if (_pos < _text.length && _text.codeUnitAt(_pos) == 0x7D) {
        _pos++;
        return out;
      }
      throw _error("Expecting ',' delimiter", _pos);
    }
  }

  List<Object?> _array(int depth) {
    _checkDepth(depth);
    _pos++; // [
    final out = <Object?>[];
    _skipWhitespace();
    if (_pos < _text.length && _text.codeUnitAt(_pos) == 0x5D) {
      _pos++;
      return out;
    }
    while (true) {
      _skipWhitespace();
      out.add(_value(depth));
      _skipWhitespace();
      if (_pos < _text.length && _text.codeUnitAt(_pos) == 0x2C) {
        _pos++;
        continue;
      }
      if (_pos < _text.length && _text.codeUnitAt(_pos) == 0x5D) {
        _pos++;
        return out;
      }
      throw _error("Expecting ',' delimiter", _pos);
    }
  }
}

/// 是否为整数记号的值（`int` 或 `BigInt`；布尔不是整数）。
bool isJsonInteger(Object? value) => value is int || value is BigInt;

/// 值的种类描述（Python `_kind`）：`a boolean`、`a float`、`an integer`、`a string`、
/// `an array`、`an object`、`null`。
String jsonKind(Object? value) => switch (value) {
  null => 'null',
  bool() => 'a boolean',
  JsonFloat() => 'a float',
  int() || BigInt() => 'an integer',
  String() => 'a string',
  List<Object?>() => 'an array',
  Map<String, Object?>() => 'an object',
  _ => value.runtimeType.toString(),
};

/// 严格 JSON 相等（运行器的断言语义）：布尔不是数字，整数不是浮点；对象成员集合相同且逐个相等。
bool jsonEquals(Object? a, Object? b) {
  if (a == null || b == null) {
    return a == null && b == null;
  }
  if (a is bool || b is bool) {
    return a is bool && b is bool && a == b;
  }
  if (isJsonInteger(a) || isJsonInteger(b)) {
    if (!isJsonInteger(a) || !isJsonInteger(b)) {
      return false;
    }
    final x = a is int ? BigInt.from(a) : a as BigInt;
    final y = b is int ? BigInt.from(b) : b as BigInt;
    return x == y;
  }
  if (a is JsonFloat || b is JsonFloat) {
    return a is JsonFloat && b is JsonFloat && a == b;
  }
  if (a is String || b is String) {
    return a is String && b is String && a == b;
  }
  if (a is List<Object?> && b is List<Object?>) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!jsonEquals(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  if (a is Map<String, Object?> && b is Map<String, Object?>) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || !jsonEquals(entry.value, b[entry.key])) {
        return false;
      }
    }
    return true;
  }
  return false;
}

/// 给人看的 JSON（运行器输出；仿 Python `json.dumps(v, ensure_ascii=False, sort_keys=True)`，
/// 分隔符 `, ` 与 `: `）。不是规范化 JSON。
String displayJson(Object? value) {
  final buffer = StringBuffer();
  void write(Object? v) {
    switch (v) {
      case null:
        buffer.write('null');
      case bool():
        buffer.write(v ? 'true' : 'false');
      case int() || BigInt() || JsonFloat():
        buffer.write(v.toString());
      case String():
        buffer.write(jsonQuote(v));
      case List<Object?>():
        buffer.write('[');
        for (var i = 0; i < v.length; i++) {
          if (i > 0) {
            buffer.write(', ');
          }
          write(v[i]);
        }
        buffer.write(']');
      case Map<String, Object?>():
        final keys = v.keys.toList()..sort();
        buffer.write('{');
        for (var i = 0; i < keys.length; i++) {
          if (i > 0) {
            buffer.write(', ');
          }
          buffer.write('${jsonQuote(keys[i])}: ');
          write(v[keys[i]]);
        }
        buffer.write('}');
      default:
        buffer.write(v.toString());
    }
  }

  write(value);
  return buffer.toString();
}

/// JSON 字符串字面量，转义规则与 Python `json.dumps(s, ensure_ascii=False)` 相同：只转义 `"`、
/// `\` 与 U+0000–U+001F（`\b \t \n \f \r` 用短形式，其余 `\u00xx` 小写十六进制）；其他字符
/// （含 `/`、U+007F、U+2028、中文）原样输出。不检查孤立代理项（见 `canonicalJson`）。
String jsonQuote(String text) {
  final buffer = StringBuffer('"');
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    switch (c) {
      case 0x22:
        buffer.write(r'\"');
      case 0x5C:
        buffer.write(r'\\');
      case 0x08:
        buffer.write(r'\b');
      case 0x0C:
        buffer.write(r'\f');
      case 0x0A:
        buffer.write(r'\n');
      case 0x0D:
        buffer.write(r'\r');
      case 0x09:
        buffer.write(r'\t');
      default:
        if (c < 0x20) {
          buffer.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
        } else {
          buffer.writeCharCode(c);
        }
    }
  }
  buffer.write('"');
  return buffer.toString();
}

/// 字符串是否含孤立代理项（不是合法 Unicode）。
bool hasLoneSurrogate(String text) {
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c >= 0xD800 && c <= 0xDBFF) {
      if (i + 1 < text.length) {
        final next = text.codeUnitAt(i + 1);
        if (next >= 0xDC00 && next <= 0xDFFF) {
          i++;
          continue;
        }
      }
      return true;
    }
    if (c >= 0xDC00 && c <= 0xDFFF) {
      return true;
    }
  }
  return false;
}
