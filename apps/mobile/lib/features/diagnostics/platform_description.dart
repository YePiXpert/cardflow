import 'package:flutter/foundation.dart';

/// 运行平台的描述。
@immutable
class PlatformDescription {
  const PlatformDescription({
    required this.osName,
    required this.osVersion,
    required this.dartVersion,
    required this.localeName,
  });

  /// 系统名称，如 `ios`。
  final String osName;

  /// 系统版本，如 `Version 18.1 (Build 22B83)`。
  final String osVersion;

  /// Dart 运行时版本。
  final String dartVersion;

  /// 设备语言区域，如 `zh_CN`。
  final String localeName;
}
