import 'dart:io' show Platform;

import 'platform_description.dart';

/// 原生平台：系统名称与版本来自 dart:io 的 [Platform]。
PlatformDescription describePlatform() => PlatformDescription(
  osName: Platform.operatingSystem,
  osVersion: Platform.operatingSystemVersion,
  dartVersion: Platform.version.split(' ').first,
  localeName: Platform.localeName,
);
