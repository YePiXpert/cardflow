# CardFlow 移动端

Flutter iOS 本地客户端。依赖版本见 `pubspec.yaml` 与锁文件。

```sh
flutter pub get
flutter analyze
flutter test
cd packages/cardflow_domain
dart pub get
dart test
```

规则协议在 `../../packages/rules-protocol/`，产品和架构规格在根目录 `docs/`。
安装包通过 `.github/workflows/mobile.yml` 构建，iOS 安装由持有者自行签名。
原始开发交接、真机诊断和个人环境记录保存在维护者私有资料库。
截图与诊断仅使用合成数据，生成的 `evidence/` 内容不得提交。
