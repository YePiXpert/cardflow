/// 协议错误。
library;

/// 文档违反协议 v1（Python `ProtocolError`）。
///
/// [path] 是指向违规值的 RFC 6901 JSON Pointer（`''` = 整个文档）；[message] 只说明违反的规则，
/// 从不回显原值（ID、日期、利率、数字或其片段都不出现，R3E-12）。
final class ProtocolError implements Exception {
  /// 协议错误。
  const ProtocolError(this.path, this.message);

  /// JSON Pointer。
  final String path;

  /// 违反的规则。
  final String message;

  @override
  String toString() => '${path.isEmpty ? '<document>' : path}: $message';
}
