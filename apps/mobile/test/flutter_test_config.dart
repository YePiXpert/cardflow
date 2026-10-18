// 所有测试的全局配置（flutter_test 约定的文件名）。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // tap() 落点被别的组件挡住时直接失败，而不是只打印警告（曾在 CI 上因此偶发失败：
  // 按钮滚到 AppBar 底下，点击落空）。
  WidgetController.hitTestWarningShouldBeFatal = true;
  await testMain();
}
