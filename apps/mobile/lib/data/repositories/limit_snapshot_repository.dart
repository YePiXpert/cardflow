import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate, Timestamp;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../ids.dart';
import '../time/business_tz.dart';
import '../time/clock.dart';
import '../validation/text_rules.dart';
import 'credit_pool_repository.dart' show maxAmountMinor;
import 'models.dart';
import 'repository_errors.dart';
import 'workspace_scope.dart';

/// 一次额度快照的输入（P-04 额度快照表单）。金额都是最小单位。
@immutable
final class LimitSnapshotDraft {
  const LimitSnapshotDraft({
    required this.currencyAccountId,
    required this.fixedMinor,
    required this.usedMinor,
    required this.availableRawMinor,
    required this.includesHolds,
    required this.source,
    required this.balanceAsOf,
    required this.observedAt,
    this.tempMinor = 0,
    this.tempExpiresOn,
    this.specialMinor = 0,
    this.specialPurpose,
    this.holdsMinor = 0,
    this.confirmationLevel = ConfirmationLevel.userConfirmed,
  });

  final String currencyAccountId;
  final int fixedMinor;
  final int tempMinor;
  final LocalDate? tempExpiresOn;
  final int specialMinor;
  final String? specialPurpose;
  final int usedMinor;

  /// 银行显示的可用额，可为负（超限原值保留，F-26）。
  final int availableRawMinor;

  /// 快照时点已知的预授权占用合计。
  final int holdsMinor;

  /// 银行显示的可用额是否已扣除预授权（F-25）。
  final bool includesHolds;

  final SnapshotSource source;

  /// 实际余额时点（G3：不晚于现在）。
  final Timestamp balanceAsOf;

  /// 观测时点（G3：不晚于现在，不早于实际余额时点）。
  final Timestamp observedAt;

  final ConfirmationLevel confirmationLevel;
}

/// 额度快照（当前工作空间）。只追加，不修改。
final class LimitSnapshotRepository {
  LimitSnapshotRepository(this._scope);

  final WorkspaceScope _scope;

  AppDatabase get _db => _scope.db;
  String get _ws => _scope.workspaceId;

  /// 本工作空间的全部快照。
  Future<List<LimitSnapshotRow>> all() => (_db.select(
    _db.limitSnapshots,
  )..where((s) => s.workspaceId.equals(_ws))).get();

  /// 某币种子账户的快照历史，最新在前（按实际余额时点的绝对时刻，再按记录时点）。
  Future<List<LimitSnapshotRow>> history(String currencyAccountId) async {
    final rows =
        await (_db.select(_db.limitSnapshots)..where(
              (s) =>
                  s.workspaceId.equals(_ws) &
                  s.currencyAccountId.equals(currencyAccountId),
            ))
            .get();
    return sortNewestFirst(rows);
  }

  /// 每个币种子账户的最新快照。
  Future<Map<String, LimitSnapshotRow>> latestByCurrencyAccount() async {
    final latest = <String, LimitSnapshotRow>{};
    for (final row in sortNewestFirst(await all())) {
      latest.putIfAbsent(row.currencyAccountId, () => row);
    }
    return latest;
  }

