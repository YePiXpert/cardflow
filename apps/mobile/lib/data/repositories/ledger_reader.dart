import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../mapping/cash_mapping.dart' show cashTimeZone;
import '../mapping/ledger_mapping.dart';
import '../time/business_tz.dart';
import '../time/clock.dart';
import 'card_wallet_reader.dart';
import 'cash_account_repository.dart';
import 'cash_event_repository.dart';
import 'credit_account_repository.dart';
import 'installment_repository.dart';
import 'ledger_models.dart';
import 'limit_snapshot_repository.dart';
import 'reconciliation_repository.dart';
import 'repayment_repository.dart';
import 'statement_repository.dart';
import 'transaction_repository.dart';
import 'workspace_scope.dart';

/// 账单中心、还款与核对、账户详情与总览（P-05/P-06/P-03/P-01）共用的读模型：一次读齐当前工作空间的
/// 账单与版本、交易、分期、还款与分配、差异项，并算出每份账单在"今天"的读数与有效状态（PRD §6.2 的
/// 2026-10-19 裁决段：同一币种子账户里最近一期是本期，更早的已并入下一期；本期剩余应还 = 新增账单 − 账单日
/// 之后银行入账的还款 ± 已出账消费转分期的调整）与每个币种子账户的负债四分法（R-STMT-02、F-30）。
///
/// 只读：[LedgerReader.load] 不写库。逾期、"用户已标记"到期后仍无证据的"待核对"都在这里推导
/// （[balances] 的 `status`、[repaymentStatusOf]），存储状态只是动作记录。
@immutable
final class LedgerData {
  const LedgerData({
    required this.wallet,
    required this.currencyAccounts,
    required this.statements,
    required this.versions,
    required this.balances,
    required this.transactions,
    required this.cycles,
    required this.plans,
    required this.periods,
    required this.repayments,
    required this.allocations,
    required this.items,
    required this.repaymentEvents,
    required this.cashAccounts,
    required this.liabilities,
    required this.todayByCurrencyAccount,
    required this.offsetRefunds,
    required this.openDuplicates,
    required this.creditDates,
    required this.cashToday,
  });

  /// 卡包读模型（账户名称、业务时区、额度快照）。
  final WalletView wallet;

  /// 币种子账户 id → 行。
  final Map<String, CurrencyAccountRow> currencyAccounts;

  /// 全部账单，账单日新的在前。
  final List<StatementRow> statements;

  /// 账单 id → 版本（按版本号）。
  final Map<String, List<StatementVersionRow>> versions;

  /// 账单 id → 今天的余额（当前版本）。
  final Map<String, StatementBalance> balances;

  /// 未删除的交易（按交易时点）。
  final List<CardTransactionRow> transactions;

  /// 交易 id → 账期归属。
  final Map<String, TxnCycle> cycles;

  final List<InstallmentPlanRow> plans;

  /// 计划 id → 各期（按期号）。
  final Map<String, List<InstallmentScheduleRow>> periods;

  /// 未作废的还款（登记新的在前）。
  final List<RepaymentRow> repayments;
  final List<RepaymentAllocationRow> allocations;

  /// 差异项（未处理的在前）。
  final List<ReconciliationItemRow> items;

  /// 还款 id → 现金时间线上那条未删除的事件。
  final Map<String, CashEventRow> repaymentEvents;

  /// 现金账户 id → 行（含已停用）。
  final Map<String, CashAccountRow> cashAccounts;

  /// 币种子账户 id → 负债四分法。
  final Map<String, LiabilityBreakdown> liabilities;

  /// 币种子账户 id → 所属信用账户业务时区里的今天。
  final Map<String, LocalDate> todayByCurrencyAccount;

  /// 已确认冲抵应还的退款。
  final Set<String> offsetRefunds;

  /// 未处理的疑似重复还款。
  final List<DuplicatePair> openDuplicates;

  /// 还款 id → 银行入账日（信用账户业务时区）。
  final Map<String, LocalDate?> creditDates;

  /// 现金时区里的今天。
  final LocalDate cashToday;

  /// 币种子账户所属的信用账户读模型。
  AccountView? accountOf(String currencyAccountId) {
    final sub = currencyAccounts[currencyAccountId];
    return sub == null ? null : wallet.account(sub.creditAccountId);
  }

