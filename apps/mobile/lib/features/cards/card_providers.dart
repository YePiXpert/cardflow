import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/db/app_database.dart';
import '../../data/db/database_providers.dart';
import '../../data/repositories/bank_repository.dart';
import '../../data/repositories/providers.dart';

part 'card_providers.g.dart';

/// 新建卡片时的银行选择（内置常用银行 + 用户添加的）。
@Riverpod(retry: noDatabaseRetry)
Future<List<BankChoice>> bankChoices(Ref ref) async {
  ref.watch(localDataRevisionProvider);
  final banks = await ref.watch(bankRepositoryProvider.future);
  return banks.choices();
}

/// P-04 需要、而卡包读模型里没有的数据：各币种子账户的快照历史（最新在前）与同银行的授信池。
@immutable
final class AccountSettingsData {
  const AccountSettingsData({required this.snapshots, required this.bankPools});

  /// 币种子账户 id → 快照历史（最新在前）。
  final Map<String, List<LimitSnapshotRow>> snapshots;

  /// 与账户同一银行的授信池。
  final List<CreditPoolRow> bankPools;
}

/// P-04 的附加数据；账户不在当前空间时失败（NotFoundException）。
@Riverpod(retry: noDatabaseRetry)
Future<AccountSettingsData> accountSettingsData(
  Ref ref,
  String accountId,
) async {
  ref.watch(localDataRevisionProvider);
  final accounts = await ref.watch(creditAccountRepositoryProvider.future);
  final snapshots = await ref.watch(limitSnapshotRepositoryProvider.future);
  final pools = await ref.watch(creditPoolRepositoryProvider.future);
  final account = await accounts.require(accountId);
  final subs = await accounts.currencyAccounts(accountId);
  return AccountSettingsData(
    snapshots: <String, List<LimitSnapshotRow>>{
      for (final sub in subs) sub.id: await snapshots.history(sub.id),
    },
    bankPools: await pools.forBank(account.bankId),
  );
}
