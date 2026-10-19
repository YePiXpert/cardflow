import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../mapping/cash_mapping.dart';
import '../time/clock.dart';
import 'bank_repository.dart';
import 'card_repository.dart';
import 'card_wallet_reader.dart' show creditAccountDisplayName;
import 'cash_account_repository.dart';
import 'cash_event_repository.dart';
import 'cash_models.dart';
import 'credit_account_repository.dart';
import 'installment_repository.dart';
import 'ledger_models.dart';
import 'recurring_item_repository.dart';
import 'scenario_repository.dart';
import 'workspace_scope.dart';

/// 交给领域包之前的现金数据（当前工作空间），已通过交叉校验（[checkCashTimelineInputs]）。
///
/// 口径：只有"计入可用现金"（[CashAvailability.counted]）且未停用的账户进入计算；计入但缺快照的账户
/// 列在 [missingSnapshot]（"数据不全：{账户}缺快照，未计入"，不补零）；不计入的列在 [excluded]。
@immutable
final class CashDomainInputs {
  const CashDomainInputs({
    required this.today,
    required this.judgeStale,
    required this.accountRows,
    required this.availability,
    required this.counted,
    required this.excluded,
    required this.missingSnapshot,
    required this.latestSnapshots,
    required this.accounts,
    required this.countedDomain,
    required this.snapshots,
    required this.events,
    required this.eventRows,
    required this.issues,
    this.installmentDue = const <TailObligation>[],
  });

  /// 现金时区里的今天。
  final LocalDate today;

  /// 是否判断陈旧（演示空间的固定时钟不判）。
  final bool judgeStale;

  /// 未删除的现金账户（含已停用），按建立时间。
  final List<CashAccountRow> accountRows;

  final Map<String, CashAvailability> availability;

  /// 计入可用现金、未停用的账户。
  final List<CashAccountRow> counted;

  /// 未停用但不计入可用现金的账户（受限资金等）。
  final List<CashAccountRow> excluded;

  /// 计入可用现金但还没有快照的账户（未计入计算）。
  final List<CashAccountRow> missingSnapshot;

  /// 每个账户的最新快照。
  final Map<String, CashSnapshotRow> latestSnapshots;

  /// 进入计算的账户（计入且有快照）→ 领域 [CashAccount]，按建立时间。
  final List<CashAccount> accounts;

  /// 全部计入的账户（含缺快照的）→ 领域 [CashAccount]：交给 `dataIssues`。
  final List<CashAccount> countedDomain;

  /// 进入计算的账户的最新快照（含已包含的事件）。
  final Map<String, Snapshot> snapshots;

  /// 计入的账户的未删除事件 → 领域 [CashEvent]，按日期与登记顺序。
  final List<CashEvent> events;

  /// 全部未删除事件（所有账户）的行，按 id。
  final Map<String, CashEventRow> eventRows;

  /// 领域包 `dataIssues`（`staleAfterDays` = 7；演示空间去掉陈旧）。
  final List<DataIssue> issues;

  /// 进行中分期计划尚未结清的各期（到期日、本金 + 费用；F-06：窗口外的进入尾部责任）。
  final List<TailObligation> installmentDue;

  /// 快照距今天数（按现金时区的日期）。
  int? snapshotAgeDays(String accountId) {
    final snapshot = latestSnapshots[accountId];
    return snapshot == null
        ? null
        : today.differenceInDays(LocalDate.parse(snapshot.balanceAsOf));
  }

  /// 快照陈旧（> 7 天）：依赖它的结果是"假设分析"（R-CASH-09）。
  bool isStale(String accountId) =>
      issues.any((i) => i.code == 'STALE_SNAPSHOT' && i.account == accountId);

  CashAccountRow? accountRow(String id) {
    for (final row in accountRows) {
      if (row.id == id) {
        return row;
      }
    }
    return null;
  }
}

/// 资金日历的一行（一天）：流出、流入、当日最低（先支出后收入或按时刻）、日终。
@immutable
final class CashDayRow {
  const CashDayRow({
    required this.on,
    required this.outflow,
    required this.inflow,
    required this.low,
    required this.end,
    required this.gap,
    required this.eventIds,
  });

  final LocalDate on;

  /// 当日流出合计（≤0）。
  final int outflow;

  /// 当日流入合计（≥0）。
  final int inflow;

  /// 当日最低点。
  final int low;

  /// 日终余额。
  final int end;