  /// "卡 A · 人民币" 一类的子账户名称（只有一个币种时不写币种）。
  String accountName(String currencyAccountId) {
    final sub = currencyAccounts[currencyAccountId];
    final account = accountOf(currencyAccountId);
    if (sub == null || account == null) {
      return '已不存在的账户';
    }
    return account.currencies.length > 1
        ? '${account.displayName} · ${sub.currency}'
        : account.displayName;
  }

  StatementRow? statement(String id) {
    for (final s in statements) {
      if (s.id == id) {
        return s;
      }
    }
    return null;
  }

  RepaymentRow? repayment(String id) {
    for (final r in repayments) {
      if (r.id == id) {
        return r;
      }
    }
    return null;
  }

  CardTransactionRow? transaction(String id) {
    for (final t in transactions) {
      if (t.id == id) {
        return t;
      }
    }
    return null;
  }

  /// 某还款的分配。
  List<RepaymentAllocationRow> allocationsOf(String repaymentId) =>
      <RepaymentAllocationRow>[
        for (final a in allocations)
          if (a.repaymentId == repaymentId) a,
      ];

  /// 分配到某账单的还款（含分配额），登记新的在前。
  List<(RepaymentRow, int)> repaymentsOn(String statementId) =>
      <(RepaymentRow, int)>[
        for (final r in repayments)
          for (final a in allocations)
            if (a.repaymentId == r.id && a.statementId == statementId)
              (r, a.amountMinor),
      ];

  /// 差异项涉及的账单：还款分配到的账单；退款与还款入账所在账期的已出账单。
  Set<String> statementsOfItem(ReconciliationItemRow item) {
    final ids = <String>{};
    for (final r in referencedRepayments(item)) {
      for (final a in allocations) {
        if (a.repaymentId == r) {
          ids.add(a.statementId);
        }
      }
    }
    final txnId = referencedTransaction(item);
    final txn = txnId == null ? null : transaction(txnId);
    if (txn != null) {
      final dates = cycles[txn.id]?.statementDates ?? const <LocalDate>[];
      for (final s in statements) {
        if (s.currencyAccountId == txn.currencyAccountId &&
            dates.contains(LocalDate.parse(s.statementDate))) {
          ids.add(s.id);
        }
      }
    }
    return ids;
  }

  /// 某账单的未处理差异项。
  List<ReconciliationItemRow> openItemsOf(String statementId) =>
      <ReconciliationItemRow>[
        for (final item in items)
          if (item.status == ReconciliationStatus.open.code &&
              statementsOfItem(item).contains(statementId))
            item,
      ];

  /// 某还款的差异项（不论是否已处理）。
  List<ReconciliationItemRow> itemsOfRepayment(String repaymentId) =>
      <ReconciliationItemRow>[
        for (final item in items)
          if (referencedRepayments(item).contains(repaymentId)) item,
      ];

  /// 交易的差异项（退款待核对、未匹配的还款入账）。
  ReconciliationItemRow? itemOfTransaction(String transactionId) {
    for (final item in items) {
      if (referencedTransaction(item) == transactionId) {
        return item;
      }
    }
    return null;
  }

  /// 账单的确认层级：有效状态"已还清"（银行确认的还款足额）→ 银行确认；手工录入/修正 → 你已确认；
  /// 导入 → 系统估计（I-3）。
  ConfirmationShown confirmationOf(String statementId) {
    final s = statement(statementId);
    if (s == null) {
      return ConfirmationShown.userConfirmed;
    }
    if (balances[s.id]?.status == EffectiveStatementStatus.paid) {
      return ConfirmationShown.bankConfirmed;
    }
    final current = versions[s.id]?.last;
    return current?.sourceKind == StatementSource.import.code
        ? ConfirmationShown.systemEstimated
        : ConfirmationShown.userConfirmed;
  }

