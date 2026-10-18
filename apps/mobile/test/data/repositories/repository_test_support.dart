// 仓库测试的工厂函数：建库、建工作空间、造账户与卡、声明规则、记录快照。
//
// 默认用真实 sqlite3mc（临时目录里的加密库，与 App 相同的打开流程）；组件测试另用
// [openMemoryTestDatabase]（内存库，不加密，见 test/test_helpers.dart）。
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/ids.dart';
import 'package:cardflow/data/repositories/billing_rule_repository.dart';
import 'package:cardflow/data/repositories/card_repository.dart';
import 'package:cardflow/data/repositories/credit_account_repository.dart';
import 'package:cardflow/data/repositories/limit_snapshot_repository.dart';
import 'package:cardflow/data/repositories/models.dart';
import 'package:cardflow/data/repositories/workspace_repository.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow/data/time/clock.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../db/db_test_support.dart';

/// 仓库测试的"现在"：北京时间 2026-10-18 12:00。
final FixedClock testClock = FixedClock(DateTime.utc(2026, 10, 18, 4));

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
