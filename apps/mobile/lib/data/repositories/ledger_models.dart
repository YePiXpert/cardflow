/// 账单、交易、分期、还款与差异项（I-1c）的取值集合（与 `tables.dart` 的 CHECK 一一对应）。
///
/// 数据库里存的是 `code`；界面文案用 `label`。
library;

/// 交易类型（data-model §3 transactions）。金额"负债增加为正"：[sign] 1 必须为正、−1 必须为负、0 不限。
///
/// "记一笔"（P-05）只提供 [manualChoices]：分期本金与手续费由分期计划的各期表示（不另记交易，避免重复
/// 计入）；"还款入账"是银行账单上的还款行，只用于核对（不进入负债计算，负债按 P-06 登记的还款核销）。
enum TxnType {
  purchase('purchase', '消费', 1),
  refund('refund', '退款', -1),
  repayment('repayment', '还款入账（银行记录）', -1),
  transfer('transfer', '转账/取现', 0),
  fee('fee', '费用（含年费）', 1),
  interest('interest', '利息', 1),
  installmentPrincipal('installment_principal', '分期本金', 1),
  installmentFee('installment_fee', '分期手续费', 1),
  adjustment('adjustment', '调整', 0);

  const TxnType(this.code, this.label, this.sign);

  final String code;
  final String label;
  final int sign;

  static TxnType of(String code) => values.firstWhere((t) => t.code == code);

  /// "记一笔"可选的类型。
  static const List<TxnType> manualChoices = <TxnType>[
    purchase,
    refund,
    fee,
    interest,
    transfer,
    adjustment,
    repayment,
  ];

  /// 金额 [amount] 的符号与本类型是否相符（0 一律不相符）。
  bool accepts(int amount) =>
      amount != 0 && (sign == 0 || (sign > 0) == (amount > 0));

  /// 统计口径（R-STMT-08）：还款与互转不计入消费。
  bool get countsAsSpending => this == purchase;
}

/// 交易状态。
enum TxnStatus {
  pending('pending', '待入账'),
  posted('posted', '已入账'),
  reversed('reversed', '已撤销');

  const TxnStatus(this.code, this.label);

  final String code;
  final String label;

  static TxnStatus of(String code) => values.firstWhere((s) => s.code == code);
}

/// 交易时间的精度（ADR-008）。
enum TxnTimePrecision {
  datetime('datetime', '精确到时刻'),
  date('date', '只知道日期'),
  month('month', '只知道月份');

  const TxnTimePrecision(this.code, this.label);

  final String code;
  final String label;

  static TxnTimePrecision of(String code) =>
      values.firstWhere((p) => p.code == code);
}

/// 账单状态（PRD §6.2）。
enum StatementStatus {
  predicted('predicted', '预测账期'),
  issued('issued', '已出账'),
  amended('amended', '已修正'),
  partiallySettled('partially_settled', '部分结清（银行确认）'),
  settled('settled', '已结清（银行确认）'),
  overdue('overdue', '已逾期');

  const StatementStatus(this.code, this.label);

  final String code;
  final String label;

  static StatementStatus of(String code) =>
      values.firstWhere((s) => s.code == code);

  /// 状态机允许的下一个状态（PRD §6.2；"已修正"后逾期与"已出账"后逾期同样处理，见 README 偏离）。
  Set<StatementStatus> get next => switch (this) {
    predicted => const <StatementStatus>{issued},
    issued || amended => const <StatementStatus>{
      amended,
      partiallySettled,
      settled,
      overdue,
    },
    partiallySettled => const <StatementStatus>{settled, overdue},
    overdue => const <StatementStatus>{settled},
    settled => const <StatementStatus>{},
  };

  bool canBecome(StatementStatus target) => next.contains(target);

  /// 已结清（只由银行确认触发）。
  bool get isSettled => this == settled;
}

