// 仓库测试的工厂函数：建库、建工作空间、造账户与卡、声明规则、记录快照。
//
// 默认用真实 sqlite3mc（临时目录里的加密库，与 App 相同的打开流程）；组件测试另用
// [openMemoryTestDatabase]（内存库，不加密，见 test/test_helpers.dart）。
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/ids.dart';
import 'package:cardflow/data/repositories/billing_rule_repository.dart';
import 'package:cardflow/data/repositories/card_repository.dart';
import 'package:cardflow/data/repositories/cash_account_repository.dart';
import 'package:cardflow/data/repositories/cash_event_repository.dart';
import 'package:cardflow/data/repositories/cash_models.dart';
import 'package:cardflow/data/repositories/credit_account_repository.dart';
import 'package:cardflow/data/repositories/ledger_models.dart';
import 'package:cardflow/data/repositories/limit_snapshot_repository.dart';
import 'package:cardflow/data/repositories/models.dart';
import 'package:cardflow/data/repositories/repayment_repository.dart';
import 'package:cardflow/data/repositories/statement_repository.dart';
import 'package:cardflow/data/repositories/transaction_repository.dart';
import 'package:cardflow/data/repositories/workspace_repository.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow/data/time/clock.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../db/db_test_support.dart';

/// 仓库测试的"现在"：北京时间 2026-10-18 12:00。
final FixedClock testClock = FixedClock(DateTime.utc(2026, 10, 18, 4));

/// 时刻固定、但像真实空间一样判断陈旧的时钟（[FixedClock] 是演示空间的时钟，不判陈旧）。
final class StaleAwareClock implements AppClock {
  const StaleAwareClock(this.instant);

  final DateTime instant;

  @override
  DateTime now() => instant.toUtc();

  @override
  bool get isFixed => false;
}

/// 在临时目录打开真实加密库（与 App 相同的流程），测试结束时关闭。
Future<AppDatabase> openRealTestDatabase() async {
  final opened = await openTestDatabase(
    createTempLocation(),
    InMemoryDatabaseKeyStore(),
  );
  addTearDown(opened.database.close);
  return opened.database;
}

/// 内存库（不加密；只用于组件测试与不涉及加密的快速测试）。
AppDatabase openMemoryTestDatabase() =>
    AppDatabase.forTesting(NativeDatabase.memory());

/// 建一个工作空间（默认真实空间），设为当前，返回它的作用域。
Future<WorkspaceScope> createTestWorkspace(
  AppDatabase db, {
  WorkspaceKind kind = WorkspaceKind.real,
  AppClock? clock,
  bool makeCurrent = true,
}) async {
  final workspaces = WorkspaceRepository(db, clock: clock ?? testClock);
  final row = await workspaces.ensure(kind);
  if (makeCurrent) {
    await workspaces.setCurrent(row.id);
  }
  return WorkspaceScope(db: db, workspaceId: row.id, clock: clock ?? testClock);
}

/// 建一张卡（默认新建信用账户；[joinAccountId] 加入既有账户；[primaryCardId] 建附属卡）。
Future<NewCardResult> createTestCard(
  WorkspaceScope scope, {
  String bank = '招商银行',
  String last4 = '1234',
  String? alias,
  String? productName,
  String? joinAccountId,
  String? primaryCardId,
  CardNetwork? network,
  String businessTz = 'Asia/Shanghai',
}) => CardRepository(scope).create(
  NewCardDraft(
    cardId: newUuidV4(),
    newAccountId: newUuidV4(),
    bankName: bank,
    last4: last4,
    alias: alias,
    productName: productName,
    joinAccountId: joinAccountId,
    primaryCardId: primaryCardId,
    holderKind: primaryCardId == null
        ? HolderKind.primary
        : HolderKind.supplementary,
    network: network,
    businessTz: businessTz,
  ),
);

