import 'package:cardflow_domain/cardflow_domain.dart'
    show LocalDate, minorDigits;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../ids.dart';
import '../time/business_tz.dart';
import '../time/clock.dart';
import '../validation/text_rules.dart';
import 'repository_errors.dart';
import 'workspace_scope.dart';

/// 新建信用账户时默认的持卡人称呼。
const String defaultHolderAlias = '本人';

/// 新建信用账户的输入。
@immutable
final class NewCreditAccount {
  const NewCreditAccount({
    required this.id,
    required this.bankId,
    this.productName,
    this.holderAlias = defaultHolderAlias,
    this.businessTz = defaultBusinessTimeZoneId,
    this.openedOn,
  });

  /// 预先生成的 id（重试保存时沿用，不会重复建账户）。
  final String id;
  final String bankId;
  final String? productName;
  final String holderAlias;
  final String businessTz;
  final LocalDate? openedOn;
}

/// 信用账户、币种子账户与授信池成员关系（当前工作空间）。
final class CreditAccountRepository {
  CreditAccountRepository(this._scope);

  final WorkspaceScope _scope;

  AppDatabase get _db => _scope.db;
  String get _ws => _scope.workspaceId;

  /// 未删除的信用账户，按建立时间。
  Future<List<CreditAccountRow>> list() =>
      (_db.select(_db.creditAccounts)
            ..where((a) => a.workspaceId.equals(_ws) & a.deletedAt.isNull())
            ..orderBy([
              (a) => OrderingTerm.asc(a.createdAt),
              (a) => OrderingTerm.asc(a.rowId),
            ]))
          .get();

  /// 按 id 取（不属于当前工作空间或已删除时为 null）。
  Future<CreditAccountRow?> byId(String id) =>
      (_db.select(_db.creditAccounts)..where(
            (a) =>
                a.workspaceId.equals(_ws) &
                a.id.equals(id) &
                a.deletedAt.isNull(),
          ))
          .getSingleOrNull();

  /// 按 id 取，不存在抛 [NotFoundException]。
  Future<CreditAccountRow> require(String id) async =>
      await byId(id) ?? (throw const NotFoundException('信用账户'));

