import 'platform_description.dart';

/// 没有 dart:io 的平台（Web 编译烟雾测试）。
PlatformDescription describePlatform() => const PlatformDescription(
  osName: 'web',
  osVersion: '不适用',
  dartVersion: '不适用',
  localeName: '不适用',
);