/// 为信用账户声明一个规则版本（默认：账单日 10 日、当月 28 日到期）。
Future<BillingRuleVersionRow> declareTestRule(
  WorkspaceScope scope,
  String creditAccountId, {
  int statementDay = 10,
  DueRule due = const DueRule.fixedDay(day: 28),
  bool inclusive = true,
  String? cutoffTime,
  int postingDelayMin = 0,
  int postingDelayMax = 0,
  RuleEffect effect = const RuleCorrection(),
}) => BillingRuleRepository(scope).saveVersion(
  RuleSubject.creditAccount(creditAccountId),
  BillingRuleDraft(
    statementDay: statementDay,
    due: due,
    statementDayInclusive: inclusive,
    cutoffTime: cutoffTime,
    postingDelayMinDays: postingDelayMin,
    postingDelayMaxDays: postingDelayMax,
  ),
  effect: effect,
);

/// 信用账户的主子账户。
Future<CurrencyAccountRow> primaryCurrencyAccount(
  WorkspaceScope scope,
  String creditAccountId,
) async =>
    (await CreditAccountRepository(scope).currencyAccounts(creditAccountId))
        .firstWhere((c) => c.isPrimary);

/// 记录一次额度快照（默认：固定 10,000，已用 0，可用 10,000，已含预授权，北京时间 10-17 20:00）。
Future<LimitSnapshotRow> recordTestSnapshot(
  WorkspaceScope scope,
  String currencyAccountId, {
  int fixed = 1000000,
  int used = 0,
  int? available,
  int temp = 0,
  LocalDate? tempExpiresOn,
  int special = 0,
  String? specialPurpose,
  int holds = 0,
  bool includesHolds = true,
  String balanceAsOf = '2026-10-17T20:00:00+08:00',
  String? observedAt,
}) => LimitSnapshotRepository(scope).record(
  LimitSnapshotDraft(
    currencyAccountId: currencyAccountId,
    fixedMinor: fixed,
    tempMinor: temp,
    tempExpiresOn: tempExpiresOn,
    specialMinor: special,
    specialPurpose: specialPurpose,
    usedMinor: used,
    availableRawMinor: available ?? fixed + temp - used,
    holdsMinor: holds,
    includesHolds: includesHolds,
    source: SnapshotSource.bankApp,
    balanceAsOf: Timestamp.parse(balanceAsOf),
    observedAt: Timestamp.parse(observedAt ?? balanceAsOf),
  ),
);

/// 断言 [action] 以某种仓库异常失败，返回该异常。
Future<T> expectRepositoryError<T extends Object>(
  Future<Object?> Function() action,
) async {
  try {
    await action();
  } on T catch (error) {
    return error;
  }
  fail('expected $T');
}

/// 建一个现金账户（默认：银行账户"工资卡"、CNY、储备 0、可用于还款）。
Future<CashAccountRow> createTestCashAccount(
  WorkspaceScope scope, {
  String name = '工资卡',
  CashAccountKind kind = CashAccountKind.bank,
  String currency = 'CNY',
  int reserve = 0,
  bool? usable,
  LocalDate? availableFrom,
}) => CashAccountRepository(scope).create(
  NewCashAccount(
    id: newUuidV4(),
    name: name,
    kind: kind,
    currency: currency,
    reserveFloorMinor: reserve,
    usableForRepayment: usable,
    availableFrom: availableFrom,
  ),
);

/// 记一笔收支：[amount] 带符号（正 = 收入，负 = 支出）；类别按领域包测试的写法：
/// 收入 `income`、支出 `bill`（[type] 可改）。
Future<CashEventRow> addTestCashEvent(
  WorkspaceScope scope,
  String accountId,
  LocalDate on,
  int amount, {
  CashEventClass cls = CashEventClass.confirmed,
  CashPlanType? type,
  Timestamp? at,
  String? label,
}) => CashEventRepository(scope).create(
  CashEventDraft(
    cashAccountId: accountId,
    type: type ?? (amount > 0 ? CashPlanType.income : CashPlanType.debt),
    cls: cls,
    on: on,
    amountMinor: amount.abs(),
    at: at,
    label: label,
  ),
);

/// 记录一次现金余额快照（默认：实际时点为快照日北京时间 20:00；当天的事件都答"未包含"，
/// [included] 里的答"已包含"）。
Future<CashSnapshotRow> recordTestCashSnapshot(
  WorkspaceScope scope,
  String accountId,
  LocalDate asOf,
  int balance, {
  Set<String> included = const <String>{},
  String? observedAt,
}) async {
  final repo = CashSnapshotRepository(scope);
  final sameDay = await repo.sameDayEvents(accountId, asOf);
  return repo.record(
    CashSnapshotDraft(
      cashAccountId: accountId,
      balanceMinor: balance,
      balanceAsOf: asOf,
      observedAt: Timestamp.parse(observedAt ?? '${asOf}T20:00:00+08:00'),
      sameDayAnswers: <String, bool>{
        for (final e in sameDay) e.id: included.contains(e.id),
      },
    ),
  );
}

