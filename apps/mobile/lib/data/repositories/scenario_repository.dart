import 'package:cardflow_domain/cardflow_domain.dart'
    show LocalDate, Rational, canonicalJsonText, decimalText;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../ids.dart';
import '../mapping/cash_mapping.dart';
import '../time/clock.dart';
import 'cash_models.dart';
import 'cash_validation.dart';
import 'credit_pool_repository.dart' show maxAmountMinor;
import 'repository_errors.dart';
import 'workspace_scope.dart';

/// 一个情景（内置或用户压力情景）。内置情景在第一次「重算」之前没有数据库行（[row] 为空），参数固定。
@immutable
final class ScenarioView {
  const ScenarioView({
    required this.kind,
    required this.name,
    required this.params,
    this.row,
  });

  /// 内置情景（未保存时的样子）。
  factory ScenarioView.builtin(ScenarioKind kind) => ScenarioView(
    kind: kind,
    name: kind.label,
    params: kind == ScenarioKind.builtinConfirmed
        ? ScenarioParams.confirmed
        : ScenarioParams.baseline,
  );

  factory ScenarioView.fromRow(ScenarioRow row) => ScenarioView(
    kind: ScenarioKind.of(row.kind),
    name: row.name,
    params: ScenarioParams.fromRow(row),
    row: row,
  );

  final ScenarioKind kind;
  final String name;
  final ScenarioParams params;
  final ScenarioRow? row;

  /// 路由与 provider 用的键：数据库行 id；未保存的内置情景是 `builtin:<kind>`。
  String get key => row?.id ?? builtinKey(kind);

  /// 交给领域包的情景 id（协议 Id 格式）。
  String get domainId => row?.id ?? 'builtin-${kind.code}';

  bool get isBuiltin => kind.isBuiltin;

  /// 未保存的内置情景的键。
  static String builtinKey(ScenarioKind kind) => 'builtin:${kind.code}';
}

/// 新建或修改压力情景的输入（P-09 编辑器）。
@immutable
final class ScenarioDraft {
  const ScenarioDraft({
    required this.name,
    this.incomeDelayDays = 0,
    this.incomeScale,
    this.expenseScale,
    this.sameDayOrder = SameDayOrderChoice.conservative,
    this.eventOverrides = const <EventOverrideSpec>[],
    this.limitChanges = const <LimitChangeSpec>[],
  });

  final String name;

  /// 预计收入延迟天数（0–180）。
  final int incomeDelayDays;

  /// 预计收入比例（0–1；空 = 1）。
  final Rational? incomeScale;

  /// 生活支出比例（1–10；空 = 1）。
  final Rational? expenseScale;

  final SameDayOrderChoice sameDayOrder;
  final List<EventOverrideSpec> eventOverrides;

  /// 额度变化（占位，I-2 使用）。
  final List<LimitChangeSpec> limitChanges;
}

/// 情景与情景计算版本（当前工作空间）。
final class ScenarioRepository {
  ScenarioRepository(this._scope);

  final WorkspaceScope _scope;

  AppDatabase get _db => _scope.db;
  String get _ws => _scope.workspaceId;

  /// 已保存的情景行（含已保存的内置情景），按建立时间。
  Future<List<ScenarioRow>> rows() =>
      (_db.select(_db.scenarios)
            ..where((s) => s.workspaceId.equals(_ws))
            ..orderBy([
              (s) => OrderingTerm.asc(s.createdAt),
              (s) => OrderingTerm.asc(s.rowId),
            ]))
          .get();

  /// 全部情景：内置"已确认""基准预期"在前（保存与否都列出），然后是用户压力情景。
  Future<List<ScenarioView>> list() async {
    final stored = await rows();
    ScenarioView builtin(ScenarioKind kind) {
      for (final row in stored) {
        if (row.kind == kind.code) {
          return ScenarioView.fromRow(row);
        }
      }
      return ScenarioView.builtin(kind);
    }

    return <ScenarioView>[
      builtin(ScenarioKind.builtinConfirmed),
      builtin(ScenarioKind.builtinBaseline),
      for (final row in stored)
        if (row.kind == ScenarioKind.userStress.code) ScenarioView.fromRow(row),
    ];
  }

  /// 按键取（数据库行 id 或 `builtin:<kind>`）；不存在为 null。
  Future<ScenarioView?> byKey(String key) async {
    for (final view in await list()) {
      if (view.key == key || view.row?.id == key) {
        return view;
      }
    }
    return null;
  }

