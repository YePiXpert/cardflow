# 公开仓库的隐私约定

公开内容只包括通用代码、示例配置、合成样本和可复现测试。
真实节点、订阅链接、账号、会话、家庭或财务资料、运行报告、原始截图和运维交接应放在
维护者的私有资料库或本机 `private-local/`。密码和密钥使用密码管理器或部署平台 Secrets。
示例网络地址使用 RFC 5737 文档地址，域名使用 `example.com`。

## 提交前

安装 Python 3 与 Gitleaks 8.30.1，然后在每个开发副本启用检查：

```sh
git config core.hooksPath .githooks
python scripts/check-public-files.py
gitleaks protect --staged --redact --no-banner
```

提交钩子检查暂存区；GitHub Actions 检查推送后的源码树。GitHub 密钥推送保护负责拦截
其支持的密钥格式。CI 是事后检查，不能取代本地检查；不要绕过钩子提交私人资料。
`.gitignore` 不能清除已经跟踪的文件或历史提交。

Gitleaks 仅对逐项核对过的合成测试值、公开协议常量设定“文件路径 + 精确匹配值”例外，
禁止整目录跳过测试文件。修改例外必须先确认它不是真实凭据。
检测不到不代表没有隐私信息，图片、业务文本与真实节点地址仍需人工核对。

如果已经泄露密钥，先撤销或更换；历史、标签、Release、Actions 产物和他人副本需另行处理。
本次资料迁移未重写 Git 历史。
