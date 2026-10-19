import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate;
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../mapping/domain_mapping.dart';
import '../time/business_tz.dart';
import '../time/clock.dart';
import 'bank_repository.dart';
import 'billing_rule_repository.dart';
import 'card_repository.dart';
import 'credit_account_repository.dart';
import 'credit_pool_repository.dart';
import 'limit_snapshot_repository.dart';
import 'models.dart';
import 'workspace_scope.dart';

/// 余额/额度快照超过多少天算陈旧（R-CASH-09 默认 7 天）；演示空间不判陈旧。
const int staleAfterDays = 7;

/// 一个币种子账户的读模型。
@immutable
final class CurrencyAccountView {
  const CurrencyAccountView({
    required this.row,
    required this.latestSnapshot,
    required this.availableToday,
    required this.ownCapacity,
    required this.capacity,
    required this.snapshotAgeDays,
    required this.stale,
    required this.forecast,
    required this.ruleVersions,
  });

  final CurrencyAccountRow row;

  /// 最新额度快照；没有时容量未知。
  final LimitSnapshotRow? latestSnapshot;

  /// 今天可用于新增消费的银行可用额原值（临额到期已回落），可为负。
  final int? availableToday;

  /// 账户自身容量（卡层与账户层），不含池。
  final int? ownCapacity;

  /// 可供新增消费的容量（三层取最小，截零）。
  final int? capacity;

  /// 快照距今天数（按业务时区的日期）。
  final int? snapshotAgeDays;

  /// 快照是否陈旧（超过 [staleAfterDays] 天；演示空间恒为 false）。
  final bool stale;

  /// 这个子账户的预测账期（子账户有自己的规则版本时用它的，否则用信用账户的）。
  final CycleForecast forecast;

  /// 实际采用的规则版本（子账户自己的或信用账户的）。
  final List<BillingRuleVersionRow> ruleVersions;

  String get currency => row.currency;

  /// 银行可用额为负：显示"超限"，容量为 0（F-26）。
  bool get overLimit => (availableToday ?? 0) < 0;
}

/// 一个信用账户的读模型。
@immutable
final class AccountView {
  const AccountView({
    required this.account,
    required this.bank,
    required this.zone,
    required this.today,
    required this.currencies,
    required this.cards,
    required this.ruleVersions,
    required this.currentRule,
    required this.pool,
  });

  final CreditAccountRow account;
  final BankRow bank;
  final BusinessTimeZone zone;

  /// 账户业务时区里的"今天"。
  final LocalDate today;

  /// 币种子账户，主子账户在前。
  final List<CurrencyAccountView> currencies;

  /// 卡片：未停用的在前（按建立时间），已停用的在后。
  final List<CardRow> cards;

  /// 信用账户层的规则版本（按版本号）。
  final List<BillingRuleVersionRow> ruleVersions;

  /// 今天生效的信用账户层版本；没有或规则版本有冲突时为 null。
  final BillingRuleVersionRow? currentRule;

  final CreditPoolRow? pool;

  String get id => account.id;

  CurrencyAccountView get primaryCurrency => currencies.first;

  /// 预测账期（主子账户）。
  CycleForecast get forecast => primaryCurrency.forecast;

  /// 未停用的卡片。
  List<CardRow> get activeCards =>
      cards.where((c) => !c.cardStatus.isInactive).toList();

  /// 已停用（已换卡、已销卡）的卡片。
  List<CardRow> get inactiveCards =>
      cards.where((c) => c.cardStatus.isInactive).toList();

  /// 账户已停用：账户关闭，或有卡片且全部已停用（卡包里折叠）。
  bool get isInactive =>
      account.status == 'closed' ||
      (cards.isNotEmpty && cards.every((c) => c.cardStatus.isInactive));

  /// 账户在界面上的名字：主卡（未停用）的别名 → 任一未停用卡的别名 → 产品名 → 银行名。
  String get displayName => creditAccountDisplayName(account, cards, bank);

  /// 规则来源徽标；没有规则时为 null（"未设置"）。
  RuleSource? get ruleSource {
    final rule =
        currentRule ?? (ruleVersions.isEmpty ? null : ruleVersions.last);
    return rule == null ? null : RuleSource.of(rule.source);
  }
}