/// 写一行最小的还款（直接写库，状态"已登记"）：现金事件的 `linked_repayment_id` 必须指向同一空间的
/// 还款（v4 触发器）。没有给 [currencyAccountId] 时新建一张卡、用它的主子账户。返回还款 id。
Future<String> insertTestRepaymentRow(
  WorkspaceScope scope, {
  required String cashAccountId,
  String? currencyAccountId,
  String? id,
  int amount = 100000,
}) async {
  final sub =
      currencyAccountId ??
      (await primaryCurrencyAccount(
        scope,
        (await createTestCard(scope, last4: '9001')).creditAccountId,
      )).id;
  final repaymentId = id ?? newUuidV4();
  const ts = '2026-10-18T09:00:00+08:00';
  await scope.db.customStatement(
    'INSERT INTO repayments (id, workspace_id, currency_account_id, cash_account_id, '
    'amount_minor, currency, status, method, created_at, updated_at) VALUES '
    "('$repaymentId', '${scope.workspaceId}', '$sub', '$cashAccountId', $amount, 'CNY', "
    "'recorded', 'manual', '$ts', '$ts')",
  );
  return repaymentId;
}

/// 录入一期正式账单（v1，默认 10-10 出账、10-28 到期、本期应还 1,000、最低还款 100）。
Future<StatementRow> recordTestStatement(
  WorkspaceScope scope,
  String currencyAccountId, {
  LocalDate? statementDate,
  LocalDate? dueDate,
  int newBalance = 100000,
  int? minDue = 10000,
  int? installmentDue,
  int? creditBalance,
}) => StatementRepository(scope).recordIssued(
  StatementEntryDraft(
    currencyAccountId: currencyAccountId,
    statementDate: statementDate ?? LocalDate(2026, 10, 10),
    dueDate: dueDate ?? LocalDate(2026, 10, 28),
    figures: StatementFigures(
      newBalanceMinor: newBalance,
      minDueMinor: minDue,
      installmentDueMinor: installmentDue,
      creditBalanceMinor: creditBalance,
    ),
  ),
);

/// 记一笔交易（默认消费 100，北京时间 10-12 10:00，当天入账）。[amount] 带符号。
Future<CardTransactionRow> addTestTransaction(
  WorkspaceScope scope,
  String currencyAccountId, {
  TxnType type = TxnType.purchase,
  int amount = 10000,
  String txnAt = '2026-10-12T10:00:00+08:00',
  LocalDate? postedOn,
  bool unposted = false,
  String? cardId,
  String? merchant,
  String? parentTransactionId,
}) => TransactionRepository(scope).create(
  TransactionDraft(
    currencyAccountId: currencyAccountId,
    type: type,
    amountMinor: amount,
    txnAt: Timestamp.parse(txnAt),
    postedOn: unposted ? null : postedOn ?? Timestamp.parse(txnAt).date,
    cardId: cardId,
    merchant: merchant,
    parentTransactionId: parentTransactionId,
  ),
);

/// 登记一笔还款（默认手动还款，全额分配到 [statementId]）。
Future<RepaymentRow> registerTestRepayment(
  WorkspaceScope scope, {
  required String currencyAccountId,
  required String? cashAccountId,
  required int amount,
  Map<String, int>? allocations,
  String? statementId,
  RepaymentMethod method = RepaymentMethod.manual,
  LocalDate? expectedDebitOn,
  String? initiatedAt,
}) => RepaymentRepository(scope).create(
  RepaymentDraft(
    currencyAccountId: currencyAccountId,
    cashAccountId: cashAccountId,
    amountMinor: amount,
    method: method,
    allocations: allocations ?? <String, int>{?statementId: amount},
    expectedDebitOn: expectedDebitOn,
    initiatedAt: initiatedAt == null ? null : Timestamp.parse(initiatedAt),
  ),
);