/// 账单版本的来源。
enum StatementSource {
  manual('manual', '手工录入'),
  import('import', '导入'),
  correction('correction', '人工修正');

  const StatementSource(this.code, this.label);

  final String code;
  final String label;

  static StatementSource of(String code) =>
      values.firstWhere((s) => s.code == code);
}

/// 分期手续费的收取方式。
enum InstallmentFeeMode {
  /// 每期收取（建行口径：每期费用 = 本金总额 × 每期费率）。
  perPeriod('per_period', '每期收取'),

  /// 一次性在首期收取（总额 = 本金总额 × 每期费率 × 期数，取整一次；见 README 偏离）。
  upfront('upfront', '首期一次收取');

  const InstallmentFeeMode(this.code, this.label);

  final String code;
  final String label;

  static InstallmentFeeMode of(String code) =>
      values.firstWhere((m) => m.code == code);
}

/// 分期计划状态（data-model §10.12）。
enum InstallmentPlanStatus {
  active('active', '进行中'),
  completed('completed', '已还完'),
  earlySettled('early_settled', '已提前结清'),
  cancelled('cancelled', '已作废');

  const InstallmentPlanStatus(this.code, this.label);

  final String code;
  final String label;

  static InstallmentPlanStatus of(String code) =>
      values.firstWhere((s) => s.code == code);

  /// 本金由各期表示（原交易不再计入未出账）。
  bool get coversPrincipal => this != cancelled;
}

/// 分期各期的状态（data-model §10.12）。
enum InstallmentPeriodStatus {
  scheduled('scheduled', '未出账'),
  billed('billed', '已出账'),
  settled('settled', '已结清'),
  cancelled('cancelled', '已作废');

  const InstallmentPeriodStatus(this.code, this.label);

  final String code;
  final String label;

  static InstallmentPeriodStatus of(String code) =>
      values.firstWhere((s) => s.code == code);
}

/// 还款状态（PRD §6.3）。文案按 ui-spec §2/§4.5：不出现"还款成功"。
enum RepaymentStatus {
  recorded('recorded', '已登记（待银行确认）'),
  processing('processing', '处理中'),
  cashDebited('cash_debited', '现金已扣'),
  creditPosted('credit_posted', '银行已入账'),
  bankConfirmed('bank_confirmed', '银行确认'),
  failed('failed', '失败'),
  userMarkedPaid('user_marked_paid', '用户已标记（待核对）'),
  needsReview('needs_review', '待核对'),
  reversed('reversed', '已冲正');

  const RepaymentStatus(this.code, this.label);

  final String code;
  final String label;

  static RepaymentStatus of(String code) =>
      values.firstWhere((s) => s.code == code);

  /// 状态机允许的下一个状态（PRD §6.3；"待核对"后取得证据同"用户已标记"后取得证据，见 README 偏离）。
  Set<RepaymentStatus> get next => switch (this) {
    recorded => const <RepaymentStatus>{processing, userMarkedPaid},
    processing => const <RepaymentStatus>{cashDebited, failed},
    cashDebited => const <RepaymentStatus>{creditPosted},
    creditPosted => const <RepaymentStatus>{bankConfirmed},
    failed => const <RepaymentStatus>{recorded},
    userMarkedPaid => const <RepaymentStatus>{bankConfirmed, needsReview},
    needsReview => const <RepaymentStatus>{bankConfirmed},
    bankConfirmed => const <RepaymentStatus>{reversed},
    reversed => const <RepaymentStatus>{},
  };

  bool canBecome(RepaymentStatus target) => next.contains(target);

  /// 负债已按银行入账核销（F-31：负债按 `credit_posted_at` 的日期核销）。
  bool get isCredited => this == creditPosted || this == bankConfirmed;

  /// 还在等银行的证据（P-01 待办"待核对的还款"）。
  bool get awaitsEvidence =>
      this == userMarkedPaid ||
      this == needsReview ||
      this == cashDebited ||
      this == creditPosted;
}