/// 信用账户在界面上的名字：主卡（未停用）的别名 → 任一未停用卡的别名 → 产品名 → 银行名。
String creditAccountDisplayName(
  CreditAccountRow account,
  Iterable<CardRow> cards,
  BankRow bank,
) {
  final active = cards.where(
    (c) => c.creditAccountId == account.id && !c.cardStatus.isInactive,
  );
  for (final card in active) {
    if (card.kind == HolderKind.primary && card.alias != null) {
      return card.alias!;
    }
  }
  for (final card in active) {
    if (card.alias != null) {
      return card.alias!;
    }
  }
  return account.productName ?? bank.name;
}

/// 一个授信池的读模型（F-23）。
@immutable
final class PoolView {
  const PoolView({
    required this.pool,
    required this.bank,
    required this.members,
    required this.usedTotal,
    required this.rawAvailable,
    required this.capacity,
    required this.combinedCapacity,
    required this.missingSnapshots,
  });

  final CreditPoolRow pool;
  final BankRow bank;
  final List<AccountView> members;

  /// Σ 成员已用（池币种）；有成员缺快照时为 null。
  final int? usedTotal;

  /// 池可用原值 = 池上限 − Σ 已用（可为负）；未知时为 null。
  final int? rawAvailable;

  /// 池层容量（截零、扣除成员的预授权）。
  final int? capacity;

  /// 池内账户可用合计（不超过池层容量）。
  final int? combinedCapacity;

  /// 缺该币种额度快照的成员数。
  final int missingSnapshots;
}

/// 卡包（P-02）、详情（P-03）、总览（P-01）共用的读模型：授信池 › 信用账户 › 币种子账户 › 卡片。
@immutable
final class WalletView {
  const WalletView({required this.pools, required this.accounts});

  final List<PoolView> pools;

  /// 全部未删除的信用账户（按建立时间）。
  final List<AccountView> accounts;

  bool get isEmpty => accounts.isEmpty;

  /// 不在任何池里的账户。
  List<AccountView> get unpooledAccounts =>
      accounts.where((a) => a.pool == null).toList();

  AccountView? account(String id) {
    for (final a in accounts) {
      if (a.id == id) {
        return a;
      }
    }
    return null;
  }

  PoolView? poolOf(String accountId) {
    for (final p in pools) {
      if (p.members.any((m) => m.id == accountId)) {
        return p;
      }
    }
    return null;
  }
}

/// 读模型的组装（数据层 → 领域对象映射的入口）：一次读齐当前工作空间的账户、卡片、规则与快照，
/// 用领域包算预测账期（`selectRule` + `cyclesForTransaction`）与三层容量（`capacityLayers`）。
final class CardWalletReader {
  CardWalletReader(this._scope);

  final WorkspaceScope _scope;

