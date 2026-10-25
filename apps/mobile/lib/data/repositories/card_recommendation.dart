/// 单笔单卡比较：只读取卡片、额度和账期；现金充足是产品假设，不创建虚拟现金数据。
library;

import 'package:cardflow_domain/cardflow_domain.dart';

import '../db/app_database.dart';
import '../mapping/domain_mapping.dart';
import 'card_wallet_reader.dart';

final class NextCycleHint {
  const NextCycleHint({
    required this.waitDays,
    required this.swipeOn,
    required this.nextDueDate,
    required this.extraDays,
  });

  final int waitDays;
  final LocalDate swipeOn;
  final LocalDate nextDueDate;
  final int extraDays;
}

final class CardSplitItem {
  const CardSplitItem({required this.card, required this.amount});
  final CardRecommendation card;
  final int amount;
}

final class CardRecommendation {
  const CardRecommendation({
    required this.account,
    required this.card,
    required this.currency,
    required this.capacity,
    required this.forecast,
    required this.reason,
    required this.stale,
    required this.snapshotDate,
    this.nextCycleHint,
  });

  final AccountView account;
  final CardRow card;
  final String currency;
  final int? capacity;
  final ForecastPredicted? forecast;
  final String? reason;
  final bool stale;
  final String? snapshotDate;
  final NextCycleHint? nextCycleHint;
  bool get eligible => reason == null;
  LocalDate get dueDate => forecast!.conservative.dueDate;
  String get title => '${account.bank.name} ···· ${card.last4}';
}

/// 结果只属于本次输入，不改变余额、额度、账单或预留。
final class RecommendationResult {
  const RecommendationResult(
    this.eligible,
    this.excluded, {
    this.splitPlan = const <CardSplitItem>[],
    this.totalCapacity = 0,
  });
  final List<CardRecommendation> eligible;
  final List<CardRecommendation> excluded;
  final List<CardSplitItem> splitPlan;
  final int totalCapacity;
}

NextCycleHint? _computeNextCycleHint(
  CurrencyAccountView? sub,
  ForecastPredicted? forecast,
  LocalDate on,
) {
  if (sub == null || forecast == null) return null;
  final currentDue = forecast.conservative.dueDate;
  for (var wait = 1; wait <= 3; wait++) {
    final nextDate = on.addDays(wait);
    final nextForecast = forecastCycles(sub.ruleVersions, nextDate);
    if (nextForecast is ForecastPredicted) {
      final nextDue = nextForecast.conservative.dueDate;
      final extra = nextDue.differenceInDays(currentDue);
      if (extra > 0) {
        return NextCycleHint(
          waitDays: wait,
          swipeOn: nextDate,
          nextDueDate: nextDue,
          extraDays: extra,
        );
      }
    }
  }
  return null;
}

