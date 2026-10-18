/// 本地有限搜索（engine-spec §8、ADR-004）：手机端没有 CP-SAT，在 K ≤ 3 张卡的范围内按候选切点
/// 枚举分配，以独立验证器为可行性预言机。
///
/// * 找到 → 给出方案并标注 `proven: false`："本地找到可行方案，非最优证明"；
/// * 找不到 → "本地未找到（非证明无解）"——有限搜索从不证明无解，也从不写成"没有可用组合"；
/// * 时间预算默认 2 s（可配置），用完即停并如实标注；
/// * 排序与服务端一致：按画像的目标层（engine-spec §4）逐层比较，末层之后取**按卡输入顺序字典序
///   最大**的分配（engine-spec §12.5 的平局规则）。候选集合覆盖最优解时，结果与 CP-SAT 相同，但仍
///   不声称已证最优。
///
/// 候选切点（每张卡、在其余卡的最小拆分与容量约束下）：可承担的最大与最小金额（容量、单笔上限、
/// 信用账户、池；最小拆分）、本卡单独的现金余量切点、其余卡各取现金余量后的补足额、等分（向下与
/// 向上取整）、共享层（信用账户、池）剩余额；取值范围不超过 [BoundedSearchOptions.exhaustiveRangeLimit]
/// 个整数时逐一枚举（按最小单位步长）。最后一张卡取剩余金额。
///
/// 流程与服务端 `plan()` 的前半段相同：先数据检查（NEEDS_DATA），再各情景基线（决策情景基线不满足
/// = BASELINE_SHORTFALL，不搜索），再建模前的资格判定。
library;

import 'allocation.dart';
import 'cash.dart';
import 'checks.dart';
import 'money.dart';
import 'protocol/adapter.dart';
import 'protocol/outputs.dart';
import 'rational.dart';
import 'time.dart';
import 'verifier.dart';

/// 有限搜索的结局。
enum LocalSearchOutcome {
  /// 本地找到可行方案（非最优证明）。
  found,

  /// 本地未找到（非证明无解）。
  notFound,

  /// 数据不全，未搜索。
  needsData,

  /// 决策情景在新增消费前已有缺口，未搜索。
  baselineShortfall,
}

/// 有限搜索的参数。
final class BoundedSearchOptions {
  /// 参数（默认 K ≤ 3、预算 2 s）。
  const BoundedSearchOptions({
    this.maxCards = 3,
    this.budget = const Duration(seconds: 2),
    this.exhaustiveRangeLimit = 64,
    this.clock,
  });

  /// 用卡数上限（1–3；实际取它与请求的 K 中较小者）。
  final int maxCards;

  /// 时间预算。
  final Duration budget;

  /// 一张卡的取值范围不超过这么多个整数时逐一枚举。
  final int exhaustiveRangeLimit;

  /// 单调时钟（微秒）；测试注入，默认用 `Stopwatch`。
  final int Function()? clock;
}

/// 有限搜索的结果。`proven` 永远为 false：本地结果不是最优证明，也不是无解证明。
final class BoundedSearchResult {
  /// 结果。
  const BoundedSearchResult({
    required this.outcome,
    required this.decisionScenario,
    required this.profile,
    this.allocation = const <String, int>{},
    this.verification,
    this.failingScenarios = const <String>[],
    this.dataIssues = const <DataIssue>[],
    this.baseline = const <String, BaselineCheck>{},
    this.objectives = const <String, int>{},
    this.exclusions = const <String, Exclusion>{},
    this.maxCards = 0,
    this.candidates = 0,
    this.verifierCalls = 0,
    this.exhausted = false,
    this.timedOut = false,
    this.elapsedMicros = 0,
  });

  /// 结局。
  final LocalSearchOutcome outcome;

  /// 决策情景。
  final String decisionScenario;

  /// 画像。
  final String profile;

  /// 找到的分配（卡的输入顺序）；未找到时为空。
  final Map<String, int> allocation;

  /// 找到的分配在**所有**情景下的独立验证；未找到时为 null。
  final Verification? verification;

  /// 未通过的情景（验证或基线不通过；与服务端 failing_scenarios 同义）。
  final List<String> failingScenarios;

  /// 数据问题（NEEDS_DATA 时）。
  final List<DataIssue> dataIssues;

  /// 各情景基线。
  final Map<String, BaselineCheck> baseline;

  /// 找到的分配的目标层取值（min_margin、fees、net_verified_benefit、buffer、cards）。
  final Map<String, int> objectives;

