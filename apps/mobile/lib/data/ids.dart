import 'dart:math';

/// 本地主键：UUID v4（RFC 4122 第 4 版，122 位随机）的小写字符串形式
/// `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`（y 为 8/9/a/b）。
///
/// 随机数默认来自 [Random.secure]（系统安全随机数）；不引入 uuid 包（不在 architecture §11 表内）。
/// 生成的字符串也满足规则协议 v1 的 `Id` 格式（`^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$`）。
String newUuidV4([Random? random]) {
  final source = random ?? _secureRandom;
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // 版本 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 变体
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

final Random _secureRandom = Random.secure();

final RegExp _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// 是否为 [newUuidV4] 产生的格式。
bool isUuidV4(String value) => _uuidV4.hasMatch(value);
