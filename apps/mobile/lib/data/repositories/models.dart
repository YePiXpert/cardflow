/// 仓库层的取值集合（与 `tables.dart` 的 CHECK 一一对应）与小型值对象。
///
/// 数据库里存的是 [code]；界面文案用 [label]。行对象就是 drift 生成的 `*Row`（`app_database.g.dart`）。
library;

import 'package:flutter/foundation.dart';

import '../db/app_database.dart';

/// 工作空间种类（R-SYS-13）。
enum WorkspaceKind {
  real('real', '真实', '我的数据'),
  demo('demo', '演示', '演示数据');

  const WorkspaceKind(this.code, this.label, this.defaultName);

  final String code;

  /// 顶栏空间标识。
  final String label;

  /// 新建时的名称。
  final String defaultName;

  static WorkspaceKind of(String code) =>
      values.firstWhere((k) => k.code == code);
}

/// 当前工作空间（provider 对外暴露的值对象，与 drift 生成的 [WorkspaceRow] 分开：代码生成的
/// provider 不能直接引用同一轮生成的 drift 类型）。
@immutable
final class Workspace {
  const Workspace({required this.id, required this.kind, required this.name});

  factory Workspace.fromRow(WorkspaceRow row) =>
      Workspace(id: row.id, kind: WorkspaceKind.of(row.kind), name: row.name);

  final String id;
  final WorkspaceKind kind;
  final String name;

  bool get isDemo => kind == WorkspaceKind.demo;

  @override
  bool operator ==(Object other) =>
      other is Workspace &&
      other.id == id &&
      other.kind == kind &&
      other.name == name;

  @override
  int get hashCode => Object.hash(id, kind, name);
}

/// 卡片状态（PRD §6.1）。
enum CardStatus {
  draft('draft', '草稿'),
  active('active', '已启用'),
  frozen('frozen', '已冻结'),
  replaced('replaced', '已换卡'),
  closed('closed', '已销卡');

  const CardStatus(this.code, this.label);

  final String code;
  final String label;

  static CardStatus of(String code) => values.firstWhere((s) => s.code == code);

  /// 状态机允许的下一个状态：`draft → active`、`active → frozen/replaced/closed`、
  /// `frozen → active/closed`；`replaced`、`closed` 是终态。
  Set<CardStatus> get next => switch (this) {
    draft => const <CardStatus>{active},
    active => const <CardStatus>{frozen, replaced, closed},
    frozen => const <CardStatus>{active, closed},
    replaced || closed => const <CardStatus>{},
  };

  bool canBecome(CardStatus target) => next.contains(target);

  /// 已停用（卡包里折叠）。
  bool get isInactive => this == replaced || this == closed;
}

/// 主卡/附属卡。
enum HolderKind {
  primary('primary', '主卡'),
  supplementary('supplementary', '附属卡');

  const HolderKind(this.code, this.label);

  final String code;
  final String label;

  static HolderKind of(String code) => values.firstWhere((k) => k.code == code);
}

/// 卡组织。
enum CardNetwork {
  unionpay('unionpay', '银联'),
  visa('visa', 'Visa'),
  mastercard('mastercard', 'Mastercard'),
  amex('amex', 'American Express'),
  jcb('jcb', 'JCB'),
  discover('discover', 'Discover'),
  other('other', '其他');

  const CardNetwork(this.code, this.label);

  final String code;
  final String label;

  static CardNetwork? ofNullable(String? code) =>
      code == null ? null : values.firstWhere((n) => n.code == code);
}

/// 卡片行的便捷读法。
extension CardRowFields on CardRow {
  CardStatus get cardStatus => CardStatus.of(status);

  HolderKind get kind => HolderKind.of(holderKind);

  CardNetwork? get cardNetwork => CardNetwork.ofNullable(network);
}

/// 账期规则的主体种类。
enum RuleSubjectKind {
  creditAccount('credit_account'),
  currencyAccount('currency_account');

  const RuleSubjectKind(this.code);

  final String code;
}

/// 规则主体。
@immutable
final class RuleSubject {
  const RuleSubject.creditAccount(this.id)
    : kind = RuleSubjectKind.creditAccount;

  const RuleSubject.currencyAccount(this.id)
    : kind = RuleSubjectKind.currencyAccount;

  final RuleSubjectKind kind;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is RuleSubject && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

/// 规则来源（P-02/P-03 的来源徽标）。
enum RuleSource {
  userDeclared('user_declared', '手动设置'),
  officialTemplate('official_template', '官方模板');

  const RuleSource(this.code, this.label);

  final String code;
  final String label;

  static RuleSource of(String code) => values.firstWhere((s) => s.code == code);
}

/// 规则版本的审核状态（本地只写 `user_declared` 与 `expired`）。
enum ReviewStatus {
  draft('draft', '草稿'),
  inReview('in_review', '审核中'),
  userDeclared('user_declared', '已生效'),
  expired('expired', '已失效');

  const ReviewStatus(this.code, this.label);

  final String code;
  final String label;

  static ReviewStatus of(String code) =>
      values.firstWhere((s) => s.code == code);
}

/// 额度快照的来源。
enum SnapshotSource {
  bankApp('bank_app', '银行 App'),
  statement('statement', '账单'),
  user('user', '自行估计'),
  import('import', '导入');

  const SnapshotSource(this.code, this.label);

  final String code;
  final String label;

  static SnapshotSource of(String code) =>
      values.firstWhere((s) => s.code == code);
}

/// 确认层级（ui-spec §4.3）。
enum ConfirmationLevel {
  systemEstimated('system_estimated', '系统估计'),
  userConfirmed('user_confirmed', '手动记录'),
  bankConfirmed('bank_confirmed', '银行确认');

  const ConfirmationLevel(this.code, this.label);

  final String code;
  final String label;

  static ConfirmationLevel of(String code) =>
      values.firstWhere((c) => c.code == code);
}