  /// 某账单账期内的交易（账期的账单日等于它；入账不确定的、可能落在它上面的也列出）。
  List<(CardTransactionRow, TxnCycle)> transactionsOf(String statementId) {
    final s = statement(statementId);
    if (s == null) {
      return const <(CardTransactionRow, TxnCycle)>[];
    }
    final date = LocalDate.parse(s.statementDate);
    return <(CardTransactionRow, TxnCycle)>[
      for (final t in transactions)
        if (t.currencyAccountId == s.currencyAccountId)
          if (cycles[t.id] case final c?)
            if (c.statementDates.contains(date)) (t, c),
    ];
  }

  /// 某币种子账户的分期计划（未作废的在前）与各期。
  List<InstallmentPlanRow> plansOf(String currencyAccountId) =>
      <InstallmentPlanRow>[
        for (final p in plans)
          if (p.currencyAccountId == currencyAccountId &&
              p.status != InstallmentPlanStatus.cancelled.code)
            p,
        for (final p in plans)
          if (p.currencyAccountId == currencyAccountId &&
              p.status == InstallmentPlanStatus.cancelled.code)
            p,
      ];

  /// 分期计划的成本（F-37），在调用它的 isolate 里同步计算（有理数 IRR，60 期要秒级）。只给测试与工具用：
  /// 界面一律经 `installmentCostProvider`（按计划 id 记忆化、后台 isolate，审查 R-04）。
  InstallmentCost costOf(InstallmentPlanRow plan) =>
      InstallmentCostInput.ofPlan(
        plan,
        periods[plan.id] ?? const <InstallmentScheduleRow>[],
      ).compute();

  /// 某币种子账户的账单，账单日新的在前。
  List<StatementRow> statementsOf(String currencyAccountId) => <StatementRow>[
    for (final s in statements)
      if (s.currencyAccountId == currencyAccountId) s,
  ];

  /// 某还款的最近状态与它最近一笔还款（P-03"还款状态"）。
  RepaymentRow? latestRepaymentOn(String statementId) {
    final list = repaymentsOn(statementId);
    return list.isEmpty ? null : list.first.$1;
  }

  /// 某币种子账户的本期账单（最近一期；没有账单时为 null）。
  StatementBalance? currentStatementOf(String currencyAccountId) =>
      liabilities[currencyAccountId]?.latest;

  /// 某账单的有效状态（PRD §6.2 裁决段）；账单不在当前空间时为 null。
  EffectiveStatementStatus? statusOf(String statementId) =>
      balances[statementId]?.status;

  /// 近期到期（P-01，14 天内到期或已逾期、剩余应还 > 0 的本期账单），到期早的在前。已并入下一期的旧账单、
  /// 已还清/已转分期/无需还款的都不列出。
  List<StatementBalance> upcoming({int days = 14}) {
    final list = <StatementBalance>[];
    for (final s in statements) {
      final balance = balances[s.id];
      if (balance == null || !balance.status.owes) {
        continue;
      }
      final due = balance.dueDate;
      if (balance.status == EffectiveStatementStatus.overdue ||
          (due >= balance.today && due <= balance.today.addDays(days))) {
        list.add(balance);
      }
    }
    list.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return list;
  }

  /// 还款的有效状态：存储状态为"用户已标记"、而分配到的账单里有已过到期日的 → 待核对（UF-3 步骤 6；
  /// 读模型推导，不写库）；其余为存储状态。
  RepaymentStatus repaymentStatusOf(RepaymentRow repayment) {
    final stored = RepaymentStatus.of(repayment.status);
    if (stored != RepaymentStatus.userMarkedPaid) {
      return stored;
    }
    final today = todayByCurrencyAccount[repayment.currencyAccountId];
    if (today == null) {
      return stored;
    }
    for (final a in allocations) {
      if (a.repaymentId != repayment.id) {
        continue;
      }
      final s = statement(a.statementId);
      if (s != null && LocalDate.parse(s.dueDate) < today) {
        return RepaymentStatus.needsReview;
      }
    }
    return stored;
  }

  /// 等银行证据的还款（P-01 待办"待核对的还款"）：用户已标记、待核对、现金已扣、银行已入账。
  List<RepaymentRow> get awaitingEvidence => <RepaymentRow>[
    for (final r in repayments)
      if (repaymentStatusOf(r).awaitsEvidence) r,
  ];

