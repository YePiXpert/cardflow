import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'platform_description.dart';
import 'platform_info.dart';

part 'app_diagnostics.g.dart';

/// 构建时注入的源码提交（CI：`--dart-define=CARDFLOW_GIT_SHA=<sha>`）。本机构建为空。
const String injectedGitSha = String.fromEnvironment('CARDFLOW_GIT_SHA');

/// 当前构建类型。
String currentBuildMode() {
  if (kReleaseMode) {
    return 'release';
  }
  if (kProfileMode) {
    return 'profile';
  }
  return 'debug';
}

/// 源码版本的展示文字：CI 构建显示提交前 12 位，本机构建显示"本机构建"。
String describeSourceRevision(String gitSha) {
  final sha = gitSha.trim();
  if (sha.isEmpty) {
    return '本机构建';
  }
  return sha.length > 12 ? sha.substring(0, 12) : sha;
}

/// 诊断页"应用"与"系统"两节的数据。不含任何用户数据。
@immutable
class AppDiagnostics {
  const AppDiagnostics({
    required this.appName,
    required this.version,
    required this.buildNumber,
    required this.bundleId,
    required this.buildMode,
    required this.sourceRevision,
    required this.platform,
  });

  /// 显示名称（iOS 为 CFBundleDisplayName）。
  final String appName;

  /// 版本号（CFBundleShortVersionString）。
  final String version;

  /// 构建号（CFBundleVersion）。
  final String buildNumber;

  /// Bundle ID（重签工具若改写了它，这里能看出来）。
  final String bundleId;

  /// release / profile / debug。
  final String buildMode;

  /// 源码提交或"本机构建"。
  final String sourceRevision;

  /// 系统与运行时。
  final PlatformDescription platform;
}

/// 读取 App 与系统信息（package_info_plus + dart:io Platform）。
@riverpod
Future<AppDiagnostics> appDiagnostics(Ref ref) async {
  final info = await PackageInfo.fromPlatform();
  return AppDiagnostics(
    appName: info.appName,
    version: info.version,
    buildNumber: info.buildNumber,
    bundleId: info.packageName,
    buildMode: currentBuildMode(),
    sourceRevision: describeSourceRevision(injectedGitSha),
    platform: describePlatform(),
  );
}
