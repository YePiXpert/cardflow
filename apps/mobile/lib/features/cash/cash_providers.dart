import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate;
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/db/app_database.dart';
import '../../data/db/database_providers.dart';
import '../../data/repositories/providers.dart';

part 'cash_providers.g.dart';

/// 某账户某一天已登记的收支（记录快照时逐条询问"余额是否已包含"）。
@immutable
final class SameDayEvents {
  const SameDayEvents(this.events);

  final List<CashEventRow> events;
}

/// [accountId] 在 [date]（`YYYY-MM-DD`）这一天的未删除收支。
@Riverpod(retry: noDatabaseRetry)
Future<SameDayEvents> sameDayCashEvents(
  Ref ref,
  String accountId,
  String date,
) async {
  ref.watch(localDataRevisionProvider);
  final repo = await ref.watch(cashSnapshotRepositoryProvider.future);
  return SameDayEvents(
    await repo.sameDayEvents(accountId, LocalDate.parse(date)),
  );
}

/// 一笔收支与它的账户（P-08 修改收支）。
@immutable
final class CashEventEntry {
  const CashEventEntry({required this.row, required this.account});

  final CashEventRow row;
  final CashAccountRow account;
}

/// 按 id 取一笔未删除的收支；不在当前空间时失败（NotFoundException）。
@Riverpod(retry: noDatabaseRetry)
Future<CashEventEntry> cashEventEntry(Ref ref, String eventId) async {
  ref.watch(localDataRevisionProvider);
  final events = await ref.watch(cashEventRepositoryProvider.future);
  final accounts = await ref.watch(cashAccountRepositoryProvider.future);
  final row = await events.require(eventId);
  return CashEventEntry(
    row: row,
    account: await accounts.require(row.cashAccountId),
  );
}
