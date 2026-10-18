import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../ids.dart';
import '../time/business_tz.dart';
import '../time/clock.dart';
import '../validation/text_rules.dart';
import 'bank_repository.dart';
import 'credit_account_repository.dart';
import 'models.dart';
import 'repository_errors.dart';
import 'workspace_scope.dart';

/// 新建卡片的输入（P-02 新建弹层）。
///
/// 卡片挂在哪个信用账户：
/// - 附属卡：[primaryCardId] 指定主卡，挂在主卡的账户上（附卡须指定主卡）；
/// - 主卡且 [joinAccountId] 非空：加入既有账户（同一授信的另一张卡，F-21）；
/// - 否则新建信用账户（银行 [bankName]，id 用 [newAccountId]），同时建 CNY 主子账户。
///
/// [cardId]、[newAccountId] 由调用方预先生成：同一次"保存"重试时沿用，不会重复建卡
/// （ui-spec P-02 九态"重试保存，不重复建卡"）。
@immutable
final class NewCardDraft {
  const NewCardDraft({
    required this.cardId,
    required this.newAccountId,
    required this.last4,
    this.holderKind = HolderKind.primary,
    this.bankName,
    this.productName,
    this.alias,
    this.network,
    this.holderAlias = defaultHolderAlias,
    this.primaryCardId,
    this.joinAccountId,
    this.expiresYm,
    this.businessTz = defaultBusinessTimeZoneId,
  });

  final String cardId;
  final String newAccountId;
  final String last4;
  final HolderKind holderKind;
  final String? bankName;
  final String? productName;
  final String? alias;
  final CardNetwork? network;
  final String holderAlias;
  final String? primaryCardId;
  final String? joinAccountId;

  /// `YYYY-MM`。
  final String? expiresYm;

  /// 新建账户时的业务时区。
  final String businessTz;
}

/// 新建卡片的结果。
@immutable
final class NewCardResult {
  const NewCardResult({
    required this.cardId,
    required this.creditAccountId,
    required this.createdAccount,
  });

  final String cardId;
  final String creditAccountId;

  /// 这次是否新建了信用账户（与 CNY 主子账户）。
  final bool createdAccount;
}

final RegExp _expiresYm = RegExp(r'^[0-9]{4}-(0[1-9]|1[0-2])$');

/// 卡片（当前工作空间）：建卡、换卡/补卡、冻结/解冻、销卡（PRD §6.1）。
final class CardRepository {
  CardRepository(this._scope)
    : _accounts = CreditAccountRepository(_scope),
      _banks = BankRepository(_scope);

  final WorkspaceScope _scope;
  final CreditAccountRepository _accounts;
  final BankRepository _banks;

  AppDatabase get _db => _scope.db;
  String get _ws => _scope.workspaceId;

  /// 卡片（可只取某个信用账户的），按建立时间。
  Future<List<CardRow>> list({String? creditAccountId}) =>
      (_db.select(_db.cards)
            ..where(
              (c) =>
                  c.workspaceId.equals(_ws) &
                  (creditAccountId == null
                      ? const Constant(true)
                      : c.creditAccountId.equals(creditAccountId)),
            )
            ..orderBy([
              (c) => OrderingTerm.asc(c.createdAt),
              (c) => OrderingTerm.asc(c.rowId),
            ]))
          .get();

  /// 按 id 取。
  Future<CardRow?> byId(String id) =>
      (_db.select(_db.cards)
            ..where((c) => c.workspaceId.equals(_ws) & c.id.equals(id)))
          .getSingleOrNull();

  /// 按 id 取，不存在抛 [NotFoundException]。
  Future<CardRow> require(String id) async =>
      await byId(id) ?? (throw const NotFoundException('卡片'));