/// 还款方式。
enum RepaymentMethod {
  autoDebit('auto_debit', '自动扣款'),
  manual('manual', '手动还款（银行 App/网银）'),
  thirdParty('third_party', '第三方支付'),
  other('other', '其他');

  const RepaymentMethod(this.code, this.label);

  final String code;
  final String label;

  static RepaymentMethod of(String code) =>
      values.firstWhere((m) => m.code == code);

  /// 用户手工发起的（疑似重复：一笔自动扣款 + 一笔手工，F-32）。
  bool get isManual => this != autoDebit;
}

/// 对账差异项的类型（R-STMT-09）：来源与建议动作随类型给出。
enum ReconciliationKind {
  amountMismatch(
    'amount_mismatch',
    '金额不符',
    source: '还款扣款或入账的金额与登记的不同',
    suggestion: '核对银行流水与账单；登记有误时作废后重新登记',
  ),
  duplicateRepayment(
    'duplicate_repayment',
    '疑似重复还款',
    source: '同一天、同一账户、同金额的一笔自动扣款与一笔手工还款',
    suggestion: '核对银行流水：是同一笔就作废重复的登记，确为两笔就标记为两笔',
  ),
  refundPending(
    'refund_pending',
    '退款待核对',
    source: '退款是否冲抵本期应还按账户规则，规则未知',
    suggestion: '等下期账单或银行 App 确认后标记是否已冲抵；未确认前应还不变、不计入收入',
  ),
  unmatchedRepayment(
    'unmatched_repayment',
    '未匹配的还款',
    source: '银行记录里有一笔还款入账，但没有对应的还款登记',
    suggestion: '去登记这笔还款，或确认不是你的还款后忽略',
  );

  const ReconciliationKind(
    this.code,
    this.label, {
    required this.source,
    required this.suggestion,
  });

  final String code;
  final String label;

  /// 来源说明。
  final String source;

  /// 建议动作。
  final String suggestion;

  static ReconciliationKind of(String code) =>
      values.firstWhere((k) => k.code == code);
}

/// 差异项状态。
enum ReconciliationStatus {
  open('open', '待处理'),
  resolved('resolved', '已处理'),
  dismissed('dismissed', '已忽略');

  const ReconciliationStatus(this.code, this.label);

  final String code;
  final String label;

  static ReconciliationStatus of(String code) =>
      values.firstWhere((s) => s.code == code);
}

/// 差异项的处理结果。
enum ReconciliationResolution {
  distinct('distinct', '确为两笔还款'),
  samePayment('same_payment', '同一笔，已作废重复的登记'),
  offset('offset', '退款已冲抵应还'),
  notOffset('not_offset', '退款未冲抵本期应还'),
  acknowledged('acknowledged', '已核对'),
  registered('registered', '已登记对应还款'),
  dismissed('dismissed', '已忽略');

  const ReconciliationResolution(this.code, this.label);

  final String code;
  final String label;

  static ReconciliationResolution of(String code) =>
      values.firstWhere((r) => r.code == code);

  /// 各类型可用的处理结果（忽略另有入口）。
  static List<ReconciliationResolution> choicesFor(ReconciliationKind kind) =>
      switch (kind) {
        ReconciliationKind.duplicateRepayment =>
          const <ReconciliationResolution>[distinct, samePayment],
        ReconciliationKind.refundPending => const <ReconciliationResolution>[
          offset,
          notOffset,
        ],
        ReconciliationKind.amountMismatch => const <ReconciliationResolution>[
          acknowledged,
        ],
        ReconciliationKind.unmatchedRepayment =>
          const <ReconciliationResolution>[registered],
      };
}

/// 处理者。
enum ResolvedBy {
  user('user', '本机用户'),
  system('system', '系统');

  const ResolvedBy(this.code, this.label);

  final String code;
  final String label;

  static ResolvedBy of(String code) => values.firstWhere((r) => r.code == code);
}
