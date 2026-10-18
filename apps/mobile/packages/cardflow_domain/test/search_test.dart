// 本地有限搜索（engine-spec §8、ADR-004；简报 I0-7）：F-18 返回 A 800000 + C 200000（proven=false），
// K=1 返回"本地未找到（非证明无解）"，时间预算生效，平局取按卡输入顺序字典序最大的分配；
// 另以独立的暴力参考（与 Python diff_reference.py 同法：枚举全部分配、验证器判可行、按画像目标层
// 与平局规则选优）在随机小文档上核对搜索结果。
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:cardflow_domain/testing.dart';
import 'package:test/test.dart';

import 'support/repo.dart';

BoundedSearchResult searchF18({
  BoundedSearchOptions options = const BoundedSearchOptions(),
  Map<String, Object?>? doc,
  String? decision,
}) => boundedSearchFromProtocol(
  doc ?? f18Input(),
  decisionScenario: decision,
  options: options,
);

/// 每次调用前进 [step] 微秒的假时钟。
int Function() fakeClock(int step) {
  var now = 0;
  return () {
    final t = now;
    now += step;
    return t;
  };
}

void main() {
  group('F-18 (brief acceptance)', () {
    test('K <= 3 finds A 800000 + C 200000, labelled not proven', () {
      final r = searchF18();
      expect(r.outcome, LocalSearchOutcome.found);
      expect(r.allocation, {'A': 800000, 'C': 200000});
      expect(r.allocation.keys, ['A', 'C']); // 卡的输入顺序
      expect(r.proven, isFalse);
      expect(r.message, '本地找到可行方案，非最优证明');
      expect(r.verification!.ok, isTrue);
      expect(r.verification!.weightedBufferDays, '42.4');
      expect(r.failingScenarios, [
        'confirmed',
        'stress_income_delay',
      ]); // 与 Python plan() 相同
      // 与 Python CP-SAT 的目标层取值相同（test_regression_sample.py）
      expect(r.objectives['min_margin'], 100000);
      expect(r.objectives['buffer'], 800000 * 43 + 200000 * 40);
      expect(r.objectives['cards'], 2);
      expect(r.objectives['fees'], 0);
      expect(r.exhausted, isTrue);
      expect(r.timedOut, isFalse);
      expect(r.maxCards, 3);
      expect(r.verifierCalls, greaterThan(0));
      expect(r.elapsedMicros, lessThan(2000000));
    });

    test('K = 1 finds nothing locally: "本地未找到（非证明无解）"', () {
      final r = searchF18(options: const BoundedSearchOptions(maxCards: 1));
      expect(r.outcome, LocalSearchOutcome.notFound);
      expect(r.message, '本地未找到（非证明无解）');
      expect(r.proven, isFalse);
      expect(r.allocation, isEmpty);
      expect(r.verification, isNull);
      expect(r.maxCards, 1);
      expect(r.exhausted, isTrue);
      final noSplit = f18Input();
      obj(noSplit['request'])['allow_split'] = false; // 请求的 K = 1
      final r2 = searchF18(doc: noSplit);
      expect((r2.outcome, r2.maxCards), (LocalSearchOutcome.notFound, 1));
    });

    test('the decision scenario follows the brief: stress as decision is not found, confirmed is a shortfall', () {
      expect(
        searchF18(decision: 'stress_income_delay').outcome,
        LocalSearchOutcome.notFound,
      );
      final shortfall = searchF18(decision: 'confirmed');
      expect(shortfall.outcome, LocalSearchOutcome.baselineShortfall);
      expect(shortfall.failingScenarios, ['confirmed']);
      expect(
        shortfall
            .baseline['confirmed']!
            .accounts['cash-main']!
            .breaches
            .first
            .on,
        LocalDate(2026, 11, 8),
      );
    });

    test('data problems stop the search (NEEDS_DATA)', () {
      final stale = f18Input();
      obj(stale['request'])['txn_date'] = '2026-10-30';
      final r = searchF18(doc: stale);
      expect(r.outcome, LocalSearchOutcome.needsData);
      expect([for (final i in r.dataIssues) i.code], ['STALE_SNAPSHOT']);
      final unknown = searchF18(decision: 'nope');
      expect(
        [for (final i in unknown.dataIssues) i.code],
        ['UNKNOWN_DECISION_SCENARIO'],
      );
      expect(
        () => searchF18(options: const BoundedSearchOptions(maxCards: 4)),
        throwsArgumentError,
      );
    });

    test(
      'the JSON form carries the not-proven label and protocol-shaped lines',
      () {
        final json = searchF18().toJson();
        expect(json['outcome'], 'found');
        expect(json['proven'], isFalse);
        expect(json['message'], '本地找到可行方案，非最优证明');
        expect(
          [
            for (final l in arr(json['allocation']))
              (obj(l)['card_id'], obj(l)['amount_minor']),
          ],
          [('A', 800000), ('C', 200000)],
        );
        canonicalJson(json); // 是合法 JSON 值
      },
    );
  });

  group('time budget', () {
    test('a fake clock that jumps 1 s per reading stops the search within the 2 s budget', () {
      final r = searchF18(
        options: BoundedSearchOptions(clock: fakeClock(1000000)),
      );
      expect(r.timedOut, isTrue);
      expect(r.exhausted, isFalse);
      expect(r.candidates, lessThanOrEqualTo(2));
      expect(r.proven, isFalse);
    });

    test('a zero budget evaluates nothing and says "not found locally"', () {
      final r = searchF18(
        options: const BoundedSearchOptions(budget: Duration.zero),
      );
      expect(r.outcome, LocalSearchOutcome.notFound);
      expect(r.candidates, 0);
      expect(r.timedOut, isTrue);
      expect(r.message, '本地未找到（非证明无解）');
    });

    test('a large instance stops near a 100 ms budget (real clock)', () {
      final cards = [
        for (var i = 0; i < 120; i++)
          protocolCard('c$i', available: 5000, statementDay: 1 + i % 28),
      ];
      final doc = protocolDocument(
        cards,
        amount: 12000,
        balance: 100000000,
        split: true,
        maxCards: 3,
      );
      final r = boundedSearchFromProtocol(
        doc,
        options: const BoundedSearchOptions(
          budget: Duration(milliseconds: 100),
        ),
      );
      expect(r.timedOut, isTrue);
      expect(r.elapsedMicros, lessThan(1000000));
      if (r.outcome == LocalSearchOutcome.found) {
        expect(r.verification!.ok, isTrue);
      }
    });
  });

  test('ties: the lexicographically largest allocation in card input order (as in Python)', () {
    final doc = protocolDocument(
      [protocolCard('A', available: 1000), protocolCard('B', available: 1000)],
      amount: 1500,
      balance: 100000000,
      split: true,
      maxCards: 2,
    );
    // Python plan_from_protocol 在三种画像下都给出 A 1000 + B 500
    for (final profile in profiles) {
      obj(doc['options'])['profile'] = profile;
      expect(boundedSearchFromProtocol(doc).allocation, {
        'A': 1000,
        'B': 500,
      }, reason: profile);
    }
  });

  test(
    'a fee-bearing plan is verified and never claimed optimal (R3E-07 probe)',
    () {
      final doc = f18Input();
      obj(arr(doc['cards'])[0])['fee_rate'] = '0.006';
      final r = boundedSearchFromProtocol(doc);
      expect(r.outcome, LocalSearchOutcome.found);
      expect(r.verification!.ok, isTrue);
      expect(r.proven, isFalse);
      // CP-SAT 的最优是 A 497166 + C 502834（余量 97017）；候选切点给出可行的 A 500000 + C 500000
      // （余量 97000）——本地结果只保证可行，不声称最优。
      expect(r.objectives['min_margin']!, lessThanOrEqualTo(97017));
    },
  );

  test('matches an independent brute-force reference on 200 random small documents', () {
    final rng = TestRandom(2026);
    var compared = 0;
    var found = 0;
    for (var n = 0; n < 400 && compared < 200; n++) {
      final doc = randomPlanInput(rng);
      final p = inputsFromProtocol(doc);
      final decision = p.options.decisionScenario;
      final result = boundedSearch(
        p.inputs,
        p.scenarios,
        decisionScenario: decision,
        profile: p.options.profile,
        staleAfterDays: p.options.staleAfterDays,
      );
      if (result.outcome == LocalSearchOutcome.needsData ||
          result.outcome == LocalSearchOutcome.baselineShortfall) {
        continue;
      }
      expect(result.exhausted, isTrue);
      compared++;
      final expected = bruteForce(p, decision, p.options.profile);
      expect(result.allocation, expected, reason: '#$n ${p.options.profile}');
      if (expected.isNotEmpty) {
        found++;
        final total = expected.values.fold<int>(0, (a, b) => a + b);
        expect(total, p.inputs.request.amount);
        expect(result.verification!.ok, isTrue);
      }
    }
    expect(compared, 200);
    expect(found, greaterThan(50));
  });
}

