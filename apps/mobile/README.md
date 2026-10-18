# apps/mobile — 卡序 iOS App（Flutter）

本目录是卡序的 Flutter 工程（I-0a 骨架）。构建、触发 iOS 构建、下载与签名安装见根 README 的"移动端"一节；计划见 `docs/80-delivery/ios-first-plan.md`。

## 目录

| 路径 | 内容 |
|---|---|
| `lib/main.dart` | 入口：建立 Provider 容器、安装错误钩子、启动 App |
| `lib/app/` | App 外壳：`app.dart`（MaterialApp、语言）、`router.dart`/`routes.dart`（go_router，五个主导航）、`shell/`（底部 Tab）、`theme/`（`tokens.dart` 设计 token 唯一来源，`app_theme.dart` 浅色/深色主题）、`money/`（金额格式与 `minorDigits` 表、全局金额隐藏开关）、`widgets/`（`MoneyText`、首次空白态等） |
| `lib/features/<模块>/` | 功能模块：`overview` 总览、`cards` 卡包、`planner` 规划、`promotions` 发现、`settings` 我的、`onboarding` 欢迎页、`diagnostics` 诊断页与内存日志 |
| `lib/domain/` | 纯 Dart 领域层（下一任务移植引擎；禁止 double，见 `analysis_options.yaml` 末尾的约定） |
| `lib/data/` | 数据层（下一任务：加密 drift） |
| `test/` | 单元与 widget 测试；`test/ios/ios_config_test.dart` 在 Linux 上检查 iOS 工程配置 |
| `ios/` | iOS 工程：`Flutter/CardFlow.xcconfig`（Bundle ID 与签名参数的唯一来源）、`Runner/PrivacyInfo.xcprivacy`（隐私清单） |
| `web/` | 只用于 CI 的 Web 编译烟雾测试，不发布 |

## 约定

- 依赖版本写死到补丁号，取自 `docs/20-architecture/architecture.md` §11；表外依赖先评审再加。
- Riverpod 用代码生成（`@riverpod`）。改了带注解的文件后：`dart run build_runner build`，再 `dart format .`；生成的 `*.g.dart` 随源码提交（CI 不跑生成）。
- 颜色、字号、间距、圆角只从 `lib/app/theme/tokens.dart` 取；金额一律用 `MoneyText`（整数最小单位 + 币种）。
- 诊断日志只记事件标识与脱敏摘要：不得写入金额、卡号、账单正文；数字会被替换为 `#`。
- iOS：最低 15.0；插件走 Swift Package Manager（Flutter 3.47 默认），目前没有 Podfile。若将来引入只支持 CocoaPods 的插件，Podfile 必须写 `platform :ios, '15.0'`（测试会检查）。
- 不提交任何签名材料（证书、描述文件、团队 ID、entitlements）。在 Mac 上自行签名时，把团队 ID 写进不入库的 `ios/Flutter/CardFlow.local.xcconfig`。
- 重新运行 `flutter create` 时必须带 `--org li.yep`，否则会生成错误的包名。