  /// 这一天是缺口点（流出使余额低于储备，领域包 `evaluate` 的口径）。
  final bool gap;

  /// 当日的事件（情景变换后计入这一天的）。
  final List<String> eventIds;
}

/// 一个账户在一个口径下的资金日历。
@immutable
final class CashAccountForecast {
  const CashAccountForecast({
    required this.row,
    required this.account,
    required this.snapshot,
    required this.report,
    required this.days,
    required this.amounts,
    required this.ageDays,
    required this.stale,
    required this.availability,
  });

  final CashAccountRow row;
  final CashAccount account;
  final CashSnapshotRow snapshot;

  /// 领域包 `evaluateAccounts` 的结果（时间线、全部缺口点、最低点）。
  final CashReport report;

  /// 有事件的日子（不含快照点）。
  final List<CashDayRow> days;

  /// 情景变换后的金额（事件 id → 金额）。
  final Map<String, int> amounts;
  final int ageDays;
  final bool stale;
  final CashAvailability availability;

  /// 快照本身已低于储备（快照点缺口）。
  Breach? get snapshotBreach {
    for (final b in report.breaches) {
      if (b.phase == PointPhase.snapshot) {
        return b;
      }
    }
    return null;
  }
}

/// 一个缺口点与造成它的事件。
@immutable
final class CashGap {
  const CashGap({required this.account, required this.breach});

  final CashAccountForecast account;
  final Breach breach;
}

/// 一个币种的摘要（账户之间从不相互抵补：最低点是"最差的那个账户的最低点"）。
@immutable
final class CashSummary {
  const CashSummary({
    required this.currency,
    required this.lowest,
    required this.gapCount,
    required this.firstGap,
  });

  final String currency;

  /// 全窗口最低点所在的账户（最低余额最小者；相同时日期早者、账户在前者）。
  final CashAccountForecast lowest;

  /// 缺口点总数。
  final int gapCount;

  /// 最早的缺口点。
  final CashGap? firstGap;

  int get lowestBalance => lowest.report.minBalance;

  LocalDate get lowestOn => lowest.report.minOn;

  /// 距零：最低点减零（负数 = 缺口）。
  int get marginToZero => lowestBalance;

  /// 距储备：最低点减该账户储备（负数 = 低于储备）。
  int get marginToReserve => lowestBalance - lowest.account.reserveFloor;
}

/// 尾部责任：窗口外的计划（planned）事件与分期计划尚未结清的各期（R-CASH-08、F-06）。
@immutable
final class TailObligation {
  const TailObligation({
    required this.on,
    required this.amountMinor,
    required this.currency,
    required this.accountName,
    required this.label,
    required this.source,
    required this.refId,
  });

  final LocalDate on;
  final int amountMinor;
  final String currency;
  final String accountName;
  final String label;

  /// `cash_event`（计划事件）或 `installment`（分期的一期，I-1c；`refId` 为 `计划 id/期号`）。
  final String source;

  /// 来源行的 id。
  final String refId;
}

/// 选了压力口径，但还没有压力情景（或所选情景已删除）。
final class ScenarioMissingException implements Exception {
  const ScenarioMissingException();

  @override
  String toString() => 'ScenarioMissingException';
}

/// 资金日历的查询（P-07 控制条）。
@immutable
final class CashForecastQuery {
  const CashForecastQuery({
    this.windowDays = 30,
    this.basis = CashBasis.baseline,
    this.scenarioKey,
    this.accountId,
  });

  /// 7 / 30 / 90 / 180。
  final int windowDays;
  final CashBasis basis;

  /// 压力情景的键（[CashBasis.stress] 时必填）。
  final String? scenarioKey;

  /// 只看一个账户；空 = 全部计入的账户（逐账户计算，不互抵）。
  final String? accountId;

  CashForecastQuery copyWith({
    int? windowDays,
    CashBasis? basis,
    String? scenarioKey,
    String? accountId,
    bool clearAccount = false,
  }) => CashForecastQuery(
    windowDays: windowDays ?? this.windowDays,
    basis: basis ?? this.basis,
    scenarioKey: scenarioKey ?? this.scenarioKey,
    accountId: clearAccount ? null : accountId ?? this.accountId,
  );

  @override
  bool operator ==(Object other) =>
      other is CashForecastQuery &&
      other.windowDays == windowDays &&
      other.basis == basis &&
      other.scenarioKey == scenarioKey &&
      other.accountId == accountId;