/// 暴力参考：枚举可用卡上至多 min(K, 3) 张卡、每张金额在 [最小拆分, 上限] 内、合计等于请求金额的
/// 全部分配；验证器判定可行；按画像目标层（模型的 min_margin 用最直接的写法计算）选优，平局取按卡
/// 输入顺序字典序最大的分配。
Map<String, int> bruteForce(
  ParsedPlanInput p,
  String decision,
  String profile,
) {
  final inputs = p.inputs;
  final layers = capacityLayers(inputs);
  final eligible = [
    for (final c in inputs.cards)
      if (classify(c, inputs, layers: layers) case (
        final CardPlanInfo info,
        null,
      ))
        info,
  ];
  final k = inputs.request.k < 3 ? inputs.request.k : 3;
  final amount = inputs.request.amount;
  final caps = [for (final i in eligible) cardLimit(i.card, layers).$1];
  final mins = [
    for (final i in eligible) i.card.minSplit ?? inputs.request.minSplit,
  ];
  final scenario = p.scenarios[decision]!;
  final timelines = <String, Timeline>{
    for (final a in inputs.accounts)
      a.id: buildTimeline(
        a,
        inputs.snapshots[a.id]!,
        inputs.events,
        scenario,
        inputs.horizonEnd,
        checkpointDays: [
          for (final i in eligible)
            if (i.card.repayFrom == a.id) i.repayOn,
        ],
      ),
  };
  final dates = <int>{
    for (final t in timelines.values)
      for (final pt in t.points)
        if (pt.phase == PointPhase.low) pt.on.epochDay,
  }.toList()..sort();

  int valueOn(Timeline t, int day) {
    var value = t.points.first.balance;
    for (final pt in t.points.skip(1)) {
      if (pt.on.epochDay == day && pt.phase == PointPhase.low) {
        return pt.balance;
      }
      if (pt.on.epochDay < day && pt.phase == PointPhase.end) {
        value = pt.balance;
      }
    }
    return value;
  }

  Map<String, int>? best;
  List<int>? bestKey;
  List<int>? bestVector;
  void consider(List<int> amounts) {
    final alloc = <String, int>{
      for (var i = 0; i < eligible.length; i++)
        if (amounts[i] > 0) eligible[i].card.id: amounts[i],
    };
    if (!verify(inputs, alloc, {decision: scenario}, decision).ok) {
      return;
    }
    int? margin;
    for (final a in inputs.accounts) {
      for (final day in dates) {
        var spent = 0;
        for (var i = 0; i < eligible.length; i++) {
          if (amounts[i] > 0 &&
              eligible[i].card.repayFrom == a.id &&
              eligible[i].repayOn.epochDay <= day) {
            spent += amounts[i] + cardFee(eligible[i].card, amounts[i]);
          }
        }
        final v = valueOn(timelines[a.id]!, day) - spent - a.reserveFloor;
        margin = margin == null || v < margin ? v : margin;
      }
    }
    var fees = 0;
    var benefit = 0;
    var buffer = 0;
    for (var i = 0; i < eligible.length; i++) {
      final x = amounts[i];
      if (x == 0) {
        continue;
      }
      final card = eligible[i].card;
      fees += cardFee(card, x);
      var b = (Rational.fromInt(x) * card.verifiedBenefitRate).floor().toInt();
      final cap = card.verifiedBenefitCap;
      if (cap != null && cap < b) {
        b = cap;
      }
      benefit += b;
      buffer += x * eligible[i].bufferDays;
    }
    final objectives = {
      'min_margin': margin ?? 0,
      'fees': fees,
      'net_verified_benefit': benefit - fees,
      'buffer': buffer,
      'cards': alloc.length,
    };
    final key = [
      for (final (name, sense) in objectiveTiers[profile]!)
        sense == 'max' ? -objectives[name]! : objectives[name]!,
    ];
    final vector = [for (final c in inputs.cards) alloc[c.id] ?? 0];
    int compare(List<int> a, List<int> b) {
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) {
          return a[i].compareTo(b[i]);
        }
      }
      return 0;
    }

    final better =
        bestKey == null ||
        compare(key, bestKey!) < 0 ||
        (compare(key, bestKey!) == 0 && compare(vector, bestVector!) > 0);
    if (better) {
      best = alloc;
      bestKey = key;
      bestVector = vector;
    }
  }

  final amounts = List<int>.filled(eligible.length, 0);
  void rec(int i, int rest, int used) {
    if (i == eligible.length) {
      if (rest == 0) {
        consider(List<int>.of(amounts));
      }
      return;
    }
    amounts[i] = 0;
    rec(i + 1, rest, used);
    if (used < k) {
      for (var x = mins[i] < 1 ? 1 : mins[i]; x <= caps[i] && x <= rest; x++) {
        amounts[i] = x;
        rec(i + 1, rest - x, used + 1);
      }
      amounts[i] = 0;
    }
  }

  rec(0, amount, 0);
  if (best == null) {
    return const <String, int>{};
  }
  return {
    for (final c in inputs.cards)
      if (best![c.id] != null) c.id: best![c.id]!,
  };
}
