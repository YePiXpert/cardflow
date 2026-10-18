import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../mapping/cash_mapping.dart';
import '../time/clock.dart';
import 'cash_account_repository.dart';
import 'cash_event_repository.dart';
import 'cash_models.dart';
import 'recurring_item_repository.dart';
import 'repository_errors.dart';
import 'workspace_scope.dart';

/// 一个现金账户的概况（P-08 账户列表）：最新快照、"{n} 天前"、陈旧、可用性、储备。
@immutable
final class CashAccountSummary {
  const CashAccountSummary({
    required this.row,
    required this.latestSnapshot,
    required this.ageDays,
    required this.stale,
    required this.availability,
  });

  final CashAccountRow row;
  final CashSnapshotRow? latestSnapshot;

  /// 快照距今天数（按现金时区的日期）；没有快照时为 null。
  final int? ageDays;

  /// 快照超过 7 天（演示空间不判）。
  final bool stale;
  final CashAvailability availability;

  bool get active => row.status == CashAccountStatus.active.code;

  CashAccountKind get kind => CashAccountKind.of(row.kind);

  /// 计入可用现金但没有快照："未计入规划"（P-08 九态"数据不全"）。
  bool get missingSnapshot =>
      active && availability.counted && latestSnapshot == null;
}

/// 周期事项的概况：下一期与单期例外数。
@immutable
final class RecurringItemSummary {
  const RecurringItemSummary({
    required this.row,
    required this.next,
    required this.exceptions,
  });

  final RecurringItemRow row;

  /// 今天及以后最近的一期（已展开的事件；没有时为 null）。
  final CashEventRow? next;

  /// 单期覆盖与跳过的项数。
  final int exceptions;
}

/// P-08 现金账户与收支计划的读模型。
@immutable
final class CashPlanView {
  const CashPlanView({
    required this.today,
    required this.accounts,
    required this.plan,
    required this.recurring,
    required this.transfers,
  });

  /// 现金时区里的今天。
  final LocalDate today;

  /// 未删除的现金账户：使用中在前（按建立时间），已停用在后。
  final List<CashAccountSummary> accounts;

  /// 收支计划：不是调拨、不是周期事项的未删除事件，日期不早于今天往前 31 天，按日期。
  final List<CashEventRow> plan;

  final List<RecurringItemSummary> recurring;

  /// 未删除的调拨。
  final List<TransferView> transfers;

  bool get isEmpty => accounts.isEmpty;

  CashAccountSummary? account(String id) {
    for (final a in accounts) {
      if (a.row.id == id) {
        return a;
      }
    }
    return null;
  }

  /// 使用中的账户（新增收支、调拨时可选）。
  List<CashAccountRow> get activeAccounts => <CashAccountRow>[
    for (final a in accounts)
      if (a.active) a.row,
  ];
}

/// 一次快照与它已包含的事件。
@immutable
final class CashSnapshotEntry {
  const CashSnapshotEntry({required this.row, required this.included});

  final CashSnapshotRow row;

  /// 余额已包含的事件（已删除的事件仍列出，便于追溯）。
  final List<CashEventRow> included;
}

/// P-08 账户详情：快照历史（含已包含的事件）与本账户的收支。
@immutable
final class CashAccountDetailView {
  const CashAccountDetailView({
    required this.summary,
    required this.snapshots,
    required this.events,
    required this.recurring,
  });

  final CashAccountSummary summary;

  /// 快照历史，最新在前。
  final List<CashSnapshotEntry> snapshots;

  /// 本账户未删除的事件（含周期事项与调拨），日期不早于今天往前 31 天。
  final List<CashEventRow> events;

  final List<RecurringItemRow> recurring;
}

/// 周期事项详情：各期（展开的事件与例外）。
@immutable
final class RecurringDetailView {
  const RecurringDetailView({
    required this.row,
    required this.account,
    required this.occurrences,
    required this.today,
  });

  final RecurringItemRow row;
  final CashAccountRow account;
  final List<RecurringOccurrence> occurrences;
  final LocalDate today;
}

/// P-08 的读模型组装（只读；读之前把周期事项展开到"今天 + 180 天"，没有要补的期时不写库）。
final class CashPlanReader {
  CashPlanReader(this._scope);

