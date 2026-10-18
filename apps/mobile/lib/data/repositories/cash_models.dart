/// 现金部分（I-1b）的取值集合（与 `tables.dart` 的 CHECK 一一对应）与小型值对象。
///
/// 数据库里存的是 `code`；界面文案用 `label`。
library;

import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate;
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';

/// 现金账户种类（R-CASH-01）。理财与受限资金默认不可当日用于还款。
enum CashAccountKind {
  bank('bank', '银行账户', usableByDefault: true),
  wallet('wallet', '支付钱包', usableByDefault: true),
  wealth('wealth', '理财', usableByDefault: false),
  restricted('restricted', '受限资金', usableByDefault: false);

  const CashAccountKind(this.code, this.label, {required this.usableByDefault});

  final String code;
  final String label;

  /// 新建时"可用于还款"的默认值（P-08：理财/受限默认不可当日还款）。
  final bool usableByDefault;

  static CashAccountKind of(String code) =>
      values.firstWhere((k) => k.code == code);
}

/// 现金账户状态。
enum CashAccountStatus {
  active('active', '使用中'),
  closed('closed', '已停用');

  const CashAccountStatus(this.code, this.label);

  final String code;
  final String label;

  static CashAccountStatus of(String code) =>
      values.firstWhere((s) => s.code == code);
}

/// 现金事件的层级（R-CASH-03）：没有任何"概率"字段。用户登记的收支只能选确定或预计；
/// 计划（planned）由系统生成（I-1c 的还款、I-2 的计划运行）。
enum CashEventClass {
  confirmed('confirmed', '确定'),
  expected('expected', '预计'),
  planned('planned', '计划');

  const CashEventClass(this.code, this.label);

  final String code;
  final String label;

  /// 用户可以选的层级。
  static const List<CashEventClass> userChoices = <CashEventClass>[
    confirmed,
    expected,
  ];

  static CashEventClass of(String code) =>
      values.firstWhere((c) => c.code == code);
}

/// 现金事件类别（与领域包、规则协议 v1 的 category 同一集合）。[sign]：1 必须为正，−1 必须为负，
/// 0 正负皆可。
enum CashCategory {
  income('income', '收入', 1),
  bill('bill', '其他债务', -1),
  living('living', '生活支出', -1),
  repayment('repayment', '信用卡还款', -1),
  transferIn('transfer_in', '调入', 1),
  transferOut('transfer_out', '调出', -1),
  fee('fee', '费用', -1),
  other('other', '其他', 0);

  const CashCategory(this.code, this.label, this.sign);

  final String code;
  final String label;
  final int sign;

  static CashCategory of(String code) =>
      values.firstWhere((c) => c.code == code);

  /// 金额 [amount] 的符号与本类别是否相符（0 一律不相符）。
  bool accepts(int amount) =>
      amount != 0 && (sign == 0 || (sign > 0) == (amount > 0));
}

/// 发生状态：尚未发生 / 已发生（已发生的一定是确定的）。
enum PostingStatus {
  planned('planned', '尚未发生'),
  posted('posted', '已发生');

  const PostingStatus(this.code, this.label);

  final String code;
  final String label;

  static PostingStatus of(String code) =>
      values.firstWhere((s) => s.code == code);
}

/// P-08 收支计划的条目类型（ui-spec P-08）：决定类别与正负号。周期事项与调拨另有入口。
enum CashPlanType {
  income('income', '收入', CashCategory.income, 1),
  living('living', '固定生活支出', CashCategory.living, -1),
  debt('debt', '其他债务', CashCategory.bill, -1),
  oneOff('one_off', '一次性支出', CashCategory.other, -1);

  const CashPlanType(this.code, this.label, this.category, this.sign);

  /// 路由参数 `?type=` 的取值。
  final String code;
  final String label;
  final CashCategory category;

  /// 金额的正负（用户输入正数，存库时乘以它）。
  final int sign;

  static CashPlanType? parse(String? code) {
    for (final t in values) {
      if (t.code == code) {
        return t;
      }
    }
    return null;
  }

