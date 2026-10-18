import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../ids.dart';
import '../time/business_tz.dart';
import '../time/clock.dart';
import '../validation/text_rules.dart';
import 'repository_errors.dart';
import 'workspace_scope.dart';

/// 内置常用银行（只有名称，不带任何规则）。第一次被选用时才写进 `banks`（`is_builtin = 1`）。
const List<String> builtinBankNames = <String>[
  '中国工商银行',
  '中国农业银行',
  '中国银行',
  '中国建设银行',
  '交通银行',
  '中国邮政储蓄银行',
  '招商银行',
  '浦发银行',
  '中信银行',
  '中国光大银行',
  '华夏银行',
  '中国民生银行',
  '广发银行',
  '兴业银行',
  '平安银行',
  '浙商银行',
  '北京银行',
  '上海银行',
  '江苏银行',
  '宁波银行',
];

/// 银行选择器里的一项：内置银行（可能还没写库）或用户添加的银行。
@immutable
final class BankChoice {
  const BankChoice({required this.name, this.bankId, required this.builtin});

  final String name;

  /// 已写进本工作空间 `banks` 表时的 id。
  final String? bankId;

  final bool builtin;
}

/// 银行（当前工作空间）。
final class BankRepository {
  BankRepository(this._scope);

  final WorkspaceScope _scope;

  AppDatabase get _db => _scope.db;

  /// 本工作空间已写库的银行（按名称）。
  Future<List<BankRow>> listStored() =>
      (_db.select(_db.banks)
            ..where((b) => b.workspaceId.equals(_scope.workspaceId))
            ..orderBy([(b) => OrderingTerm.asc(b.name)]))
          .get();

  /// 按 id 取本工作空间的银行。
  Future<BankRow?> byId(String id) =>
      (_db.select(_db.banks)..where(
            (b) => b.workspaceId.equals(_scope.workspaceId) & b.id.equals(id),
          ))
          .getSingleOrNull();

  /// 选择器：内置银行（固定顺序）在前，用户添加的在后。
  Future<List<BankChoice>> choices() async {
    final stored = {for (final b in await listStored()) b.name: b};
    return <BankChoice>[
      for (final name in builtinBankNames)
        BankChoice(name: name, bankId: stored[name]?.id, builtin: true),
      for (final bank in stored.values)
        if (!builtinBankNames.contains(bank.name))
          BankChoice(name: bank.name, bankId: bank.id, builtin: false),
    ];
  }

  /// 按名称取得银行，没有则写库（内置名称标 `is_builtin`）。名称做 G2/G5 校验。
  Future<BankRow> ensureByName(String rawName) async {
    final name = rawName.trim();
    final problem = validateFreeText(name, required: true, fieldName: '银行名称');
    if (problem != null) {
      throw ValidationException('bank', problem);
    }
    return _db.transaction(() async {
      final existing =
          await (_db.select(_db.banks)..where(
                (b) =>
                    b.workspaceId.equals(_scope.workspaceId) &
                    b.name.equals(name),
              ))
              .getSingleOrNull();
      if (existing != null) {
        return existing;
      }
      final id = newUuidV4();
      try {
        await _db
            .into(_db.banks)
            .insert(
              BanksCompanion.insert(
                id: id,
                workspaceId: _scope.workspaceId,
                name: name,
                businessTzDefault: const Value(defaultBusinessTimeZoneId),
                isBuiltin: Value(builtinBankNames.contains(name)),
                createdAt: _scope.clock.nowText(),
              ),
            );
      } on Object catch (error, stack) {
        rethrowAsRepositoryException(error, stack);
      }
      return (await byId(id))!;
    });
  }
}