  final WorkspaceScope _scope;

  LocalDate get _today => _scope.clock.today(cashTimeZone);

  Future<CashPlanView> load() async {
    final today = _today;
    final recurringRepo = RecurringItemRepository(_scope);
    await recurringRepo.expandUntil(today.addDays(cashHorizonDays));
    final summaries = await _summaries();
    final events = CashEventRepository(_scope);
    final from = today.addDays(-31);
    final all = await events.list(from: from);
    final items = await recurringRepo.list();
    final recurring = <RecurringItemSummary>[];
    for (final item in items) {
      CashEventRow? next;
      for (final e in all) {
        if (e.recurringItemId == item.id &&
            LocalDate.parse(e.eventOn) >= today) {
          next = e;
          break;
        }
      }
      recurring.add(
        RecurringItemSummary(
          row: item,
          next: next,
          exceptions: (await recurringRepo.overridesOf(item.id)).length,
        ),
      );
    }
    return CashPlanView(
      today: today,
      accounts: summaries,
      plan: <CashEventRow>[
        for (final e in all)
          if (e.transferGroupId == null && e.recurringItemId == null) e,
      ],
      recurring: recurring,
      transfers: await events.transfers(),
    );
  }

  /// 账户详情；账户不在当前空间时抛 [NotFoundException]。
  Future<CashAccountDetailView> loadAccount(String accountId) async {
    final today = _today;
    await RecurringItemRepository(_scope)
        .expandUntil(today.addDays(cashHorizonDays));
    final summary = (await _summaries()).firstWhere(
      (s) => s.row.id == accountId,
      orElse: () => throw const NotFoundException('现金账户'),
    );
    final snapshotRepo = CashSnapshotRepository(_scope);
    final history = await snapshotRepo.history(accountId);
    final includes = await snapshotRepo.includedEventIds();
    final db = _scope.db;
    final included = <String, CashEventRow>{
      for (final e
          in await (db.select(db.cashEvents)..where(
                (e) =>
                    e.workspaceId.equals(_scope.workspaceId) &
                    e.cashAccountId.equals(accountId),
              ))
              .get())
        e.id: e,
    };
    return CashAccountDetailView(
      summary: summary,
      snapshots: <CashSnapshotEntry>[
        for (final s in history)
          CashSnapshotEntry(
            row: s,
            included: <CashEventRow>[
              for (final id in includes[s.id] ?? const <String>{})
                ?included[id],
            ]..sort((a, b) => a.eventOn.compareTo(b.eventOn)),
          ),
      ],
      events: await CashEventRepository(_scope)
          .list(cashAccountId: accountId, from: today.addDays(-31)),
      recurring: <RecurringItemRow>[
        for (final r in await RecurringItemRepository(_scope).list())
          if (r.cashAccountId == accountId) r,
      ],
    );
  }

  /// 周期事项详情；不在当前空间时抛 [NotFoundException]。
  Future<RecurringDetailView> loadRecurring(String itemId) async {
    final repo = RecurringItemRepository(_scope);
    await repo.expandUntil(_today.addDays(cashHorizonDays));
    final row = await repo.require(itemId);
    return RecurringDetailView(
      row: row,
      account: await CashAccountRepository(_scope).require(row.cashAccountId),
      occurrences: await repo.occurrences(itemId),
      today: _today,
    );
  }

  Future<List<CashAccountSummary>> _summaries() async {
    final today = _today;
    final accounts = await CashAccountRepository(_scope).list();
    final latest = await CashSnapshotRepository(_scope).latestByAccount();
    final judgeStale = !_scope.clock.isFixed;
    final out = <CashAccountSummary>[];
    for (final row in accounts) {
      final snapshot = latest[row.id];
      final age = snapshot == null
          ? null
          : today.differenceInDays(LocalDate.parse(snapshot.balanceAsOf));
      out.add(
        CashAccountSummary(
          row: row,
          latestSnapshot: snapshot,
          ageDays: age,
          stale: judgeStale && age != null && age > cashStaleAfterDays,
          availability: CashAvailability.of(row),
        ),
      );
    }
    return <CashAccountSummary>[
      ...out.where((a) => a.active),
      ...out.where((a) => !a.active),
    ];
  }
}