  /// 不在任何已录入账单里的交易（P-05"不在已录账单里的交易"）：账期的账单日都没有录入账单的（未出账的、
  /// 所在账期还没录入正式账单的、没有账期规则的）。[creditAccountId] 非空时只看这个信用账户。
  List<(CardTransactionRow, TxnCycle)> looseTransactions({
    String? creditAccountId,
  }) {
    final recorded = <String, Set<LocalDate>>{};
    for (final s in statements) {
      recorded
          .putIfAbsent(s.currencyAccountId, () => <LocalDate>{})
          .add(LocalDate.parse(s.statementDate));
    }
    return <(CardTransactionRow, TxnCycle)>[
      for (final t in transactions)
        if (creditAccountId == null ||
            currencyAccounts[t.currencyAccountId]?.creditAccountId ==
                creditAccountId)
          if (cycles[t.id] ?? const TxnCycleNoRule() case final c)
            if (!c.statementDates.any(
              (d) => recorded[t.currencyAccountId]?.contains(d) ?? false,
            ))
              (t, c),
    ];
  }

  /// 入账日未知、可能账期跨过本期账单日的交易（Q-3）：可能已在本期账单里，也可能还没出账——负债按未出账
  /// 计（偏大），界面提示"可能已出账，请补入账日"。
  bool mayBeBilled(CardTransactionRow txn) {
    final cycle = cycles[txn.id];
    final current = currentStatementOf(txn.currencyAccountId);
    if (txn.postedOn != null || cycle is! TxnCyclePossible || current == null) {
      return false;
    }
    final date = current.statementDate;
    final dates = cycle.statementDates;
    return dates.any((d) => d <= date) && dates.any((d) => d > date);
  }

  /// 系统处理的差异项的原因（审查 R-07：引用的交易被删除、还款登记被作废后由系统标为已处理）。不是系统
  /// 处理的为 null。删除与作废都不可撤销，所以按引用对象现在的状态就能写明原因。
  String? systemCloseReason(ReconciliationItemRow item) {
    if (item.resolvedBy != ResolvedBy.system.code) {
      return null;
    }
    final txnId = referencedTransaction(item);
    if (txnId != null && transaction(txnId) == null) {
      return '引用的交易已删除';
    }
    if (referencedRepayments(item).any((id) => repayment(id) == null)) {
      return '引用的还款登记已作废';
    }
    return '引用的记录已变更';
  }

  /// 未处理的差异项。
  List<ReconciliationItemRow> get openItems => <ReconciliationItemRow>[
    for (final i in items)
      if (i.status == ReconciliationStatus.open.code) i,
  ];

  /// 按币种合计的负债四分法（P-01；不同币种不相加）。
  Map<String, LiabilityTotals> get totalsByCurrency {
    final totals = <String, LiabilityTotals>{};
    for (final entry in liabilities.entries) {
      final l = entry.value;
      final t = totals[l.currency] ?? LiabilityTotals.zero(l.currency);
      totals[l.currency] = t.plus(l);
    }
    return totals;
  }
}

/// 确认层级的展示（ui-spec §4.3）。
enum ConfirmationShown {
  systemEstimated('系统估计'),
  userConfirmed('你已确认'),
  bankConfirmed('银行确认');

  const ConfirmationShown(this.label);

  final String label;
}

/// 一个币种的负债合计（P-01）。
@immutable
final class LiabilityTotals {
  const LiabilityTotals({
    required this.currency,
    required this.currentDue,
    required this.unbilled,
    required this.futureInstallmentPrincipal,
    required this.total,
    required this.creditBalance,
  });

  factory LiabilityTotals.zero(String currency) => LiabilityTotals(
    currency: currency,
    currentDue: 0,
    unbilled: 0,
    futureInstallmentPrincipal: 0,
    total: 0,
    creditBalance: 0,
  );

  final String currency;
  final int currentDue;
  final int unbilled;
  final int futureInstallmentPrincipal;
  final int total;
  final int creditBalance;

  LiabilityTotals plus(LiabilityBreakdown l) => LiabilityTotals(
    currency: currency,
    currentDue: currentDue + l.currentDue,
    unbilled: unbilled + l.unbilled,
    futureInstallmentPrincipal:
        futureInstallmentPrincipal + l.futureInstallmentPrincipal,
    total: total + l.total,
    creditBalance: creditBalance + l.creditBalance,
  );
}

