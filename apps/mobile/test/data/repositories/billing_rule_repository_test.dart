// 账期规则版本（真实 sqlite3mc）：F-14 数据侧（新版本封口旧版、按日期用 selectRule 选版本）、
// 区间不重叠、更正、业务校验、F-19（库里的截止时点）、3 期预览与领域包 F-12/F-16 的例子一致。
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/mapping/domain_mapping.dart';
import 'package:cardflow/data/repositories/billing_rule_repository.dart';
import 'package:cardflow/data/repositories/credit_account_repository.dart';
import 'package:cardflow/data/repositories/models.dart';
import 'package:cardflow/data/repositories/repository_errors.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repository_test_support.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

void main() {
  late AppDatabase db;
  late WorkspaceScope scope;
  late BillingRuleRepository rules;
  late String accountId;
  late RuleSubject subject;

  setUp(() async {
    db = await openRealTestDatabase();
    scope = await createTestWorkspace(db);
    rules = BillingRuleRepository(scope);
    accountId = (await createTestCard(scope)).creditAccountId;
    subject = RuleSubject.creditAccount(accountId);
  });

  test('第一个版本：effective_from 为空（全部历史）、用户声明、版本 1', () async {
    final v1 = await declareTestRule(scope, accountId);
    expect(v1.version, 1);
    expect(v1.effectiveFrom, isNull);
    expect(v1.effectiveTo, isNull);
    expect(v1.source, 'user_declared');
    expect(v1.reviewStatus, 'user_declared');
    expect((await rules.effectiveOn(subject, d(1999, 1, 1)))!.id, v1.id);
  });

  test('F-14 数据侧：新版本从某日起生效 → 旧版封口并标 expired；按入账日用 selectRule 选版本', () async {
    final v1 = await declareTestRule(scope, accountId);
    final v2 = await declareTestRule(
      scope,
      accountId,
      statementDay: 15,
      due: const DueRule.fixedDay(day: 5, monthOffset: 1),
      effect: RuleEffectiveFrom(d(2026, 11, 1)),
    );

    final versions = await rules.versions(subject);
    expect(versions.map((r) => r.version), <int>[1, 2]);
    final sealed = versions.first;
    expect(sealed.id, v1.id);
    expect(sealed.effectiveTo, '2026-11-01');
    expect(sealed.reviewStatus, 'expired');
    expect(v2.effectiveFrom, '2026-11-01');
    expect(v2.effectiveTo, isNull);

    final domain = versions.map(billingRuleFromRow).toList();
    expect(selectRule(domain, d(2026, 10, 16)).ruleId, v1.id);
    expect(selectRule(domain, d(2026, 10, 31)).ruleId, v1.id);
    expect(selectRule(domain, d(2026, 11, 1)).ruleId, v2.id);
    // 旧入账日按旧规则（账单 10 日），新入账日按新规则（账单 15 日）。
    expect(
      cycleForPosting(
        selectRule(domain, d(2026, 10, 16)),
        d(2026, 10, 16),
      ).dueDate,
      d(2026, 11, 28),
    );
    expect(
      cycleForPosting(
        selectRule(domain, d(2026, 11, 2)),
        d(2026, 11, 2),
      ).dueDate,
      d(2026, 12, 5),
    );
  });

  test('生效日须晚于当前版本的生效日；区间不重叠', () async {
    await declareTestRule(scope, accountId);
    await declareTestRule(
      scope,
      accountId,
      effect: RuleEffectiveFrom(d(2026, 11, 1)),
    );
    for (final bad in <LocalDate>[d(2026, 11, 1), d(2026, 10, 1)]) {
      final error = await expectRepositoryError<ValidationException>(
        () => declareTestRule(
          scope,
          accountId,
          statementDay: 20,
          effect: RuleEffectiveFrom(bad),
        ),
      );
      expect(error.field, 'effectiveFrom');
    }
    final versions = await rules.versions(subject);
    expect(versions, hasLength(2));
    expect(
      rangesOverlap(<({LocalDate? from, LocalDate? to})>[
        for (final r in versions)
          (
            from: parseOptionalDate(r.effectiveFrom),
            to: parseOptionalDate(r.effectiveTo),
          ),
      ]),
      isFalse,
    );
  });

  test('更正当前版本：新版本接替整个区间，旧版本区间为空、任何日期都不选中它', () async {
    final v1 = await declareTestRule(scope, accountId, statementDay: 11);
    final v2 = await declareTestRule(scope, accountId, statementDay: 10);
    final sealedV1 = (await rules.versions(subject)).first;
    expect(sealedV1.effectiveTo, emptyRangeEnd);
    expect(isEmptyRange(sealedV1), isTrue);
    expect(v2.effectiveFrom, isNull);
    expect((await rules.effectiveOn(subject, d(2000, 1, 1)))!.id, v2.id);

    final v3 = await declareTestRule(
      scope,
      accountId,
      statementDay: 12,
      effect: RuleEffectiveFrom(d(2026, 11, 1)),
    );
    final v4 = await declareTestRule(scope, accountId, statementDay: 13);
    final all = await rules.versions(subject);
    final byId = {for (final r in all) r.id: r};
    expect(byId[v3.id]!.effectiveTo, '2026-11-01', reason: 'v3 区间为空');
    expect(isEmptyRange(byId[v3.id]!), isTrue);
    expect(v4.effectiveFrom, '2026-11-01');
    final domain = all.map(billingRuleFromRow).toList();
    expect(selectRule(domain, d(2026, 10, 31)).ruleId, v2.id);
    expect(selectRule(domain, d(2026, 11, 1)).ruleId, v4.id);
    expect(domain.where((r) => r.isEffectiveOn(d(2026, 11, 1))), hasLength(1));
    expect(v1.id, isNot(v2.id));
  });

  test('规则校验：到期须晚于账单日；工作日与顺延需要日历（本阶段不可用）；入账延迟 min ≤ max', () async {
    final problems = <String?>[
      billingRuleDraftProblem(
        const BillingRuleDraft(
          statementDay: 28,
          due: DueRule.fixedDay(day: 25),
        ),
      ),
      // 账单日 31、当月 30 日到期：在 31 天的月份里到期早于账单日。
      billingRuleDraftProblem(
        const BillingRuleDraft(
          statementDay: 31,
          due: DueRule.fixedDay(day: 30),
        ),
      ),
      billingRuleDraftProblem(
        const BillingRuleDraft(
          statementDay: 10,
          due: DueRule.daysAfterStatement(days: 3, dayKind: DayKind.business),
        ),
      ),
      billingRuleDraftProblem(
        const BillingRuleDraft(
          statementDay: 10,
          due: DueRule.fixedDay(day: 28),
          holidayRollover: HolidayRollover.nextBusinessDay,
        ),
      ),
      billingRuleDraftProblem(
        const BillingRuleDraft(
          statementDay: 10,
          due: DueRule.fixedDay(day: 28),
          postingDelayMinDays: 3,
          postingDelayMaxDays: 1,
        ),
      ),
      billingRuleDraftProblem(
        const BillingRuleDraft(
          statementDay: 10,
          due: DueRule.fixedDay(day: 28),
          cutoffTime: '25:00',
        ),
      ),
    ];
    expect(problems, <String>[
      '到期日须晚于账单日',
      '到期日须晚于账单日',
      '按工作日计算需要已核验的工作日日历，本阶段不可用',
      '节假日顺延需要已核验的工作日日历，本阶段不可用',
      '入账延迟须满足 0 ≤ 最少 ≤ 最多 ≤ 30 天',
      '截止时点格式应为 HH:MM',
    ]);
    expect(
      billingRuleDraftProblem(
        const BillingRuleDraft(
          statementDay: 31,
          due: DueRule.fixedDay(day: 30, monthOffset: 1),
        ),
      ),
      isNull,
    );
    final error = await expectRepositoryError<ValidationException>(
      () => declareTestRule(
        scope,
        accountId,
        statementDay: 28,
        due: const DueRule.fixedDay(day: 25),
      ),
    );
    expect(error.message, '到期日须晚于账单日');
    expect(await rules.versions(subject), isEmpty);
  });

  test('F-19：规则在库里的截止时点决定入账日（同一业务日、截止前后两笔差 1 天）', () async {
    await declareTestRule(scope, accountId, cutoffTime: '17:00');
    final account = await CreditAccountRepository(scope).require(accountId);
    final versions = await rules.versions(subject);
    LocalDate posting(String at) => postingDateFor(
      Timestamp.parse(at),
      account: account,
      versions: versions,
    );
    final before = posting('2026-10-20T16:59:00+08:00');
    final after = posting('2026-10-20T17:01:00+08:00');
    expect(before, d(2026, 10, 20));
    expect(after, d(2026, 10, 21));
    expect(after.differenceInDays(before), 1);
    // 同一瞬间用 UTC 写：仍按账户业务时区（北京时间 17:01）判断。
    expect(posting('2026-10-20T09:01:00Z'), d(2026, 10, 21));
  });

  test('预测账期：入账延迟窗口跨过账单日时给出两个可能账期（最早到期在前）', () async {
    await declareTestRule(
      scope,
      accountId,
      statementDay: 20,
      due: const DueRule.fixedDay(day: 8, monthOffset: 1),
      postingDelayMax: 3,
    );
    final forecast = forecastCycles(
      await rules.versions(subject),
      d(2026, 10, 19),
    ) as ForecastPredicted;
    expect(forecast.cycles.map((c) => c.dueDate), <LocalDate>[
      d(2026, 11, 8),
      d(2026, 12, 8),
    ]);
    expect(
      forecastCycles(const <BillingRuleVersionRow>[], d(2026, 10, 19)),
      isA<ForecastNoRule>(),
    );
  });

  group('3 期预览与领域包 billing_test 的例子一致', () {
    BillingRule rule(int day, DueRule due, {bool inclusive = true}) =>
        BillingRule(
          ruleId: 'p',
          statementDay: day,
          due: due,
          statementDayInclusive: inclusive,
        );

    test('F-12：账单日当天入账的归属开关（20 日，次月 8 日到期）', () {
      const due = DueRule.fixedDay(day: 8, monthOffset: 1);
      final inc = previewCycles(rule(20, due), d(2026, 10, 20));
      final exc = previewCycles(
        rule(20, due, inclusive: false),
        d(2026, 10, 20),
      );
      expect(inc.map((c) => '${c.statementDate}/${c.dueDate}'), <String>[
        '2026-10-20/2026-11-08',
        '2026-11-20/2026-12-08',
        '2026-12-20/2027-01-08',
      ]);
      expect(exc.first.statementDate, d(2026, 11, 20));
    });

    test('F-16：月末截断与闰年（31 日，账单后 20 天）', () {
      final r = rule(31, const DueRule.daysAfterStatement(days: 20));
      expect(
        previewCycles(
          r,
          d(2025, 2, 10),
        ).map((c) => '${c.statementDate}/${c.dueDate}'),
        <String>[
          '2025-02-28/2025-03-20',
          '2025-03-31/2025-04-20',
          '2025-04-30/2025-05-20',
        ],
      );
      expect(
        previewCycles(r, d(2024, 2, 10)).first.statementDate,
        d(2024, 2, 29),
      );
      expect(
        previewCycles(r, d(2026, 4, 30)).first.statementDate,
        d(2026, 4, 30),
      );
    });

    test('回归样本：A 10 日/当月 28 日，交易 2026-10-16 → 11-10/11-28 起', () {
      final a = previewCycles(
        rule(10, const DueRule.fixedDay(day: 28)),
        d(2026, 10, 16),
      );
      expect(a.first.statementDate, d(2026, 11, 10));
      expect(a.first.dueDate, d(2026, 11, 28));
      expect(a.last.statementDate, d(2027, 1, 10));
    });
  });

  test('规则主体须属于当前工作空间', () async {
    final other = await createTestWorkspace(
      db,
      kind: WorkspaceKind.demo,
      makeCurrent: false,
    );
    final foreign = (await createTestCard(other)).creditAccountId;
    await expectRepositoryError<NotFoundException>(
      () => declareTestRule(scope, foreign),
    );
    expect(await BillingRuleRepository(other).all(), isEmpty);
  });
}