  /// 新建信用账户，同时建 CNY 主子账户（PRD UF-1 步骤 3）。可在调用方的事务里调用。
  /// 返回主子账户。
  Future<CurrencyAccountRow> create(NewCreditAccount draft) async {
    final productName = _optionalText(draft.productName);
    final holderAlias = draft.holderAlias.trim();
    _check('productName', validateFreeText(productName, fieldName: '产品名'));
    _check(
      'holderAlias',
      validateFreeText(holderAlias, required: true, fieldName: '持卡人'),
    );
    if (findBusinessTimeZone(draft.businessTz) == null) {
      throw const ValidationException('businessTz', '本期只支持列表中的时区');
    }
    return _db.transaction(() async {
      final bank =
          await (_db.select(_db.banks)..where(
                (b) => b.workspaceId.equals(_ws) & b.id.equals(draft.bankId),
              ))
              .getSingleOrNull();
      if (bank == null) {
        throw const NotFoundException('银行');
      }
      final now = _scope.clock.nowText();
      final primaryId = newUuidV4();
      try {
        await _db
            .into(_db.creditAccounts)
            .insert(
              CreditAccountsCompanion.insert(
                id: draft.id,
                workspaceId: _ws,
                bankId: draft.bankId,
                productName: Value(productName),
                holderAlias: holderAlias,
                businessTz: Value(draft.businessTz),
                openedOn: Value(draft.openedOn?.toString()),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await _db
            .into(_db.currencyAccounts)
            .insert(
              CurrencyAccountsCompanion.insert(
                id: primaryId,
                workspaceId: _ws,
                creditAccountId: draft.id,
                currency: 'CNY',
                isPrimary: const Value(true),
                createdAt: now,
              ),
            );
      } on Object catch (error, stack) {
        rethrowAsRepositoryException(error, stack);
      }
      return (await currencyAccountById(primaryId))!;
    });
  }

  /// 修改账户资料（产品名、持卡人称呼、业务时区、开户日）。
  Future<void> updateDetails(
    String id, {
    String? productName,
    String? holderAlias,
    String? businessTz,
    LocalDate? openedOn,
  }) async {
    final normalizedProduct = _optionalText(productName);
    _check(
      'productName',
      validateFreeText(normalizedProduct, fieldName: '产品名'),
    );
    if (holderAlias != null) {
      _check(
        'holderAlias',
        validateFreeText(holderAlias, required: true, fieldName: '持卡人'),
      );
    }
    if (businessTz != null && findBusinessTimeZone(businessTz) == null) {
      throw const ValidationException('businessTz', '本期只支持列表中的时区');
    }
    await _db.transaction(() async {
      final row = await require(id);
      await (_db.update(
        _db.creditAccounts,
      )..where((a) => a.workspaceId.equals(_ws) & a.id.equals(id))).write(
        CreditAccountsCompanion(
          productName: productName == null
              ? const Value.absent()
              : Value(normalizedProduct),
          holderAlias: holderAlias == null
              ? const Value.absent()
              : Value(holderAlias.trim()),
          businessTz: businessTz == null
              ? const Value.absent()
              : Value(businessTz),
          openedOn: openedOn == null
              ? const Value.absent()
              : Value(openedOn.toString()),
          rowVersion: Value(row.rowVersion + 1),
          updatedAt: Value(_scope.clock.nowText()),
        ),
      );
    });
  }

  // ---- 币种子账户 ----

  /// 币种子账户（可只取某个信用账户的）；主子账户在前，其余按币种。
  Future<List<CurrencyAccountRow>> currencyAccounts([
    String? creditAccountId,
  ]) =>
      (_db.select(_db.currencyAccounts)
            ..where(
              (c) =>
                  c.workspaceId.equals(_ws) &
                  (creditAccountId == null
                      ? const Constant(true)
                      : c.creditAccountId.equals(creditAccountId)),
            )
            ..orderBy([
              (c) => OrderingTerm.desc(c.isPrimary),
              (c) => OrderingTerm.asc(c.currency),
            ]))
          .get();

  /// 按 id 取币种子账户。
  Future<CurrencyAccountRow?> currencyAccountById(String id) =>
      (_db.select(_db.currencyAccounts)
            ..where((c) => c.workspaceId.equals(_ws) & c.id.equals(id)))
          .getSingleOrNull();

  /// 增加一个币种子账户（币种只能是领域包 minorDigits 的 13 种；同一币种只能有一个）。
  Future<CurrencyAccountRow> addCurrencyAccount(
    String creditAccountId,
    String currency,
  ) async {
    if (!minorDigits.containsKey(currency)) {
      throw const ValidationException('currency', '不支持的币种');
    }
    return _db.transaction(() async {
      await require(creditAccountId);
      final existing = await currencyAccounts(creditAccountId);
      if (existing.any((c) => c.currency == currency)) {
        throw const ConflictException('该币种子账户已存在');
      }
      final id = newUuidV4();
      await _db
          .into(_db.currencyAccounts)
          .insert(
            CurrencyAccountsCompanion.insert(
              id: id,
              workspaceId: _ws,
              creditAccountId: creditAccountId,
              currency: currency,
              createdAt: _scope.clock.nowText(),
            ),
          );
      return (await currencyAccountById(id))!;
    });
  }

  /// 删除币种子账户：主子账户不可删；已有额度快照、账期规则、交易、账单、还款或分期的不可删（不丢数据；
  /// 含已删除/作废的记录——它们仍引用这个子账户，审查 R-08）；账户所在授信池用这个币种时须先移出授信池。
  /// 异常一律包装为 [RepositoryException]。
  Future<void> removeCurrencyAccount(String currencyAccountId) async {
    try {
      await _removeCurrencyAccount(currencyAccountId);
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  Future<void> _removeCurrencyAccount(String currencyAccountId) =>
      _db.transaction(() async {
        final row = await currencyAccountById(currencyAccountId);
        if (row == null) {
          throw const NotFoundException('币种子账户');
        }
        if (row.isPrimary) {
          throw const ConflictException('主子账户不可删除');
        }
        final snapshots =
            await (_db.select(_db.limitSnapshots)..where(
                  (s) =>
                      s.workspaceId.equals(_ws) &
                      s.currencyAccountId.equals(currencyAccountId),
                ))
                .get();
        final rules =
            await (_db.select(_db.billingRuleVersions)..where(
                  (r) =>
                      r.workspaceId.equals(_ws) &
                      r.subjectKind.equals('currency_account') &
                      r.subjectId.equals(currencyAccountId),
                ))
                .get();
        if (snapshots.isNotEmpty || rules.isNotEmpty) {
          throw const ConflictException('该子账户已有额度快照或账期规则，不能删除');
        }
        final records = <String>[
          for (final (table, what) in const <(String, String)>[
            ('transactions', '交易'),
            ('statements', '账单'),
            ('repayments', '还款'),
            ('installment_plans', '分期'),
          ])
            if (await _referencedBy(table, currencyAccountId)) what,
        ];
        if (records.isNotEmpty) {
          throw ConflictException(
            '该子账户已有${records.join('、')}记录，不能删除（删除会丢失这些记录）',
          );
        }
        final account = await require(row.creditAccountId);
        final poolId = account.poolId;
        if (poolId != null) {
          final pool = await _poolById(poolId);
          if (pool?.currency == row.currency) {
            throw const ConflictException('账户所在授信池按这个币种计算，请先移出授信池');
          }
        }
        await (_db.delete(_db.currencyAccounts)..where(
              (c) => c.workspaceId.equals(_ws) & c.id.equals(currencyAccountId),
            ))
            .go();
      });

  /// [table] 里是否有行（含已删除/作废的）引用这个币种子账户。
  Future<bool> _referencedBy(String table, String currencyAccountId) async {
    final row = await _db
        .customSelect(
          'SELECT EXISTS (SELECT 1 FROM $table WHERE workspace_id = ? '
          'AND currency_account_id = ?) AS used',
          variables: <Variable<Object>>[
            Variable<String>(_ws),
            Variable<String>(currencyAccountId),
          ],
        )
        .getSingle();
    return row.read<int>('used') == 1;
  }

  // ---- 授信池成员 ----

  /// 授信池的成员账户。
  Future<List<CreditAccountRow>> poolMembers(String poolId) =>
      (_db.select(_db.creditAccounts)
            ..where(
              (a) =>
                  a.workspaceId.equals(_ws) &
                  a.poolId.equals(poolId) &
                  a.deletedAt.isNull(),
            )
            ..orderBy([
              (a) => OrderingTerm.asc(a.createdAt),
              (a) => OrderingTerm.asc(a.rowId),
            ]))
          .get();

  /// 把账户加入授信池（F-23）。池与账户须属于同一银行；账户须有池所用币种的子账户；
  /// 只支持单层池（协议 v1 只有一层，engine-spec §12.3）。
  Future<void> joinPool(String creditAccountId, String poolId) =>
      _db.transaction(() async {
        final account = await require(creditAccountId);
        final pool = await _poolById(poolId);
        if (pool == null) {
          throw const NotFoundException('授信池');
        }
        if (pool.bankId != account.bankId) {
          throw const ConflictException('授信池须与信用账户属于同一银行');
        }
        if (pool.parentPoolId != null) {
          throw const ConflictException('本期只支持单层授信池');
        }
        final currencies = await currencyAccounts(creditAccountId);
        if (!currencies.any((c) => c.currency == pool.currency)) {
          throw ConflictException('账户没有${pool.currency}子账户，不能加入按该币种计算的授信池');
        }
        await _setPool(account, poolId);
      });

  /// 把账户移出授信池。
  Future<void> leavePool(String creditAccountId) => _db.transaction(() async {
    await _setPool(await require(creditAccountId), null);
  });

  Future<void> _setPool(CreditAccountRow account, String? poolId) async {
    try {
      await (_db.update(_db.creditAccounts)
            ..where((a) => a.workspaceId.equals(_ws) & a.id.equals(account.id)))
          .write(
            CreditAccountsCompanion(
              poolId: Value(poolId),
              rowVersion: Value(account.rowVersion + 1),
              updatedAt: Value(_scope.clock.nowText()),
            ),
          );
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  Future<CreditPoolRow?> _poolById(String id) =>
      (_db.select(_db.creditPools)
            ..where((p) => p.workspaceId.equals(_ws) & p.id.equals(id)))
          .getSingleOrNull();
}

String? _optionalText(String? text) {
  final value = text?.trim();
  return value == null || value.isEmpty ? null : value;
}

void _check(String field, String? problem) {
  if (problem != null) {
    throw ValidationException(field, problem);
  }
}
