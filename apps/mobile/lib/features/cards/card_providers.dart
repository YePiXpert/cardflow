import 'package:riverpod_annotation/riverpod_annotation.dart';

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
