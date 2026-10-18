/// 演示空间的合成数据（R-SYS-13、ui-spec §4.2、PRD §10）。
///
/// 卡 A/B/C 的账期与可用额与回归样本一致（engine-spec §9：A 账单 10 日/当月 28 日到期、可用 8,000；
/// B 账单 20 日/次月 8 日、可用 15,000；C 账单 5 日/当月 25 日、可用 6,000），另加与 B 同行的卡 D：
///
/// | 卡 | 银行 | 体现 |
/// |---|---|---|
/// | A（主卡 + 附属卡） | 演示银行甲 | 两张卡同一信用账户（F-21） |
/// | B | 演示银行乙 | 临时额度 5,000，2026-11-15 到期（F-27） |
/// | D | 演示银行乙（另一个独立授信，F-22） | 可用 −200，超限（F-26） |
/// | B + D | "乙行共享额度"池，上限 20,000 | 池内可用合计不超过池上限（F-23） |
/// | C | 演示银行丙 | 截止时点 22:00 的规则说明 |
///
/// 现金部分（I-1b，[seedDemoCash]）：现金账户 2 个（"工资卡"、受限的"定期存款"）、余额快照（工资卡的
/// 快照当天已包含早餐、未包含水电费）、收支计划（与回归样本 engine-spec §9 的事件同一组数值）、
/// 一个周期事项（房租，每月 27 日，12-27 那一期覆盖为 1,200）、一笔调拨（11-01 工资卡 → 定期存款
/// 2,500）、一个压力情景（收入推迟 3 天），并计算"基准预期"与压力情景各一个版本。固定"今天"下，
/// 基准口径 30 天内有一个可见缺口：11-01 定存转出后工资卡余额 300，低于储备 2,000。
///
/// 所有写入都经仓库（同样的校验），在一个事务里完成；固定"今天" = 2026-10-16（[demoClock]）。
library;

import 'package:cardflow_domain/cardflow_domain.dart';

import '../db/app_database.dart';
import '../ids.dart';
import '../repositories/billing_rule_repository.dart';
import '../repositories/card_repository.dart';
import '../repositories/cash_account_repository.dart';
import '../repositories/cash_event_repository.dart';
import '../repositories/cash_forecast_reader.dart';
import '../repositories/cash_models.dart';
import '../repositories/credit_account_repository.dart';
import '../repositories/credit_pool_repository.dart';
import '../repositories/limit_snapshot_repository.dart';
import '../repositories/models.dart';
import '../repositories/recurring_item_repository.dart';
import '../repositories/scenario_repository.dart';
import '../repositories/workspace_repository.dart';
import '../repositories/workspace_scope.dart';
import '../time/clock.dart';

/// 演示数据的快照时点（北京时间 2026-10-15 20:00，"今天"的前一天）。
final Timestamp demoSnapshotAsOf = Timestamp.parse('2026-10-15T20:00:00+08:00');

/// 取得演示空间：已有则直接返回；没有则新建并写入合成数据（一个事务，失败不留下半截）。
Future<WorkspaceRow> ensureDemoWorkspace(AppDatabase db) =>
    db.transaction(() async {
      final workspaces = WorkspaceRepository(db, clock: demoClock);
      final existing = await workspaces.live(WorkspaceKind.demo);
      if (existing != null) {
        return existing;
      }
      final demo = await workspaces.ensure(WorkspaceKind.demo);
      await seedDemoWorkspace(
        WorkspaceScope(db: db, workspaceId: demo.id, clock: demoClock),
      );
      return demo;
    });

