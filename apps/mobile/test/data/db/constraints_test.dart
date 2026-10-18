// 本地库 v2 的约束与触发器（数据库层兜底；仓库层的规则另见 test/data/repositories/）：
// 币种只允许领域包的 13 种、末四位、G2 兜底、跨工作空间关联被复合外键拒绝、卡片状态机、
// 规则主体与区间、快照只追加、归属列不可改、部分唯一索引。真实 sqlite3mc。
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/database_platform.dart';
import 'package:cardflow_domain/cardflow_domain.dart' show minorDigits;
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/common.dart' show SqliteException;

import 'db_test_support.dart';

const String _w1 = 'w1';
const String _w2 = 'w2';
const String _ts = '2026-10-18T08:00:00+08:00';

/// 断言 [sql] 违反约束（SQLITE_CONSTRAINT，主结果码 19）。
Future<void> _rejects(GeneratedDatabase db, String sql) async {
  try {
    await db.customStatement(sql);
  } on Object catch (error) {
    final cause = unwrapRemoteError(error);
    expect(cause, isA<SqliteException>(), reason: sql);
    expect((cause as SqliteException).resultCode, 19, reason: sql);
    return;
  }
  fail('应被约束拒绝：$sql');
}

String _card(
  String id, {
  String workspace = _w1,
  String account = 'a1',
  String last4 = '1234',
  String status = 'active',
  String holderKind = 'primary',
  String? primary,
  String? alias,
}) =>
    'INSERT INTO cards (id, workspace_id, credit_account_id, last4, holder_kind, '
    'primary_card_id, status, alias, created_at, updated_at) VALUES '
    "('$id', '$workspace', '$account', '$last4', '$holderKind', "
    "${primary == null ? 'NULL' : "'$primary'"}, '$status', "
    "${alias == null ? 'NULL' : "'$alias'"}, '$_ts', '$_ts')";

String _rule(
  String id, {
  String workspace = _w1,
  String subject = 'a1',
  String subjectKind = 'credit_account',
  int version = 1,
  String? from,
  String? to,
}) =>
    'INSERT INTO billing_rule_versions (id, workspace_id, subject_kind, subject_id, '
    'statement_day, due_kind, due_day, source, effective_from, effective_to, version, '
    "review_status, created_at) VALUES ('$id', '$workspace', '$subjectKind', '$subject', "
    "10, 'fixed_day', 28, 'user_declared', ${from == null ? 'NULL' : "'$from'"}, "
    "${to == null ? 'NULL' : "'$to'"}, $version, 'user_declared', '$_ts')";

