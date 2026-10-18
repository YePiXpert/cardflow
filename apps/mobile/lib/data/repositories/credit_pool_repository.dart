import 'package:cardflow_domain/cardflow_domain.dart' show minorDigits;
import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../ids.dart';
import '../time/clock.dart';
import '../validation/text_rules.dart';
import 'repository_errors.dart';
import 'workspace_scope.dart';

/// 金额上限：规则协议 v1 的 MinorAmount（|v| ≤ 10^13）。
const int maxAmountMinor = 10000000000000;

/// 授信池（当前工作空间）。成员关系见 `CreditAccountRepository.joinPool`/`leavePool`。
final class CreditPoolRepository {
  CreditPoolRepository(this._scope);

  final WorkspaceScope _scope;

  AppDatabase get _db => _scope.db;
  String get _ws => _scope.workspaceId;

  /// 全部授信池，按建立时间。
  Future<List<CreditPoolRow>> list() =>
      (_db.select(_db.creditPools)
            ..where((p) => p.workspaceId.equals(_ws))
            ..orderBy([
              (p) => OrderingTerm.asc(p.createdAt),
              (p) => OrderingTerm.asc(p.rowId),
            ]))
          .get();

  /// 某银行的授信池。
  Future<List<CreditPoolRow>> forBank(String bankId) =>
      (_db.select(_db.creditPools)
            ..where((p) => p.workspaceId.equals(_ws) & p.bankId.equals(bankId))
            ..orderBy([
              (p) => OrderingTerm.asc(p.createdAt),
              (p) => OrderingTerm.asc(p.rowId),
            ]))
          .get();

  /// 按 id 取。
  Future<CreditPoolRow?> byId(String id) =>
      (_db.select(_db.creditPools)
            ..where((p) => p.workspaceId.equals(_ws) & p.id.equals(id)))
          .getSingleOrNull();

  /// 新建单层授信池（池上限 ≥0，币种为 13 种之一，名称 G2/G5）。
  Future<CreditPoolRow> create({
    required String bankId,
    required String name,
    required int sharedLimitMinor,
    String currency = 'CNY',
  }) async {
    final trimmed = name.trim();
    final problem = validateFreeText(trimmed, required: true, fieldName: '池名称');
    if (problem != null) {
      throw ValidationException('name', problem);
    }
    if (sharedLimitMinor < 0 || sharedLimitMinor > maxAmountMinor) {
      throw const ValidationException('sharedLimit', '池上限须为不小于 0 的金额');
    }
    if (!minorDigits.containsKey(currency)) {
      throw const ValidationException('currency', '不支持的币种');
    }
    return _db.transaction(() async {
      final bank =
          await (_db.select(_db.banks)
                ..where((b) => b.workspaceId.equals(_ws) & b.id.equals(bankId)))
              .getSingleOrNull();
      if (bank == null) {
        throw const NotFoundException('银行');
      }
      final sameName = await forBank(bankId);
      if (sameName.any((p) => p.name == trimmed)) {
        throw const ConflictException('该银行已有同名授信池');
      }
      final id = newUuidV4();
      final now = _scope.clock.nowText();
      try {
        await _db
            .into(_db.creditPools)
            .insert(
              CreditPoolsCompanion.insert(
                id: id,
                workspaceId: _ws,
                bankId: bankId,
                name: trimmed,
                sharedLimitMinor: sharedLimitMinor,
                currency: currency,
                createdAt: now,
                updatedAt: now,
              ),
            );
      } on Object catch (error, stack) {
        rethrowAsRepositoryException(error, stack);
      }
      return (await byId(id))!;
    });
  }

  /// 修改池上限。
  Future<void> updateLimit(String poolId, int sharedLimitMinor) async {
    if (sharedLimitMinor < 0 || sharedLimitMinor > maxAmountMinor) {
      throw const ValidationException('sharedLimit', '池上限须为不小于 0 的金额');
    }
    await _db.transaction(() async {
      final pool = await byId(poolId);
      if (pool == null) {
        throw const NotFoundException('授信池');
      }
      await (_db.update(
        _db.creditPools,
      )..where((p) => p.workspaceId.equals(_ws) & p.id.equals(poolId))).write(
        CreditPoolsCompanion(
          sharedLimitMinor: Value(sharedLimitMinor),
          rowVersion: Value(pool.rowVersion + 1),
          updatedAt: Value(_scope.clock.nowText()),
        ),
      );
    });
  }
}