/// 把合成数据写进 [scope] 所指的（空的）工作空间。
Future<void> seedDemoWorkspace(WorkspaceScope scope) async {
  final cards = CardRepository(scope);
  final accounts = CreditAccountRepository(scope);
  final pools = CreditPoolRepository(scope);
  final rules = BillingRuleRepository(scope);
  final snapshots = LimitSnapshotRepository(scope);

  Future<String> card(
    String bank,
    String last4,
    String alias, {
    String product = '演示白金卡',
    String? joinAccountId,
    String? primaryCardId,
    CardNetwork network = CardNetwork.unionpay,
  }) async {
    final result = await cards.create(
      NewCardDraft(
        cardId: newUuidV4(),
        newAccountId: newUuidV4(),
        bankName: bank,
        productName: product,
        alias: alias,
        last4: last4,
        network: network,
        holderKind: primaryCardId == null
            ? HolderKind.primary
            : HolderKind.supplementary,
        primaryCardId: primaryCardId,
        joinAccountId: joinAccountId,
        expiresYm: '2030-12',
      ),
    );
    return result.cardId;
  }

  Future<String> accountOf(String cardId) async =>
      (await cards.require(cardId)).creditAccountId;

  Future<void> rule(String accountId, BillingRuleDraft draft) =>
      rules.saveVersion(RuleSubject.creditAccount(accountId), draft);

  Future<void> snapshot(
    String accountId, {
    required int fixed,
    required int used,
    required int available,
    int temp = 0,
    LocalDate? tempExpiresOn,
  }) async {
    final primary = (await accounts.currencyAccounts(accountId)).first;
    await snapshots.record(
      LimitSnapshotDraft(
        currencyAccountId: primary.id,
        fixedMinor: fixed,
        tempMinor: temp,
        tempExpiresOn: tempExpiresOn,
        usedMinor: used,
        availableRawMinor: available,
        includesHolds: true,
        source: SnapshotSource.bankApp,
        balanceAsOf: demoSnapshotAsOf,
        observedAt: Timestamp.parse('2026-10-15T20:05:00+08:00'),
      ),
    );
  }

  // 卡 A：主卡与附属卡，同一信用账户（F-21）。
  final a = await card('演示银行甲', '1001', '卡 A');
  await card('演示银行甲', '1002', '卡 A 附属卡', primaryCardId: a);
  final accountA = await accountOf(a);
  await rule(
    accountA,
    const BillingRuleDraft(statementDay: 10, due: DueRule.fixedDay(day: 28)),
  );
  await snapshot(accountA, fixed: 2000000, used: 1200000, available: 800000);

  // 卡 B：临时额度带到期日（F-27）。
  final b = await card('演示银行乙', '2001', '卡 B', network: CardNetwork.visa);
  final accountB = await accountOf(b);
  await rule(
    accountB,
    const BillingRuleDraft(
      statementDay: 20,
      due: DueRule.fixedDay(day: 8, monthOffset: 1),
    ),
  );
  await snapshot(
    accountB,
    fixed: 1000000,
    temp: 500000,
    tempExpiresOn: LocalDate(2026, 11, 15),
    used: 0,
    available: 1500000,
  );

  // 卡 D：同一银行的另一个独立授信（F-22），超限（F-26）。
  final d = await card('演示银行乙', '4001', '卡 D', product: '演示金卡');
  final accountD = await accountOf(d);
  await rule(
    accountD,
    const BillingRuleDraft(
      statementDay: 15,
      due: DueRule.daysAfterStatement(days: 20),
    ),
  );
  await snapshot(accountD, fixed: 500000, used: 520000, available: -20000);

  // B 与 D 共享授信池（F-23）。
  final bankB = (await accounts.require(accountB)).bankId;
  final pool = await pools.create(
    bankId: bankB,
    name: '乙行共享额度',
    sharedLimitMinor: 2000000,
  );
  await accounts.joinPool(accountB, pool.id);
  await accounts.joinPool(accountD, pool.id);

  // 卡 C。
  final c = await card('演示银行丙', '3001', '卡 C', network: CardNetwork.mastercard);
  final accountC = await accountOf(c);
  await rule(
    accountC,
    const BillingRuleDraft(
      statementDay: 5,
      due: DueRule.fixedDay(day: 25),
      cutoffTime: '22:00',
    ),
  );
  await snapshot(accountC, fixed: 1000000, used: 400000, available: 600000);

  await seedDemoCash(scope);
}

