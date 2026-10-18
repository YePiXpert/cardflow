// 现金仓库（真实 sqlite3mc）：现金账户（G2/G5、不重名、受限资金、储备 ≥0）、余额快照（逐条询问"是否
// 已包含"、只包含快照日当天及以前的本账户事件、G3、最新快照）、收支计划（须选层级、正负由类型决定、
// 标记已发生 G3、删除）、调拨（两端不同、币种相同、到账不早于转出、两端一起确认/删除）、受限账户不进入
// 可用现金（设可用日期后进入并记假设）、给 I-1c 的还款扣款接口（planned → 确认扣款转 confirmed）。
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/repositories/cash_account_repository.dart';
import 'package:cardflow/data/repositories/cash_event_repository.dart';
import 'package:cardflow/data/repositories/cash_forecast_reader.dart';
import 'package:cardflow/data/repositories/cash_models.dart';
import 'package:cardflow/data/repositories/models.dart';
import 'package:cardflow/data/repositories/repository_errors.dart';
import 'package:cardflow/data/repositories/scenario_repository.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repository_test_support.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

void main() {
  late AppDatabase db;
  late WorkspaceScope scope;
  late CashAccountRepository accounts;
  late CashSnapshotRepository snapshots;
  late CashEventRepository events;

  setUp(() async {
    db = await openRealTestDatabase();
    scope = await createTestWorkspace(db);
    accounts = CashAccountRepository(scope);
    snapshots = CashSnapshotRepository(scope);
    events = CashEventRepository(scope);
  });

  group('现金账户', () {
    test('新建：幂等；种类决定"可用于还款"的默认值；名称 G2/G5 与不重名；储备 ≥0；币种 13 种', () async {
      final draft = NewCashAccount(
        id: 'a1-00000000-0000-4000-8000-000000000001',
        name: ' 工资卡 ',
        kind: CashAccountKind.bank,
        reserveFloorMinor: 200000,
      );
      final row = await accounts.create(draft);
      expect(row.name, '工资卡');
      expect(row.usableForRepayment, isTrue);
      expect((await accounts.create(draft)).id, row.id, reason: '重试保存不重复建账户');
      expect(await accounts.list(), hasLength(1));

      final wealth = await createTestCashAccount(
        scope,
        name: '理财',
        kind: CashAccountKind.wealth,
      );
      expect(wealth.usableForRepayment, isFalse, reason: '理财默认不可当日还款');

      for (final (name, field) in <(String, String)>[
        ('', 'name'),
        ('卡号6222020200112233', 'name'),
        ('一二三四五六七八九十一二三四五六七八九十一', 'name'),
      ]) {
        final error = await expectRepositoryError<ValidationException>(
          () => createTestCashAccount(scope, name: name),
        );
        expect(error.field, field, reason: name);
      }
      expect(
        (await expectRepositoryError<ValidationException>(
          () => createTestCashAccount(scope, name: '甲', reserve: -1),
        )).field,
        'reserveFloor',
      );
      expect(
        (await expectRepositoryError<ValidationException>(
          () => createTestCashAccount(scope, name: '乙', currency: 'RMB'),
        )).field,
        'currency',
      );
      await expectRepositoryError<ConflictException>(
        () => createTestCashAccount(scope, name: '工资卡'),
      );
    });

    test('受限资金不能直接标为可用于还款，只能设可用日期；修改与停用', () async {
      final error = await expectRepositoryError<ValidationException>(
        () => createTestCashAccount(
          scope,
          name: '定期',
          kind: CashAccountKind.restricted,
          usable: true,
        ),
      );
      expect(error.field, 'usableForRepayment');
      final locked = await createTestCashAccount(
        scope,
        name: '定期',
        kind: CashAccountKind.restricted,
      );
      expect(locked.usableForRepayment, isFalse);
      expect(CashAvailability.of(locked).counted, isFalse);
      await accounts.update(locked.id, availableFrom: d(2026, 11, 10));
      final updated = await accounts.require(locked.id);
      expect(CashAvailability.of(updated).counted, isTrue);
      expect(CashAvailability.of(updated).usableOn(d(2026, 11, 9)), isFalse);
      expect(CashAvailability.of(updated).usableOn(d(2026, 11, 10)), isTrue);
      await accounts.update(
        locked.id,
        clearAvailableFrom: true,
        reserveFloorMinor: 100,
      );
      expect((await accounts.require(locked.id)).availableFrom, isNull);
      await expectRepositoryError<ValidationException>(
        () => accounts.update(locked.id, usableForRepayment: true),
      );
      await accounts.setStatus(locked.id, CashAccountStatus.closed);
      expect((await accounts.require(locked.id)).status, 'closed');
    });
  });

  group('余额快照', () {
    test('当天已有事件时逐条询问"是否已包含"：没答完不能存；答"已包含"的写进包含关系', () async {
      final acc = await createTestCashAccount(scope);
      final a = await addTestCashEvent(scope, acc.id, d(2026, 10, 18), -1000);
      final b = await addTestCashEvent(scope, acc.id, d(2026, 10, 18), 5000);
      final error = await expectRepositoryError<ValidationException>(
        () => snapshots.record(
          CashSnapshotDraft(
            cashAccountId: acc.id,
            balanceMinor: 100000,
            balanceAsOf: d(2026, 10, 18),
            observedAt: Timestamp.parse('2026-10-18T11:00:00+08:00'),
            sameDayAnswers: {a.id: true},
          ),
        ),
      );
      expect(error.field, 'includes');
      final row = await snapshots.record(
        CashSnapshotDraft(
          cashAccountId: acc.id,
          balanceMinor: 100000,
          balanceAsOf: d(2026, 10, 18),
          observedAt: Timestamp.parse('2026-10-18T11:00:00+08:00'),
          sameDayAnswers: {a.id: true, b.id: false},
        ),
      );
      expect(await snapshots.includedIn(row.id), {a.id});
    });

    test('只能包含本账户、快照日当天及以前的未删除事件', () async {
      final acc = await createTestCashAccount(scope);
      final other = await createTestCashAccount(scope, name: '零钱');
      final before = await addTestCashEvent(
        scope,
        acc.id,
        d(2026, 10, 15),
        -1000,
      );
      final after = await addTestCashEvent(
        scope,
        acc.id,
        d(2026, 10, 18),
        -1000,
      );
      final foreign = await addTestCashEvent(
        scope,
        other.id,
        d(2026, 10, 16),
        -1000,
      );
      Future<void> record(Map<String, bool> answers) => snapshots.record(
        CashSnapshotDraft(
          cashAccountId: acc.id,
          balanceMinor: 100000,
          balanceAsOf: d(2026, 10, 16),
          observedAt: Timestamp.parse('2026-10-16T20:00:00+08:00'),
          sameDayAnswers: answers,
        ),
      );
      for (final answers in <Map<String, bool>>[
        {after.id: true},
        {foreign.id: true},
      ]) {
        expect(
          (await expectRepositoryError<ValidationException>(
            () => record(answers),
          )).field,
          'includes',
        );
      }
      await record({before.id: true});
    });

    test('G3：余额日期不晚于今天，实际时点不晚于现在、不早于余额日期；余额可为负；最新快照', () async {
      final acc = await createTestCashAccount(scope);
      Future<CashSnapshotRow> record(
        LocalDate asOf,
        String observed, {
        int balance = 1000,
      }) => snapshots.record(
        CashSnapshotDraft(
          cashAccountId: acc.id,
          balanceMinor: balance,
          balanceAsOf: asOf,
          observedAt: Timestamp.parse(observed),
        ),
      );
      expect(
        (await expectRepositoryError<ValidationException>(
          () => record(d(2026, 10, 19), '2026-10-18T09:00:00+08:00'),
        )).field,
        'balanceAsOf',
      );
      expect(
        (await expectRepositoryError<ValidationException>(
          () => record(d(2026, 10, 18), '2026-10-18T13:00:00+08:00'),
        )).field,
        'observedAt',
        reason: '现在是 12:00',
      );
      expect(
        (await expectRepositoryError<ValidationException>(
          () => record(d(2026, 10, 17), '2026-10-16T23:00:00+08:00'),
        )).field,
        'observedAt',
      );
      await record(d(2026, 10, 10), '2026-10-10T09:00:00+08:00');
      // 同一时刻写成 UTC：按现金时区仍是 10-17。
      final newest = await record(
        d(2026, 10, 17),
        '2026-10-17T01:00:00Z',
        balance: -500,
      );
      await record(d(2026, 10, 12), '2026-10-12T09:00:00+08:00');
      expect((await snapshots.latestByAccount())[acc.id]!.id, newest.id);
      expect(newest.balanceMinor, -500);
      expect((await snapshots.history(acc.id)).map((s) => s.balanceAsOf), [
        '2026-10-17',
        '2026-10-12',
        '2026-10-10',
      ]);
    });
  });

  group('收支计划', () {
    test('须选层级（确定/预计）；正负由类型决定；时刻按现金时区写入且须在当天；名称 G2/G5', () async {
      final acc = await createTestCashAccount(scope);
      final rent = await events.create(
        CashEventDraft(
          cashAccountId: acc.id,
          type: CashPlanType.living,
          cls: CashEventClass.confirmed,
          on: d(2026, 10, 27),
          amountMinor: 100000,
          at: Timestamp.parse('2026-10-27T01:30:00Z'),
          label: '房租',
        ),
      );
      expect(rent.amountMinor, -100000);
      expect(rent.category, 'living');
      expect(rent.eventAt, '2026-10-27T09:30:00+08:00');
      final salary = await addTestCashEvent(
        scope,
        acc.id,
        d(2026, 11, 6),
        850000,
        cls: CashEventClass.expected,
      );
      expect(
        (salary.amountMinor, salary.category, salary.cls),
        (850000, 'income', 'expected'),
      );

      Future<ValidationException> bad(CashEventDraft draft) =>
          expectRepositoryError<ValidationException>(
            () => events.create(draft),
          );
      CashEventDraft draft({
        CashEventClass cls = CashEventClass.confirmed,
        int amount = 100,
        Timestamp? at,
        String? label,
      }) => CashEventDraft(
        cashAccountId: acc.id,
        type: CashPlanType.oneOff,
        cls: cls,
        on: d(2026, 10, 30),
        amountMinor: amount,
        at: at,
        label: label,
      );
      expect((await bad(draft(cls: CashEventClass.planned))).field, 'cls');
      expect((await bad(draft(amount: 0))).field, 'amount');
      expect((await bad(draft(amount: 10000000000001))).field, 'amount');
      expect(
        (await bad(draft(at: Timestamp.parse('2026-10-30T20:00:00Z')))).field,
        'at',
        reason: 'UTC 20:00 是现金时区的次日',
      );
      expect((await bad(draft(label: '卡号6222020200112233'))).field, 'label');
      final oneOff = await events.create(draft(label: '换手机'));
      expect((oneOff.amountMinor, oneOff.category), (-100, 'other'));
      expect(CashPlanType.ofEvent(oneOff), CashPlanType.oneOff);
    });

    test('标记已发生（计划/预计 → 确定、已发生）：G3 不晚于今天；可更正金额；已发生的不能退回预计', () async {
      final acc = await createTestCashAccount(scope);
      final future = await addTestCashEvent(
        scope,
        acc.id,
        d(2026, 10, 20),
        5000,
        cls: CashEventClass.expected,
      );
      expect(
        (await expectRepositoryError<ValidationException>(
          () => events.markPosted(future.id),
        )).field,
        'on',
      );
      final past = await addTestCashEvent(
        scope,
        acc.id,
        d(2026, 10, 17),
        5000,
        cls: CashEventClass.expected,
      );
      await events.markPosted(past.id, amountMinor: 4800);
      final posted = await events.require(past.id);
      expect(
        (posted.cls, posted.postingStatus, posted.amountMinor),
        ('confirmed', 'posted', 4800),
      );
      await expectRepositoryError<ConflictException>(
        () => events.update(past.id, cls: CashEventClass.expected),
      );
      expect(
        (await expectRepositoryError<ValidationException>(
          () => events.update(past.id, on: d(2026, 10, 19)),
        )).field,
        'on',
        reason: '已发生的收支，日期不能晚于今天（G3）',
      );
      await events.update(past.id, amountMinor: 4900, label: '奖金');
      expect((await events.require(past.id)).amountMinor, 4900);
      await events.delete(past.id);
      expect(await events.byId(past.id), isNull);
      expect(await events.list(), hasLength(1));
    });
  });

  group('调拨', () {
    test('两条事件共享调拨组：转出为负、到账为正；两端不同、币种相同、到账不早于转出', () async {
      final main = await createTestCashAccount(scope);
      final saving = await createTestCashAccount(
        scope,
        name: '定期',
        kind: CashAccountKind.restricted,
      );
      final usd = await createTestCashAccount(
        scope,
        name: '美元户',
        currency: 'USD',
      );
      TransferDraft draft({
        String? to,
        LocalDate? inOn,
        Timestamp? outAt,
        Timestamp? inAt,
      }) => TransferDraft(
        fromAccountId: main.id,
        toAccountId: to ?? saving.id,
        amountMinor: 250000,
        outOn: d(2026, 11, 1),
        inOn: inOn ?? d(2026, 11, 1),
        outAt: outAt,
        inAt: inAt,
        cls: CashEventClass.confirmed,
        label: '定存',
      );
      Future<String> fails(TransferDraft draft) async =>
          (await expectRepositoryError<ValidationException>(
            () => events.createTransfer(draft),
          )).field;
      expect(await fails(draft(to: main.id)), 'toAccount');
      expect(await fails(draft(to: usd.id)), 'toAccount');
      expect(await fails(draft(inOn: d(2026, 10, 31))), 'inOn');
      expect(
        await fails(
          draft(
            outAt: Timestamp.parse('2026-11-01T15:00:00+08:00'),
            inAt: Timestamp.parse('2026-11-01T09:00:00+08:00'),
          ),
        ),
        'inAt',
      );
      final group = await events.createTransfer(draft());
      final transfers = await events.transfers();
      expect(transfers, hasLength(1));
      expect(transfers.single.groupId, group);
      expect(
        (transfers.single.out.amountMinor, transfers.single.out.category),
        (-250000, 'transfer_out'),
      );
      expect(
        (
          transfers.single.into.amountMinor,
          transfers.single.into.cashAccountId,
        ),
        (250000, saving.id),
      );
      await expectRepositoryError<ConflictException>(
        () => events.update(transfers.single.out.id, amountMinor: 1),
      );
      await events.delete(transfers.single.into.id);
      expect(await events.transfers(), isEmpty);
      expect(await events.list(), isEmpty, reason: '两端一起删除');
    });
  });

  test('受限资金或不可用于还款且未设可用日期的账户不进入可用现金；设了可用日期的进入并记假设', () async {
    final main = await createTestCashAccount(scope, reserve: 200000);
    final locked = await createTestCashAccount(
      scope,
      name: '定期',
      kind: CashAccountKind.restricted,
    );
    final wealth = await createTestCashAccount(
      scope,
      name: '理财',
      kind: CashAccountKind.wealth,
    );
    for (final acc in [main, locked, wealth]) {
      await recordTestCashSnapshot(scope, acc.id, d(2026, 10, 17), 1000000);
    }
    await addTestCashEvent(scope, locked.id, d(2026, 10, 20), -5000000 + 1);
    final reader = CashForecastReader(scope);
    var inputs = await reader.loadInputs();
    expect(inputs.counted.map((a) => a.name), ['工资卡']);
    expect(inputs.excluded.map((a) => a.name), ['定期', '理财']);
    expect(inputs.accounts.map((a) => a.id), [main.id]);
    expect(inputs.events.every((e) => e.account == main.id), isTrue);
    final baseline = (await ScenarioRepository(scope).list())[1];
    var forecast = forecastFrom(inputs, baseline, windowDays: 30);
    expect(forecast.accounts.map((a) => a.row.name), ['工资卡']);
    expect(forecast.gaps, isEmpty, reason: '受限账户的支出不进入可用现金的检查');

    await accounts.update(locked.id, availableFrom: d(2026, 11, 10));
    inputs = await reader.loadInputs();
    expect(inputs.counted.map((a) => a.name), ['工资卡', '定期']);
    final lockedDomain = inputs.accounts.firstWhere((a) => a.id == locked.id);
    expect(lockedDomain.usableForRepayment, isFalse, reason: '可用日期之前不可用于还款');
    forecast = forecastFrom(inputs, baseline, windowDays: 30);
    expect(
      forecast.assumptions.any((a) => a.contains('定期：2026-11-10 起才可用于还款')),
      isTrue,
    );
  });

  group('给 I-1c 的还款扣款接口', () {
    test('由还款生成计划扣款（planned，linked_repayment_id）；改期改额；确认扣款后按扣款日转为确定', () async {
      final acc = await createTestCashAccount(scope);
      const repayment = 'repayment-00000000-0000-4000-8000-000000000001';
      final planned = await events.planRepaymentDebit(
        repaymentId: repayment,
        cashAccountId: acc.id,
        on: d(2026, 11, 8),
        amountMinor: 500000,
        label: '卡 B 还款',
      );
      expect(
        (
          planned.cls,
          planned.category,
          planned.postingStatus,
          planned.amountMinor,
        ),
        ('planned', 'repayment', 'planned', -500000),
      );
      expect(planned.linkedRepaymentId, repayment);
      await expectRepositoryError<ConflictException>(
        () => events.update(planned.id, amountMinor: 1),
      );
      final moved = await events.planRepaymentDebit(
        repaymentId: repayment,
        cashAccountId: acc.id,
        on: d(2026, 11, 7),
        amountMinor: 480000,
      );
      expect(moved.id, planned.id, reason: '每笔还款一条事件');
      expect((moved.eventOn, moved.amountMinor), ('2026-11-07', -480000));

      // 扣款发生在北京时间 10-18 08:30（写成 UTC 前一天 00:30Z）：按扣款日生效（F-31）。
      final debited = await events.confirmRepaymentDebit(
        repaymentId: repayment,
        debitedAt: Timestamp.parse('2026-10-18T00:30:00Z'),
      );
      expect(
        (debited.cls, debited.postingStatus, debited.eventOn, debited.eventAt),
        ('confirmed', 'posted', '2026-10-18', '2026-10-18T08:30:00+08:00'),
      );
      await expectRepositoryError<ConflictException>(
        () => events.cancelRepaymentDebit(repayment),
      );
      await expectRepositoryError<ConflictException>(
        () => events.planRepaymentDebit(
          repaymentId: repayment,
          cashAccountId: acc.id,
          on: d(2026, 11, 8),
          amountMinor: 1,
        ),
      );
    });

    test('撤销计划扣款：事件作废；扣款时点不能晚于现在', () async {
      final acc = await createTestCashAccount(scope);
      await events.planRepaymentDebit(
        repaymentId: 'r1',
        cashAccountId: acc.id,
        on: d(2026, 11, 8),
        amountMinor: 1000,
      );
      expect(
        (await expectRepositoryError<ValidationException>(
          () => events.confirmRepaymentDebit(
            repaymentId: 'r1',
            debitedAt: Timestamp.parse('2026-10-18T13:00:00+08:00'),
          ),
        )).field,
        'debitedAt',
      );
      await events.cancelRepaymentDebit('r1');
      expect(await events.byRepayment('r1'), isNull);
      expect(await events.list(), isEmpty);
    });
  });

  test('确认层级与来源：快照记录的来源与确认层级原样保存', () async {
    final acc = await createTestCashAccount(scope);
    final row = await snapshots.record(
      CashSnapshotDraft(
        cashAccountId: acc.id,
        balanceMinor: 1,
        balanceAsOf: d(2026, 10, 18),
        observedAt: Timestamp.parse('2026-10-18T10:00:00+08:00'),
        source: SnapshotSource.statement,
        confirmationLevel: ConfirmationLevel.bankConfirmed,
      ),
    );
    expect(
      (row.sourceKind, row.confirmationLevel),
      ('statement', 'bank_confirmed'),
    );
  });
}