  /// 建模前被排除的卡及原因。
  final Map<String, Exclusion> exclusions;

  /// 实际的用卡数上限（min(请求的 K, 搜索上限)）。
  final int maxCards;

  /// 评估过的候选数。
  final int candidates;

  /// 调用验证器（可行性预言机）的次数。
  final int verifierCalls;

  /// 候选空间是否在预算内全部评估完。
  final bool exhausted;

  /// 是否因时间预算用完而停止。
  final bool timedOut;

  /// 耗时（微秒）。
  final int elapsedMicros;

  /// 永远为 false（非最优证明、非无解证明）。
  bool get proven => false;

  /// 结果的 JSON 形式（本地运行记录与调试用；不是协议 v1 的 PlanOutcome）。分配行与验证用
  /// 协议 v1 的 `AllocationLine` / `Verification` 写法。
  Map<String, Object?> toJson() => <String, Object?>{
    'outcome': outcome.name,
    'message': message,
    'proven': proven,
    'decision_scenario': decisionScenario,
    'profile': profile,
    'max_cards': maxCards,
    'allocation': verification == null
        ? <Object?>[]
        : allocationLinesToProtocol(verification!),
    'verification': verification == null
        ? null
        : verificationToProtocol(verification!),
    'failing_scenarios': <Object?>[...failingScenarios],
    'objectives': <String, Object?>{...objectives},
    'exclusions': <Object?>[
      for (final MapEntry(key: cardId, value: e) in exclusions.entries)
        <String, Object?>{
          'card_id': cardId,
          'reason': e.code,
          if (e.detail != null) 'detail': e.detail,
        },
    ],
    'data_issues': dataIssuesToProtocol(dataIssues),
    'baseline': <String, Object?>{
      for (final MapEntry(:key, :value) in baseline.entries)
        key: baselineCheckToProtocol(value),
    },
    'candidates': candidates,
    'verifier_calls': verifierCalls,
    'exhausted': exhausted,
    'timed_out': timedOut,
    'elapsed_us': elapsedMicros,
  };

  /// 给用户看的结论。
  String get message => switch (outcome) {
    LocalSearchOutcome.found => '本地找到可行方案，非最优证明',
    LocalSearchOutcome.notFound => '本地未找到（非证明无解）',
    LocalSearchOutcome.needsData => '数据不全，本地未搜索',
    LocalSearchOutcome.baselineShortfall => '新增消费前已有现金缺口，本地未搜索',
  };
}

/// 对 PlanInput 文档做有限搜索：决策情景、画像与快照过期天数默认取文档的 `options`。
/// 文档非法时抛 [ProtocolError]。
BoundedSearchResult boundedSearchFromProtocol(
  Object? document, {
  String? decisionScenario,
  String? profile,
  BoundedSearchOptions options = const BoundedSearchOptions(),
}) {
  final parsed = inputsFromProtocol(document);
  return boundedSearch(
    parsed.inputs,
    parsed.scenarios,
    decisionScenario: decisionScenario ?? parsed.options.decisionScenario,
    profile: profile ?? parsed.options.profile,
    staleAfterDays: parsed.options.staleAfterDays,
    options: options,
  );
}

int Function() _stopwatchClock() {
  final watch = Stopwatch()..start();
  return () => watch.elapsedMicroseconds;
}

