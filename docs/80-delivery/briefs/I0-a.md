# 简报 I-0a · Flutter 工程骨架 + iOS 配置 + CI 出第一个未签名 IPA

派发：2026-10-18。对应 `ios-first-plan.md` 的 I0-3、I0-4、I0-8。若需重新派发，在开头加一句"先核对磁盘与 git 现状，不要重复创建"。

## 环境与规则
- 仓库 /projects/cardflow = `YePiXpert/cardflow`（公开，main）；`gh` 已登录；git 身份已配置。
- Flutter 3.47.7 在 /opt/flutter-sdk；本机只能 analyze / test / build web；iOS 构建只能在 GitHub Actions macOS runner。
- 用户无 Mac，用自有证书给未签名 IPA 签名安装；项目与 CI 不接触任何签名材料。
- 提交、代码、文档、CI 中不得出现 Claude/AI 署名或 trailer。
- 宿主是生产 VPS：不运行 docker；不改 /opt 下除 flutter-sdk 外的目录；不装系统包（需要则停下汇报）。
- 范围：apps/mobile/、.github/workflows/、evidence/i0/I0-a/、根 README 的"移动端"一节。Dart 依赖只能来自 architecture §11 版本表。
- 直接在 main 小步提交推送（CI 靠 push 触发），不开 PR；推送前核对未加入 build/、.dart_tool/、ios/Pods/、ephemeral、secrets。
- iOS 构建本任务最多触发 4 次。
- 必读：ios-first-plan.md、ADR-001、ADR-015、architecture §3/§11、ui-spec §1/§2/§3（尤其 §3.4、§3.5）。

## 1. Flutter 工程 apps/mobile
- `flutter create --platforms=ios,web --org li.yep --project-name cardflow`；Bundle ID 必须 `li.yep.cardflow`；不生成 android/。
- 依赖（写死补丁号）：flutter_riverpod、riverpod_annotation、riverpod_generator、go_router、intl、package_info_plus；dev：flutter_lints、build_runner、riverpod_generator。
- 目录：lib/app（入口、路由、主题）、lib/features/<模块>（onboarding/overview/cards/planner/promotions/settings 空页面 + diagnostics）、lib/domain（空）、lib/data（空）。
- 五主导航按 ui-spec §1；每页显示页名与"首次空白"状态文案（ui-spec §2）。
- 主题 token 集中一个文件；浅/深色；文字随系统缩放；触控 ≥44pt。
- `MoneyText`：整数最小单位 + 币种；位数表 CNY/USD/EUR/HKD/GBP/MOP/TWD=2、JPY/KRW/VND=0、KWD/BHD/JOD=3；等宽数字；负数语义词/颜色；隐藏金额模式。analysis_options 写明 lib/domain 禁止 double（规则下一任务实现）。
- 诊断页（设置 Tab）：版本/构建号、系统版本（dart:io）、构建类型、Bundle ID、"加密库状态：待下一阶段"占位、内存环形日志（≤500 条，不含金额与正文）、"复制诊断信息"。
- analysis_options：flutter_lints + strict-casts/inference/raw-types；`flutter analyze --fatal-infos` 零输出。
- 测试：五 Tab 可达；MoneyText（0 位、3 位小数币种、负数、隐藏）；诊断页渲染。

## 2. iOS 配置
- 最低 iOS 15.0（Podfile 与 IPHONEOS_DEPLOYMENT_TARGET）。
- ios/Flutter/CardFlow.xcconfig：`PRODUCT_BUNDLE_IDENTIFIER = li.yep.cardflow`、`DEVELOPMENT_TEAM =`、`CODE_SIGN_STYLE = Manual`、`CODE_SIGN_IDENTITY =`；由 Debug/Release/Profile.xcconfig include；pbxproj 中硬编码的 Bundle ID 改为引用；仓库无 Team ID。
- Info.plist：CFBundleDisplayName=卡序；CFBundleLocalizations zh_CN、en；暂无权限用途说明；无 UIBackgroundModes。
- PrivacyInfo.xcprivacy：Flutter 常见 Required Reason API（UserDefaults、文件时间戳、系统启动时间、磁盘空间）；NSPrivacyTracking=false。
- 不加 entitlement、App Group、推送。

## 3. CI `.github/workflows/mobile.yml`
- `permissions: contents: read`；按 ref 的并发组。
- job `dart`（ubuntu-latest；push/pull_request，paths 过滤）：subosito/flutter-action（3.47.7 stable，cache）→ pub get → `dart format --output=none --set-exit-if-changed .` → `flutter analyze --fatal-infos` → `flutter test` → `flutter build web --release`。
- job `ios-unsigned`（macos-26；仅 workflow_dispatch 或 `ios-v*` 标签）：pub get → `flutter build ios --release --no-codesign`（不用 `build ipa`）→ `mkdir Payload && cp -R build/ios/iphoneos/Runner.app Payload/ && zip -qry cardflow-unsigned-<sha>.ipa Payload` → 校验 Info.plist（CFBundleIdentifier、MinimumOSVersion 15.0）→ upload-artifact（14 天）；失败时上传构建日志。
- 固定 action 大版本并用 `gh api` 核实存在；注释写明 macOS 分钟 10 倍、只手动触发。不加服务端 Python CI。

## 4. 走通一次
本机 analyze/test/build web 存证 → 推送等 `dart` 绿 → `gh workflow run mobile.yml --ref main` 触发 ios-unsigned → `gh run download` → `unzip -l` + plistlib 检查（CFBundleIdentifier、CFBundleShortVersionString、MinimumOSVersion、无 embedded.mobileprovision）→ 记录 artifact URL、大小、sha256 → 更新根 README"移动端"一节（本机命令、触发构建、下载 artifact、用户签名安装的通用步骤：Payload/Runner.app 结构、嵌套 Frameworks 一并签名、Bundle ID 与签名身份不变才能覆盖安装）。

## 验收（evidence/i0/I0-a/）
flutter-doctor.txt、analyze.txt、test.txt、build-web.txt、ci-dart-run.txt、ci-ios-run.txt、ipa-inspect.txt、git-log.txt。

## 回复格式
1. 完成项与路径；2. 验收结果；3. artifact 地址与安装注意（给用户，简短）；4. 偏离/疑问（CI 上的 iOS 原生问题）；5. 给下一任务（I-0b 加密库、I-0c Dart 引擎）的接口说明。