  @override
  int get hashCode => Object.hash(windowDays, basis, scenarioKey, accountId);
}

/// 资金日历（P-07）与总览现金压力卡（P-01）的读模型。
@immutable
final class CashForecast {
  const CashForecast({
    required this.inputs,
    required this.scenario,
    required this.horizonEnd,
    required this.accounts,
    required this.summaries,
    required this.gaps,
    required this.tail,
    required this.assumptions,
    required this.inactiveOverrides,
  });

  final CashDomainInputs inputs;
  final ScenarioView scenario;

  /// 窗口最后一天（含）：今天 + 窗口天数 − 1。
  final LocalDate horizonEnd;

  /// 进入计算的账户（按查询筛选）。
  final List<CashAccountForecast> accounts;

  /// 按币种的摘要（计算的账户多于一个币种时有多条）。
  final List<CashSummary> summaries;

  /// 全部缺口点（按日期，同日按账户顺序）。
  final List<CashGap> gaps;

  /// 尾部责任（窗口外的计划事件）。
  final List<TailObligation> tail;

  /// 假设：领域包的说明（先支出后收入、快照当天未包含事件、情景改期…）与数据层的说明（可用日期、陈旧）。
  final List<String> assumptions;

  /// 指向已删除事件、未生效的情景覆盖。
  final List<EventOverrideSpec> inactiveOverrides;

  LocalDate get today => inputs.today;

  /// 还没有任何现金账户（首次空白）。
  bool get hasNoAccounts => inputs.accountRows.isEmpty;

  /// 有账户计入但都没有快照（或都不计入）：无法计算。
  bool get nothingToCompute => accounts.isEmpty;

  /// 有陈旧快照参与计算：结果是"假设分析"（R-CASH-09）。
  bool get assumptionAnalysis => accounts.any((a) => a.stale);

  int get gapCount => gaps.length;
}

/// 现金读模型的组装：一次读齐当前工作空间的现金账户、快照、事件，映射成领域对象，交给领域包计算
/// （`evaluateAccounts`、`dataIssues`）；资金日历、总览现金压力卡与情景计算都经过这里。
final class CashForecastReader {
  CashForecastReader(this._scope);

  final WorkspaceScope _scope;

  /// 读入当前工作空间的现金数据。[expand] 为真时先把周期事项展开到"今天 + 180 天"（没有要补的期时
  /// 不写库）。交叉校验不通过时抛 [CashInputsException]。
  Future<CashDomainInputs> loadInputs({bool expand = true}) async {
    final today = _scope.clock.today(cashTimeZone);
    if (expand) {
      await RecurringItemRepository(_scope)
          .expandUntil(today.addDays(cashHorizonDays));
    }
    final accountRows = await CashAccountRepository(_scope).list();
    final snapshotRepo = CashSnapshotRepository(_scope);
    final latest = await snapshotRepo.latestByAccount();
    final includes = await snapshotRepo.includedEventIds();
    final eventRows = await CashEventRepository(_scope).list();
    final rowById = {for (final e in eventRows) e.id: e};

    final availability = <String, CashAvailability>{
      for (final row in accountRows) row.id: CashAvailability.of(row),
    };
    final active = accountRows
        .where((a) => a.status == CashAccountStatus.active.code)
        .toList();
    final counted = active.where((a) => availability[a.id]!.counted).toList();
    final excluded = active.where((a) => !availability[a.id]!.counted).toList();

    Snapshot domainSnapshot(CashSnapshotRow row) =>
        snapshotFromRow(row, <String>[
          for (final id in includes[row.id] ?? const <String>{})
            // 已删除的事件不在事件列表里：从包含关系里去掉（它本来就不影响时间线）。
            if (rowById[id]?.cashAccountId == row.cashAccountId) id,
        ]);

    // 交叉校验：全部未删除的账户、快照与事件（含已停用、不计入的），确保库里的数据整体一致。
    final allAccounts = <CashAccount>[
      for (final row in accountRows) cashAccountFromRow(row, today: today),
    ];
    final transferGroups = <String, List<String>>{};
    for (final e in eventRows) {
      final group = e.transferGroupId;
      if (group != null) {
        transferGroups.putIfAbsent(group, () => <String>[]).add(e.id);
      }
    }
    checkCashTimelineInputs(
      accounts: allAccounts,
      snapshots: <String, Snapshot>{
        for (final entry in latest.entries)
          entry.key: domainSnapshot(entry.value),
      },
      events: <CashEvent>[for (final e in eventRows) cashEventFromRow(e)],
      transferGroups: transferGroups,
    );

    final countedIds = {for (final a in counted) a.id};
    final countedDomain = <CashAccount>[
      for (final row in counted) cashAccountFromRow(row, today: today),
    ];
    final snapshots = <String, Snapshot>{
      for (final row in counted)
        if (latest[row.id] case final s?) row.id: domainSnapshot(s),
    };
    final events = <CashEvent>[
      for (final e in eventRows)
        if (countedIds.contains(e.cashAccountId)) cashEventFromRow(e),
    ];
    final issues = countedDomain.isEmpty
        ? const <DataIssue>[]
        : dataIssues(
            ModelInputs(
              request: PlanRequest(
                amount: 1,
                currency: countedDomain.first.currency,
                txnDate: today,
              ),
              cards: const <CardOption>[],
              pools: const <String, int>{},
              accounts: countedDomain,
              snapshots: snapshots,
              events: events,
              horizonEnd: today.addDays(cashHorizonDays),
            ),
            cashStaleAfterDays,
          );
    final judgeStale = !_scope.clock.isFixed;
    final installmentDue = await _installmentDue();
    return CashDomainInputs(
      today: today,
      judgeStale: judgeStale,
      accountRows: accountRows,
      availability: availability,
      counted: counted,
      excluded: excluded,
      missingSnapshot: counted.where((a) => latest[a.id] == null).toList(),
      latestSnapshots: latest,
      accounts: <CashAccount>[
        for (final a in countedDomain)
          if (snapshots.containsKey(a.id)) a,
      ],
      countedDomain: countedDomain,
      snapshots: snapshots,
      events: events,
      eventRows: rowById,
      issues: <DataIssue>[
        for (final issue in issues)
          if (judgeStale || issue.code != 'STALE_SNAPSHOT') issue,
      ],
      installmentDue: installmentDue,
    );
  }

