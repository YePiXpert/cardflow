# sources.md · 官方来源、核验日期、适用范围与不确定点

核验日期统一为 **2026-10-16**（Asia/Shanghai）。"核验方式"：直接 = 本会话用抓取工具读到页面正文并逐字对照；间接 = 由源页链接到的其他官方页面补充；失败 = 未取得正文。抓取日期不等于规则生效日期；银行规则是否适用于具体账户仍需按账户核验。原始响应缓存（本轮临时目录，不随文档交付）：`scratchpad/data/`、`scratchpad/fetched/`。

## 1. 任务书附录 A 来源（S01–S16）

| 编号 | 资料 | URL | 文档日期 | 核验方式 | 适用范围（本项目） | 关键事实（原文摘录） | 已知不确定点 |
|---|---|---|---|---|---|---|---|
| S01 | 招商银行：看懂账单上的日期 | https://cc.cmbchina.com/content/cusservice/43.htm | 未取得 | **失败**：HTTP 200 但返回 4,756 字节无正文的拦截页（curl 与抓取工具一致） | 招行账单日/到期日/免息期口径 | — | 需用户在浏览器端保存页面；规则状态 pending |
| S02 | 建设银行：用卡攻略—新手入门 | https://creditcard1.ccb.com/chn/2022-12/27/article_2022122709500329719.shtml | 发布时间 2022-12-27 | 直接 | 共享额度、分期占额、临额有效期、还款日固定 | "您名下所有建行信用卡共享信用额度"；"账单和现金分期余额会一直占用额度，随着每一期还款，逐期释放"；"临时额度（有效期一般为1个月）"；"到期还款日为每月固定日期" | 页面较旧；账单日定义、免息期计算、临额到期是否计入本期应还页面未提及 |
| S03 | 招商银行信用卡章程（第十三版） | https://cc.cmbchina.com/common/2019zc.htm | 未取得 | **失败**：同 S01 拦截页；检索到的官方 PDF（s3gw.cmbimg.com/…/20230710/59209ebd-….pdf）返回 404 | 免息资格、计息、最低还款、冲抵顺序、溢缴款、预授权 | — | 阻塞项 B-04：取得完整文本后再实现招行计息与冲抵顺序 |
| S04 | Apple：SMS and MMS Message Filtering | https://developer.apple.com/documentation/identitylookup/sms-and-mms-message-filtering | 页面未显示日期 | 直接（正文经 Apple 文档 JSON 数据源读取） | iOS 短信能力边界 | "IdentityLookup works only with SMS and MMS messages from unknown senders; it doesn't work with messages from senders in a user's Contacts list or with iMessage messages from any source."；"your Message Filter app extension can't access the network directly."；"Your app extension also can't write data to containers shared with the containing app." | 无 |
| S05 | Google Play：Use of SMS or Call Log permission groups | https://support.google.com/googleplay/android-developer/answer/10208820?hl=en | 未显示发布日期；含条款生效日 | 直接 | Android 短信适配器政策 | "Apps must be actively registered as the default SMS, Phone, or Assistant handler before prompting users…"；例外含 "SMS-based money management — For example, apps that track and manage budget"（READ_SMS/RECEIVE_SMS 等，须审核）；"personal loans or budgeting apps may not exfiltrate or share non-financial or personal SMS history of a user."；"Apps that fail to meet policy requirements or lack a Permissions Declaration Form may be removed from Google Play." | 2027-01-27 生效条款仅涉及 READ_CALL_LOG 的来电验证用途，与本项目无直接关系；例外须逐案审批 |
| S06 | Google：Choose Gmail API scopes | https://developers.google.com/workspace/gmail/api/auth/scopes | Last updated 2026-09-10 | 直接 + 间接（CASA 页） | 邮件自动导入的 OAuth 条件 | gmail.readonly、gmail.metadata 均为 Restricted；"View your email message metadata such as labels and headers, but not the email body."；"If you store restricted scope data on servers (or transmit), then you must go through a security assessment."；补充：support.google.com/cloud/answer/13465431 "applications requesting access to restricted scopes must undergo an annual security assessment"（CASA） | 无"只读某 label"的 scope；费用未在页面给出 |
| S07 | 银联国际：浦发银联信用卡境外交易返现活动 | https://m.unionpayintl.com/cardholderServ/serviceCenter/wap/merchant/1201718813891?type=1 | 页面未显示日期；活动期 2026-08-10 至 2026-12-31（北京时间） | 直接 | 活动规则模型的最小字段覆盖样本（不是推荐该卡或活动） | "北京时间2026年8月10日00：00-2026年12月31日23:00"；"未报名或报名不成功卡片无法参与活动一、活动二、活动三"；交易时间以"进入中国银联后台系统的时间为准"；"按消费入账时间先到先得"；"每卡每月返现上限300元"；"计算结果直接取小数点后两位，不作四舍五入处理"；"持卡人如发生退货、冲正、撤销等交易，将不进行返现"；"当月已返金额将在下月应返金额中扣除"；"返现池若未消耗完毕则自动作废，不计入下月返现池" | 单笔最低金额、名额、每卡封顶（活动四）页面未提及；"具体活动时间以实际开展为准" |
| S08 | Google OR-Tools：CP-SAT Solver | https://developers.google.com/optimization/cp/cp_solver | Last updated 2024-08-28 | 直接（含 cp_tasks 页） | 求解器状态契约与整数建模 | OPTIMAL "An optimal feasible solution was found."；FEASIBLE "A feasible solution was found, but we don't know if it's optimal."；INFEASIBLE "The problem was proven infeasible."；MODEL_INVALID "The given CpModelProto didn't pass the validation step."；UNKNOWN 适用于 "before something caused the solver to stop, such as a time limit, a memory limit, or a custom limit set by the user."；"the CP-SAT solver works over the integers"；`solver.parameters.max_time_in_seconds` | 纯可行性问题找到解时返回 OPTIMAL（cp_model.proto 枚举：UNKNOWN=0, MODEL_INVALID=1, FEASIBLE=2, INFEASIBLE=3, OPTIMAL=4） |
| S09 | Flutter：Offline-first support | https://docs.flutter.dev/app-architecture/design-patterns/offline-first | 2026-05-05（Flutter 3.47） | 直接 | 本地/远程数据层与同步 | "repositories act as the single source of truth"；写入离线优先 "first stores the new data in the database, and then attempts to send it to the API service" + `synchronized` 标志；同步时机：Timer、workmanager、connectivity_plus、下拉刷新、服务器推送 | 页面不涉及冲突解决，本项目另行设计（ADR-007） |
| S10 | Flutter：Build and release an iOS app | https://docs.flutter.dev/deployment/ios | 2026-07-31（Flutter 3.47） | 直接 + 间接（Apple Upcoming Requirements） | iOS 发布依赖 | "Xcode is required to build and release your app. You must use a device running macOS to follow this guide."；"you must first enroll in the Apple Developer Program."；补充：Apple 自 2026-04-28 起 "Apps uploaded to App Store Connect must be built with Xcode 26 or later using an SDK for iOS 26…"；自 2026-09-09 起须 target iOS 13+ | 页面写 "Flutter supports iOS 13 and later"，而 supported-platforms 页（2026-09-22）写最低 iOS 15；以后者为准 |
| S11 | OWASP MASVS | https://mas.owasp.org/MASVS/ | 最新版 v2.1.0（2024-01-18，GitHub release） | 直接 + 间接 | 移动端安全验收参考（非认证） | 八个控制组 STORAGE/CRYPTO/AUTH/NETWORK/PLATFORM/CODE/RESILIENCE/PRIVACY；"OWASP… does not certify any vendors, verifiers or software."；"It does not contain specific controls for the remote endpoints"（后端用 ASVS） | MASTG v2.0.0（2026-07-14）移除了官方 Checklist 表格；旧版清单仅供历史参考 |
| S12 | Apple：App Review Guidelines | https://developer.apple.com/app-store/review/guidelines/ | Last Updated: June 8, 2026 | 直接 | 发布合规 | 5.1.1(v) "If your app supports account creation, you must also offer account deletion within the app."；5.1.1(iii) 数据最小化；5.1.1(ii) 可撤回同意；5.1.2(i) "You must clearly disclose where personal data will be shared with third parties, including with third-party AI, and obtain explicit permission before doing so."；5.1.1(ix) "Apps that provide services in highly regulated fields (such as banking and financial services, …) or that require sensitive user information should be submitted by a legal entity … not by an individual developer."；3.2.1(viii) 金融交易/投资/资金管理类 App 应由提供该服务的金融机构提交；4.8 第三方登录须提供等效替代，仅用自有账号体系可豁免 | 5.1.1(ix) 对"个人开发者提交个人理财工具"的适用性需按实际审核结果判断，列为发布风险 |
| S13 | 国家网信办：个人信息保护法 | https://www.cac.gov.cn/2021-08/20/c_1631050028355286.htm | 2021-08-20 通过，2021-11-01 施行 | 直接 | 敏感个人信息、权利、跨境、个人事务例外 | 第二十八条："…金融账户…"属敏感个人信息；第二十九条"应当取得个人的单独同意"；第三十条告知必要性与影响；第五十五条事前影响评估；第十五条撤回同意；第四十五~四十七条查阅复制/更正/删除；第三十八、三十九条跨境条件与单独同意；第七十二条"自然人因个人或者家庭事务处理个人信息的，不适用本法。" | 个人自用与对外提供服务的边界需按实际场景评估 |
| S14 | Anthropic：Prompting Claude Fable 5 | https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5 | 页面未显示日期 | 直接 | 任务组织参考 | "Use subagents frequently… prefer asynchronous communication"；"Before reporting progress, audit each claim against a tool result from this session."；"Separate, fresh-context verifier subagents tend to outperform self-critique." | 以当前环境配置为准（子代理固定为 Opus） |
| S15 | 建设银行龙卡信用卡商户分期业务协议 | https://my.ccb.com/cn/creditcard/installment/shop/fqgl/operation_clause.html | 2024 年 9 月版 | 直接 | 分期占额/释放/尾差/利息/账单列示/提前结清/退货 | "商户分期本金总额将全额占用甲方的信用额度"；"当甲方每期按时还款后，可用额度逐期释放"；"每期分期本金采用四舍五入的方式进行金额拆分，差额在最后一期进行调整"；"分期利息计息方式为分期收取，近似折算年化利率（单利）最高不超过18.25%"；"乙方将在其信用卡对账单中列示相应的商品价款总额（非当期还款额）"；"须一次性支付剩余本金，并按已入账期数承担相应分期利息"；"在商户同意并向乙方返还相应款项后，乙方对…分期付款金额、期数和分期利息进行调整" | 每期分期利率数值未给；已收利息是否退还未提及 |
| S16 | 招商银行：刷卡常见问题 | https://cc.cmbchina.com/content/cusservice/63.htm | 未取得 | **失败**：同 S01 | 退款入账时间、预授权、撤销与退货 | — | 规则状态 pending |