RecommendationResult recommendCards({
  required WalletView wallet,
  required int amount,
  required String currency,
  required LocalDate on,
}) {
  if (amount <= 0) {
    throw ArgumentError.value(amount, 'amount', 'must be positive');
  }
  final subs = <String, CurrencyAccountView>{
    for (final a in wallet.accounts)
      for (final s in a.currencies)
        if (s.currency == currency) a.id: s,
  };
  final model = CapacityModel.build(
    currency: currency,
    on: on,
    accounts: <AccountCapacityInput>[
      for (final a in wallet.accounts)
        if (subs.containsKey(a.id))
          AccountCapacityInput(
            accountId: a.id,
            snapshot: subs[a.id]!.latestSnapshot,
            cards: a.cards,
            poolId: a.pool?.currency == currency ? a.pool!.id : null,
          ),
    ],
    pools: <PoolCapacityInput>[
      for (final p in wallet.pools)
        if (p.pool.currency == currency)
          PoolCapacityInput(
            poolId: p.pool.id,
            sharedLimitMinor: p.pool.sharedLimitMinor,
            memberAccountIds: p.members.map((a) => a.id).toList(),
          ),
    ],
  );
  final eligible = <CardRecommendation>[];
  final excluded = <CardRecommendation>[];
  for (final a in wallet.accounts) {
    final sub = subs[a.id];
    final forecast = sub == null ? null : forecastCycles(sub.ruleVersions, on);
    final predicted = forecast is ForecastPredicted ? forecast : null;
    final hint = _computeNextCycleHint(sub, predicted, on);
    final capacity = model.accountCapacity(a.id);
    final missingPool =
        a.pool?.currency == currency &&
        model.poolRawAvailable(a.pool!.id) == null;
    for (final card in a.cards) {
      String? reason;
      if (a.isInactive ||
          card.status == 'closed' ||
          card.status == 'replaced') {
        reason = '卡片已停用';
      } else if (a.account.status == 'frozen' || card.status == 'frozen') {
        reason = '卡片已冻结';
      } else if (card.effectiveFrom != null &&
          LocalDate.parse(card.effectiveFrom!) > on) {
        reason = '消费日卡片尚未生效';
      } else if (sub == null) {
        reason = '不支持本次币种';
      } else if (sub.latestSnapshot == null || missingPool) {
        reason = missingPool ? '共享额度资料不全，请更新成员卡额度' : '请补充可用额度';
      } else if ((capacity ?? 0) < amount) {
        reason = '可用额度不足';
      } else if (forecast is ForecastNoRule) {
        reason = '请设置账期规则';
      } else if (forecast is! ForecastPredicted) {
        reason = '该消费日期无法计算账期，请检查规则';
      }
      final row = CardRecommendation(
        account: a,
        card: card,
        currency: currency,
        capacity: missingPool ? null : capacity,
        forecast: predicted,
        reason: reason,
        stale: sub?.stale ?? false,
        snapshotDate: sub?.latestSnapshot?.balanceAsOf,
        nextCycleHint: hint,
      );
      (row.eligible ? eligible : excluded).add(row);
    }
  }
  int identity(CardRecommendation a, CardRecommendation b) {
    var order = a.account.bank.name.compareTo(b.account.bank.name);
    if (order == 0) order = a.card.last4.compareTo(b.card.last4);
    return order == 0 ? a.card.id.compareTo(b.card.id) : order;
  }

  int byPriority(CardRecommendation a, CardRecommendation b) {
    var order = b.dueDate.compareTo(a.dueDate);
    if (order == 0) order = b.capacity!.compareTo(a.capacity!);
    return order == 0 ? identity(a, b) : order;
  }

  eligible.sort(byPriority);
  excluded.sort(identity);

  final usable = <CardRecommendation>[
    ...eligible,
    for (final row in excluded)
      if (row.reason == '可用额度不足' &&
          row.forecast != null &&
          (row.capacity ?? 0) > 0)
        row,
  ]..sort(byPriority);

  final poolLimit = <String, int>{
    for (final p in wallet.pools)
      if (p.pool.currency == currency && model.poolCapacity(p.pool.id) != null)
        p.pool.id: model.poolCapacity(p.pool.id)!,
  };
  final poolForTotal = Map<String, int>.of(poolLimit);
  final poolForSplit = Map<String, int>.of(poolLimit);
  var totalCapacity = 0;
  var remaining = amount;
  final split = <CardSplitItem>[];
  final seenAccounts = <String>{};
  for (final row in usable) {
    if (!seenAccounts.add(row.account.id)) continue;
    final own = model.accountOwnCapacity(row.account.id) ?? 0;
    final poolId = row.account.pool?.currency == currency
        ? row.account.pool!.id
        : null;
    final availTotal = poolId != null && poolForTotal.containsKey(poolId)
        ? (own < poolForTotal[poolId]! ? own : poolForTotal[poolId]!)
        : own;
    if (availTotal > 0) {
      totalCapacity += availTotal;
      if (poolId != null && poolForTotal.containsKey(poolId)) {
        poolForTotal[poolId] = poolForTotal[poolId]! - availTotal;
      }
    }
    if (eligible.isEmpty && remaining > 0) {
      final availSplit = poolId != null && poolForSplit.containsKey(poolId)
          ? (own < poolForSplit[poolId]! ? own : poolForSplit[poolId]!)
          : own;
      if (availSplit > 0) {
        final take = remaining < availSplit ? remaining : availSplit;
        split.add(CardSplitItem(card: row, amount: take));
        remaining -= take;
        if (poolId != null && poolForSplit.containsKey(poolId)) {
          poolForSplit[poolId] = poolForSplit[poolId]! - take;
        }
      }
    }
  }
  final splitPlan = eligible.isEmpty && remaining == 0 && split.length > 1
      ? List<CardSplitItem>.unmodifiable(split)
      : const <CardSplitItem>[];

  return RecommendationResult(
    List.unmodifiable(eligible),
    List.unmodifiable(excluded),
    splitPlan: splitPlan,
    totalCapacity: totalCapacity,
  );
}