/// 在 [scenarios] 中以 [decisionScenario] 为决策情景、按 [profile] 的目标层做有限搜索。
BoundedSearchResult boundedSearch(
  ModelInputs inputs,
  Map<String, Scenario> scenarios, {
  required String decisionScenario,
  String profile = 'cash_safety',
  int staleAfterDays = 7,
  BoundedSearchOptions options = const BoundedSearchOptions(),
}) {
  if (options.maxCards < 1 || options.maxCards > 3) {
    throw ArgumentError.value(options.maxCards, 'maxCards', 'must be 1..3');
  }
  final tiers = objectiveTiers[profile];
  if (tiers == null) {
    throw ArgumentError.value(profile, 'profile', 'unknown profile');
  }
  final clock = options.clock ?? _stopwatchClock();
  final started = clock();
  final budget = options.budget.inMicroseconds;
  int elapsed() => clock() - started;

  final issues = dataIssues(inputs, staleAfterDays);
  if (!scenarios.containsKey(decisionScenario)) {
    issues.add(
      DataIssue('UNKNOWN_DECISION_SCENARIO', scenario: decisionScenario),
    );
  }
  if (issues.isNotEmpty) {
    return BoundedSearchResult(
      outcome: LocalSearchOutcome.needsData,
      decisionScenario: decisionScenario,
      profile: profile,
      dataIssues: issues,
      elapsedMicros: elapsed(),
    );
  }
  final baseline = <String, BaselineCheck>{
    for (final MapEntry(:key, :value) in scenarios.entries)
      key: baselineCheck(inputs, value),
  };
  final decision = scenarios[decisionScenario]!;
  if (!baseline[decisionScenario]!.ok) {
    return BoundedSearchResult(
      outcome: LocalSearchOutcome.baselineShortfall,
      decisionScenario: decisionScenario,
      profile: profile,
      baseline: baseline,
      failingScenarios: [
        for (final MapEntry(:key, :value) in baseline.entries)
          if (!value.ok) key,
      ],
      elapsedMicros: elapsed(),
    );
  }
  final layers = capacityLayers(inputs);
  final exclusions = <String, Exclusion>{};
  final infos = <CardPlanInfo>[];
  for (final c in inputs.cards) {
    final (info, exclusion) = classify(c, inputs, layers: layers);
    if (exclusion != null) {
      exclusions[c.id] = exclusion;
    } else {
      infos.add(info!);
    }
  }
  final k = inputs.request.k < options.maxCards
      ? inputs.request.k
      : options.maxCards;
  if (infos.isEmpty) {
    return BoundedSearchResult(
      outcome: LocalSearchOutcome.notFound,
      decisionScenario: decisionScenario,
      profile: profile,
      baseline: baseline,
      exclusions: exclusions,
      maxCards: k,
      exhausted: true,
      elapsedMicros: elapsed(),
    );
  }
  final search = _Search(
    inputs: inputs,
    decisionId: decisionScenario,
    decision: decision,
    infos: infos,
    layers: layers,
    tiers: tiers,
    rangeLimit: options.exhaustiveRangeLimit,
    outOfTime: () => elapsed() >= budget,
  );
  final exhausted = search.run(k);
  final best = search.best;
  if (best == null) {
    return BoundedSearchResult(
      outcome: LocalSearchOutcome.notFound,
      decisionScenario: decisionScenario,
      profile: profile,
      baseline: baseline,
      exclusions: exclusions,
      maxCards: k,
      candidates: search.candidates,
      verifierCalls: search.verifierCalls,
      exhausted: exhausted,
      timedOut: !exhausted,
      elapsedMicros: elapsed(),
    );
  }
  final allocation = search.allocationOf(best);
  final verification = verify(inputs, allocation, scenarios, decisionScenario);
  if (!verification.ok) {
    // 决策情景的预言机已接受它，全情景验证不可能在决策情景上拒绝；若发生是缺陷，不吞掉。
    throw StateError('verifier disagreement on the bounded-search allocation');
  }
  final failing = [
    for (final MapEntry(:key, :value) in verification.checks.entries)
      if (!value.ok) key,
  ];
  baseline.forEach((scenarioId, b) {
    if (!b.ok && !failing.contains(scenarioId)) {
      failing.add(scenarioId);
    }
  });
  return BoundedSearchResult(
    outcome: LocalSearchOutcome.found,
    decisionScenario: decisionScenario,
    profile: profile,
    allocation: allocation,
    verification: verification,
    failingScenarios: failing,
    baseline: baseline,
    objectives: best.objectives,
    exclusions: exclusions,
    maxCards: k,
    candidates: search.candidates,
    verifierCalls: search.verifierCalls,
    exhausted: exhausted,
    timedOut: !exhausted,
    elapsedMicros: elapsed(),
  );
}

/// 一个候选：按卡输入顺序的（卡序号, 金额）与目标层取值。
final class _Candidate {
  _Candidate(this.parts, this.objectives, this.key);

  /// （infos 中的序号, 金额），序号递增。
  final List<(int, int)> parts;
  final Map<String, int> objectives;

  /// 越小越好的目标向量（max 层取相反数）。
  final List<int> key;
}

final class _Search {
  _Search({
    required this.inputs,
    required this.decisionId,
    required this.decision,
    required this.infos,
    required this.layers,
    required this.tiers,
    required this.rangeLimit,
    required this.outOfTime,
  }) : _margins = _MarginModel(inputs, decision, infos) {
    for (final info in infos) {
      final (cap, _) = cardLimit(info.card, layers);
      _caps.add(cap);
      _minSplits.add(info.card.minSplit ?? inputs.request.minSplit);
    }
    for (var i = 0; i < infos.length; i++) {
      _cash.add(_margins.cashCut(i, (x) => x + cardFee(infos[i].card, x)));
    }
  }