void main() {
  late AppDatabase db;

  setUp(() async {
    final opened = await openTestDatabase(
      createTempLocation(),
      InMemoryDatabaseKeyStore(),
    );
    db = opened.database;
    addTearDown(db.close);
    for (final sql in <String>[
      "INSERT INTO workspaces (id, kind, name, created_at) VALUES ('$_w1', 'real', '我的数据', '$_ts')",
      "INSERT INTO workspaces (id, kind, name, created_at) VALUES ('$_w2', 'demo', '演示数据', '$_ts')",
      "INSERT INTO banks (id, workspace_id, name, created_at) VALUES ('b1', '$_w1', '招商银行', '$_ts')",
      "INSERT INTO banks (id, workspace_id, name, created_at) VALUES ('b2', '$_w2', '招商银行', '$_ts')",
      'INSERT INTO credit_accounts (id, workspace_id, bank_id, holder_alias, created_at, updated_at) '
          "VALUES ('a1', '$_w1', 'b1', '本人', '$_ts', '$_ts')",
      'INSERT INTO credit_accounts (id, workspace_id, bank_id, holder_alias, created_at, updated_at) '
          "VALUES ('a3', '$_w1', 'b1', '本人', '$_ts', '$_ts')",
      'INSERT INTO credit_accounts (id, workspace_id, bank_id, holder_alias, created_at, updated_at) '
          "VALUES ('a2', '$_w2', 'b2', '本人', '$_ts', '$_ts')",
      'INSERT INTO currency_accounts (id, workspace_id, credit_account_id, currency, is_primary, created_at) '
          "VALUES ('c1', '$_w1', 'a1', 'CNY', 1, '$_ts')",
      _card('k1'),
    ]) {
      await db.customStatement(sql);
    }
  });

  test('币种 CHECK 恰好是领域包 minorDigits 的 13 种（审查 §4 第 8 条）', () async {
    final checks = await db
        .customSelect(
          "SELECT name, sql FROM sqlite_master WHERE type = 'table' "
          "AND sql LIKE '%currency IN (%'",
        )
        .get();
    expect(checks.map((r) => r.read<String>('name')).toSet(), <String>{
      'credit_pools',
      'currency_accounts',
    });
    for (final row in checks) {
      final listed = RegExp(r'currency IN \(([^)]*)\)')
          .firstMatch(row.read<String>('sql'))!
          .group(1)!
          .split(',')
          .map((s) => s.trim().replaceAll("'", ''))
          .toSet();
      expect(
        listed,
        minorDigits.keys.toSet(),
        reason: row.read<String>('name'),
      );
    }

    var n = 0;
    for (final currency in minorDigits.keys) {
      n++;
      await db.customStatement(
        'INSERT INTO credit_pools (id, workspace_id, bank_id, name, shared_limit_minor, '
        "currency, created_at, updated_at) VALUES ('p$n', '$_w1', 'b1', '池$n', 100, "
        "'$currency', '$_ts', '$_ts')",
      );
    }
    for (final bad in <String>['XXX', 'cny', 'RMB', '']) {
      await _rejects(
        db,
        'INSERT INTO currency_accounts (id, workspace_id, credit_account_id, currency, '
        "created_at) VALUES ('cx', '$_w1', 'a1', '$bad', '$_ts')",
      );
    }
  });

  test('末四位必须恰好 4 位 ASCII 数字', () async {
    await db.customStatement(_card('k2', last4: '0007'));
    for (final bad in <String>['123', '12345', '12a4', '１２３４', ' 123']) {
      await _rejects(db, _card('kx', last4: bad));
    }
  });

  test('G2 兜底：自由文本含 13 位连续数字被拒绝（12 位可以）', () async {
    await db.customStatement(_card('k3', alias: '工资卡123456789012'));
    await _rejects(db, _card('kx', alias: '卡号6222020200112'));
    await _rejects(
      db,
      "UPDATE credit_accounts SET product_name = '6222020200112233445' WHERE id = 'a1'",
    );
    await _rejects(
      db,
      "INSERT INTO banks (id, workspace_id, name, created_at) VALUES ('bx', '$_w1', "
      "'1234567890123', '$_ts')",
    );
  });

  test('跨工作空间的关联被复合外键拒绝', () async {
    await _rejects(db, _card('kx', workspace: _w2, account: 'a1'));
    await _rejects(
      db,
      'INSERT INTO currency_accounts (id, workspace_id, credit_account_id, currency, '
      "created_at) VALUES ('cx', '$_w2', 'a1', 'USD', '$_ts')",
    );
    await _rejects(
      db,
      'INSERT INTO limit_snapshots (id, workspace_id, currency_account_id, fixed_minor, '
      'used_minor, available_raw_minor, includes_holds, source_kind, balance_as_of, '
      "observed_at, recorded_at, confirmation_level) VALUES ('sx', '$_w2', 'c1', 0, 0, 0, "
      "1, 'user', '$_ts', '$_ts', '$_ts', 'user_confirmed')",
    );
    await db.customStatement(
      'INSERT INTO credit_pools (id, workspace_id, bank_id, name, shared_limit_minor, '
      "currency, created_at, updated_at) VALUES ('p2', '$_w2', 'b2', '池', 1, 'CNY', "
      "'$_ts', '$_ts')",
    );
    await _rejects(
      db,
      "UPDATE credit_accounts SET pool_id = 'p2' WHERE id = 'a1'",
    );
    await _rejects(db, _rule('rx', workspace: _w2, subject: 'a1'));
  });

  test('附属卡的主卡、换卡的新卡必须在同一信用账户', () async {
    await db.customStatement(_card('k9', account: 'a3'));
    await db.customStatement(
      _card('s1', holderKind: 'supplementary', primary: 'k1'),
    );
    await _rejects(db, _card('sx', holderKind: 'supplementary', primary: 'k9'));
    await _rejects(db, _card('sy', holderKind: 'supplementary'));
    await _rejects(
      db,
      "UPDATE cards SET status = 'replaced', replaced_by_card_id = 'k9' WHERE id = 'k1'",
    );
  });

  test('卡片状态机（PRD §6.1）由触发器兜底', () async {
    await db.customStatement(_card('d1', status: 'draft'));
    await _rejects(db, "UPDATE cards SET status = 'frozen' WHERE id = 'd1'");
    await db.customStatement(
      "UPDATE cards SET status = 'active' WHERE id = 'd1'",
    );
    await _rejects(db, "UPDATE cards SET status = 'draft' WHERE id = 'd1'");
    await db.customStatement(
      "UPDATE cards SET status = 'frozen' WHERE id = 'd1'",
    );
    await _rejects(
      db,
      "UPDATE cards SET status = 'replaced', replaced_by_card_id = 'k1' WHERE id = 'd1'",
    );
    await db.customStatement(
      "UPDATE cards SET status = 'closed', closed_on = '2026-10-18' WHERE id = 'd1'",
    );
    await _rejects(db, "UPDATE cards SET status = 'active' WHERE id = 'd1'");
    await _rejects(
      db,
      "UPDATE cards SET status = 'active', closed_on = NULL WHERE id = 'd1'",
    );
    await _rejects(db, "UPDATE cards SET last4 = '9999' WHERE id = 'k1'");
  });

  test('规则：主体须在同一工作空间；区间不重叠；已有版本只能封口', () async {
    await _rejects(db, _rule('r0', subject: 'nope'));
    await db.customStatement(_rule('r1', to: '2026-10-20'));
    await _rejects(db, _rule('rx', version: 2, from: '2026-10-19'));
    await _rejects(db, _rule('ry', version: 2));
    await db.customStatement(_rule('r2', version: 2, from: '2026-10-20'));
    // 空区间（被更正取代）不参与重叠检查。
    await db.customStatement(
      _rule('r3', version: 3, from: '2026-11-01', to: '2026-11-01'),
    );
    await db.customStatement(_rule('r4', version: 4, to: '0001-01-01'));
    // 封口：effective_to 只能变早；状态只能变为 expired；其余列不可改。
    await db.customStatement(
      "UPDATE billing_rule_versions SET effective_to = '2026-12-01', "
      "review_status = 'expired' WHERE id = 'r2'",
    );
    await _rejects(
      db,
      "UPDATE billing_rule_versions SET effective_to = '2027-01-01' WHERE id = 'r2'",
    );
    await _rejects(
      db,
      "UPDATE billing_rule_versions SET effective_to = NULL WHERE id = 'r2'",
    );
    await _rejects(
      db,
      "UPDATE billing_rule_versions SET review_status = 'user_declared' WHERE id = 'r2'",
    );
    await _rejects(
      db,
      "UPDATE billing_rule_versions SET statement_day = 11 WHERE id = 'r1'",
    );
    // 工作空间私有规则不得标 verified/published（R2-13）。
    await _rejects(
      db,
      _rule(
        'rz',
        version: 9,
        from: '2030-01-01',
      ).replaceFirst("'user_declared', '$_ts')", "'verified', '$_ts')"),
    );
  });

  test('额度快照：只追加；临时额度须到期日、专项须用途；可用额可负', () async {
    String snapshot(String id, {String extra = '', String values = ''}) =>
        'INSERT INTO limit_snapshots (id, workspace_id, currency_account_id, fixed_minor, '
        'used_minor, available_raw_minor, includes_holds, source_kind, balance_as_of, '
        'observed_at, recorded_at, confirmation_level$extra) VALUES '
        "('$id', '$_w1', 'c1', 1000000, 1030000, -30000, 1, 'bank_app', '$_ts', '$_ts', "
        "'$_ts', 'user_confirmed'$values)";
    await db.customStatement(snapshot('s1'));
    await _rejects(
      db,
      "UPDATE limit_snapshots SET available_raw_minor = 0 WHERE id = 's1'",
    );
    await _rejects(
      db,
      snapshot('s2', extra: ', temp_minor', values: ', 500000'),
    );
    await db.customStatement(
      snapshot(
        's3',
        extra: ', temp_minor, temp_expires_on',
        values: ", 500000, '2026-11-15'",
      ),
    );
    await _rejects(
      db,
      snapshot('s4', extra: ', special_minor', values: ', 100'),
    );
  });

  test('归属列不可改；每账户一个主子账户；同一种工作空间只有一个未删除的', () async {
    await _rejects(
      db,
      "UPDATE banks SET workspace_id = '$_w2' WHERE id = 'b1'",
    );
    await _rejects(
      db,
      "UPDATE credit_accounts SET bank_id = 'b2' WHERE id = 'a1'",
    );
    await _rejects(
      db,
      "UPDATE currency_accounts SET currency = 'USD' WHERE id = 'c1'",
    );
    await _rejects(
      db,
      'INSERT INTO currency_accounts (id, workspace_id, credit_account_id, currency, '
      "is_primary, created_at) VALUES ('c2', '$_w1', 'a1', 'USD', 1, '$_ts')",
    );
    await _rejects(
      db,
      "INSERT INTO workspaces (id, kind, name, created_at) VALUES ('w3', 'real', '另一个', '$_ts')",
    );
    await db.customStatement(
      "UPDATE workspaces SET deleted_at = '$_ts' WHERE id = '$_w2'",
    );
    await db.customStatement(
      "INSERT INTO workspaces (id, kind, name, created_at) VALUES ('w4', 'demo', '演示数据', '$_ts')",
    );
  });
}
