# ADR-015 移动端分发：用户自签安装，v1 不上架

状态：已接受 · 2026-10-16（用户决定："我到时候自签就行"）

背景：原计划 iOS 经 Apple Developer Program + TestFlight 交付，Android 由用户提供签名密钥出正式 AAB/APK；金融/敏感信息类 App 上架还可能被要求法人主体（S12 5.1.1(ix)）。本 App 以个人自用起步。
决策：v1 不上架 App Store / Google Play，不走 TestFlight。项目交付可自签的构建产物与签名说明；签名由用户用自己的签名身份完成，密钥与证书不进仓库、不进 CI、不交给代理。
- Android：`flutter build apk --release`（可按 ABI 拆分），不出 AAB。用户本机签名：Gradle 读取不进仓库的 `key.properties`，或对未签名 APK 执行 `zipalign` + `apksigner`。
- iOS：在 macOS + Xcode 上构建。用户用自己的 Apple ID（免费或付费个人账号）在 Xcode 中签名并装到真机；或用 `flutter build ios --release --no-codesign` 打出未签名 IPA，再用自选工具签名。
- Bundle ID / applicationId 由用户在首次安装前确定，之后不再改；工程用 xcconfig / Gradle 参数注入，不硬编码团队 ID。

后果：
1. 签名身份决定本地数据能否保留。只有签名身份不变才能覆盖安装：Android 换密钥（未做 v3 密钥轮换时）只能卸载重装，本地库与 Keystore 密钥一并清除；iOS 换团队 ID 无法覆盖安装，钥匙串访问组也随之变化，数据库密钥读不到（待真机核验）。因此更换签名身份视同换设备：先备份或同步，再按 UF-9 恢复（security-privacy §5）。签名说明必须写明这一点；由 TC-MOB-14 覆盖。
2. iOS 免费 Apple ID 的描述文件约 7 天过期：过期后 App 无法启动但数据仍在，用同一 Apple ID 重签后覆盖安装即可；付费个人账号约 1 年（均待核验）。
3. 自签条件下的能力差异在 WP-51 真机记录：免费账号没有 APNs 推送（ADR-010 以本地通知为核心，不受影响）；分享扩展依赖的 App Group 在自签构建上是否可用待核验（T-024），不可用时回退为"用其他应用打开"（注册文档类型）+ 应用内文件选择；第三方重签工具可能改写 Bundle ID / App Group（待核验）。
4. 篡改检测（SEC-M-21~22）不硬编码证书指纹：期望指纹在构建时由用户注入，未配置则跳过，只提示不阻断。
5. 上架类检查（App Review 法人主体与 3.2.1(viii)、Play SMS 权限声明表、Play 数据安全表）不再是 v1 发布前提，security-privacy §10 保留为"将来上架时"检查项；隐私清单仍随工程维护。
6. 验收证据：Android = 未签名 APK 哈希 + 测试密钥签名后的安装与覆盖升级记录 + 用户自签安装确认（E-21）；iOS = Mac 构建记录 + 用户自签真机安装记录（E-22）。

修订（2026-10-18）：用户没有 Mac，只需要 iOS 端。构建在 GitHub Actions 的 `macos-26` runner 上进行：`flutter build ios --release --no-codesign` → 未签名 IPA 作为 workflow artifact；用户下载后用自有证书与非 Mac 签名工具签名安装。项目不接触证书、不在 CI 存放签名材料。v1 不使用任何特殊 entitlement（不做推送、不做分享扩展），任何证书重签都能安装与覆盖升级。Android 构建不再是 v1 目标。详见 `80-delivery/ios-first-plan.md`。

备选：TestFlight / App Store（放弃：需付费账号与审核，金融类可能要求法人主体）；企业证书或第三方共享证书（不推荐：可能随时被吊销导致无法启动，且签名方不可控）。
重新评估：用户决定上架时另立 ADR，并恢复 security-privacy §10 的上架检查项。