  /// 进行中的分期计划尚未结清（未出账、已出账）的各期：到期日、金额（本金 + 费用，记为流出）、信用账户名。
  Future<List<TailObligation>> _installmentDue() async {
    final installments = InstallmentRepository(_scope);
    final plans = <InstallmentPlanRow>[
      for (final p in await installments.plans())
        if (p.status == InstallmentPlanStatus.active.code) p,
    ];
    if (plans.isEmpty) {
      return const <TailObligation>[];
    }
    final accounts = CreditAccountRepository(_scope);
    final subs = {for (final c in await accounts.currencyAccounts()) c.id: c};
    final credit = {for (final a in await accounts.list()) a.id: a};
    final banks = {
      for (final b in await BankRepository(_scope).listStored()) b.id: b,
    };
    final cards = await CardRepository(_scope).list();
    final due = <TailObligation>[];
    for (final plan in plans) {
      final sub = subs[plan.currencyAccountId];
      final account = sub == null ? null : credit[sub.creditAccountId];
      final bank = account == null ? null : banks[account.bankId];
      if (sub == null || account == null || bank == null) {
        continue;
      }
      final name = creditAccountDisplayName(account, cards, bank);
      for (final p in await installments.schedule(plan.id)) {
        final status = InstallmentPeriodStatus.of(p.status);
        if (status != InstallmentPeriodStatus.scheduled &&
            status != InstallmentPeriodStatus.billed) {
          continue;
        }
        due.add(
          TailObligation(
            on: LocalDate.parse(p.dueDate),
            amountMinor: -(p.principalMinor + p.feeMinor),
            currency: sub.currency,
            accountName: name,
            label: '分期 第 ${p.periodNo}/${plan.periods} 期',
            source: 'installment',
            refId: '${plan.id}/${p.periodNo}',
          ),
        );
      }
    }
    return due;
  }

  /// 查询对应的情景（内置两条或压力情景）；压力情景不存在时为 null。
  Future<ScenarioView?> scenarioFor(CashForecastQuery query) async {
    final repo = ScenarioRepository(_scope);
    ScenarioView builtin(List<ScenarioView> all, ScenarioKind kind) =>
        all.firstWhere((s) => s.kind == kind);
    return switch (query.basis) {
      CashBasis.confirmed => builtin(
        await repo.list(),
        ScenarioKind.builtinConfirmed,
      ),
      CashBasis.baseline => builtin(
        await repo.list(),
        ScenarioKind.builtinBaseline,
      ),
      CashBasis.stress =>
        query.scenarioKey == null ? null : await repo.byKey(query.scenarioKey!),
    };
  }

