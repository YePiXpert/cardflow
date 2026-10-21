/// 单笔单卡比较：只读取卡片、额度和账期；现金充足是产品假设，不创建虚拟现金数据。
library;

import 'package:cardflow_domain/cardflow_domain.dart';

import '../db/app_database.dart';
import '../mapping/domain_mapping.dart';
import 'card_wallet_reader.dart';

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
  });

  final AccountView account;
  final CardRow card;
  final String currency;
  final int? capacity;
  final ForecastPredicted? forecast;
  final String? reason;
  final bool stale;
  final String? snapshotDate;
  bool get eligible => reason == null;
  LocalDate get dueDate => forecast!.conservative.dueDate;
  String get title => '${account.bank.name} ···· ${card.last4}';
}

/// 结果只属于本次输入，不改变余额、额度、账单或预留。
final class RecommendationResult {
  const RecommendationResult(this.eligible, this.excluded);
  final List<CardRecommendation> eligible;
  final List<CardRecommendation> excluded;
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
        forecast: forecast is ForecastPredicted ? forecast : null,
        reason: reason,
        stale: sub?.stale ?? false,
        snapshotDate: sub?.latestSnapshot?.balanceAsOf,
      );
      (row.eligible ? eligible : excluded).add(row);
    }
  }
  int identity(CardRecommendation a, CardRecommendation b) {
    var order = a.account.bank.name.compareTo(b.account.bank.name);
    if (order == 0) order = a.card.last4.compareTo(b.card.last4);
    return order == 0 ? a.card.id.compareTo(b.card.id) : order;
  }

  eligible.sort((a, b) {
    var order = b.dueDate.compareTo(a.dueDate);
    if (order == 0) order = b.capacity!.compareTo(a.capacity!);
    return order == 0 ? identity(a, b) : order;
  });
  excluded.sort(identity);
  return RecommendationResult(
    List.unmodifiable(eligible),
    List.unmodifiable(excluded),
  );
}
