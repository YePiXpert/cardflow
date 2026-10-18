/// 规范化 JSON 与 `protocol_input_hash`（README"规范化 JSON 与 input_hash"；Python
/// `protocol.canonical_json` / `protocol_input_hash`）。
///
/// 规则（RFC 8785/JCS，唯一差别：整数永远按精确十进制写出，不经过 double）：无空白，分隔符
/// `,` 与 `:`；对象成员按键的 UTF-16 代码单元排序（Dart `String.compareTo` 即此序）；字符串只转义
/// `"`、`\` 与 U+0000–U+001F，其余字符原样 UTF-8 输出，孤立代理项是错误；整数（含超出 64 位的
/// `BigInt`）写成精确十进制；非整数按 ECMAScript `Number.prototype.toString`。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'errors.dart';
import 'json.dart';

/// [value] 的规范化 JSON（UTF-8 字节）。非 JSON 值、非字符串键、孤立代理项抛 [ProtocolError]。
Uint8List canonicalJson(Object? value) =>
    Uint8List.fromList(utf8.encode(canonicalJsonText(value)));

/// [value] 的规范化 JSON 文本。
String canonicalJsonText(Object? value) {
  final buffer = StringBuffer();
  _canon(value, '', buffer);
  return buffer.toString();
}

/// `lowercase_hex(sha256(canonical_json(PlanInput)))`：语言中立的输入哈希（PlanOutcome.input_hash、
/// 本地运行记录、fixture 运行器）。
String protocolInputHash(Object? document) =>
    sha256.convert(canonicalJson(document)).toString();

String _pointer(String path, String key) =>
    '$path/${key.replaceAll('~', '~0').replaceAll('/', '~1')}';

String _canonString(String text, String path) {
  if (hasLoneSurrogate(text)) {
    throw ProtocolError(
      path,
      'string contains a lone surrogate (not valid Unicode)',
    );
  }
  return jsonQuote(text);
}

void _canon(Object? value, String path, StringBuffer out) {
  switch (value) {
    case null:
      out.write('null');
    case true:
      out.write('true');
    case false:
      out.write('false');
    case int():
      out.write(value.toString());
    case BigInt():
      out.write(value.toString());
    case JsonFloat():
      out.write(value.binary64.toEcmaScript());
    case String():
      out.write(_canonString(value, path));
    case List<Object?>():
      out.write('[');
      for (var i = 0; i < value.length; i++) {
        if (i > 0) {
          out.write(',');
        }
        _canon(value[i], '$path/$i', out);
      }
      out.write(']');
    case Map<Object?, Object?>():
      final keys = <String>[];
      for (final key in value.keys) {
        if (key is! String) {
          throw ProtocolError(path, 'object keys must be strings');
        }
        keys.add(key);
      }
      keys.sort(); // UTF-16 代码单元序（RFC 8785 §3.2.3）
      out.write('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) {
          out.write(',');
        }
        out
          ..write(_canonString(keys[i], path))
          ..write(':');
        _canon(value[keys[i]], _pointer(path, keys[i]), out);
      }
      out.write('}');
    default:
      throw ProtocolError(path, '${value.runtimeType} is not a JSON value');
  }
}