/// 账单相关读模型的组装。
final class LedgerReader {
  LedgerReader(this._scope);

  final WorkspaceScope _scope;

  /// 读入（只读，不写库：逾期与"待核对"都是推导出来的有效状态）。
  Future<LedgerData> load() async {
    final wallet = await CardWalletReader(_scope).load();
    final subs = await CreditAccountRepository(_scope).currencyAccounts();
    final statementRepo = StatementRepository(_scope);
    final statements = await statementRepo.list();
    final versions = <String, List<StatementVersionRow>>{};
    for (final v in await statementRepo.allVersions()) {
      versions.putIfAbsent(v.statementId, () => <StatementVersionRow>[]).add(v);
    }
    final transactions = await TransactionRepository(_scope).list();
    final installments = InstallmentRepository(_scope);
    final plans = await installments.plans();
    final periods = <String, List<InstallmentScheduleRow>>{};
    for (final p in await installments.allPeriods()) {
      periods.putIfAbsent(p.planId, () => <InstallmentScheduleRow>[]).add(p);
    }
    final repaymentRepo = RepaymentRepository(_scope);
    final repayments = await repaymentRepo.list();
    final allocations = await repaymentRepo.allAllocations();
    final reconciliation = ReconciliationRepository(_scope);
    final items = await reconciliation.list();
    final openDuplicates = await reconciliation.openDuplicatePairs();
    final offsetRefunds = await reconciliation.offsetRefunds();
    final cashEvents = CashEventRepository(_scope);
    final repaymentEvents = <String, CashEventRow>{
      for (final r in repayments) r.id: ?await cashEvents.byRepayment(r.id),
    };
    final cashAccounts = {
      for (final a in await CashAccountRepository(_scope).list()) a.id: a,
    };

    final subById = {for (final c in subs) c.id: c};
    final zoneOf = <String, BusinessTimeZone>{};
    final todayOf = <String, LocalDate>{};
    final rulesOf = <String, List<BillingRuleVersionRow>>{};
    for (final sub in subs) {
      final account = wallet.account(sub.creditAccountId);
      if (account == null) {
        continue;
      }
      zoneOf[sub.id] = account.zone;
      todayOf[sub.id] = account.today;
      for (final c in account.currencies) {
        if (c.row.id == sub.id) {
          rulesOf[sub.id] = c.ruleVersions;
        }
      }
    }

    // 还款的银行入账日（信用账户业务时区，截止时点按规则）。
    final creditDates = <String, LocalDate?>{};
    for (final r in repayments) {
      final account = wallet.account(
        subById[r.currencyAccountId]?.creditAccountId ?? '',
      );
      creditDates[r.id] = account == null
          ? null
          : creditDateOf(
              r,
              account: account.account,
              versions: rulesOf[r.currencyAccountId] ?? const [],
            );
    }
    final cycles = <String, TxnCycle>{};
    for (final t in transactions) {
      final zone = zoneOf[t.currencyAccountId];
      if (zone == null) {
        continue;
      }
      cycles[t.id] = transactionCycle(
        t,
        versions: rulesOf[t.currencyAccountId] ?? const [],
        issued: <IssuedStatement>[
          for (final s in statements)
            if (s.currencyAccountId == t.currencyAccountId)
              IssuedStatement(
                LocalDate.parse(s.statementDate),
                LocalDate.parse(s.dueDate),
                'statement',
              ),
        ],
        zone: zone,
      );
    }

    // 每个币种子账户：账单按账单日升序，最近一期是本期，更早的并入下一期（PRD §6.2 裁决段）。
    final balances = <String, StatementBalance>{};
    final currentOf = <String, StatementBalance>{};
    for (final sub in subs) {
      final today = todayOf[sub.id];
      if (today == null) {
        continue;
      }
      final own = <StatementRow>[
        for (final s in statements.reversed)
          if (s.currencyAccountId == sub.id) s,
      ]..sort((a, b) => a.statementDate.compareTo(b.statementDate));
      final mine = <RepaymentRow>[
        for (final r in repayments)
          if (r.currencyAccountId == sub.id) r,
      ];
      for (var i = 0; i < own.length; i++) {
        final s = own[i];
        final current = versions[s.id]?.last;
        if (current == null) {
          continue;
        }
        if (i + 1 < own.length) {
          balances[s.id] = StatementBalance(
            statement: s,
            current: current,
            today: today,
            mergedInto: LocalDate.parse(own[i + 1].statementDate),
          );
          continue;
        }
        final date = LocalDate.parse(s.statementDate);
        final balance = StatementBalance(
          statement: s,
          current: current,
          today: today,
          paidAfter: creditedAfter(
            repayments: mine,
            creditDates: creditDates,
            after: date,
            on: today,
            openDuplicates: openDuplicates,
          ),
          paidAfterConfirmed: creditedAfter(
            repayments: mine,
            creditDates: creditDates,
            after: date,
            on: today,
            openDuplicates: openDuplicates,
            bankConfirmedOnly: true,
          ),
          adjustments: installmentAdjustmentsFor(
            statement: s,
            version: current,
            plans: plans,
            periods: periods,
            cycles: cycles,
          ),
        );
        balances[s.id] = balance;
        currentOf[sub.id] = balance;
      }
    }

    final covered = <String>{
      for (final p in plans)
        if (InstallmentPlanStatus.of(p.status).coversPrincipal) p.transactionId,
    };
    final liabilities = <String, LiabilityBreakdown>{};
    for (final sub in subs) {
      final zone = zoneOf[sub.id];
      if (zone == null) {
        continue;
      }
      liabilities[sub.id] = liabilityOf(
        currency: sub.currency,
        latest: currentOf[sub.id],
        transactions: <(CardTransactionRow, TxnCycle)>[
          for (final t in transactions)
            if (t.currencyAccountId == sub.id)
              (t, cycles[t.id] ?? const TxnCycleNoRule()),
        ],
        coveredByPlans: covered,
        refundIncluded: offsetRefunds,
        periods: <InstallmentScheduleRow>[
          for (final p in plans)
            if (p.currencyAccountId == sub.id &&
                InstallmentPlanStatus.of(p.status).coversPrincipal)
              ...?periods[p.id],
        ],
        zone: zone,
      );
    }

    return LedgerData(
      wallet: wallet,
      currencyAccounts: subById,
      statements: statements,
      versions: versions,
      balances: balances,
      transactions: transactions,
      cycles: cycles,
      plans: plans,
      periods: periods,
      repayments: repayments,
      allocations: allocations,
      items: items,
      repaymentEvents: repaymentEvents,
      cashAccounts: cashAccounts,
      liabilities: liabilities,
      todayByCurrencyAccount: todayOf,
      offsetRefunds: offsetRefunds,
      openDuplicates: openDuplicates,
      creditDates: creditDates,
      cashToday: _scope.clock.today(cashTimeZone),
    );
  }