  /// 资金日历（P-07）。压力口径的情景不存在时抛 [ScenarioMissingException]。
  Future<CashForecast> forecast(CashForecastQuery query) async {
    final inputs = await loadInputs();
    final scenario = await scenarioFor(query);
    if (scenario == null) {
      throw const ScenarioMissingException();
    }
    return forecastFrom(
      inputs,
      scenario,
      windowDays: query.windowDays,
      accountId: query.accountId,
    );
  }

  /// 情景计算：写入新的计算版本（区间 = 今天 至 今天 + 180 天，全部计入的账户）。内置情景第一次计算时
  /// 才写入数据库行。
  Future<ScenarioRunRow> recompute(String scenarioKey) async {
    final repo = ScenarioRepository(_scope);
    var scenario = await repo.require(scenarioKey);
    if (scenario.row == null) {
      scenario = ScenarioView.fromRow(await repo.ensureBuiltin(scenario.kind));
    }
    final inputs = await loadInputs();
    final from = inputs.today;
    final to = from.addDays(cashHorizonDays);
    final forecast = forecastFrom(
      inputs,
      scenario,
      windowDays: cashHorizonDays + 1,
    );
    return repo.addRun(
      scenarioId: scenario.row!.id,
      horizonFrom: from,
      horizonTo: to,
      inputsHash: inputsHash(inputs, scenario, from, to),
      result: runResultOf(forecast),
    );
  }

  /// 计算版本是否已过期：用它自己的区间与当前数据、当前参数重新算输入哈希，与存下的不同即过期。
  bool isRunStale(
    CashDomainInputs inputs,
    ScenarioView scenario,
    ScenarioRunRow run,
  ) =>
      inputsHash(
        inputs,
        scenario,
        LocalDate.parse(run.horizonFrom),
        LocalDate.parse(run.horizonTo),
      ) !=
      run.inputsHash;
}

