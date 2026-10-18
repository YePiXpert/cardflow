// iOS 工程配置的不变量（I0-8）。在 Linux CI 上就能拦住签名材料入库、Bundle ID 被改、
// 最低系统版本漂移、隐私清单丢失等问题，不必等 macOS 构建才发现。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String bundleId = 'li.yep.cardflow';
const String pbxprojPath = 'ios/Runner.xcodeproj/project.pbxproj';

String read(String path) => File(path).readAsStringSync();

/// 只看纳入版本控制的 iOS 文件（跳过 ephemeral、Pods、.symlinks 等生成目录）。
Iterable<File> trackedIosFiles() sync* {
  const skipped = <String>['/ephemeral/', '/Pods/', '/.symlinks/', '/build/'];
  for (final entity in Directory('ios').listSync(recursive: true)) {
    if (entity is! File) {
      continue;
    }
    final path = entity.path.replaceAll(r'\', '/');
    if (skipped.any(path.contains) ||
        path.endsWith('Generated.xcconfig') ||
        path.endsWith('flutter_export_environment.sh') ||
        path.contains('GeneratedPluginRegistrant')) {
      continue;
    }
    yield entity;
  }
}

/// pbxproj 中所有 XCBuildConfiguration 块：块 ID → 块文本。
Map<String, String> buildConfigurations(String pbxproj) => <String, String>{
  for (final m in RegExp(
    r'\t\t([0-9A-F]{24}) /\* \w+ \*/ = \{\n\t\t\tisa = XCBuildConfiguration;\n(.*?)\n\t\t\};',
    dotAll: true,
  ).allMatches(pbxproj))
    m.group(1)!: m.group(2)!,
};

void main() {
  group('Bundle ID 与签名参数', () {
    test('Bundle ID 只在 Flutter/CardFlow.xcconfig 中定义', () {
      final xcconfig = read('ios/Flutter/CardFlow.xcconfig');
      expect(
        RegExp(
          r'^PRODUCT_BUNDLE_IDENTIFIER = li\.yep\.cardflow$',
          multiLine: true,
        ).hasMatch(xcconfig),
        isTrue,
      );
      final pbxproj = read(pbxprojPath);
      expect(pbxproj, isNot(contains(bundleId)));
      expect(pbxproj, isNot(contains('li.yep')));
    });

    test('签名参数为空，由用户在安装前自行签名', () {
      final xcconfig = read('ios/Flutter/CardFlow.xcconfig');
      expect(
        xcconfig,
        matches(RegExp(r'^DEVELOPMENT_TEAM =\s*$', multiLine: true)),
      );
      expect(
        xcconfig,
        matches(RegExp(r'^CODE_SIGN_STYLE = Manual$', multiLine: true)),
      );
      expect(
        xcconfig,
        matches(RegExp(r'^CODE_SIGN_IDENTITY =\s*$', multiLine: true)),
      );
      expect(xcconfig, contains('#include? "CardFlow.local.xcconfig"'));
      expect(
        read('ios/.gitignore'),
        contains('Flutter/CardFlow.local.xcconfig'),
      );
    });

    test('Debug/Release.xcconfig 引入 CardFlow.xcconfig（在 Generated 之后）', () {
      for (final name in <String>['Debug', 'Release']) {
        final lines = read('ios/Flutter/$name.xcconfig')
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.startsWith('#include'))
            .toList();
        final generated = lines.indexOf('#include "Generated.xcconfig"');
        final cardflow = lines.indexOf('#include "CardFlow.xcconfig"');
        expect(generated, isNonNegative, reason: name);
        expect(cardflow, greaterThan(generated), reason: name);
      }
    });

    test('每个 target 配置都以 Debug/Release.xcconfig 为基础，且不覆盖 Bundle ID 与签名', () {
      final pbxproj = read(pbxprojPath);
      final configs = buildConfigurations(pbxproj);
      expect(configs, hasLength(9));
      final targetConfigs = configs.values.where(
        (body) =>
            body.contains('INFOPLIST_FILE = Runner/Info.plist') ||
            body.contains('BUNDLE_LOADER'),
      );
      expect(targetConfigs, hasLength(6));
      for (final body in targetConfigs) {
        expect(
          body,
          matches(
            RegExp(
              r'baseConfigurationReference = [0-9A-F]{24} /\* (Debug|Release)\.xcconfig \*/;',
            ),
          ),
        );
        expect(body, isNot(contains('DEVELOPMENT_TEAM')));
        expect(body, isNot(contains('CODE_SIGN_STYLE')));
        expect(body, isNot(contains('CODE_SIGN_IDENTITY')));
      }
      final runnerBundleIds = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = (.*);')
          .allMatches(pbxproj)
          .map((m) => m.group(1))
          .toSet();
      expect(runnerBundleIds, <String>{r'"$(inherited).RunnerTests"'});
    });

    test('仓库内没有团队 ID、证书、描述文件或 entitlements', () {
      final teamId = RegExp(
        r'(DEVELOPMENT_TEAM|DevelopmentTeam)\s*=\s*"?[A-Z0-9]{10}"?',
      );
      for (final file in trackedIosFiles()) {
        final path = file.path;
        expect(
          path,
          isNot(
            matches(
              RegExp(
                r'\.(entitlements|mobileprovision|p12|cer|certSigningRequest)$',
              ),
            ),
          ),
        );
        if (path.endsWith('.png')) {
          continue;
        }
        final text = file.readAsStringSync();
        expect(teamId.hasMatch(text), isFalse, reason: path);
        expect(text, isNot(contains('PROVISIONING_PROFILE')), reason: path);
        expect(text, isNot(contains('CODE_SIGN_ENTITLEMENTS')), reason: path);
      }
    });
  });

  group('最低系统版本', () {
    test('Xcode 工程的 IPHONEOS_DEPLOYMENT_TARGET 全部为 15.0', () {
      final values = RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = ([^;]+);')
          .allMatches(read(pbxprojPath))
          .map((m) => m.group(1))
          .toList();
      expect(values, isNotEmpty);
      expect(values.toSet(), <String>{'15.0'});
    });

    test('若引入 CocoaPods，Podfile 必须声明 platform :ios, 15.0', () {
      final podfile = File('ios/Podfile');
      if (!podfile.existsSync()) {
        // 当前所有插件都走 Swift Package Manager（Flutter 3.47 默认），没有 Podfile。
        return;
      }
      expect(
        RegExp(
          r"^platform :ios, '15\.0'$",
          multiLine: true,
        ).hasMatch(podfile.readAsStringSync()),
        isTrue,
      );
    });
  });

  group('Info.plist', () {
    final plist = read('ios/Runner/Info.plist');

    String? stringValue(String key) =>
        RegExp('<key>$key</key>\\s*<string>([^<]*)</string>')
            .firstMatch(plist)
            ?.group(1);

    test('显示名为"卡序"，Bundle ID 来自构建设置', () {
      expect(stringValue('CFBundleDisplayName'), '卡序');
      expect(
        stringValue('CFBundleIdentifier'),
        r'$(PRODUCT_BUNDLE_IDENTIFIER)',
      );
    });

    test('声明 zh_CN 与 en 两种语言', () {
      final array = RegExp(
        r'<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>',
        dotAll: true,
      ).firstMatch(plist);
      expect(array, isNotNull);
      final values = RegExp(r'<string>([^<]*)</string>')
          .allMatches(array!.group(1)!)
          .map((m) => m.group(1))
          .toList();
      expect(values, <String>['zh_CN', 'en']);
    });

    test('没有权限用途说明、后台模式或 App Group', () {
      expect(
        plist,
        isNot(matches(RegExp(r'<key>NS\w+UsageDescription</key>'))),
      );
      expect(plist, isNot(contains('UIBackgroundModes')));
      expect(plist, isNot(contains('application-groups')));
    });
  });

  group('PrivacyInfo.xcprivacy', () {
    final manifest = read('ios/Runner/PrivacyInfo.xcprivacy');

    test('不跟踪、不收集数据', () {
      expect(
        manifest,
        matches(RegExp(r'<key>NSPrivacyTracking</key>\s*<false/>')),
      );
      expect(
        manifest,
        matches(RegExp(r'<key>NSPrivacyTrackingDomains</key>\s*<array/>')),
      );
      expect(
        manifest,
        matches(RegExp(r'<key>NSPrivacyCollectedDataTypes</key>\s*<array/>')),
      );
    });

    test('登记 Flutter 应用常见的 Required Reason API', () {
      const expected = <String, String>{
        'NSPrivacyAccessedAPICategoryUserDefaults': 'CA92.1',
        'NSPrivacyAccessedAPICategoryFileTimestamp': 'C617.1',
        'NSPrivacyAccessedAPICategorySystemBootTime': '35F9.1',
        'NSPrivacyAccessedAPICategoryDiskSpace': 'E174.1',
      };
      for (final MapEntry(key: category, value: reason) in expected.entries) {
        expect(
          manifest,
          matches(
            RegExp(
              '<string>$category</string>\\s*'
              '<key>NSPrivacyAccessedAPITypeReasons</key>\\s*'
              '<array>\\s*<string>${RegExp.escape(reason)}</string>',
            ),
          ),
          reason: category,
        );
      }
    });

    test('已加入 Runner target 的资源构建阶段', () {
      final pbxproj = read(pbxprojPath);
      final fileRef = RegExp(
        r'([0-9A-F]{24}) /\* PrivacyInfo\.xcprivacy \*/ = \{isa = PBXFileReference;',
      ).firstMatch(pbxproj);
      expect(fileRef, isNotNull);
      final buildFile = RegExp(
        '([0-9A-F]{24}) /\\* PrivacyInfo\\.xcprivacy in Resources \\*/ = '
        '\\{isa = PBXBuildFile; fileRef = ${fileRef!.group(1)} ',
      ).firstMatch(pbxproj);
      expect(buildFile, isNotNull);
      final resourcesPhase = RegExp(
        r'97C146EC1CF9000F007C117D /\* Resources \*/ = \{.*?files = \((.*?)\);',
        dotAll: true,
      ).firstMatch(pbxproj);
      expect(resourcesPhase?.group(1), contains(buildFile!.group(1)));
    });
  });
}
