/// RFC 6901 JSON Pointer（运行器的断言语义；Python `run_fixtures.resolve`）。
library;

/// 指针目标不存在。
final class PointerLookupError implements Exception {
  /// 查找失败。
  const PointerLookupError(this.message);

  /// 原因。
  final String message;

  @override
  String toString() => message;
}

/// 把对象成员名转义为指针片段（`~` → `~0`，`/` → `~1`）。
String escapePointerSegment(String key) =>
    key.replaceAll('~', '~0').replaceAll('/', '~1');

/// `path` 下成员 [key] 的指针。
String childPointer(String path, Object key) =>
    '$path/${escapePointerSegment(key.toString())}';

final RegExp _arrayIndex = RegExp(r'^(0|[1-9][0-9]*)$');

/// 解析指针；目标不存在时抛 [PointerLookupError]。数组下标不得有前导零。
Object? resolvePointer(Object? document, String pointer) {
  if (pointer.isEmpty) {
    return document;
  }
  var node = document;
  final segments = pointer.split('/').skip(1);
  for (final raw in segments) {
    final segment = raw.replaceAll('~1', '/').replaceAll('~0', '~');
    if (node is Map<String, Object?>) {
      if (!node.containsKey(segment)) {
        throw PointerLookupError("no member '$segment'");
      }
      node = node[segment];
    } else if (node is List<Object?>) {
      if (!_arrayIndex.hasMatch(segment)) {
        throw PointerLookupError("'$segment' is not an array index");
      }
      final index = int.tryParse(segment);
      if (index == null || index >= node.length) {
        throw PointerLookupError(
          'index $segment out of range (${node.length} items)',
        );
      }
      node = node[index];
    } else {
      throw PointerLookupError(
        "cannot descend into ${node.runtimeType} with '$segment'",
      );
    }
  }
  return node;
}