/// 在已读入的数据上计算一个口径的资金日历（窗口 = 今天起 [windowDays] 天）。逐账户调用领域包
/// `evaluateAccounts`（账户之间从不相互抵补），再把时间线整理成日行、缺口列表、摘要、尾部责任与假设。
CashForecast forecastFrom(
  CashDomainInputs inputs,
  ScenarioView scenario, {
  required int windowDays,
  String? accountId,
}) {
  final today = inputs.today;
  final horizonEnd = today.addDays(windowDays - 1);
  final liveEventIds = inputs.eventRows.keys.toSet();
  final domainScenario = scenarioFromParams(
    scenario.domainId,
    scenario.params,
    liveEventIds: liveEventIds,
    description: scenario.name,
  );
  final shown = <CashAccount>[
    for (final a in inputs.accounts)
      if (accountId == null || a.id == accountId) a,
  ];
  final reports = evaluateAccounts(
    shown,
    inputs.snapshots,
    inputs.events,
    domainScenario,
    horizonEnd,
  );
  final accounts = <CashAccountForecast>[];
  for (final account in shown) {
    final report = reports[account.id]!;
    final amounts = <String, int>{
      for (final e in inputs.events)
        if (e.account == account.id)
          if (scenarioEvent(e, domainScenario) case final t?) e.id: t.amount,
    };
    final breachDays = <int>{
      for (final b in report.breaches)
        if (b.phase == PointPhase.low) b.on.epochDay,
    };
    final days = <CashDayRow>[];
    final points = report.timeline.points;
    for (var i = 1; i + 1 < points.length; i += 2) {
      final low = points[i];
      final end = points[i + 1];
      var outflow = 0;
      var inflow = 0;
      for (final id in end.eventIds) {
        final amount = amounts[id] ?? 0;
        if (amount < 0) {
          outflow += amount;
        } else {
          inflow += amount;
        }
      }
      days.add(
        CashDayRow(
          on: end.on,
          outflow: outflow,
          inflow: inflow,
          low: low.balance,
          end: end.balance,
          gap: breachDays.contains(end.on.epochDay),
          eventIds: end.eventIds,
        ),
      );
    }
    final row = inputs.accountRow(account.id)!;
    accounts.add(
      CashAccountForecast(
        row: row,
        account: account,
        snapshot: inputs.latestSnapshots[account.id]!,
        report: report,
        days: days,
        amounts: amounts,
        ageDays: inputs.snapshotAgeDays(account.id)!,
        stale: inputs.isStale(account.id),
        availability: inputs.availability[account.id]!,
      ),
    );
  }

  final gaps = <CashGap>[
    for (final a in accounts)
      for (final b in a.report.breaches) CashGap(account: a, breach: b),
  ];
  final order = {for (var i = 0; i < accounts.length; i++) accounts[i]: i};
  gaps.sort((x, y) {
    final byDate = x.breach.on.compareTo(y.breach.on);
    return byDate != 0
        ? byDate
        : order[x.account]!.compareTo(order[y.account]!);
  });

  final summaries = <CashSummary>[];
  for (final currency in <String>{
    for (final a in accounts) a.account.currency,
  }) {
    final group = accounts
        .where((a) => a.account.currency == currency)
        .toList();
    var lowest = group.first;
    for (final a in group.skip(1)) {
      final r = a.report;
      final best = lowest.report;
      if (r.minBalance < best.minBalance ||
          (r.minBalance == best.minBalance && r.minOn < best.minOn)) {
        lowest = a;
      }
    }
    final groupGaps = gaps.where((g) => g.account.account.currency == currency);
    summaries.add(
      CashSummary(
        currency: currency,
        lowest: lowest,
        gapCount: groupGaps.length,
        firstGap: groupGaps.isEmpty ? null : groupGaps.first,
      ),
    );
  }

  final shownIds = {for (final a in shown) a.id};
  final tail = <TailObligation>[
    for (final e in inputs.eventRows.values)
      if (shownIds.contains(e.cashAccountId) &&
          e.cls == CashEventClass.planned.code &&
          LocalDate.parse(e.eventOn) > horizonEnd)
        TailObligation(
          on: LocalDate.parse(e.eventOn),
          amountMinor: e.amountMinor,
          currency: inputs.accountRow(e.cashAccountId)!.currency,
          accountName: inputs.accountRow(e.cashAccountId)!.name,
          label: e.label ?? CashCategory.of(e.category).label,
          source: 'cash_event',
          refId: e.id,
        ),
    // F-06：分期在窗口外的到期期次（不属于任何现金账户，筛选账户时照样列出）。
    for (final t in inputs.installmentDue)
      if (t.on > horizonEnd) t,
  ]..sort((a, b) => a.on.compareTo(b.on));

  final assumptions = <String>[
    for (final a in accounts)
      for (final text in a.report.assumptions) '${a.row.name}：$text',
    for (final a in accounts)
      if (a.availability.usableFrom case final from? when from > today)
        '${a.row.name}：$from 起才可用于还款，之前的余额不算可用于还款',
    for (final a in accounts)
      if (a.stale) '${a.row.name}：余额快照已是 ${a.ageDays} 天前，结果为假设分析（未补零）',
  ];
  final inactive = <EventOverrideSpec>[
    for (final o in scenario.params.eventOverrides)
      if (!liveEventIds.contains(o.eventId)) o,
  ];
  if (inactive.isNotEmpty) {
    assumptions.add('情景中有 ${inactive.length} 项覆盖指向已删除的收支，未生效');
  }
  return CashForecast(
    inputs: inputs,
    scenario: scenario,
    horizonEnd: horizonEnd,
    accounts: accounts,
    summaries: summaries,
    gaps: gaps,
    tail: tail,
    assumptions: assumptions,
    inactiveOverrides: inactive,
  );
}

/// 计算版本的输入哈希（区间 [from, to]、计入的账户与快照、区间内的事件、情景参数）。
String inputsHash(
  CashDomainInputs inputs,
  ScenarioView scenario,
  LocalDate from,
  LocalDate to,
) => cashInputsHash(
  from: from,
  to: to,
  accounts: inputs.accounts,
  snapshots: inputs.snapshots,
  events: inputs.events,
  params: scenario.params,
  usableFrom: <String, LocalDate?>{
    for (final a in inputs.accounts)
      a.id: inputs.availability[a.id]!.usableFrom,
  },
);