  /// 一条事件属于哪种条目（调拨、还款、费用为 null）。
  static CashPlanType? ofEvent(CashEventRow row) {
    final category = CashCategory.of(row.category);
    return switch (category) {
      CashCategory.income => income,
      CashCategory.living => living,
      CashCategory.bill => debt,
      CashCategory.other => row.amountMinor < 0 ? oneOff : income,
      _ => null,
    };
  }
}

/// 周期事项的频率。
enum RecurringFrequency {
  monthly('monthly', '每月'),
  weekly('weekly', '每周'),
  biweekly('biweekly', '每两周'),
  yearly('yearly', '每年');

  const RecurringFrequency(this.code, this.label);

  final String code;
  final String label;

  static RecurringFrequency of(String code) =>
      values.firstWhere((f) => f.code == code);

  /// 按月/按年时可以选"月末"。
  bool get allowsMonthEnd => this == monthly || this == yearly;
}

/// 周期事项按月/按年时的日规则（不支持工作日规则：本阶段没有已核验的节假日日历）。
enum DayRule {
  anchorDay('anchor_day', '同一日（小月按月末）'),
  monthEnd('month_end', '每月最后一天');

  const DayRule(this.code, this.label);

  final String code;
  final String label;

  static DayRule of(String code) => values.firstWhere((r) => r.code == code);
}

/// 情景种类。
enum ScenarioKind {
  builtinConfirmed('builtin_confirmed', '已确认'),
  builtinBaseline('builtin_baseline', '基准预期'),
  userStress('user_stress', '压力情景');

  const ScenarioKind(this.code, this.label);

  final String code;

  /// 内置情景的名称；压力情景的种类名。
  final String label;

  bool get isBuiltin => this != userStress;

  static ScenarioKind of(String code) =>
      values.firstWhere((k) => k.code == code);
}

/// 同日顺序（engine-spec §12.4）。
enum SameDayOrderChoice {
  conservative('conservative', '先支出后收入（保守）'),
  timestamp('timestamp', '按时刻排序（须所有事件有时刻）');

  const SameDayOrderChoice(this.code, this.label);

  final String code;
  final String label;

  static SameDayOrderChoice of(String code) =>
      values.firstWhere((o) => o.code == code);
}

/// 资金日历的口径（R-CASH-03）。
enum CashBasis {
  confirmed('confirmed', '已确认'),
  baseline('baseline', '基准预期'),
  stress('stress', '压力情景');

  const CashBasis(this.code, this.label);

  final String code;
  final String label;
}

/// 现金账户能否计入"可用现金"（R-CASH-01；I-1b 简报 §1）。
///
/// - 受限账户，或 `usable_for_repayment = 0` 且没有 `available_from` 的账户：不计入；
/// - 有 `available_from`：从该日起可用于还款（之前的余额不算可用于还款，资金日历照常逐账户计算并记假设）；
/// - 其余：可用于还款。
@immutable
final class CashAvailability {
  const CashAvailability._(this.counted, this.usableFrom, this.reason);

  factory CashAvailability.of(CashAccountRow row) {
    final from = row.availableFrom;
    if (from != null) {
      return CashAvailability._(true, LocalDate.parse(from), null);
    }
    final kind = CashAccountKind.of(row.kind);
    if (kind == CashAccountKind.restricted) {
      return const CashAvailability._(false, null, '受限资金，未设可用日期');
    }
    if (!row.usableForRepayment) {
      return const CashAvailability._(false, null, '不可用于还款，未设可用日期');
    }
    return const CashAvailability._(true, null, null);
  }

  /// 是否计入可用现金（资金日历、总览、规划都只看这些账户）。
  final bool counted;

  /// 可用于还款的起始日（有可用日期时）。
  final LocalDate? usableFrom;

  /// 不计入的原因（界面文案）。
  final String? reason;

  /// 在 [on] 这一天能否用于还款。
  bool usableOn(LocalDate on) =>
      counted && (usableFrom == null || usableFrom! <= on);

  /// 界面上的一句说明。
  String get label => switch ((counted, usableFrom)) {
    (false, _) => '不计入可用现金（$reason）',
    (true, final LocalDate from?) => '$from 起可用于还款',
    _ => '可用于还款',
  };
}