  Future<WalletView> load() async {
    final banks = {
      for (final b in await BankRepository(_scope).listStored()) b.id: b,
    };
    final accountRepo = CreditAccountRepository(_scope);
    final accounts = await accountRepo.list();
    final currencies = await accountRepo.currencyAccounts();
    final cards = await CardRepository(_scope).list();
    final rules = await BillingRuleRepository(_scope).all();
    final pools = {
      for (final p in await CreditPoolRepository(_scope).list()) p.id: p,
    };
    final latest = await LimitSnapshotRepository(_scope)
        .latestByCurrencyAccount();

    List<BillingRuleVersionRow> rulesOf(String kind, String id) =>
        rules.where((r) => r.subjectKind == kind && r.subjectId == id).toList()
          ..sort((a, b) => a.version.compareTo(b.version));

    // 先按账户算出每个币种子账户的今天与容量输入。
    final todayOf = <String, LocalDate>{};
    final zoneOf = <String, BusinessTimeZone>{};
    for (final account in accounts) {
      final zone = businessTimeZoneOf(account.businessTz);
      zoneOf[account.id] = zone;
      todayOf[account.id] = _scope.clock.today(zone);
    }
    final models = <String, CapacityModel>{};
    final currencyCodes = currencies.map((c) => c.currency).toSet();
    for (final currency in currencyCodes) {
      final inputs = <AccountCapacityInput>[];
      for (final account in accounts) {
        CurrencyAccountRow? sub;
        for (final c in currencies) {
          if (c.creditAccountId == account.id && c.currency == currency) {
            sub = c;
          }
        }
        if (sub == null) {
          continue;
        }
        final pool = account.poolId == null ? null : pools[account.poolId];
        inputs.add(
          AccountCapacityInput(
            accountId: account.id,
            snapshot: latest[sub.id],
            cards: cards.where((c) => c.creditAccountId == account.id).toList(),
            poolId: pool != null && pool.currency == currency ? pool.id : null,
            on: todayOf[account.id],
          ),
        );
      }
      final poolInputs = <PoolCapacityInput>[
        for (final pool in pools.values)
          if (pool.currency == currency)
            PoolCapacityInput(
              poolId: pool.id,
              sharedLimitMinor: pool.sharedLimitMinor,
              memberAccountIds: accounts
                  .where((a) => a.poolId == pool.id)
                  .map((a) => a.id)
                  .toList(),
            ),
      ];
      models[currency] = CapacityModel.build(
        currency: currency,
        on: _scope.clock.today(defaultBusinessTimeZone),
        accounts: inputs,
        pools: poolInputs,
      );
    }

    final views = <AccountView>[];
    for (final account in accounts) {
      final zone = zoneOf[account.id]!;
      final today = todayOf[account.id]!;
      final accountRules = rulesOf('credit_account', account.id);
      final subViews = <CurrencyAccountView>[];
      for (final sub in currencies.where(
        (c) => c.creditAccountId == account.id,
      )) {
        final own = rulesOf('currency_account', sub.id);
        final effective = own.isNotEmpty ? own : accountRules;
        final snapshot = latest[sub.id];
        final model = models[sub.currency]!;
        final age = snapshot == null
            ? null
            : today.differenceInDays(snapshotBusinessDate(snapshot, zone));
        subViews.add(
          CurrencyAccountView(
            row: sub,
            latestSnapshot: snapshot,
            availableToday: snapshot == null
                ? null
                : availableOn(snapshot, today),
            ownCapacity: model.accountOwnCapacity(account.id),
            capacity: model.accountCapacity(account.id),
            snapshotAgeDays: age,
            stale: !_scope.clock.isFixed && age != null && age > staleAfterDays,
            forecast: forecastCycles(effective, today),
            ruleVersions: effective,
          ),
        );
      }
      // 未停用的在前；同组内保持仓库给出的建立顺序（稳定）。
      final ownCards = cards.where((c) => c.creditAccountId == account.id);
      final accountCards = <CardRow>[
        ...ownCards.where((c) => !c.cardStatus.isInactive),
        ...ownCards.where((c) => c.cardStatus.isInactive),
      ];
      BillingRuleVersionRow? current;
      final forecast = forecastCycles(accountRules, today);
      if (forecast is ForecastPredicted) {
        current = accountRules.firstWhere(
          (r) => r.id == forecast.ruleVersionId,
        );
      }
      views.add(
        AccountView(
          account: account,
          bank: banks[account.bankId]!,
          zone: zone,
          today: today,
          currencies: subViews,
          cards: accountCards,
          ruleVersions: accountRules,
          currentRule: current,
          pool: account.poolId == null ? null : pools[account.poolId],
        ),
      );
    }

    final poolViews = <PoolView>[];
    for (final pool in pools.values) {
      final members = views.where((v) => v.account.poolId == pool.id).toList();
      final model = models[pool.currency];
      final memberIds = members.map((m) => m.id).toList();
      final raw = model?.poolRawAvailable(pool.id);
      poolViews.add(
        PoolView(
          pool: pool,
          bank: banks[pool.bankId]!,
          members: members,
          usedTotal: raw == null ? null : pool.sharedLimitMinor - raw,
          rawAvailable: raw,
          capacity: model?.poolCapacity(pool.id),
          combinedCapacity: model?.poolCombinedCapacity(pool.id, memberIds),
          missingSnapshots: model == null
              ? members.length
              : model.poolMissingSnapshots(pool.id),
        ),
      );
    }
    return WalletView(pools: poolViews, accounts: views);
  }
}