  /// 同一银行（按名称）、同一末四位、尚未停用的卡片：新建时提示"可能是同一信用账户的另一张卡"。
  Future<List<CardRow>> sameBankSameLast4({
    required String bankName,
    required String last4,
  }) async {
    final query =
        _db.select(_db.cards).join([
          innerJoin(
            _db.creditAccounts,
            _db.creditAccounts.id.equalsExp(_db.cards.creditAccountId) &
                _db.creditAccounts.workspaceId.equalsExp(_db.cards.workspaceId),
          ),
          innerJoin(
            _db.banks,
            _db.banks.id.equalsExp(_db.creditAccounts.bankId) &
                _db.banks.workspaceId.equalsExp(_db.creditAccounts.workspaceId),
          ),
        ])..where(
          _db.cards.workspaceId.equals(_ws) &
              _db.cards.last4.equals(normalizeLast4(last4)) &
              _db.banks.name.equals(bankName.trim()) &
              _db.cards.status.isNotIn(<String>[
                CardStatus.replaced.code,
                CardStatus.closed.code,
              ]) &
              _db.creditAccounts.deletedAt.isNull(),
        );
    return (await query.get()).map((r) => r.readTable(_db.cards)).toList();
  }

  /// 新建卡片：需要时同时建信用账户与 CNY 主子账户；卡片按状态机 `draft → active`。
  /// 同一个 [NewCardDraft.cardId] 再次保存时直接返回已建的结果（幂等）。
  Future<NewCardResult> create(NewCardDraft draft) async {
    final last4Problem = validateLast4(draft.last4);
    if (last4Problem != null) {
      throw ValidationException('last4', last4Problem);
    }
    final alias = _optionalText(draft.alias);
    _check('alias', validateFreeText(alias, fieldName: '别名'));
    _check(
      'productName',
      validateFreeText(draft.productName, fieldName: '产品名'),
    );
    _check(
      'holderAlias',
      validateFreeText(draft.holderAlias, required: true, fieldName: '持卡人'),
    );
    final expiresYm = _optionalText(draft.expiresYm);
    if (expiresYm != null && !_expiresYm.hasMatch(expiresYm)) {
      throw const ValidationException('expiresYm', '到期年月格式应为 YYYY-MM');
    }

    try {
      return await _db.transaction(() async {
        final existing = await byId(draft.cardId);
        if (existing != null) {
          return NewCardResult(
            cardId: existing.id,
            creditAccountId: existing.creditAccountId,
            createdAccount: false,
          );
        }

        String accountId;
        var createdAccount = false;
        String? primaryCardId;
        if (draft.holderKind == HolderKind.supplementary) {
          final primaryId = draft.primaryCardId;
          if (primaryId == null) {
            throw const ValidationException('primaryCard', '附属卡须指定主卡');
          }
          final primary = await byId(primaryId);
          if (primary == null ||
              primary.kind != HolderKind.primary ||
              primary.cardStatus.isInactive) {
            throw const ValidationException('primaryCard', '请选择一张未停用的主卡');
          }
          accountId = primary.creditAccountId;
          primaryCardId = primary.id;
        } else if (draft.joinAccountId != null) {
          final account = await _accounts.require(draft.joinAccountId!);
          final bankName = draft.bankName?.trim();
          if (bankName != null && bankName.isNotEmpty) {
            final bank = await _banks.byId(account.bankId);
            if (bank?.name != bankName) {
              throw const ValidationException('account', '只能加入同一银行的信用账户');
            }
          }
          accountId = account.id;
        } else {
          final bankName = draft.bankName;
          if (bankName == null || bankName.trim().isEmpty) {
            throw const ValidationException('bank', '请选择银行');
          }
          final bank = await _banks.ensureByName(bankName);
          await _accounts.create(
            NewCreditAccount(
              id: draft.newAccountId,
              bankId: bank.id,
              productName: draft.productName,
              holderAlias: draft.holderAlias,
              businessTz: draft.businessTz,
            ),
          );
          accountId = draft.newAccountId;
          createdAccount = true;
        }

        final now = _scope.clock.nowText();
        await _db
            .into(_db.cards)
            .insert(
              CardsCompanion.insert(
                id: draft.cardId,
                workspaceId: _ws,
                creditAccountId: accountId,
                last4: normalizeLast4(draft.last4),
                network: Value(draft.network?.code),
                holderKind: draft.holderKind.code,
                primaryCardId: Value(primaryCardId),
                status: CardStatus.draft.code,
                expiresYm: Value(expiresYm),
                alias: Value(alias),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await _transition(await require(draft.cardId), CardStatus.active);
        return NewCardResult(
          cardId: draft.cardId,
          creditAccountId: accountId,
          createdAccount: createdAccount,
        );
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 换卡/补卡（F-24）：新卡（新末四位、生效日 [effectiveFrom]）挂在同一信用账户，状态
  /// `active`；旧卡变为 `replaced` 并指向新卡。账户、币种子账户、历史数据都不动。旧卡须为
  /// `active`（冻结的卡先解冻，PRD §6.1）。返回新卡。
  Future<CardRow> replace(
    String cardId, {
    required String newLast4,
    required LocalDate effectiveFrom,
    String? newCardId,
  }) async {
    final last4Problem = validateLast4(newLast4);
    if (last4Problem != null) {
      throw ValidationException('last4', last4Problem);
    }
    try {
      return await _db.transaction(() async {
        final old = await require(cardId);
        if (!old.cardStatus.canBecome(CardStatus.replaced)) {
          throw IllegalCardTransitionException(
            old.cardStatus,
            CardStatus.replaced,
          );
        }
        final id = newCardId ?? newUuidV4();
        final now = _scope.clock.nowText();
        await _db
            .into(_db.cards)
            .insert(
              CardsCompanion.insert(
                id: id,
                workspaceId: _ws,
                creditAccountId: old.creditAccountId,
                last4: normalizeLast4(newLast4),
                network: Value(old.network),
                holderKind: old.holderKind,
                primaryCardId: Value(old.primaryCardId),
                status: CardStatus.draft.code,
                expiresYm: const Value(null),
                alias: Value(old.alias),
                effectiveFrom: Value(effectiveFrom.toString()),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await _transition(await require(id), CardStatus.active);
        await _transition(
          old,
          CardStatus.replaced,
          extra: CardsCompanion(replacedByCardId: Value(id)),
        );
        return require(id);
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 冻结（`active → frozen`）。
  Future<void> freeze(String cardId) => _guarded(
    () async => _transition(await require(cardId), CardStatus.frozen),
  );

  /// 解冻（`frozen → active`）。
  Future<void> unfreeze(String cardId) => _guarded(
    () async => _transition(await require(cardId), CardStatus.active),
  );

  /// 销卡（`active/frozen → closed`），销卡日 [closedOn] 不得晚于账户业务时区里的今天。
  Future<void> close(String cardId, {required LocalDate closedOn}) =>
      _guarded(() async {
        final card = await require(cardId);
        final account = await _accounts.require(card.creditAccountId);
        final zone = businessTimeZoneOf(account.businessTz);
        if (closedOn > _scope.clock.today(zone)) {
          throw const ValidationException('closedOn', '销卡日不能晚于今天');
        }
        await _transition(
          card,
          CardStatus.closed,
          extra: CardsCompanion(closedOn: Value(closedOn.toString())),
        );
      });

  /// 修改别名（G2/G5）。
  Future<void> rename(String cardId, String? alias) => _guarded(() async {
    final value = _optionalText(alias);
    _check('alias', validateFreeText(value, fieldName: '别名'));
    final card = await require(cardId);
    await (_db.update(
      _db.cards,
    )..where((c) => c.workspaceId.equals(_ws) & c.id.equals(cardId))).write(
      CardsCompanion(
        alias: Value(value),
        rowVersion: Value(card.rowVersion + 1),
        updatedAt: Value(_scope.clock.nowText()),
      ),
    );
  });

  Future<void> _transition(
    CardRow card,
    CardStatus target, {
    CardsCompanion extra = const CardsCompanion(),
  }) async {
    final from = card.cardStatus;
    if (!from.canBecome(target)) {
      throw IllegalCardTransitionException(from, target);
    }
    await (_db.update(
      _db.cards,
    )..where((c) => c.workspaceId.equals(_ws) & c.id.equals(card.id))).write(
      extra.copyWith(
        status: Value(target.code),
        rowVersion: Value(card.rowVersion + 1),
        updatedAt: Value(_scope.clock.nowText()),
      ),
    );
  }

  Future<T> _guarded<T>(Future<T> Function() action) async {
    try {
      return await _db.transaction(action);
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }
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
