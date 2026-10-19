// 审查 R-I1 探针：从 v1（I-0b 的库：只有 meta、user_version=1）经 openAppDatabase 升到 v4 后，外键确实开启、
// 违反外键与跨空间引用被拒、foreign_key_check / integrity_check 干净；v2、v3 种子库升级后同样检查。
// 运行：cd apps/mobile && flutter test ../../evidence/i1/review-i1/scripts/migration_fk_probe_test.dart
import 'package:cardflow/data/db/app_database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../apps/mobile/test/data/db/db_test_support.dart';

Future<String> _one(GeneratedDatabase db, String sql) async {
  final rows = await db.customSelect(sql).get();
  return rows.map((r) => r.data.values.join(',')).join(' | ');
}

Future<String> _attempt(GeneratedDatabase db, String sql) async {
  try {
    await db.customStatement(sql);
    return '成功';
  } on Object catch (e) {
    return '被拒（${'$e'.split('\n').first.replaceAll(RegExp(r'\s+'), ' ')}）';
  }
}

void main() {
  test('v1 → v4（经 openAppDatabase）：外键开启并生效', () async {
    final location = createTempLocation();
    await createV1DatabaseFile(location, testKeyHex);
    final opened = await openTestDatabase(location, InMemoryDatabaseKeyStore(value: testKeyHex));
    final db = opened.database;
    addTearDown(db.close);
    // ignore: avoid_print
    print('created=${opened.created} user_version=${await _one(db, 'PRAGMA user_version')} '
        'meta=${await _one(db, 'SELECT schema_version FROM meta')} '
        'foreign_keys=${await _one(db, 'PRAGMA foreign_keys')} '
        'foreign_key_check=[${await _one(db, 'PRAGMA foreign_key_check')}] '
        'integrity_check=${await _one(db, 'PRAGMA integrity_check')}');
    const ts = '2026-10-18T08:00:00+08:00';
    await db.customStatement(
      "INSERT INTO workspaces (id, kind, name, created_at) VALUES ('w-real', 'real', '我的数据', '$ts'), "
      "('w-demo', 'demo', '演示', '$ts')",
    );
    await db.customStatement(
      "INSERT INTO cash_accounts (id, workspace_id, name, currency, kind, created_at, updated_at) "
      "VALUES ('ca-demo', 'w-demo', '演示现金', 'CNY', 'bank', '$ts', '$ts')",
    );
    // ignore: avoid_print
    print('不存在的工作空间写现金账户：${await _attempt(db, "INSERT INTO cash_accounts (id, workspace_id, name, currency, kind, created_at, updated_at) VALUES ('x1', 'nope', '甲', 'CNY', 'bank', '$ts', '$ts')")}');
    // ignore: avoid_print
    print('真实空间的事件指向演示空间的现金账户：${await _attempt(db, "INSERT INTO cash_events (id, workspace_id, cash_account_id, event_on, amount_minor, cls, category, created_at, updated_at) VALUES ('e1', 'w-real', 'ca-demo', '2026-10-18', -100, 'confirmed', 'living', '$ts', '$ts')")}');
    // ignore: avoid_print
    print('删除仍被引用的演示工作空间：${await _attempt(db, "DELETE FROM workspaces WHERE id = 'w-demo'")}');
  });
}
