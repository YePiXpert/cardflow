// 现金时间线与验证器的性质（tests/engine/test_properties.py 中与验证器/现金相关的性质、
// test_review_wave3_fixes.py 的 R3E-03 性质）。Python 用 hypothesis；这里用带固定种子的生成器，
// 每条性质 >= 100 例（与 Python 的 max_examples 相同或更多）。
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:cardflow_domain/testing.dart';
import 'package:test/test.dart';

const acc = CashAccount(id: 'm', name: 'main');
final sc = Scenario(id: 's');
final start = LocalDate(2026, 10, 16);
final horizon = LocalDate(2027, 3, 1);

/// Python `_events(pairs)`：(第几天, 金额) → 已确认账单。
List<CashEvent> eventsOf(List<(int, int)> pairs) => [
  for (final (i, (day, amount)) in pairs.indexed)
    CashEvent(
      id: 'e$i',
      account: 'm',
      on: start.addDays(day),
      amount: amount,
      cls: EventClass.confirmed,
      category: 'bill',
    ),
];

/// hypothesis 策略的对应：balance 0..10^6，最多 12 个 (0..120 天, -500000..500000)。
List<(int, int)> randomPairs(TestRandom rng) => [
  for (var i = 0; i < rng.randint(0, 12); i++)
    (rng.randint(0, 120), rng.randint(-500000, 500000)),
];

CashReport report(int balance, List<CashEvent> events) => evaluate(
  buildTimeline(
    acc,
    Snapshot(account: 'm', balance: balance, asOf: start),
    events,
    sc,
    horizon,
  ),
  0,
);

void main() {
  test('more confirmed cash never hurts (150 examples)', () {
    final rng = TestRandom(101);
    for (var n = 0; n < 150; n++) {
      final balance = rng.randint(0, 1000000);
      final extra = rng.randint(0, 500000);
      final events = eventsOf(randomPairs(rng));
      final r1 = report(balance, events);
      final r2 = report(balance + extra, events);
      expect(r2.minBalance, r1.minBalance + extra);
      expect(!r1.ok || r2.ok, isTrue); // r1.ok <= r2.ok
    }
  });

  test('a known outflow never raises cash (150 examples)', () {
    final rng = TestRandom(102);
    for (var n = 0; n < 150; n++) {
      final balance = rng.randint(0, 1000000);
      final events = eventsOf(randomPairs(rng));
      final day = rng.randint(0, 120);
      final out = rng.randint(1, 300000);
      final base = report(balance, events);
      final more = report(balance, [
        ...events,
        CashEvent(
          id: 'x',
          account: 'm',
          on: start.addDays(day),
          amount: -out,
          cls: EventClass.confirmed,
          category: 'bill',
        ),
      ]);
      expect(more.minBalance <= base.minBalance, isTrue);
      expect(more.endBalance, base.endBalance - out);
    }
  });

  test('event order does not matter (150 examples)', () {
    final rng = TestRandom(103);
    for (var n = 0; n < 150; n++) {
      final balance = rng.randint(0, 1000000);
      final events = eventsOf(randomPairs(rng));
      final shuffled = rng.sample(events, events.length);
      final a = report(balance, events);
      final b = report(balance, shuffled);
      expect(b.minBalance, a.minBalance);
      expect(b.endBalance, a.endBalance);
      expect(
        [for (final x in b.breaches) (x.on, x.balance)],
        [for (final x in a.breaches) (x.on, x.balance)],
      );
    }
  });

  test('R3E-03: delaying or shrinking income never raises a balance (300 random documents)', () {
    final rng = TestRandom(3);
    var checked = 0;
    for (var n = 0; n < 300; n++) {
      final doc = randomPlanInput(rng);
      if ((doc['snapshots']! as List<Object?>).length !=
          (doc['cash_accounts']! as List<Object?>).length) {
        continue;
      }
      final p = inputsFromProtocol(doc);
      final base = p.scenarios['baseline']!;
      final worse = Scenario(
        id: 'worse',
        includeExpected: base.includeExpected,
        incomeDelayDays: rng.choice(const [1, 3, 7]),
        incomeScale: Rational.parseDecimal(rng.choice(const ['1', '0.5', '0'])),
        expenseScale: base.expenseScale,
        eventOverrides: base.eventOverrides,
        sameDayOrder: base.sameDayOrder,
      );
      for (final a in p.inputs.accounts) {
        Timeline timeline(Scenario s) => buildTimeline(
          a,
          p.inputs.snapshots[a.id]!,
          p.inputs.events,
          s,
          p.inputs.horizonEnd,
        );
        final b = timeline(base);
        final w = timeline(worse);
        // 两条时间线的每个检查点：当日最低点，或沿用此前期末（模型检查点的值）
        final days = <int>{
          for (final t in [b, w])
            for (final pt in t.points)
              if (pt.phase == PointPhase.low) pt.on.epochDay,
        }.toList()..sort();
        final dates = [for (final day in days) LocalDate.fromEpochDay(day)];
        final vb = lowSeries(b, dates);
        final vw = lowSeries(w, dates);
        for (var i = 0; i < dates.length; i++) {
          expect(
            vw[i] <= vb[i],
            isTrue,
            reason: 'account ${a.id} on ${dates[i]}',
          );
          checked++;
        }
      }
    }
    expect(checked, greaterThan(500));
  });

  test('verifier invariants on random documents and allocations (300 documents x 3)', () {
    final rng = TestRandom(104);
    var verified = 0;
    for (var n = 0; n < 300; n++) {
      final doc = randomPlanInput(rng);
      final p = inputsFromProtocol(doc);
      if (dataIssues(p.inputs, p.options.staleAfterDays).isNotEmpty) {
        continue;
      }
      for (final allocation in randomAllocations(rng, doc, 3)) {
        final v = verify(
          p.inputs,
          allocation,
          p.scenarios,
          p.options.decisionScenario,
        );
        verified++;
        expect(
          v.ok,
          v.structuralOk && v.checks[p.options.decisionScenario]!.ok,
        );
        expect(v.structuralOk, v.violations.isEmpty);
        expect(v.checks.keys, p.scenarios.keys);
        var fees = 0;
        for (final line in v.lines) {
          fees += line.fee;
          expect(
            line.bufferDays,
            line.repayOn.differenceInDays(p.inputs.request.txnDate),
          );
        }
        expect(v.fees, fees);
        for (final chk in v.checks.values) {
          expect(
            chk.firstBreach,
            chk.breaches.isEmpty ? isNull : same(chk.breaches.first),
          );
          expect(chk.ok, chk.breaches.isEmpty && chk.globalBreaches.isEmpty);
          for (final b in chk.breaches) {
            expect(b.gapToZero, b.balance < 0 ? -b.balance : 0);
            expect(b.gapToReserve > 0, isTrue);
          }
        }
      }
    }
    expect(verified, greaterThan(500));
  });
}