  final ModelInputs inputs;
  final String decisionId;
  final Scenario decision;
  final List<CardPlanInfo> infos;
  final CapacityLayers layers;
  final List<(String, String)> tiers;
  final int rangeLimit;
  final bool Function() outOfTime;
  final _MarginModel _margins;
  final List<int> _caps = <int>[];
  final List<int> _minSplits = <int>[];
  final List<int?> _cash = <int?>[];

  _Candidate? best;
  int candidates = 0;
  int _combinations = 0;
  int verifierCalls = 0;
  bool _stopped = false;

  Map<String, int> allocationOf(_Candidate c) => <String, int>{
    for (final (i, amount) in c.parts) infos[i].card.id: amount,
  };

  /// 枚举全部候选；预算内评估完返回 true。
  bool run(int k) {
    final n = infos.length;
    final combo = <int>[];
    void combinations(int start, int size) {
      if (_stopped) {
        return;
      }
      if (combo.length == size) {
        if (++_combinations % 1024 == 0 && outOfTime()) {
          _stopped = true;
          return;
        }
        _assign(combo, 0, inputs.request.amount, <int>[]);
        return;
      }
      for (var i = start; i < n && !_stopped; i++) {
        combo.add(i);
        combinations(i + 1, size);
        combo.removeLast();
      }
    }

    for (var size = 1; size <= k && size <= n && !_stopped; size++) {
      combinations(0, size);
    }
    return !_stopped;
  }

  void _assign(List<int> combo, int pos, int remaining, List<int> chosen) {
    if (_stopped) {
      return;
    }
    final card = combo[pos];
    if (pos == combo.length - 1) {
      if (remaining >= _minSplits[card] && remaining <= _caps[card]) {
        _evaluate(combo, [...chosen, remaining]);
      }
      return;
    }
    var restMin = 0;
    var restCap = 0;
    var restCash = 0;
    var restCashKnown = true;
    for (var j = pos + 1; j < combo.length; j++) {
      restMin += _minSplits[combo[j]];
      restCap += _caps[combo[j]];
      final cash = _cash[combo[j]];
      if (cash == null) {
        restCashKnown = false;
      } else {
        restCash += cash;
      }
    }
    final lo = _max(_minSplits[card], remaining - restCap);
    final hi = _min(_caps[card], remaining - restMin);
    if (lo > hi) {
      return;
    }
    final values = <int>{lo, hi};
    void cut(int v) {
      if (v >= lo && v <= hi) {
        values.add(v);
      }
    }

    final cash = _cash[card];
    if (cash != null) {
      cut(cash);
    }
    if (restCashKnown) {
      cut(remaining - restCash);
    }
    final parts = combo.length - pos;
    cut(remaining ~/ parts);
    cut((remaining + parts - 1) ~/ parts);
    final c = infos[card].card;
    final accountCap = layers.account[c.accountId];
    final poolId = c.poolId;
    final poolCap = poolId == null ? null : layers.pool[poolId];
    if (accountCap != null || poolCap != null) {
      var accountUsed = 0;
      var poolUsed = 0;
      for (var j = 0; j < pos; j++) {
        final other = infos[combo[j]].card;
        if (other.accountId == c.accountId) {
          accountUsed += chosen[j];
        }
        if (poolId != null && other.poolId == poolId) {
          poolUsed += chosen[j];
        }
      }
      if (accountCap != null) {
        cut(accountCap - accountUsed);
      }
      if (poolCap != null) {
        cut(poolCap - poolUsed);
      }
    }
    if (hi - lo < rangeLimit) {
      for (var v = lo; v <= hi; v++) {
        values.add(v);
      }
    }
    final ordered = values.toList()..sort((a, b) => b.compareTo(a));
    for (final v in ordered) {
      if (_stopped) {
        return;
      }
      _assign(combo, pos + 1, remaining - v, [...chosen, v]);
    }
  }

  void _evaluate(List<int> combo, List<int> amounts) {
    if (outOfTime()) {
      _stopped = true;
      return;
    }
    candidates++;
    final parts = <(int, int)>[
      for (var i = 0; i < combo.length; i++) (combo[i], amounts[i]),
    ];
    final objectives = _objectives(parts);
    final key = [
      for (final (name, sense) in tiers)
        sense == 'max' ? -objectives[name]! : objectives[name]!,
    ];
    final candidate = _Candidate(parts, objectives, key);
    final current = best;
    if (current != null && !_better(candidate, current)) {
      return;
    }
    verifierCalls++;
    final allocation = allocationOf(candidate);
    final check = verify(inputs, allocation, <String, Scenario>{
      decisionId: decision,
    }, decisionId);
    if (check.ok) {
      best = candidate;
    }
  }

