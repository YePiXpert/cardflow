/// 与 Python 引擎逐字一致的少量文本写法（`repr(str)`、`repr(list[str])`）。
///
/// 验证器的违规消息与规则错误消息里出现 Python 的 `{cid!r}` 与列表 repr；Dart 端输出要与
/// Python 引擎逐字节一致（parity），因此在这里复刻。
library;

/// Python `repr(text)`：默认单引号；含单引号且不含双引号时用双引号；转义反斜杠、引号、
/// `\n` `\r` `\t` 与其他控制字符（`\xNN`）。
String pyRepr(String text) {
  final quote = text.contains("'") && !text.contains('"') ? '"' : "'";
  final buffer = StringBuffer(quote);
  for (final rune in text.runes) {
    switch (rune) {
      case 0x5C:
        buffer.write(r'\\');
      case 0x0A:
        buffer.write(r'\n');
      case 0x0D:
        buffer.write(r'\r');
      case 0x09:
        buffer.write(r'\t');
      default:
        if (rune == quote.codeUnitAt(0)) {
          buffer.write('\\$quote');
        } else if (rune < 0x20 || rune == 0x7F) {
          buffer.write('\\x${rune.toRadixString(16).padLeft(2, '0')}');
        } else {
          buffer.writeCharCode(rune);
        }
    }
  }
  buffer.write(quote);
  return buffer.toString();
}

/// Python `repr(list_of_str)`：`['a', 'b']`。
String pyListRepr(Iterable<String> items) =>
    '[${items.map(pyRepr).join(', ')}]';

/// Python 的字符串比较（按 Unicode 码点；`sorted(list_of_str)` 的顺序）。与 Dart
/// `String.compareTo`（UTF-16 码元）只在 U+E000–U+FFFF 与增补平面字符相比时不同。
int compareCodePoints(String a, String b) {
  final ia = a.runes.iterator;
  final ib = b.runes.iterator;
  while (true) {
    final hasA = ia.moveNext();
    final hasB = ib.moveNext();
    if (!hasA || !hasB) {
      return hasA == hasB ? 0 : (hasA ? 1 : -1);
    }
    if (ia.current != ib.current) {
      return ia.current < ib.current ? -1 : 1;
    }
  }
}