## 2. 本轮补充核验的来源（S17–S30）

| 编号 | 资料 | URL | 文档日期 | 核验方式 | 用途 | 关键事实 |
|---|---|---|---|---|---|---|
| S17 | Flutter 支持平台 | https://docs.flutter.dev/reference/supported-platforms | 2026-09-22 | 直接 | 最低 OS 版本 | iOS 15 起（CI 测 18、26）；Android API 24 起 |
| S18 | Flutter 发布清单 | https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json | 2026-10-08 | 直接 | 版本锁定 | stable 3.47.7，Dart 3.13.5 |
| S19 | flutter_tools build_ios.dart | https://raw.githubusercontent.com/flutter/flutter/stable/packages/flutter_tools/lib/src/commands/build_ios.dart | stable | 直接 | iOS 构建限制 | "Building for iOS is only supported on macOS." |
| S20 | drift 加密文档 | https://drift.simonbinder.eu/platforms/encryption/ | 当前 | 直接 | 本地加密库路线 | "SQLCipher is no longer supported with a straightforward setup"；推荐 sqlite3 构建钩子 `source: sqlite3mc`；旧库迁移需 `PRAGMA cipher='sqlcipher'; PRAGMA legacy=4` |
| S21 | sqlite3 包 UPGRADING_TO_V3 / hook 文档 | pub.dev/packages/sqlite3（3.7.1） | 2026-10-13 | 直接 | 同上 | `source: sqlcipher` 自 3.3.3 恢复支持；Android/Windows/Linux 链接 OpenSSL；SQLite3MC 与 SQLCipher 各有许可证 |
| S22 | pub.dev 各包页面与 API | https://pub.dev/packages/<name> | 2026-10-16 | 直接 | 依赖版本/许可证/维护状态 | 见 `20-architecture/architecture.md` §11 版本表 |
| S23 | PyPI JSON | https://pypi.org/pypi/<name>/json | 2026-10-16 | 直接 | 后端依赖 | 同上 |
| S24 | npm registry / Node 发布计划 | https://registry.npmjs.org/<name>；https://raw.githubusercontent.com/nodejs/Release/main/schedule.json | 2026-10-16 | 直接 | Web 后台依赖 | React 19.3.1、Vite 8.3.4、TypeScript 7.0.2；Node 24 LTS（2026-10-20 转维护期），Node 26 计划 2026-10-28 转 LTS |
| S25 | PostgreSQL 版本页 | https://www.postgresql.org/versions.json | 2026-10-16 | 直接 | 数据库版本 | 18.6（2026-08-13），EOL 2030-11-14；19 RC1 未 GA |
| S26 | Docker Hub postgres 标签 | https://hub.docker.com/v2/repositories/library/postgres/tags | 2026-10-07 | 直接 | 镜像锁定 | `postgres:18.6-trixie` 等 |
| S27 | Google ML Kit 文本识别 | https://developers.google.com/ml-kit/vision/text-recognition/v2/android（及 /ios） | 当前 | 直接 | 设备端中文 OCR | 中文脚本需单独模型；iOS "About 38 MB per script SDK"；Android 打包版每脚本每架构约 4 MB |
| S28 | Google 受限 scope 验证 | https://support.google.com/cloud/answer/13465431 | 2026-08-19 | 间接 | Gmail OAuth 条件 | "complete a security assessment at least every 12 months"（CASA） |
| S29 | OWASP MAS 评估与认证页；MASTG 清单移除公告 | https://mas.owasp.org/MASVS/04-Assessment_and_Certification/；mas.owasp.org 新闻 2026-07-14 | 2026-07-14 | 间接 | 安全验收口径 | OWASP 不认证；MASTG v2 不再提供官方 Checklist 表格 |
| S30 | Apple Upcoming Requirements | https://developer.apple.com/news/upcoming-requirements/ | 当前 | 间接 | iOS 构建环境 | 2026-04-28 起须 Xcode 26 / iOS 26 SDK |

## 3. 未取得/待补充清单

| 项 | 状态 | 需要的动作 |
|---|---|---|
| 招行 S01/S03/S16 正文 | 自动抓取被拦截；PDF 404 | 用户在浏览器保存 HTML/PDF 至 `docs/sources/raw/cmb/`，主会话复核后更新 `bank-rules-spec.md` §7 |
| 各银行"账单日当天入账归属"与"节假日顺延" | 未核验 | 逐账户按正式账单核对后设置 |
| 各卡产品权益/年费规则 | 未核验 | 由用户录入或后台模板（标注来源） |
| 活动来源白名单与抓取许可 | 未核验 | 后台逐来源登记 robots/条款 |
| Syncfusion 许可全文、workmanager 被用户强退后的 iOS 行为 | 未核验 | 不采用 Syncfusion；workmanager 行为在 M0 真机 PoC 验证 |