  /// 目标层更优；全部相等时按卡输入顺序字典序更大（§12.5）。
  bool _better(_Candidate a, _Candidate b) {
    for (var i = 0; i < a.key.length; i++) {
      if (a.key[i] != b.key[i]) {
        return a.key[i] < b.key[i];
      }
    }
    return _lexGreater(a.parts, b.parts);
  }

  static bool _lexGreater(List<(int, int)> a, List<(int, int)> b) {
    var i = 0;
    var j = 0;
    while (i < a.length || j < b.length) {
      final ai = i < a.length ? a[i].$1 : 1 << 30;
      final bj = j < b.length ? b[j].$1 : 1 << 30;
      final card = ai < bj ? ai : bj;
      final x = ai == card ? a[i].$2 : 0;
      final y = bj == card ? b[j].$2 : 0;
      if (x != y) {
        return x > y;
      }
      if (ai == card) {
        i++;
      }
      if (bj == card) {
        j++;
      }
    }
    return false;
  }

  Map<String, int> _objectives(List<(int, int)> parts) {
    var fees = 0;
    var benefit = 0;
    var buffer = 0;
    final repayments = <(int, int)>[];
    for (final (i, x) in parts) {
      final card = infos[i].card;
      final fee = cardFee(card, x);
      fees += fee;
      if (!card.verifiedBenefitRate.isZero) {
        var b = applyRate(x, card.verifiedBenefitRate, RoundingMode.down);
        final cap = card.verifiedBenefitCap;
        if (cap != null && cap < b) {
          b = cap;
        }
        benefit += b;
      }
      buffer += x * infos[i].bufferDays;
      repayments.add((i, x + fee));
    }
    return <String, int>{
      'min_margin': _margins.margin(repayments),
      'fees': fees,
      'net_verified_benefit': benefit - fees,
      'buffer': buffer,
      'cards': parts.length,
    };
  }
}

int _max(int a, int b) => a > b ? a : b;
int _min(int a, int b) => a < b ? a : b;

/// 模型的最差现金余量（engine-spec §3 第 8 条、§4 层 1；Python 模型与差分参考的 `min_margin`）：
/// 决策情景下、不含新计划的各账户时间线，以可用卡的还款日为额外检查点；检查点 = 所有账户 low 点
/// 日期的并集；每个检查点上 `当日最低点（或沿用此前期末） − 已到期的还款（金额 + 费用） − 储备`，
/// 取所有账户、所有检查点的最小值。只用于排序；可行与否由验证器判定。
///
/// 区间最小值查询的端点只会是 0、检查点总数或某张可用卡的还款日位置，因此每个账户按这些断点
/// 分块，块最小值上建稀疏表，每次查询 O(1)。
final class _MarginModel {
  _MarginModel(
    ModelInputs inputs,
    Scenario decision,
    List<CardPlanInfo> infos,
  ) {
    final checkpointDays = <String, List<LocalDate>>{};
    for (final info in infos) {
      checkpointDays
          .putIfAbsent(info.card.repayFrom, () => <LocalDate>[])
          .add(info.repayOn);
    }
    final timelines = <Timeline>[
      for (final a in inputs.accounts)
        buildTimeline(
          a,
          inputs.snapshots[a.id]!,
          inputs.events,
          decision,
          inputs.horizonEnd,
          checkpointDays: checkpointDays[a.id] ?? const <LocalDate>[],
        ),
    ];
    final dateSet = <int>{};
    for (final t in timelines) {
      for (final p in t.points) {
        if (p.phase == PointPhase.low) {
          dateSet.add(p.on.epochDay);
        }
      }
    }
    final epochDays = dateSet.toList()..sort();
    final dates = [for (final d in epochDays) LocalDate.fromEpochDay(d)];
    _dateCount = dates.length;
    final position = <int, int>{
      for (var i = 0; i < epochDays.length; i++) epochDays[i]: i,
    };
    final accountIndex = <String, int>{
      for (var a = 0; a < inputs.accounts.length; a++) inputs.accounts[a].id: a,
    };
    for (final info in infos) {
      _cardAccount.add(accountIndex[info.card.repayFrom]!);
      _cardIndex.add(position[info.repayOn.epochDay]!);
    }
    for (var a = 0; a < inputs.accounts.length; a++) {
      final floor = inputs.accounts[a].reserveFloor;
      final values = [
        for (final v in lowSeries(timelines[a], dates)) v - floor,
      ];
      final breaks = <int>{0, _dateCount};
      for (var c = 0; c < infos.length; c++) {
        if (_cardAccount[c] == a) {
          breaks.add(_cardIndex[c]);
        }
      }
      _ranges.add(_BlockRangeMin(values, breaks.toList()..sort()));
    }
  }

