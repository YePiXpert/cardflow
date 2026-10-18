# 简报 I-0b · 加密本地库 PoC-1 + 诊断页登记加密状态 + 第二个未签名 IPA

派发：2026-10-18。对应 `ios-first-plan.md` 的 I0-5。若需重新派发，在开头加一句"先核对磁盘与 git 现状，不要重复创建"。

## 环境与规则（与 I-0a 相同）
- 仓库 /projects/cardflow = `YePiXpert/cardflow`（公开，main）；`gh` 已登录；git 身份已配置。
- Flutter 3.47.7 在 /opt/flutter-sdk（`export PATH=/opt/flutter-sdk/bin:$PATH`）；本机有 gcc 14，可编译构建钩子；本机只能 analyze / test / build web；iOS 构建只在 GitHub Actions `macos-26`。
- 用户无 Mac，自有证书签名安装未签名 IPA；项目与 CI 不接触签名材料。
- 提交、代码、文档、CI 中不得出现 Claude/AI 署名或 trailer。
- 宿主是生产 VPS：不运行 docker；不改 /opt 下除 flutter-sdk 外的目录；不装系统包；只停自己启动的进程。
- 范围：apps/mobile/、.github/workflows/mobile.yml（如需）、evidence/i0/I0-b/、根 README"移动端"一节。Dart 依赖只能来自 architecture §11 版本表（drift 2.35.2、drift_flutter 0.3.1、sqlite3 3.7.1、flutter_secure_storage 11.2.0；回退方案 sqflite_sqlcipher 3.4.1）；表外依赖先停下汇报。
- 直接在 main 小步提交推送，不开 PR；推送前核对未加入 build/、.dart_tool/、ephemeral、secrets。
- iOS 构建本任务最多触发 3 次。
- 证据存 evidence/i0/I0-b/（tee）。不把 mock 当完成；规格矛盾选最保守做法并写进"偏离/疑问"。
- 必读：ios-first-plan.md、ADR-001、docs/60-ops-security/security-privacy.md §3（STORAGE/CRYPTO/AUTH）与 §5（设备数据库密钥）、docs/40-data-api/data-model.md §8、I-0a 汇报中的接口说明（`lib/features/diagnostics/crypto_status.dart` 的 `cryptoLibraryStatus`、`diagnosticLogProvider` 用法、测试辅助函数、SwiftPM/native-assets 说明）、apps/mobile/README.md。

## 1. 加密数据库（lib/data/db/）
- drift + sqlite3，加密经 sqlite3 包的构建钩子选择 sqlite3mc（pubspec `hooks.user_defines`；精确写法以 drift 文档"Encryption"页与 sqlite3 包 README 为准，把查到的出处记入证据）。Flutter 3.47.7 默认开启 native-assets，不需要 Podfile。
- **密钥**：首次启动用 `Random.secure()` 生成 32 字节，存 flutter_secure_storage（iOS Keychain，accessibility = unlocked_this_device；不进 iCloud 备份）；以原始密钥形式传给 sqlite3mc（避免口令派生），密钥绝不进日志、诊断报告、异常消息。
- **失败即止**：打开后执行 `PRAGMA cipher_version`，为空则拒绝使用该库并抛出带错误码的异常（不得退回明文库）；密钥错误时打开失败同样抛错误码。
- 最小 schema：只建 `meta` 表（schema_version、created_at），真正的业务表在 I-1；提供 drift 数据库类、迁移策略骨架、`databaseProvider`。
- Web：`flutter build web` 必须继续通过（编译烟雾）；Web 运行时不要求可用，用条件导入或"不支持"实现。
- **回退**：若钩子方案在 macOS CI 构建失败且本机无法定位原因，最多 2 次 iOS 尝试后切换 sqflite_sqlcipher 3.4.1（ADR-001 备选），保持同样的密钥与 cipher_version 检查；在汇报与 README 写明原因。

## 2. 诊断页
- 把 `cryptoLibraryStatus` 的占位换成真实检查：成功显示 cipher 名称与版本；失败显示错误码。密钥存在性只显示"已生成/未生成"。
- 新增"数据库基准"按钮：建临时加密库 → 事务内写入 10 万行 → 关闭 → 重新打开并 COUNT，显示打开耗时与查询耗时（ms），结果进入可复制的诊断报告（报告正文可含数字；环形日志按既有规则脱敏）。这是 ADR-001 PoC-1 退出条件"10 万行冷启动 <1 s"的真机依据，由用户回传。
- 用 `diagnosticLogProvider` 记录 db.opened / db.open_failed（只记错误码）。

## 3. 测试
- 真实钩子编译下（本机 gcc / CI ubuntu）：开关往返；cipher_version 非空；错误密钥打开失败；无密钥拒绝打开；密钥生成只发生一次（用假 secure storage）；基准函数小 N 单元测试；日志与报告不含密钥。
- 如本机编译钩子失败，先排查；确实无法本地运行的测试必须在 CI dart job 上跑，本机以明确的失败信息提示，不得静默跳过。

## 4. iOS
- 不加任何 entitlement（flutter_secure_storage 默认钥匙串不需要 access group）；不加新的 Info.plist 用途说明；保持 `test/ios/ios_config_test.dart` 的不变量。

## 5. 走通一次
本机 analyze/test/build web 存证 → 推送等 dart job 绿 → 触发 ios-unsigned → `gh run download` → 检查 IPA（Bundle ID、MinimumOSVersion、包内含 sqlite3mc 相关二进制或框架）→ 记录 artifact URL、大小、sha256 → 更新根 README"移动端"一节与 apps/mobile/README.md（加密方案、密钥存放、失败即止）。

## 验收（evidence/i0/I0-b/）
hook-source.txt（文档出处与 pubspec 片段）、analyze.txt、test.txt、build-web.txt、ci-dart-run.txt、ci-ios-run.txt、ipa-inspect.txt、git-log.txt。

## 回复格式
1. 完成项与路径；2. 验收结果；3. artifact 地址与用户需回传的内容（cipher_version、基准毫秒数、源码版本）；4. 偏离/疑问（含是否回退）；5. 给 I-0c（Dart 引擎移植）的接口说明：数据库类与 provider 用法、如何加表与迁移、测试辅助。
