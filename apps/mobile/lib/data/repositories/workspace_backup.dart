import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../ids.dart';
import 'workspace_repository.dart';
import 'workspace_scope.dart';

const String backupFormatVersion = 'cardflow-backup-v1';

/// 导出当前工作空间的卡片、账户、共享额度、账期规则与额度快照为 JSON 文本。
Future<String> exportWorkspaceBackup(WorkspaceScope scope) async {
  final db = scope.db;
  final ws = scope.workspaceId;
  final banks = await (db.select(
    db.banks,
  )..where((t) => t.workspaceId.equals(ws))).get();
  final pools = await (db.select(
    db.creditPools,
  )..where((t) => t.workspaceId.equals(ws))).get();
  final accounts = await (db.select(
    db.creditAccounts,
  )..where((t) => t.workspaceId.equals(ws))).get();
  final currencies = await (db.select(
    db.currencyAccounts,
  )..where((t) => t.workspaceId.equals(ws))).get();
  final cards = await (db.select(
    db.cards,
  )..where((t) => t.workspaceId.equals(ws))).get();
  final rules =
      await (db.select(db.billingRuleVersions)
            ..where((t) => t.workspaceId.equals(ws))
            ..orderBy([(t) => OrderingTerm.asc(t.version)]))
          .get();
  final snapshots = await (db.select(
    db.limitSnapshots,
  )..where((t) => t.workspaceId.equals(ws))).get();

  final payload = <String, Object?>{
    'format': backupFormatVersion,
    'banks': [for (final r in banks) r.toJson()],
    'creditPools': [for (final r in pools) r.toJson()],
    'creditAccounts': [for (final r in accounts) r.toJson()],
    'currencyAccounts': [for (final r in currencies) r.toJson()],
    'cards': [for (final r in cards) r.toJson()],
    'billingRuleVersions': [for (final r in rules) r.toJson()],
    'limitSnapshots': [for (final r in snapshots) r.toJson()],
  };
  return jsonEncode(payload);
}

/// 从备份 JSON 文本恢复到当前工作空间（覆盖当前工作空间内的数据，不影响另一工作空间）。
Future<int> restoreWorkspaceBackup(WorkspaceScope scope, String rawJson) async {
  final Object? decoded;
  try {
    decoded = jsonDecode(rawJson.trim());
  } on Object {
    throw const FormatException('备份数据格式无效，请粘贴完整的备份内容');
  }
  if (decoded is! Map<String, dynamic> ||
      decoded['format'] != backupFormatVersion) {
    throw const FormatException('备份数据格式无效，请粘贴完整的备份内容');
  }
  final map = decoded;

  List<Map<String, dynamic>> readList(String key) {
    final v = map[key];
    if (v is! List) {
      throw const FormatException('备份数据不完整');
    }
    return <Map<String, dynamic>>[
      for (final item in v)
        if (item is Map<String, dynamic>)
          Map<String, dynamic>.of(item)
        else
          throw const FormatException('备份数据不完整'),
    ];
  }

  final banksJson = readList('banks');
  final poolsJson = readList('creditPools');
  final accountsJson = readList('creditAccounts');
  final currenciesJson = readList('currencyAccounts');
  final cardsJson = readList('cards');
  final rulesJson = readList('billingRuleVersions');
  final snapshotsJson = readList('limitSnapshots');

  final idMap = <String, String>{};
  String remap(Object? raw) {
    if (raw is! String || raw.isEmpty) {
      throw const FormatException('备份数据不完整');
    }
    return idMap.putIfAbsent(raw, newUuidV4);
  }

  String? remapOpt(Object? raw) =>
      raw is String && raw.isNotEmpty ? remap(raw) : null;

  final ws = scope.workspaceId;
  final db = scope.db;

  try {
    await db.transaction(() async {
      for (final table in workspaceDataTables) {
        await db.customUpdate(
          'DELETE FROM $table WHERE workspace_id = ?',
          variables: <Variable<Object>>[Variable<String>(ws)],
          updateKind: UpdateKind.delete,
          updates: <TableInfo<Table, Object?>>{
            for (final t in db.allTables)
              if (t.actualTableName == table) t,
          },
        );
      }

      for (final m in banksJson) {
        m['id'] = remap(m['id']);
        m['workspaceId'] = ws;
        await db.into(db.banks).insert(BankRow.fromJson(m));
      }

      for (final m in poolsJson) {
        m['id'] = remap(m['id']);
        m['workspaceId'] = ws;
        m['bankId'] = remap(m['bankId']);
        m['parentPoolId'] = remapOpt(m['parentPoolId']);
        await db.into(db.creditPools).insert(CreditPoolRow.fromJson(m));
      }

      for (final m in accountsJson) {
        m['id'] = remap(m['id']);
        m['workspaceId'] = ws;
        m['bankId'] = remap(m['bankId']);
        m['poolId'] = remapOpt(m['poolId']);
        await db.into(db.creditAccounts).insert(CreditAccountRow.fromJson(m));
      }

      for (final m in currenciesJson) {
        m['id'] = remap(m['id']);
        m['workspaceId'] = ws;
        m['creditAccountId'] = remap(m['creditAccountId']);
        await db
            .into(db.currencyAccounts)
            .insert(CurrencyAccountRow.fromJson(m));
      }

      final mappedCards = <CardRow>[
        for (final m in cardsJson)
          CardRow.fromJson(<String, dynamic>{
            ...m,
            'id': remap(m['id']),
            'workspaceId': ws,
            'creditAccountId': remap(m['creditAccountId']),
            'primaryCardId': remapOpt(m['primaryCardId']),
            'replacedByCardId': remapOpt(m['replacedByCardId']),
          }),
      ];
      final insertedCardIds = <String>{};
      final pendingCards = List<CardRow>.of(mappedCards);
      while (pendingCards.isNotEmpty) {
        var progressed = false;
        for (var i = 0; i < pendingCards.length; i++) {
          final c = pendingCards[i];
          final primaryReady =
              c.primaryCardId == null ||
              insertedCardIds.contains(c.primaryCardId);
          final replacedReady =
              c.replacedByCardId == null ||
              insertedCardIds.contains(c.replacedByCardId);
          if (primaryReady && replacedReady) {
            await db.into(db.cards).insert(c);
            insertedCardIds.add(c.id);
            pendingCards.removeAt(i);
            progressed = true;
            break;
          }
        }
        if (!progressed) {
          throw const FormatException('卡片关联关系无效');
        }
      }

      for (final m in rulesJson) {
        m['id'] = remap(m['id']);
        m['workspaceId'] = ws;
        m['subjectId'] = remap(m['subjectId']);
        await db
            .into(db.billingRuleVersions)
            .insert(BillingRuleVersionRow.fromJson(m));
      }

      for (final m in snapshotsJson) {
        m['id'] = remap(m['id']);
        m['workspaceId'] = ws;
        m['currencyAccountId'] = remap(m['currencyAccountId']);
        await db.into(db.limitSnapshots).insert(LimitSnapshotRow.fromJson(m));
      }
    });
  } on FormatException {
    rethrow;
  } on Object {
    throw const FormatException('备份数据校验未通过，无法恢复');
  }

  return accountsJson.length;
}
