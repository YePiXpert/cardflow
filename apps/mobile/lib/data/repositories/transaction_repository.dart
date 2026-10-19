import 'package:cardflow_domain/cardflow_domain.dart'
    show LocalDate, Timestamp, protocolInputHash;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../ids.dart';
import '../time/business_tz.dart';
import '../time/clock.dart';
import '../validation/text_rules.dart';
import 'credit_pool_repository.dart' show maxAmountMinor;
import 'ledger_models.dart';
import 'models.dart';
import 'reconciliation_repository.dart';
import 'repository_errors.dart';
import 'workspace_scope.dart';

/// "记一笔"的输入（P-05，G1~G3）。[amountMinor] 带符号（负债增加为正）：消费、费用、利息为正，退款与
/// 还款入账为负，转账/取现与调整由界面按方向给出符号。
@immutable
final class TransactionDraft {
  const TransactionDraft({
    required this.currencyAccountId,
    required this.type,
    required this.amountMinor,
    required this.txnAt,
    this.precision = TxnTimePrecision.datetime,
    this.cardId,
    this.postedOn,
    this.merchant,
    this.category,
    this.parentTransactionId,
  });

  final String currencyAccountId;
  final TxnType type;
  final int amountMinor;

  /// 交易时点（G3：不晚于现在）；只知道日期时取当天 00:00（[precision] 为 `date`）。
  final Timestamp txnAt;
  final TxnTimePrecision precision;

  /// 刷的哪张卡（可空；必须属于该子账户的信用账户）。
  final String? cardId;

  /// 银行入账日（可空：未知时按入账延迟区间给出"可能账期"，F-15）；不早于交易日、不晚于今天。
  final LocalDate? postedOn;
  final String? merchant;
  final String? category;

  /// 退款对应的原交易（同一币种子账户）。
  final String? parentTransactionId;
}

/// 信用卡交易（当前工作空间）。交易挂在币种子账户上，卡片只是介质（F-24：换卡后旧卡交易不迁移）。
///
/// 退款一律生成"退款待核对"差异项（F-34：退款规则未知，应还不变、不计入收入）；"还款入账"（银行记录）
/// 没有对应的还款登记时生成"未匹配的还款"差异项。
final class TransactionRepository {
  TransactionRepository(this._scope);

  final WorkspaceScope _scope;

  AppDatabase get _db => _scope.db;
  String get _ws => _scope.workspaceId;

  /// 未删除的交易（可只取某币种子账户的），按交易时点、再按登记顺序。
  Future<List<CardTransactionRow>> list({String? currencyAccountId}) async {
    final rows =
        await (_db.select(_db.cardTransactions)..where(
              (t) =>
                  t.workspaceId.equals(_ws) &
                  t.deletedAt.isNull() &
                  (currencyAccountId == null
                      ? const Constant(true)
                      : t.currencyAccountId.equals(currencyAccountId)),
            ))
            .get();
    rows.sort((a, b) {
      final byTime = Timestamp.parse(a.txnAt).utcMicros
          .compareTo(Timestamp.parse(b.txnAt).utcMicros);
      return byTime != 0 ? byTime : a.recordedAt.compareTo(b.recordedAt);
    });
    return rows;
  }

  Future<CardTransactionRow?> byId(String id) =>
      (_db.select(_db.cardTransactions)..where(
            (t) =>
                t.workspaceId.equals(_ws) &
                t.id.equals(id) &
                t.deletedAt.isNull(),
          ))
          .getSingleOrNull();

  Future<CardTransactionRow> require(String id) async =>
      await byId(id) ?? (throw const NotFoundException('交易'));

