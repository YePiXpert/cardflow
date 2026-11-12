# 卡序 CardFlow

消费前比较现有信用卡，选择额度足够且预计还款日更晚的一张。
当前客户端为 iOS、纯本地使用；后端实现保留在源码中。

公开样本为合成数据。真实账单、个人设备诊断、运行日志与实例运维资料不放在此仓库。

## 目录

| 路径 | 内容 |
| --- | --- |
| `apps/mobile/` | Flutter iOS 客户端与测试 |
| `services/api/` | Python API 与规则实现 |
| `packages/rules-protocol/` | 规则协议、合成 fixtures 和跨语言验证 |
| `poc/engine_reference/` | 参考引擎 |
| `deploy/` | 通用部署模板，实际配置与密钥不入库 |
| `docs/` | 产品、架构、数据、安全和测试规格 |

## 开发与验证

安装 Flutter 和项目声明的 Python/uv 依赖，再按各包 README 运行验证。
客户端入口见 [移动端说明](apps/mobile/README.md)，规格入口见 [文档索引](docs/README.md)。

```sh
cd apps/mobile
flutter pub get
flutter analyze
flutter test
```

## 安装

[GitHub Releases](https://github.com/YePiXpert/cardflow/releases) 提供公开版本。
未签名 IPA 需要使用自己的签名身份安装；升级使用相同签名身份和 Bundle ID。
卸载前先备份应用内数据。不要把签名证书、账单或含真实金额的截图作为公开反馈附件。

## 私人资料与贡献

原验收日志、真机回传、内部交接和实例部署手册已迁到维护者私有资料库。
公开仓库保留通用代码、合成测试和可复现检查。
提交前请运行 `python scripts/check-public-files.py` 并阅读 [隐私约定](PRIVACY.md)。