/// 资金日历 → 情景计算结果（存进 `scenario_runs.result`）。
CashRunResult runResultOf(CashForecast forecast) => CashRunResult(
  accounts: <RunAccountResult>[
    for (final a in forecast.accounts)
      RunAccountResult.fromReport(a.account, a.report),
  ],
  assumptions: forecast.assumptions,
  dataIssues: <Map<String, Object?>>[
    for (final issue in forecast.inputs.issues) dataIssueToJson(issue),
  ],
  excluded: <String>[for (final a in forecast.inputs.excluded) a.name],
  missingSnapshot: <String>[
    for (final a in forecast.inputs.missingSnapshot) a.name,
  ],
  inactiveOverrides: <String>[
    for (final o in forecast.inactiveOverrides) o.eventId,
  ],
);

/// 两个计算结果的逐账户对比（P-09「对比」）。
@immutable
final class RunComparisonRow {
  const RunComparisonRow({
    required this.accountId,
    required this.name,
    required this.currency,
    required this.a,
    required this.b,
  });

  final String accountId;
  final String name;
  final String currency;
  final RunAccountResult? a;
  final RunAccountResult? b;

  /// 最低现金之差（B − A）；任一方没有该账户时为 null。
  int? get minDelta =>
      a == null || b == null ? null : b!.minBalance - a!.minBalance;

  /// 缺口点数之差（B − A）。
  int? get gapDelta =>
      a == null || b == null ? null : b!.breaches.length - a!.breaches.length;
}

/// 逐账户对比两个计算结果（账户按 A 的顺序，再补 B 独有的）。
List<RunComparisonRow> compareRuns(CashRunResult a, CashRunResult b) {
  final byA = {for (final r in a.accounts) r.accountId: r};
  final byB = {for (final r in b.accounts) r.accountId: r};
  final ids = <String>[
    for (final r in a.accounts) r.accountId,
    for (final r in b.accounts)
      if (!byA.containsKey(r.accountId)) r.accountId,
  ];
  return <RunComparisonRow>[
    for (final id in ids)
      RunComparisonRow(
        accountId: id,
        name: (byB[id] ?? byA[id])!.name,
        currency: (byB[id] ?? byA[id])!.currency,
        a: byA[id],
        b: byB[id],
      ),
  ];
}

/// P-09 情景列表的一项：情景、它的计算版本（新的在前）与最新版本是否已过期。
@immutable
final class ScenarioBoardItem {
  const ScenarioBoardItem({
    required this.scenario,
    required this.runs,
    required this.stale,
  });

  final ScenarioView scenario;
  final List<ScenarioRunRow> runs;

  /// 最新版本的输入与当前数据、当前参数不符（P-09"过期"）。
  final bool stale;

  ScenarioRunRow? get latest => runs.isEmpty ? null : runs.first;

  CashRunResult? get latestResult =>
      latest == null ? null : CashRunResult.parse(latest!.result);
}

/// P-09 情景列表的读模型。
@immutable
final class ScenarioBoard {
  const ScenarioBoard({required this.inputs, required this.items});

  /// 读入当前工作空间的情景与版本，并判断每个情景最新版本是否过期。
  static Future<ScenarioBoard> load(WorkspaceScope scope) async {
    final reader = CashForecastReader(scope);
    final inputs = await reader.loadInputs();
    final repo = ScenarioRepository(scope);
    final items = <ScenarioBoardItem>[];
    for (final scenario in await repo.list()) {
      final row = scenario.row;
      final runs = row == null
          ? const <ScenarioRunRow>[]
          : await repo.runs(row.id);
      items.add(
        ScenarioBoardItem(
          scenario: scenario,
          runs: runs,
          stale:
              runs.isNotEmpty &&
              reader.isRunStale(inputs, scenario, runs.first),
        ),
      );
    }
    return ScenarioBoard(inputs: inputs, items: items);
  }

  final CashDomainInputs inputs;

  /// 内置两条在前，然后是压力情景。
  final List<ScenarioBoardItem> items;

  ScenarioBoardItem? item(String key) {
    for (final i in items) {
      if (i.scenario.key == key) {
        return i;
      }
    }
    return null;
  }

  /// 用户压力情景。
  List<ScenarioBoardItem> get stressItems => <ScenarioBoardItem>[
    for (final i in items)
      if (!i.scenario.isBuiltin) i,
  ];

  /// 全部计算版本（用于对比选择），按情景顺序、新的在前。
  List<(ScenarioBoardItem, ScenarioRunRow)> get allRuns =>
      <(ScenarioBoardItem, ScenarioRunRow)>[
        for (final i in items)
          for (final r in i.runs) (i, r),
      ];
}