  /// 记一笔（幂等：同一个 [id] 再次保存直接返回已建的）。
  ///
  /// 校验（P-05、G1~G3）：类型与金额符号相符、非零、|金额| ≤ 10^13；交易时点不晚于现在；入账日不早于交易日
  /// （按账户业务时区）、不晚于今天；卡片属于该信用账户；商户与分类 G2/G5；原交易在同一币种子账户。
  Future<CardTransactionRow> create(
    TransactionDraft draft, {
    String? id,
  }) async {
    if (!draft.type.accepts(draft.amountMinor)) {
      throw ValidationException(
        'amount',
        draft.type.sign > 0 ? '金额须为正数' : '金额须为负数（贷记）',
      );
    }
    if (draft.amountMinor.abs() > maxAmountMinor) {
      throw const ValidationException('amount', '金额超出范围');
    }
    final merchant = _optional(draft.merchant, 'merchant', '商户');
    final category = _optional(draft.category, 'category', '分类');
    final txnId = id ?? newUuidV4();
    try {
      return await _db.transaction(() async {
        final existing = await byId(txnId);
        if (existing != null) {
          return existing;
        }
        final sub =
            await (_db.select(_db.currencyAccounts)..where(
                  (c) =>
                      c.workspaceId.equals(_ws) &
                      c.id.equals(draft.currencyAccountId),
                ))
                .getSingleOrNull() ??
            (throw const NotFoundException('币种子账户'));
        final account =
            await (_db.select(_db.creditAccounts)..where(
                  (a) =>
                      a.workspaceId.equals(_ws) &
                      a.id.equals(sub.creditAccountId),
                ))
                .getSingle();
        final zone = businessTimeZoneOf(account.businessTz);
        final now = _scope.clock.now();
        if (draft.txnAt.utcMicros > now.microsecondsSinceEpoch) {
          throw const ValidationException('txnAt', '交易时间不能晚于现在');
        }
        final txnDate = businessDateOf(draft.txnAt, zone);
        final posted = draft.postedOn;
        if (posted != null) {
          if (posted < txnDate) {
            throw const ValidationException('postedOn', '入账日不能早于交易日');
          }
          if (posted > _scope.clock.today(zone)) {
            throw const ValidationException('postedOn', '入账日不能晚于今天');
          }
        }
        final cardId = draft.cardId;
        if (cardId != null) {
          final card =
              await (_db.select(_db.cards)..where(
                    (k) => k.workspaceId.equals(_ws) & k.id.equals(cardId),
                  ))
                  .getSingleOrNull();
          if (card == null || card.creditAccountId != account.id) {
            throw const ValidationException('card', '卡片不属于这个信用账户');
          }
        }
        final parentId = draft.parentTransactionId;
        if (parentId != null) {
          final parent = await byId(parentId);
          if (parent == null || parent.currencyAccountId != sub.id) {
            throw const ValidationException('parent', '原交易须在同一币种子账户');
          }
        }
        final txnAtText = timestampTextIn(
          DateTime.fromMicrosecondsSinceEpoch(
            draft.txnAt.utcMicros,
            isUtc: true,
          ),
          zone,
        );
        final nowText = _scope.clock.nowText(zone);
        await _db
            .into(_db.cardTransactions)
            .insert(
              CardTransactionsCompanion.insert(
                id: txnId,
                workspaceId: _ws,
                currencyAccountId: sub.id,
                cardId: Value(cardId),
                txnType: draft.type.code,
                amountMinor: draft.amountMinor,
                currency: sub.currency,
                txnAt: txnAtText,
                txnTz: zone.id,
                timePrecision: draft.precision.code,
                postedOn: Value(posted?.toString()),
                merchant: Value(merchant),
                category: Value(category),
                status: posted == null
                    ? TxnStatus.pending.code
                    : TxnStatus.posted.code,
                parentTransactionId: Value(parentId),
                fingerprint: transactionFingerprint(
                  currencyAccountId: sub.id,
                  type: draft.type,
                  amountMinor: draft.amountMinor,
                  currency: sub.currency,
                  txnAt: txnAtText,
                  postedOn: posted,
                  merchant: merchant,
                ),
                sourceKind: 'manual',
                confirmationLevel: ConfirmationLevel.userConfirmed.code,
                recordedAt: nowText,
                updatedAt: nowText,
              ),
            );
        final row = (await byId(txnId))!;
        await _openItemsFor(row, zone);
        return row;
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 标记已入账（待入账 → 已入账），入账日不早于交易日、不晚于今天。
  Future<void> markPosted(String id, LocalDate postedOn) async {
    try {
      await _db.transaction(() async {
        final row = await require(id);
        final zone = businessTimeZoneOf(row.txnTz);
        if (postedOn < businessDateOf(Timestamp.parse(row.txnAt), zone)) {
          throw const ValidationException('postedOn', '入账日不能早于交易日');
        }
        if (postedOn > _scope.clock.today(zone)) {
          throw const ValidationException('postedOn', '入账日不能晚于今天');
        }
        await (_db.update(
          _db.cardTransactions,
        )..where((t) => t.workspaceId.equals(_ws) & t.id.equals(id))).write(
          CardTransactionsCompanion(
            postedOn: Value(postedOn.toString()),
            status: Value(TxnStatus.posted.code),
            rowVersion: Value(row.rowVersion + 1),
            updatedAt: Value(_scope.clock.nowText(zone)),
          ),
        );
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 删除一笔交易（tombstone，不可撤销）。已转分期（计划未作废）的不能删除。引用它的未处理差异项（退款待
  /// 核对、未匹配的还款）由系统标为已处理（审查 R-07）。
  Future<void> delete(String id) async {
    try {
      await _db.transaction(() async {
        final row = await require(id);
        final plan =
            await (_db.select(_db.installmentPlans)..where(
                  (p) =>
                      p.workspaceId.equals(_ws) &
                      p.transactionId.equals(id) &
                      p.status.isNotIn(<String>[
                        InstallmentPlanStatus.cancelled.code,
                      ]),
                ))
                .getSingleOrNull();
        if (plan != null) {
          throw const ConflictException('这笔已转分期：先作废分期计划再删除');
        }
        final now = _scope.clock.nowText(businessTimeZoneOf(row.txnTz));
        await (_db.update(
          _db.cardTransactions,
        )..where((t) => t.workspaceId.equals(_ws) & t.id.equals(id))).write(
          CardTransactionsCompanion(
            deletedAt: Value(now),
            rowVersion: Value(row.rowVersion + 1),
            updatedAt: Value(now),
          ),
        );
        await ReconciliationRepository(_scope).closeBySystem(transactionId: id);
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 退款 → 退款待核对（F-34）；还款入账没有对应的还款登记 → 未匹配的还款。
  Future<void> _openItemsFor(
    CardTransactionRow row,
    BusinessTimeZone zone,
  ) async {
    final type = TxnType.of(row.txnType);
    final items = ReconciliationRepository(_scope);
    if (type == TxnType.refund) {
      await items.open(ReconciliationKind.refundPending, <String, Object?>{
        'transaction_id': row.id,
      });
    } else if (type == TxnType.repayment &&
        !await _matchesRepayment(row, zone)) {
      await items.open(ReconciliationKind.unmatchedRepayment, <String, Object?>{
        'transaction_id': row.id,
      });
    }
  }

  /// 有一笔未作废的还款登记：同一子账户、同金额、日期（入账、扣款或预计扣款）与这笔入账相差不超过 3 天。
  Future<bool> _matchesRepayment(
    CardTransactionRow row,
    BusinessTimeZone zone,
  ) async {
    final day = row.postedOn == null
        ? businessDateOf(Timestamp.parse(row.txnAt), zone)
        : LocalDate.parse(row.postedOn!);
    final candidates =
        await (_db.select(_db.repayments)..where(
              (r) =>
                  r.workspaceId.equals(_ws) &
                  r.currencyAccountId.equals(row.currencyAccountId) &
                  r.amountMinor.equals(-row.amountMinor) &
                  r.deletedAt.isNull(),
            ))
            .get();
    for (final r in candidates) {
      final dates = <LocalDate>[
        if (r.creditPostedAt case final t?)
          businessDateOf(Timestamp.parse(t), zone),
        if (r.cashDebitedAt case final t?)
          businessDateOf(Timestamp.parse(t), zone),
        if (r.expectedDebitOn case final d?) LocalDate.parse(d),
      ];
      if (dates.any((d) => d.differenceInDays(day).abs() <= 3)) {
        return true;
      }
    }
    return false;
  }

  String? _optional(String? text, String field, String name) {
    final value = text?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    final problem = validateFreeText(value, fieldName: name);
    if (problem != null) {
      throw ValidationException(field, problem);
    }
    return value;
  }
}

/// 交易指纹：规范化要素的 sha256（领域包规范化 JSON；导入去重在 I-3 使用）。
String transactionFingerprint({
  required String currencyAccountId,
  required TxnType type,
  required int amountMinor,
  required String currency,
  required String txnAt,
  required LocalDate? postedOn,
  required String? merchant,
}) => protocolInputHash(<String, Object?>{
  'kind': 'cardflow.transaction',
  'version': 1,
  'currency_account_id': currencyAccountId,
  'txn_type': type.code,
  'amount_minor': amountMinor,
  'currency': currency,
  'txn_at_utc_micros': Timestamp.parse(txnAt).utcMicros,
  'posted_on': postedOn?.toString(),
  'merchant': merchant,
});
