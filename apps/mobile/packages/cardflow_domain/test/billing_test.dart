// 移植自 services/api/tests/engine/test_billing.py（8 项）与 test_billing_clamp.py（3 项）：
// 断言与期望值不变；另加错误消息与 Python `str(e)` 逐字一致的检查（消息会进入 cycles 输出的
// `error` 与数据问题的 `detail`，parity 要求逐字节相同）。
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:test/test.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

BillingRule rule(
  int statementDay,
  DueRule due, {
  bool inclusive = true,
  String id = 'r',
}) => BillingRule(
  ruleId: id,
  statementDay: statementDay,
  due: due,
  statementDayInclusive: inclusive,
);

bool isBusinessDay(LocalDate date) => date.isoWeekday <= 5;

Matcher throwsRuleError(String message) =>
    throwsA(isA<BillingRuleError>().having((e) => '$e', 'message', message));

void main() {
  group('test_billing.py', () {
    test('fixed day: same month and next month', () {
      final a = rule(10, const DueRule.fixedDay(day: 28));
      final b = rule(20, const DueRule.fixedDay(day: 8, monthOffset: 1));
      expect(
        cycleForPosting(a, d(2026, 10, 16)).statementDate,
        d(2026, 11, 10),
      );
      expect(cycleForPosting(a, d(2026, 10, 16)).dueDate, d(2026, 11, 28));
      expect(
        cycleForPosting(b, d(2026, 10, 16)).statementDate,
        d(2026, 10, 20),
      );
      expect(cycleForPosting(b, d(2026, 10, 16)).dueDate, d(2026, 11, 8));
    });

    test('statement day inclusive toggle', () {
      const due = DueRule.fixedDay(day: 8, monthOffset: 1);
      final inc = rule(20, due);
      final exc = rule(20, due, inclusive: false);
      expect(statementDateForPosting(inc, d(2026, 10, 20)), d(2026, 10, 20));
      expect(statementDateForPosting(exc, d(2026, 10, 20)), d(2026, 11, 20));
    });

    test('month-end clamp and leap year', () {
      final r = rule(31, const DueRule.daysAfterStatement(days: 20));
      expect(statementDateForPosting(r, d(2024, 2, 10)), d(2024, 2, 29));
      expect(statementDateForPosting(r, d(2025, 2, 10)), d(2025, 2, 28));
      expect(statementDateForPosting(r, d(2026, 4, 30)), d(2026, 4, 30));
      expect(cycleForPosting(r, d(2025, 2, 10)).dueDate, d(2025, 3, 20));
    });

    test('cross year', () {
      final r = rule(25, const DueRule.fixedDay(day: 15, monthOffset: 1));
      final c = cycleForPosting(r, d(2026, 12, 26));
      expect((c.statementDate, c.dueDate), (d(2027, 1, 25), d(2027, 2, 15)));
      final c2 = cycleForPosting(r, d(2026, 12, 20));
      expect((c2.statementDate, c2.dueDate), (d(2026, 12, 25), d(2027, 1, 15)));
    });

    test('due before statement is a rule error (MODEL_INVALID)', () {
      final bad = rule(28, const DueRule.fixedDay(day: 25));
      expect(
        () => cycleForPosting(bad, d(2026, 10, 16)),
        throwsRuleError(
          'rule r: due 2026-10-25 is not after statement 2026-10-28 '
          '(month_offset/day misconfigured)',
        ),
      );
    });

    test(
      'posting uncertainty near the statement day: two cycles, earliest first',
      () {
        final r = rule(20, const DueRule.fixedDay(day: 8, monthOffset: 1));
        final cs = cyclesForTransaction(
          r,
          d(2026, 10, 19),
          postingDelayMin: 0,
          postingDelayMax: 3,
        );
        expect(cs, hasLength(2));
        expect(cs[0].dueDate, d(2026, 11, 8));
        expect(cs[1].dueDate, d(2026, 12, 8));
        // Python: [('posting delay 0d -> posting 2026-10-19',), ('posting delay 2d -> ...',)]
        expect(cs[0].assumptions, ['posting delay 0d -> posting 2026-10-19']);
        expect(cs[1].assumptions, ['posting delay 2d -> posting 2026-10-21']);
      },
    );

    test('business-day due and rollover require a calendar', () {
      final r = BillingRule(
        ruleId: 'r',
        statementDay: 10,
        due: const DueRule.daysAfterStatement(
          days: 3,
          dayKind: DayKind.business,
        ),
      );
      expect(
        () => cycleForPosting(r, d(2026, 10, 1)),
        throwsRuleError('business-day counting requires a verified calendar'),
      );
      // 账单日 2026-10-10 是周六，3 个工作日 → 周三 10-14
      expect(
        cycleForPosting(r, d(2026, 10, 1), isBusinessDay).dueDate,
        d(2026, 10, 14),
      );
      final r2 = BillingRule(
        ruleId: 'r2',
        statementDay: 10,
        due: const DueRule.fixedDay(day: 11),
        holidayRollover: HolidayRollover.nextBusinessDay,
      );
      expect(
        () => cycleForPosting(r2, d(2026, 10, 1)),
        throwsRuleError(
          'holiday_rollover requires a verified business-day calendar',
        ),
      );
      // 10-11 是周日 → 顺延到周一 10-12
      expect(
        cycleForPosting(r2, d(2026, 10, 1), isBusinessDay).dueDate,
        d(2026, 10, 12),
      );
    });

    test('rule versions and issued statement precedence', () {
      final old = BillingRule(
        ruleId: 'v1',
        statementDay: 10,
        due: const DueRule.fixedDay(day: 28),
        effectiveTo: d(2026, 11, 1),
      );
      final newer = BillingRule(
        ruleId: 'v2',
        statementDay: 15,
        due: const DueRule.fixedDay(day: 5, monthOffset: 1),
        effectiveFrom: d(2026, 11, 1),
      );
      expect(selectRule([old, newer], d(2026, 10, 16)).ruleId, 'v1');
      expect(selectRule([old, newer], d(2026, 11, 1)).ruleId, 'v2');
      final issued = [IssuedStatement(d(2026, 11, 10), d(2026, 11, 30))];
      final c = resolveCycle([old, newer], issued, d(2026, 10, 16));
      expect(c.dueDate, d(2026, 11, 30));
      expect(c.ruleId, startsWith('issued:'));
      expect(c.assumptions, ['issued statement overrides prediction']);
    });
  });

  group('test_billing_clamp.py', () {
    const due = DueRule.daysAfterStatement(days: 20);
    final inclusive = rule(31, due, id: 'r31');
    final exclusive = rule(31, due, id: 'r31x', inclusive: false);

    test(
      'posting on a clamped statement day respects the inclusive toggle',
      () {
        expect(
          statementDateForPosting(inclusive, d(2026, 4, 30)),
          d(2026, 4, 30),
        );
        expect(
          statementDateForPosting(exclusive, d(2026, 4, 30)),
          d(2026, 5, 31),
        );
        expect(
          statementDateForPosting(inclusive, d(2025, 2, 28)),
          d(2025, 2, 28),
        );
        expect(
          statementDateForPosting(exclusive, d(2025, 2, 28)),
          d(2025, 3, 31),
        );
        expect(
          statementDateForPosting(inclusive, d(2024, 2, 29)),
          d(2024, 2, 29),
        );
        expect(
          statementDateForPosting(exclusive, d(2024, 2, 29)),
          d(2024, 3, 31),
        );
      },
    );

    test("exclusive roll lands on the next month's clamped day", () {
      expect(
        statementDateForPosting(exclusive, d(2025, 1, 31)),
        d(2025, 2, 28),
      );
      expect(
        statementDateForPosting(exclusive, d(2024, 1, 31)),
        d(2024, 2, 29),
      );
      expect(statementDateForPosting(inclusive, d(2026, 5, 1)), d(2026, 5, 31));
      expect(statementDateForPosting(exclusive, d(2026, 5, 1)), d(2026, 5, 31));
    });

    test('due date follows the rolled statement date', () {
      var c = cycleForPosting(exclusive, d(2026, 4, 30));
      expect((c.statementDate, c.dueDate), (d(2026, 5, 31), d(2026, 6, 20)));
      c = cycleForPosting(inclusive, d(2026, 4, 30));
      expect((c.statementDate, c.dueDate), (d(2026, 4, 30), d(2026, 5, 20)));
    });
  });

  group('rule errors match Python str(e)', () {
    final old = BillingRule(
      ruleId: 'v1',
      statementDay: 10,
      due: const DueRule.fixedDay(day: 28),
      effectiveTo: d(2026, 11, 1),
    );

    test('a version is not effective on (or after) effective_to', () {
      expect(old.isEffectiveOn(d(2026, 10, 31)), isTrue);
      expect(old.isEffectiveOn(d(2026, 11, 1)), isFalse);
      expect(
        () => cycleForPosting(old, d(2026, 11, 1)),
        throwsRuleError('rule v1 not effective on 2026-11-01'),
      );
    });

    test('overlapping and missing versions', () {
      final other = rule(5, const DueRule.fixedDay(day: 28), id: 'v0');
      expect(
        () => selectRule([old, other], d(2026, 10, 16)),
        throwsRuleError(
          "overlapping billing rule versions on 2026-10-16: ['v1', 'v0']",
        ),
      );
      expect(
        () => selectRule([old], d(2026, 12, 16)),
        throwsRuleError('no billing rule effective on 2026-12-16'),
      );
    });

    test('a posting window that leaves the version fails the whole card', () {
      final ending = BillingRule(
        ruleId: 'r',
        statementDay: 20,
        due: const DueRule.fixedDay(day: 8, monthOffset: 1),
        effectiveTo: d(2026, 10, 18),
      );
      expect(
        () => cyclesForTransaction(ending, d(2026, 10, 16), postingDelayMax: 3),
        throwsRuleError('rule r not effective on 2026-10-18'),
      );
    });
  });
}