  /// 额度释放（F-28）：某币种子账户最新额度快照之后银行入账、但因释放时滞未知而暂不计入可用容量的还款合计。
  /// 账户规则里没有释放时滞（未知）→ 一律不释放（[releasedRepaymentsOn] 的 releaseLagDays 为 null）。
  static int unreleasedRepayments(LedgerData data, String currencyAccountId) {
    final account = data.accountOf(currencyAccountId);
    if (account == null) {
      return 0;
    }
    LimitSnapshotRow? snapshot;
    for (final c in account.currencies) {
      if (c.row.id == currencyAccountId) {
        snapshot = c.latestSnapshot;
      }
    }
    if (snapshot == null) {
      return 0;
    }
    final snapshotDate = snapshotBusinessDate(snapshot, account.zone);
    final today = data.todayByCurrencyAccount[currencyAccountId]!;
    final mine = <RepaymentRow>[
      for (final r in data.repayments)
        if (r.currencyAccountId == currencyAccountId) r,
    ];
    final credited = releasedRepaymentsOn(
      repayments: mine,
      creditDates: data.creditDates,
      snapshotDate: snapshotDate,
      on: today,
      releaseLagDays: 0,
    );
    final released = releasedRepaymentsOn(
      repayments: mine,
      creditDates: data.creditDates,
      snapshotDate: snapshotDate,
      on: today,
      releaseLagDays: null,
    );
    return credited - released;
  }
}