/// 演示空间的现金数据（见文件头）。
Future<void> seedDemoCash(WorkspaceScope scope) async {
  final accounts = CashAccountRepository(scope);
  final snapshots = CashSnapshotRepository(scope);
  final events = CashEventRepository(scope);
  final recurring = RecurringItemRepository(scope);
  final scenarios = ScenarioRepository(scope);
  LocalDate day(int month, int date) => LocalDate(2026, month, date);
  Timestamp at(LocalDate on, String time) =>
      Timestamp.parse('${on}T$time:00+08:00');

  final salary = await accounts.create(
    NewCashAccount(
      id: newUuidV4(),
      name: '工资卡',
      kind: CashAccountKind.bank,
      reserveFloorMinor: 200000,
    ),
  );
  final deposit = await accounts.create(
    NewCashAccount(
      id: newUuidV4(),
      name: '定期存款',
      kind: CashAccountKind.restricted,
    ),
  );

  // 快照当天的两笔：早餐（已发生，余额已包含）、水电费（下午扣，余额未包含 → 计入当日）。
  final breakfast = await events.create(
    CashEventDraft(
      cashAccountId: salary.id,
      type: CashPlanType.oneOff,
      cls: CashEventClass.confirmed,
      on: day(10, 16),
      at: at(day(10, 16), '08:10'),
      amountMinor: 3000,
      label: '早餐',
    ),
  );
  await events.markPosted(breakfast.id);
  final utilities = await events.create(
    CashEventDraft(
      cashAccountId: salary.id,
      type: CashPlanType.living,
      cls: CashEventClass.confirmed,
      on: day(10, 16),
      at: at(day(10, 16), '15:00'),
      amountMinor: 20000,
      label: '水电费',
    ),
  );
  await snapshots.record(
    CashSnapshotDraft(
      cashAccountId: salary.id,
      balanceMinor: 500000,
      balanceAsOf: day(10, 16),
      observedAt: at(day(10, 16), '09:30'),
      sameDayAnswers: <String, bool>{breakfast.id: true, utilities.id: false},
    ),
  );
  await snapshots.record(
    CashSnapshotDraft(
      cashAccountId: deposit.id,
      balanceMinor: 2000000,
      balanceAsOf: day(10, 15),
      observedAt: at(day(10, 15), '18:00'),
    ),
  );

  // 收支计划：回归样本的事件（生活支出改成周期事项"房租"，见下）。
  for (final (on, type, cls, amount, label)
      in <(LocalDate, CashPlanType, CashEventClass, int, String)>[
        (
          day(10, 28),
          CashPlanType.debt,
          CashEventClass.confirmed,
          100000,
          '贷款月供',
        ),
        (
          day(11, 6),
          CashPlanType.income,
          CashEventClass.expected,
          850000,
          '工资',
        ),
        (
          day(11, 8),
          CashPlanType.debt,
          CashEventClass.confirmed,
          500000,
          '已出账单',
        ),
        (
          day(11, 16),
          CashPlanType.debt,
          CashEventClass.confirmed,
          350000,
          '已出账单',
        ),
        (
          day(11, 20),
          CashPlanType.income,
          CashEventClass.expected,
          700000,
          '奖金',
        ),
        (
          day(11, 22),
          CashPlanType.living,
          CashEventClass.confirmed,
          200000,
          '日常开销',
        ),
        (
          day(11, 26),
          CashPlanType.income,
          CashEventClass.expected,
          500000,
          '报销',
        ),
      ]) {
    await events.create(
      CashEventDraft(
        cashAccountId: salary.id,
        type: type,
        cls: cls,
        on: on,
        amountMinor: amount,
        label: label,
      ),
    );
  }

  // 周期事项：房租每月 27 日；12-27 那一期续租涨价（单期覆盖，不影响他期）。
  final rent = await recurring.create(
    RecurringItemDraft(
      cashAccountId: salary.id,
      label: '房租',
      type: CashPlanType.living,
      cls: CashEventClass.confirmed,
      amountMinor: 100000,
      frequency: RecurringFrequency.monthly,
      startOn: day(10, 27),
    ),
  );
  await recurring.overrideOccurrence(rent.id, day(12, 27), amountMinor: 120000);

  // 调拨：11-01 工资卡 → 定期存款（受限资金：不计入可用现金）。
  await events.createTransfer(
    TransferDraft(
      fromAccountId: salary.id,
      toAccountId: deposit.id,
      amountMinor: 250000,
      outOn: day(11, 1),
      inOn: day(11, 1),
      cls: CashEventClass.confirmed,
      label: '定存',
    ),
  );

  // 压力情景：预计收入推迟 3 天；"基准预期"与它各计算一个版本（P-09 可对比）。
  final stress = await scenarios.create(
    const ScenarioDraft(name: '收入推迟 3 天', incomeDelayDays: 3),
  );
  final reader = CashForecastReader(scope);
  await reader.recompute(ScenarioView.builtinKey(ScenarioKind.builtinBaseline));
  await reader.recompute(stress.id);
}