  /// 按键取，不存在抛 [NotFoundException]。
  Future<ScenarioView> require(String key) async =>
      await byKey(key) ?? (throw const NotFoundException('情景'));

  /// 取得内置情景的数据库行（没有则写入；参数固定）。
  Future<ScenarioRow> ensureBuiltin(ScenarioKind kind) {
    assert(kind.isBuiltin, 'only built-in scenarios');
    return _db.transaction(() async {
      final existing =
          await (_db.select(_db.scenarios)..where(
                (s) => s.workspaceId.equals(_ws) & s.kind.equals(kind.code),
              ))
              .getSingleOrNull();
      if (existing != null) {
        return existing;
      }
      final id = newUuidV4();
      final now = _scope.clock.nowText(cashTimeZone);
      await _db
          .into(_db.scenarios)
          .insert(
            ScenariosCompanion.insert(
              id: id,
              workspaceId: _ws,
              name: kind.label,
              kind: kind.code,
              includeExpected: kind != ScenarioKind.builtinConfirmed,
              createdAt: now,
              updatedAt: now,
            ),
          );
      return (await _rowById(id))!;
    });
  }

  /// 新建压力情景（幂等：同一个 [id] 再次保存直接返回已建的）。校验见 [_validate]。
  Future<ScenarioRow> create(ScenarioDraft draft, {String? id}) async {
    final scenarioId = id ?? newUuidV4();
    try {
      return await _db.transaction(() async {
        final existing = await _rowById(scenarioId);
        if (existing != null) {
          return existing;
        }
        final values = await _validate(draft, exceptId: null);
        final now = _scope.clock.nowText(cashTimeZone);
        await _db
            .into(_db.scenarios)
            .insert(
              ScenariosCompanion.insert(
                id: scenarioId,
                workspaceId: _ws,
                name: values.name,
                kind: ScenarioKind.userStress.code,
                includeExpected: true,
                incomeDelayDays: Value(draft.incomeDelayDays),
                incomeScale: Value(values.incomeScale),
                expenseScale: Value(values.expenseScale),
                sameDayOrder: Value(draft.sameDayOrder.code),
                limitChanges: Value(values.limitChanges),
                eventOverrides: Value(values.eventOverrides),
                createdAt: now,
                updatedAt: now,
              ),
            );
        return (await _rowById(scenarioId))!;
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 修改压力情景（内置情景只读）。已有的计算版本保留，与新参数不符时显示"过期"。
  Future<void> update(String id, ScenarioDraft draft) async {
    try {
      await _db.transaction(() async {
        final row = await _rowById(id);
        if (row == null) {
          throw const NotFoundException('情景');
        }
        if (row.kind != ScenarioKind.userStress.code) {
          throw const ConflictException('内置情景不能修改');
        }
        final values = await _validate(draft, exceptId: id);
        await (_db.update(
          _db.scenarios,
        )..where((s) => s.workspaceId.equals(_ws) & s.id.equals(id))).write(
          ScenariosCompanion(
            name: Value(values.name),
            incomeDelayDays: Value(draft.incomeDelayDays),
            incomeScale: Value(values.incomeScale),
            expenseScale: Value(values.expenseScale),
            sameDayOrder: Value(draft.sameDayOrder.code),
            limitChanges: Value(values.limitChanges),
            eventOverrides: Value(values.eventOverrides),
            rowVersion: Value(row.rowVersion + 1),
            updatedAt: Value(_scope.clock.nowText(cashTimeZone)),
          ),
        );
      });
    } on Object catch (error, stack) {
      rethrowAsRepositoryException(error, stack);
    }
  }

  /// 删除压力情景与它的全部计算版本（内置情景不能删）。返回删除的版本数。
  Future<int> delete(String id) => _db.transaction(() async {
    final row = await _rowById(id);
    if (row == null) {
      throw const NotFoundException('情景');
    }
    if (row.kind != ScenarioKind.userStress.code) {
      throw const ConflictException('内置情景不能删除');
    }
    final removed = await (_db.delete(
      _db.scenarioRuns,
    )..where((r) => r.workspaceId.equals(_ws) & r.scenarioId.equals(id))).go();
    await (_db.delete(
      _db.scenarios,
    )..where((s) => s.workspaceId.equals(_ws) & s.id.equals(id))).go();
    return removed;
  });

  // ---- 计算版本 ----

  /// 某情景的计算版本，新的在前。
  Future<List<ScenarioRunRow>> runs(String scenarioId) =>
      (_db.select(_db.scenarioRuns)
            ..where(
              (r) =>
                  r.workspaceId.equals(_ws) & r.scenarioId.equals(scenarioId),
            )
            ..orderBy([(r) => OrderingTerm.desc(r.versionNo)]))
          .get();

  /// 本工作空间的全部计算版本。
  Future<List<ScenarioRunRow>> allRuns() => (_db.select(
    _db.scenarioRuns,
  )..where((r) => r.workspaceId.equals(_ws))).get();

  /// 按 id 取计算版本。
  Future<ScenarioRunRow?> runById(String id) =>
      (_db.select(_db.scenarioRuns)
            ..where((r) => r.workspaceId.equals(_ws) & r.id.equals(id)))
          .getSingleOrNull();

  /// 写入一个新的计算版本（版本号 = 已有最大 + 1；旧版本保留）。
  Future<ScenarioRunRow> addRun({
    required String scenarioId,
    required LocalDate horizonFrom,
    required LocalDate horizonTo,
    required String inputsHash,
    required CashRunResult result,
  }) => _db.transaction(() async {
    final row = await _rowById(scenarioId);
    if (row == null) {
      throw const NotFoundException('情景');
    }
    final existing = await runs(scenarioId);
    final version = existing.isEmpty ? 1 : existing.first.versionNo + 1;
    final id = newUuidV4();
    await _db
        .into(_db.scenarioRuns)
        .insert(
          ScenarioRunsCompanion.insert(
            id: id,
            workspaceId: _ws,
            scenarioId: scenarioId,
            versionNo: version,
            computedAt: _scope.clock.nowText(cashTimeZone),
            horizonFrom: horizonFrom.toString(),
            horizonTo: horizonTo.toString(),
            inputsHash: inputsHash,
            result: result.encode(),
          ),
        );
    return (await runById(id))!;
  });

  Future<ScenarioRow?> _rowById(String id) =>
      (_db.select(_db.scenarios)
            ..where((s) => s.workspaceId.equals(_ws) & s.id.equals(id)))
          .getSingleOrNull();

  /// P-09 字段校验：名称必填、唯一（G5，且不能与内置情景同名）；延迟 0–180 天；收入比例 0–100%、
  /// 支出比例 100%–1000%（压力只允许变差；1000% 是规则协议 v1 的系数上限），至多 10 位小数；
  /// 额度变化须信用账户与日期；事件覆盖只能指向未删除的事件、每个事件一次、金额与原事件同号或为 0；
  /// 按时刻排序须所有事件有时刻。
  Future<
    ({
      String name,
      String incomeScale,
      String expenseScale,
      String limitChanges,
      String eventOverrides,
    })
  >
  _validate(ScenarioDraft draft, {required String? exceptId}) async {
    final name = requiredCashLabel(draft.name, field: 'name');
    if (ScenarioKind.values.any((k) => k.isBuiltin && k.label == name)) {
      throw const ValidationException('name', '不能与内置情景同名');
    }
    final same = await (_db.select(
      _db.scenarios,
    )..where((s) => s.workspaceId.equals(_ws) & s.name.equals(name))).get();
    if (same.any((s) => s.id != exceptId)) {
      throw const ConflictException('已有同名的情景');
    }
    if (draft.incomeDelayDays < 0 || draft.incomeDelayDays > 180) {
      throw const ValidationException('incomeDelayDays', '收入延迟须在 0–180 天之间');
    }
    final income = draft.incomeScale ?? Rational.one;
    if (income < Rational.zero || income > Rational.one) {
      throw const ValidationException('incomeScale', '收入比例须在 0%–100% 之间');
    }
    final expense = draft.expenseScale ?? Rational.one;
    if (expense < Rational.one || expense > Rational.fromInt(10)) {
      throw const ValidationException('expenseScale', '支出比例须在 100%–1000% 之间');
    }
    final incomeText = _scaleText(income, 'incomeScale');
    final expenseText = _scaleText(expense, 'expenseScale');

    // 额度变化（I-2 使用）：信用账户须在本空间、日期在支持范围、变化额非零且有界。
    final limitSeen = <String>{};
    for (final change in draft.limitChanges) {
      final account =
          await (_db.select(_db.creditAccounts)..where(
                (a) =>
                    a.workspaceId.equals(_ws) &
                    a.id.equals(change.creditAccountId) &
                    a.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (account == null) {
        throw const ValidationException('limitChanges', '额度变化须选择信用账户');
      }
      checkCashDate('limitChanges', change.on);
      if (change.changeMinor == 0 ||
          change.changeMinor.abs() > maxAmountMinor) {
        throw const ValidationException('limitChanges', '额度变化须为非零金额');
      }
      if (!limitSeen.add('${change.creditAccountId}/${change.on}')) {
        throw const ValidationException('limitChanges', '同一账户同一天只能有一项额度变化');
      }
    }

    // 事件覆盖：指向未删除的事件，每个事件一次。
    final overridden = <String>{};
    for (final o in draft.eventOverrides) {
      if (!overridden.add(o.eventId)) {
        throw const ValidationException('eventOverrides', '同一笔收支只能覆盖一次');
      }
      if (o.on == null && o.amountMinor == null) {
        throw const ValidationException('eventOverrides', '覆盖须填写新日期或新金额');
      }
      final event =
          await (_db.select(_db.cashEvents)..where(
                (e) =>
                    e.workspaceId.equals(_ws) &
                    e.id.equals(o.eventId) &
                    e.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (event == null) {
        throw const ValidationException('eventOverrides', '覆盖的收支已不存在');
      }
      final on = o.on;
      if (on != null) {
        checkCashDate('eventOverrides', on);
      }
      final amount = o.amountMinor;
      if (amount != null &&
          (amount.abs() > maxAmountMinor ||
              (amount != 0 && (amount < 0) != (event.amountMinor < 0)))) {
        throw const ValidationException('eventOverrides', '覆盖金额须与原收支同为收入或同为支出');
      }
    }

    // 按时刻排序：所有事件都须有时刻（P-09 字段校验）。
    if (draft.sameDayOrder == SameDayOrderChoice.timestamp) {
      final untimed = await _untimedEventCount();
      if (untimed > 0) {
        throw ValidationException(
          'sameDayOrder',
          '按时刻排序须所有收支都有时刻：还有 $untimed 笔没有时刻',
        );
      }
    }
    return (
      name: name,
      incomeScale: incomeText,
      expenseScale: expenseText,
      limitChanges: canonicalJsonText(<Object?>[
        for (final c in draft.limitChanges) c.toJson(),
      ]),
      eventOverrides: canonicalJsonText(<Object?>[
        for (final o in draft.eventOverrides) o.toJson(),
      ]),
    );
  }

  /// 资金日历可能用到的事件（未停用账户、今天往前 31 天到今天 + 180 天）里没有时刻的笔数。
  Future<int> _untimedEventCount() async {
    final today = _scope.clock.today(cashTimeZone);
    final from = today.addDays(-31).toString();
    final to = today.addDays(cashHorizonDays).toString();
    final rows =
        await (_db.select(_db.cashEvents).join([
              innerJoin(
                _db.cashAccounts,
                _db.cashAccounts.workspaceId.equalsExp(
                      _db.cashEvents.workspaceId,
                    ) &
                    _db.cashAccounts.id.equalsExp(_db.cashEvents.cashAccountId),
              ),
            ])..where(
              _db.cashEvents.workspaceId.equals(_ws) &
                  _db.cashEvents.deletedAt.isNull() &
                  _db.cashEvents.eventAt.isNull() &
                  _db.cashEvents.eventOn.isBetweenValues(from, to) &
                  _db.cashAccounts.status.equals(
                    CashAccountStatus.active.code,
                  ) &
                  _db.cashAccounts.deletedAt.isNull(),
            ))
            .get();
    return rows.length;
  }
}

/// 情景系数 → 规范十进制文本（至多 10 位小数，规则协议 v1 的 ScaleFactor）。
String _scaleText(Rational value, String field) {
  final String text;
  try {
    text = decimalText(value);
  } on ArgumentError {
    throw ValidationException(field, '比例须是有限小数');
  }
  final dot = text.indexOf('.');
  if (dot >= 0 && text.length - dot - 1 > 10) {
    throw ValidationException(field, '比例至多 10 位小数');
  }
  return text;
}