  static const int _none = 1 << 62;

  late final int _dateCount;
  final List<_BlockRangeMin> _ranges = <_BlockRangeMin>[];
  final List<int> _cardAccount = <int>[];
  final List<int> _cardIndex = <int>[];

  /// [repayments]：（卡序号, 还款额 = 金额 + 费用）。
  int margin(List<(int, int)> repayments) {
    if (_dateCount == 0) {
      return 0;
    }
    final byAccount = <int, List<(int, int)>>{};
    for (final (card, amount) in repayments) {
      byAccount.putIfAbsent(_cardAccount[card], () => <(int, int)>[]).add((
        _cardIndex[card],
        amount,
      ));
    }
    var result = _none;
    for (var a = 0; a < _ranges.length; a++) {
      final range = _ranges[a];
      final used = byAccount[a];
      if (used == null) {
        if (range.all < result) {
          result = range.all;
        }
        continue;
      }
      used.sort((x, y) => x.$1.compareTo(y.$1));
      var start = 0;
      var spent = 0;
      for (final (index, amount) in used) {
        if (index > start) {
          final m = range.min(start, index) - spent;
          if (m < result) {
            result = m;
          }
          start = index;
        }
        spent += amount;
      }
      final m = range.min(start, _dateCount) - spent;
      if (m < result) {
        result = m;
      }
    }
    return result;
  }

  /// 卡 [card] 单独使用时现金允许的最大金额：在其还款日及之后的每个检查点上，
  /// `还款额(x) <= 余量`（[repaymentOf] 含费用，单调不减）；不足 1 个最小单位时为 null。
  int? cashCut(int card, int Function(int x) repaymentOf) {
    final headroom = _ranges[_cardAccount[card]].min(
      _cardIndex[card],
      _dateCount,
    );
    if (headroom == _none || headroom < 1) {
      return null;
    }
    var lo = 0;
    var hi = headroom;
    while (lo < hi) {
      final mid = lo + (hi - lo + 1) ~/ 2;
      if (repaymentOf(mid) <= headroom) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo >= 1 ? lo : null;
  }
}

/// 只在给定断点上查询的区间最小值：断点之间分块，块最小值上建稀疏表。
final class _BlockRangeMin {
  _BlockRangeMin(List<int> values, this._breaks) {
    for (var k = 0; k + 1 < _breaks.length; k++) {
      var min = _MarginModel._none;
      for (var i = _breaks[k]; i < _breaks[k + 1]; i++) {
        if (values[i] < min) {
          min = values[i];
        }
      }
      _blockOf[_breaks[k]] = k;
      _table.isEmpty ? _table.add(<int>[min]) : _table.first.add(min);
    }
    _blockOf[_breaks.last] = _breaks.length - 1;
    if (_table.isEmpty) {
      _table.add(<int>[]);
    }
    final blocks = _table.first.length;
    for (var width = 1; width * 2 <= blocks; width *= 2) {
      final previous = _table.last;
      _table.add(<int>[
        for (var k = 0; k + width * 2 <= blocks; k++)
          previous[k] < previous[k + width] ? previous[k] : previous[k + width],
      ]);
    }
    all = blocks == 0 ? _MarginModel._none : min(0, _breaks.last);
  }

  final List<int> _breaks;
  final Map<int, int> _blockOf = <int, int>{};
  final List<List<int>> _table = <List<int>>[];

  /// 整个序列的最小值。
  late final int all;

  /// `[from, to)` 的最小值；端点必须是断点。空区间为一个很大的数。
  int min(int from, int to) {
    final a = _blockOf[from]!;
    final b = _blockOf[to]!;
    if (a >= b) {
      return _MarginModel._none;
    }
    var level = 0;
    while ((2 << level) <= b - a) {
      level++;
    }
    final row = _table[level];
    final x = row[a];
    final y = row[b - (1 << level)];
    return x < y ? x : y;
  }
}
