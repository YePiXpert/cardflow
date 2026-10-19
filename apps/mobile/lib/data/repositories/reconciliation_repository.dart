import 'dart:collection';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../ids.dart';
import '../mapping/ledger_mapping.dart' show DuplicatePair;
import '../time/clock.dart';
import 'ledger_models.dart';
import 'repository_errors.dart';
import 'workspace_scope.dart';

/// 差异项的引用（规范化 JSON 对象：键按字母序，id 列表排序）。同类、同引用至多一个差异项。
String reconciliationRefs(Map<String, Object?> refs) {
  Object? canonical(Object? value) => switch (value) {
    final Map<String, Object?> map => SplayTreeMap<String, Object?>.of(
      map.map((k, v) => MapEntry(k, canonical(v))),
    ),
    final List<String> ids => (List<String>.of(ids)..sort()),
    final List<Object?> list => list.map(canonical).toList(),
    _ => value,
  };
  return jsonEncode(canonical(refs));
}

/// 读取差异项的引用。
Map<String, Object?> reconciliationRefsOf(ReconciliationItemRow row) =>
    (jsonDecode(row.refs) as Map<Object?, Object?>).cast<String, Object?>();

/// 差异项引用的还款 id（疑似重复的两笔、金额不符的一笔）。
List<String> referencedRepayments(ReconciliationItemRow row) {
  final refs = reconciliationRefsOf(row);
  return <String>[
    ...?(refs['repayment_ids'] as List<Object?>?)?.cast<String>(),
    ?refs['repayment_id'] as String?,
  ];
}

/// 差异项引用的交易 id（退款待核对、未匹配的还款入账）。
String? referencedTransaction(ReconciliationItemRow row) =>
    reconciliationRefsOf(row)['transaction_id'] as String?;

/// 对账差异项（R-STMT-09，当前工作空间）：生成（同类同引用不重复）、处理一次（不重开）。
///
/// 疑似重复的"同一笔，作废重复的登记"要连带作废还款，走 `RepaymentRepository.resolveDuplicate`。
final class ReconciliationRepository {
  ReconciliationRepository(this._scope);

  final WorkspaceScope _scope;

  AppDatabase get _db => _scope.db;
  String get _ws => _scope.workspaceId;

  /// 差异项（可只取某状态的），未处理的在前，再按生成时间。
  Future<List<ReconciliationItemRow>> list({
    ReconciliationStatus? status,
  }) async {
    final rows =
        await (_db.select(_db.reconciliationItems)
              ..where(
                (i) =>
                    i.workspaceId.equals(_ws) &
                    (status == null
                        ? const Constant(true)
                        : i.status.equals(status.code)),
              )
              ..orderBy([
                (i) => OrderingTerm.asc(i.createdAt),
                (i) => OrderingTerm.asc(i.rowId),
              ]))
            .get();
    return <ReconciliationItemRow>[
      ...rows.where((r) => r.status == ReconciliationStatus.open.code),
      ...rows.where((r) => r.status != ReconciliationStatus.open.code),
    ];
  }

  Future<ReconciliationItemRow?> byId(String id) =>
      (_db.select(_db.reconciliationItems)
            ..where((i) => i.workspaceId.equals(_ws) & i.id.equals(id)))
          .getSingleOrNull();

  Future<ReconciliationItemRow> require(String id) async =>
      await byId(id) ?? (throw const NotFoundException('差异项'));

  /// 同类同引用的差异项（不论是否已处理）。
  Future<ReconciliationItemRow?> find(
    ReconciliationKind kind,
    Map<String, Object?> refs,
  ) =>
      (_db.select(_db.reconciliationItems)..where(
            (i) =>
                i.workspaceId.equals(_ws) &
                i.kind.equals(kind.code) &
                i.refs.equals(reconciliationRefs(refs)),
          ))
          .getSingleOrNull();

  /// 生成一个差异项；同类同引用已有（包括已处理的）时返回已有的，不重复生成、不重开。
  Future<ReconciliationItemRow> open(
    ReconciliationKind kind,
    Map<String, Object?> refs,
  ) => _db.transaction(() async {
    final existing = await find(kind, refs);
    if (existing != null) {
      return existing;
    }
    final id = newUuidV4();
    final now = _scope.clock.nowText();
    await _db
        .into(_db.reconciliationItems)
        .insert(
          ReconciliationItemsCompanion.insert(
            id: id,
            workspaceId: _ws,
            kind: kind.code,
            refs: reconciliationRefs(refs),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (await byId(id))!;
  });

  /// 处理一个未处理的差异项：结果必须是该类型可用的（[ReconciliationResolution.choicesFor]）。
  Future<void> resolve(
    String id,
    ReconciliationResolution resolution, {
    ResolvedBy by = ResolvedBy.user,
  }) => _close(id, ReconciliationStatus.resolved, resolution, by);

  /// 忽略（不作处理）。
  Future<void> dismiss(String id, {ResolvedBy by = ResolvedBy.user}) => _close(
    id,
    ReconciliationStatus.dismissed,
    ReconciliationResolution.dismissed,
    by,
  );

  Future<void> _close(
    String id,
    ReconciliationStatus status,
    ReconciliationResolution resolution,
    ResolvedBy by,
  ) async {
    try {
      await _db.transaction(() async {
        final row = await require(id);
        if (row.status != ReconciliationStatus.open.code) {
          throw const ConflictException('这一项已处理过');
        }
        final kind = ReconciliationKind.of(row.kind);
        if (status == ReconciliationStatus.resolved &&
            !ReconciliationResolution.choicesFor(kind).contains(resolution)) {
          throw const ValidationException('resolution', '这一类差异不能这样处理');
        }
        final now = _scope.clock.nowText();
        await (_db.update(
          _db.reconciliationItems,
        )..where((i) => i.workspaceId.equals(_ws) & i.id.equals(id))).write(
          ReconciliationItemsCompanion(
            status: Value(status.code),
            resolution: Value(resolution.code),
            resolvedBy: Value(by.code),
            resolvedAt: Value(now),
            rowVersion: Value(row.rowVersion + 1),
            updatedAt: Value(now),
          ),
        );
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 未处理的疑似重复还款（F-32：负债只核销一次，直到用户处理）。
  Future<List<DuplicatePair>> openDuplicatePairs() async => <DuplicatePair>[
    for (final row in await list(status: ReconciliationStatus.open))
      if (row.kind == ReconciliationKind.duplicateRepayment.code)
        if (referencedRepayments(row) case [final a, final b]) (a, b),
  ];

  /// 已确认冲抵应还的退款（其余退款待核对，不计入未出账、不计入收入，F-34）。
  Future<Set<String>> offsetRefunds() async => <String>{
    for (final row in await list(status: ReconciliationStatus.resolved))
      if (row.kind == ReconciliationKind.refundPending.code &&
          row.resolution == ReconciliationResolution.offset.code)
        ?referencedTransaction(row),
  };
}