  /// 记录一次快照。校验（P-04、G1/G3）：金额范围（可用额可负，其余不小于 0）；临时额度须
  /// 到期日、专项额度须用途；实际余额时点与观测时点不晚于现在，且实际时点不晚于观测时点。
  Future<LimitSnapshotRow> record(LimitSnapshotDraft draft) async {
    void amount(String field, int value, {bool allowNegative = false}) {
      final low = allowNegative ? -maxAmountMinor : 0;
      if (value < low || value > maxAmountMinor) {
        throw ValidationException(
          field,
          allowNegative ? '金额超出范围' : '金额须为不小于 0 的数',
        );
      }
    }

    amount('fixed', draft.fixedMinor);
    amount('temp', draft.tempMinor);
    amount('special', draft.specialMinor);
    amount('used', draft.usedMinor);
    amount('holds', draft.holdsMinor);
    amount('available', draft.availableRawMinor, allowNegative: true);
    if (draft.tempMinor > 0 && draft.tempExpiresOn == null) {
      throw const ValidationException('tempExpiresOn', '临时额度须填写到期日');
    }
    final purpose = draft.specialPurpose?.trim();
    if (draft.specialMinor > 0) {
      final problem = validateFreeText(
        purpose,
        required: true,
        fieldName: '专项额度用途',
      );
      if (problem != null) {
        throw ValidationException('specialPurpose', problem);
      }
    }
    final nowMicros = _scope.clock.now().microsecondsSinceEpoch;
    if (draft.balanceAsOf.utcMicros > nowMicros) {
      throw const ValidationException('balanceAsOf', '实际余额时点不能晚于现在');
    }
    if (draft.observedAt.utcMicros > nowMicros) {
      throw const ValidationException('observedAt', '观测时点不能晚于现在');
    }
    if (draft.balanceAsOf.utcMicros > draft.observedAt.utcMicros) {
      throw const ValidationException('balanceAsOf', '实际余额时点不能晚于观测时点');
    }

    try {
      return await _db.transaction(() async {
        final currencyAccount =
            await (_db.select(_db.currencyAccounts)..where(
                  (c) =>
                      c.workspaceId.equals(_ws) &
                      c.id.equals(draft.currencyAccountId),
                ))
                .getSingleOrNull();
        if (currencyAccount == null) {
          throw const NotFoundException('币种子账户');
        }
        final account =
            await (_db.select(_db.creditAccounts)..where(
                  (a) =>
                      a.workspaceId.equals(_ws) &
                      a.id.equals(currencyAccount.creditAccountId),
                ))
                .getSingle();
        final zone = businessTimeZoneOf(account.businessTz);
        final id = newUuidV4();
        await _db
            .into(_db.limitSnapshots)
            .insert(
              LimitSnapshotsCompanion.insert(
                id: id,
                workspaceId: _ws,
                currencyAccountId: draft.currencyAccountId,
                fixedMinor: draft.fixedMinor,
                tempMinor: Value(draft.tempMinor),
                tempExpiresOn: Value(
                  draft.tempMinor > 0 ? draft.tempExpiresOn?.toString() : null,
                ),
                specialMinor: Value(draft.specialMinor),
                specialPurpose: Value(draft.specialMinor > 0 ? purpose : null),
                usedMinor: draft.usedMinor,
                availableRawMinor: draft.availableRawMinor,
                holdsMinor: Value(draft.holdsMinor),
                includesHolds: draft.includesHolds,
                sourceKind: draft.source.code,
                balanceAsOf: draft.balanceAsOf.text,
                observedAt: draft.observedAt.text,
                recordedAt: _scope.clock.nowText(zone),
                confirmationLevel: draft.confirmationLevel.code,
              ),
            );
        return (await (_db.select(_db.limitSnapshots)
              ..where((s) => s.workspaceId.equals(_ws) & s.id.equals(id)))
            .getSingle());
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }
}

/// 快照按"最新在前"排序：实际余额时点的绝对时刻（不同偏移写入的文本不能直接按字符串比较），
/// 相同时按记录时点，再按 id（确定的顺序）。
List<LimitSnapshotRow> sortNewestFirst(Iterable<LimitSnapshotRow> rows) {
  final list = rows.toList();
  int micros(String text) => Timestamp.parse(text).utcMicros;
  list.sort((a, b) {
    final byBalance = micros(b.balanceAsOf).compareTo(micros(a.balanceAsOf));
    if (byBalance != 0) {
      return byBalance;
    }
    final byRecorded = micros(b.recordedAt).compareTo(micros(a.recordedAt));
    return byRecorded != 0 ? byRecorded : b.id.compareTo(a.id);
  });
  return list;
}

/// 快照的实际余额时点在账户业务时区里的日期（"{n} 天前"、陈旧判定用；F-20）。
LocalDate snapshotBusinessDate(LimitSnapshotRow row, BusinessTimeZone zone) =>
    businessDateOf(Timestamp.parse(row.balanceAsOf), zone);
