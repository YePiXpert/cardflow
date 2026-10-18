// 本地库 v3 的约束与触发器（现金账户、余额快照与已包含事件、现金事件、周期事项、情景；数据库层兜底，
// 仓库层的规则另见 test/data/repositories/）。真实 sqlite3mc。
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/database_platform.dart';
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

String _account(
  String id, {
  String workspace = _w1,
  String name = '工资卡',
  String currency = 'CNY',
  String kind = 'bank',
  int usable = 1,
  int reserve = 0,
}) =>
    'INSERT INTO cash_accounts (id, workspace_id, name, currency, kind, '
    'usable_for_repayment, reserve_floor_minor, created_at, updated_at) VALUES '
    "('$id', '$workspace', '$name', '$currency', '$kind', $usable, $reserve, "
    "'$_ts', '$_ts')";

String _event(
  String id, {
  String workspace = _w1,
  String account = 'ca1',
  String on = '2026-10-20',
  String? at,
  int amount = -10000,
  String cls = 'confirmed',
  String category = 'bill',
  String posting = 'planned',
  String? transferGroup,
  String? recurring,
  String? occurrence,
}) {
  String text(String? v) => v == null ? 'NULL' : "'$v'";
  return 'INSERT INTO cash_events (id, workspace_id, cash_account_id, event_on, event_at, '
      'amount_minor, cls, category, posting_status, transfer_group_id, recurring_item_id, '
      'occurrence_key, created_at, updated_at) VALUES '
      "('$id', '$workspace', '$account', '$on', ${text(at)}, $amount, '$cls', '$category', "
      "'$posting', ${text(transferGroup)}, ${text(recurring)}, ${text(occurrence)}, "
      "'$_ts', '$_ts')";
}

String _snapshot(
  String id, {
  String workspace = _w1,
  String account = 'ca1',
  String asOf = '2026-10-18',
  int balance = 500000,
}) =>
    'INSERT INTO cash_balance_snapshots (id, workspace_id, cash_account_id, balance_minor, '
    'balance_as_of, observed_at, source_kind, confirmation_level, recorded_at) VALUES '
    "('$id', '$workspace', '$account', $balance, '$asOf', '$_ts', 'bank_app', "
    "'user_confirmed', '$_ts')";

String _includes(
  String snapshot,
  String event, {
  String workspace = _w1,
  String account = 'ca1',
}) =>
    'INSERT INTO snapshot_included_events (workspace_id, cash_account_id, snapshot_id, '
    "cash_event_id) VALUES ('$workspace', '$account', '$snapshot', '$event')";

String _recurring(
  String id, {
  String account = 'ca1',
  String frequency = 'monthly',
  String dayRule = 'anchor_day',
  String anchor = '2026-10-27',
  String start = '2026-10-27',
  String category = 'living',
  int amount = -100000,
}) =>
    'INSERT INTO recurring_items (id, workspace_id, cash_account_id, label, amount_minor, cls, '
    'category, frequency, anchor_on, day_rule, start_on, created_at, updated_at) VALUES '
    "('$id', '$_w1', '$account', '房租', $amount, 'confirmed', '$category', '$frequency', "
    "'$anchor', '$dayRule', '$start', '$_ts', '$_ts')";

String _scenario(
  String id, {
  String workspace = _w1,
  String name = '收入推迟',
  String kind = 'user_stress',
  int includeExpected = 1,
  int delay = 3,
  String incomeScale = '1',
  String expenseScale = '1',
  String overrides = '[]',
}) =>
    'INSERT INTO scenarios (id, workspace_id, name, kind, include_expected, income_delay_days, '
    'income_scale, expense_scale, event_overrides, created_at, updated_at) VALUES '
    "('$id', '$workspace', '$name', '$kind', $includeExpected, $delay, '$incomeScale', "
    "'$expenseScale', '$overrides', '$_ts', '$_ts')";

String _run(
  String id,
  String scenario, {
  int version = 1,
  String hash =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  String result = '{"accounts":[]}',
}) =>
    'INSERT INTO scenario_runs (id, workspace_id, scenario_id, version_no, computed_at, '
    'horizon_from, horizon_to, inputs_hash, result) VALUES '
    "('$id', '$_w1', '$scenario', $version, '$_ts', '2026-10-18', '2027-04-16', '$hash', "
    "'$result')";

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
      _account('ca1'),
      _account('ca2', name: '零钱'),
      _account('cu', name: '美元户', currency: 'USD'),
      _account('cx', workspace: _w2),
    ]) {
      await db.customStatement(sql);
    }
  });

  test('现金账户：种类、受限不可直接标为可用、储备 ≥0、名称（G2/G5、同空间未删除的不重名）、币种不可改', () async {
    await db.customStatement(
      _account('ca3', name: '定期', kind: 'restricted', usable: 0),
    );
    await db.customStatement(
      _account('ca4', name: '理财', kind: 'wealth', usable: 1),
    );
    await _rejects(db, _account('bad1', name: '甲', kind: 'cash'));
    await _rejects(
      db,
      _account('bad2', name: '乙', kind: 'restricted', usable: 1),
    );
    await _rejects(db, _account('bad3', name: '丙', reserve: -1));
    await _rejects(db, _account('bad4', name: '丁', reserve: 10000000000001));
    await _rejects(db, _account('bad5', name: '卡号6222020200112'));
    await _rejects(db, _account('bad6', name: '一二三四五六七八九十一二三四五六七八九十一'));
    await _rejects(db, _account('bad7', name: '戊', currency: 'RMB'));
    await _rejects(db, _account('dup'));
    // 删除后可以再用同一个名称。
    await db.customStatement(
      "UPDATE cash_accounts SET deleted_at = '$_ts' WHERE id = 'ca2'",
    );
    await db.customStatement(_account('ca5', name: '零钱'));
    await _rejects(
      db,
      "UPDATE cash_accounts SET currency = 'USD' WHERE id = 'ca1'",
    );
    await _rejects(
      db,
      "UPDATE cash_accounts SET workspace_id = '$_w2' WHERE id = 'ca1'",
    );
  });

  test('现金事件：at 按自身偏移的日期必须等于 on；金额非零、有界、按类别定符号；已发生的必为确定', () async {
    await db.customStatement(
      _event('e1', on: '2026-10-20', at: '2026-10-20T23:30:00+08:00'),
    );
    // 同一瞬间写成 UTC 是 10-20T15:30Z：按自身偏移仍是 10-20。
    await db.customStatement(
      _event('e2', on: '2026-10-20', at: '2026-10-20T15:30:00Z'),
    );
    await _rejects(
      db,
      _event('bad1', on: '2026-10-21', at: '2026-10-20T23:30:00+08:00'),
    );
    await _rejects(db, _event('bad2', amount: 0));
    await _rejects(db, _event('bad3', amount: -10000000000001));
    await _rejects(db, _event('bad4', category: 'income', amount: -100));
    await _rejects(db, _event('bad5', category: 'living', amount: 100));
    await db.customStatement(_event('e3', category: 'other', amount: 100));
    await db.customStatement(_event('e4', category: 'other', amount: -100));
    await _rejects(db, _event('bad6', cls: 'expected', posting: 'posted'));
    await _rejects(db, _event('bad7', cls: 'probable'));
    await _rejects(db, _event('bad8', category: 'salary'));
    // 调拨类别必须有调拨组；有调拨组必须是调拨类别。
    await _rejects(db, _event('bad9', category: 'transfer_out'));
    await _rejects(db, _event('bad10', transferGroup: 'g0'));
    // 周期事项的事件必须带期键（反之亦然）。
    await db.customStatement(_recurring('r1'));
    await _rejects(db, _event('bad11', recurring: 'r1'));
    await _rejects(db, _event('bad12', occurrence: '2026-10-27'));
    await db.customStatement(
      _event(
        'e5',
        recurring: 'r1',
        occurrence: '2026-10-27',
        category: 'living',
      ),
    );
    // 同一期最多一条未删除的事件。
    await _rejects(
      db,
      _event(
        'bad13',
        recurring: 'r1',
        occurrence: '2026-10-27',
        category: 'living',
      ),
    );
  });

  test('现金事件：归属列不可改；已发生不能退回；删除后不再改动；跨空间/跨账户的关联被复合外键拒绝', () async {
    await db.customStatement(_event('e1'));
    await _rejects(
      db,
      "UPDATE cash_events SET cash_account_id = 'ca2' WHERE id = 'e1'",
    );
    await db.customStatement(
      "UPDATE cash_events SET posting_status = 'posted' WHERE id = 'e1'",
    );
    await _rejects(
      db,
      "UPDATE cash_events SET posting_status = 'planned' WHERE id = 'e1'",
    );
    await db.customStatement(
      "UPDATE cash_events SET deleted_at = '$_ts' WHERE id = 'e1'",
    );
    await _rejects(
      db,
      "UPDATE cash_events SET deleted_at = NULL WHERE id = 'e1'",
    );
    await _rejects(db, "UPDATE cash_events SET label = '改' WHERE id = 'e1'");
    // 其他工作空间的账户。
    await _rejects(db, _event('bad1', account: 'cx'));
    // 周期事项属于另一个账户。
    await db.customStatement(_recurring('r2', account: 'ca2'));
    await _rejects(
      db,
      _event(
        'bad2',
        recurring: 'r2',
        occurrence: '2026-10-27',
        category: 'living',
      ),
    );
  });

  test('调拨：两端账户不同、币种相同、方向相反、金额相反、到账不早于转出；一组最多两条；两端日期金额不可改', () async {
    await db.customStatement(
      _event(
        't1',
        category: 'transfer_out',
        amount: -50000,
        on: '2026-10-20',
        transferGroup: 'g1',
      ),
    );
    await _rejects(
      db,
      _event('x1', category: 'transfer_in', amount: 50000, transferGroup: 'g1'),
    );
    await _rejects(
      db,
      _event(
        'x2',
        account: 'cu',
        category: 'transfer_in',
        amount: 50000,
        transferGroup: 'g1',
      ),
    );
    await _rejects(
      db,
      _event(
        'x3',
        account: 'ca2',
        category: 'transfer_out',
        amount: -50000,
        transferGroup: 'g1',
      ),
    );
    await _rejects(
      db,
      _event(
        'x4',
        account: 'ca2',
        category: 'transfer_in',
        amount: 40000,
        transferGroup: 'g1',
      ),
    );
    await _rejects(
      db,
      _event(
        'x5',
        account: 'ca2',
        category: 'transfer_in',
        amount: 50000,
        on: '2026-10-19',
        transferGroup: 'g1',
      ),
    );
    await db.customStatement(
      _event(
        't2',
        account: 'ca2',
        category: 'transfer_in',
        amount: 50000,
        on: '2026-10-21',
        transferGroup: 'g1',
      ),
    );
    await _rejects(
      db,
      _event(
        'x6',
        account: 'ca2',
        category: 'transfer_in',
        amount: 50000,
        on: '2026-10-21',
        transferGroup: 'g1',
      ),
    );
    await _rejects(
      db,
      "UPDATE cash_events SET event_on = '2026-10-22' WHERE id = 't1'",
    );
    await _rejects(
      db,
      "UPDATE cash_events SET amount_minor = -1 WHERE id = 't1'",
    );
    // 确认（已发生）与删除可以。
    await db.customStatement(
      "UPDATE cash_events SET posting_status = 'posted' WHERE id = 't1'",
    );
  });

  test('余额快照只追加；包含关系只能列本账户、快照日当天及以前的事件，之后不改', () async {
    await db.customStatement(_snapshot('s1', asOf: '2026-10-20'));
    await _rejects(
      db,
      "UPDATE cash_balance_snapshots SET balance_minor = 0 WHERE id = 's1'",
    );
    await _rejects(db, _snapshot('bad1', balance: 10000000000001));
    await _rejects(db, _snapshot('bad2', account: 'cx'));
    await db.customStatement(_event('e-before', on: '2026-10-19'));
    await db.customStatement(_event('e-same', on: '2026-10-20'));
    await db.customStatement(_event('e-after', on: '2026-10-21'));
    await db.customStatement(_event('e-other', account: 'ca2'));
    await db.customStatement(_includes('s1', 'e-before'));
    await db.customStatement(_includes('s1', 'e-same'));
    await _rejects(db, _includes('s1', 'e-after'));
    await _rejects(db, _includes('s1', 'e-other'));
    await _rejects(db, _includes('s1', 'e-other', account: 'ca2'));
    await _rejects(
      db,
      "UPDATE snapshot_included_events SET cash_event_id = 'e-after' "
      "WHERE snapshot_id = 's1' AND cash_event_id = 'e-same'",
    );
  });

  test('周期事项：频率与日规则、起止日、类别不含调拨、按类别定符号；单期覆盖的取值', () async {
    await db.customStatement(_recurring('r1'));
    await db.customStatement(
      _recurring('r2', frequency: 'yearly', dayRule: 'month_end'),
    );
    await db.customStatement(_recurring('r3', frequency: 'biweekly'));
    await _rejects(
      db,
      _recurring('bad1', frequency: 'weekly', dayRule: 'month_end'),
    );
    await _rejects(db, _recurring('bad2', frequency: 'daily'));
    await _rejects(db, _recurring('bad3', start: '2026-10-26'));
    await _rejects(
      db,
      _recurring('bad4', category: 'transfer_out', amount: -100),
    );
    await _rejects(db, _recurring('bad5', category: 'income', amount: -100));
    String override(
      String key, {
      String action = 'override',
      String amount = 'NULL',
      String on = 'NULL',
      String at = 'NULL',
    }) =>
        'INSERT INTO recurring_overrides (workspace_id, recurring_item_id, occurrence_key, '
        'action, amount_minor, event_on, event_at, created_at, updated_at) VALUES '
        "('$_w1', 'r1', '$key', '$action', $amount, $on, $at, '$_ts', '$_ts')";
    await db.customStatement(override('2026-11-27', action: 'skip'));
    await db.customStatement(override('2026-12-27', amount: '-120000'));
    await db.customStatement(
      override(
        '2027-01-27',
        on: "'2027-01-28'",
        at: "'2027-01-28T09:00:00+08:00'",
      ),
    );
    await _rejects(db, override('2027-02-27', action: 'skip', amount: '-1'));
    await _rejects(db, override('2027-03-27'));
    await _rejects(db, override('2027-04-27', amount: '0'));
    await _rejects(
      db,
      override(
        '2027-05-27',
        on: "'2027-05-28'",
        at: "'2027-05-29T09:00:00+08:00'",
      ),
    );
  });

  test('情景：内置两条参数固定且只读、每种至多一条；压力情景的范围；JSON 必须是数组', () async {
    await db.customStatement(
      _scenario(
        'b1',
        name: '已确认',
        kind: 'builtin_confirmed',
        includeExpected: 0,
        delay: 0,
      ),
    );
    await db.customStatement(
      _scenario('b2', name: '基准预期', kind: 'builtin_baseline', delay: 0),
    );
    await _rejects(
      db,
      _scenario(
        'bad1',
        name: '另一个',
        kind: 'builtin_confirmed',
        includeExpected: 0,
        delay: 0,
      ),
    );
    await _rejects(
      db,
      _scenario('bad2', name: '假内置', kind: 'builtin_baseline', delay: 3),
    );
    await _rejects(
      db,
      _scenario(
        'bad3',
        name: '假已确认',
        kind: 'builtin_confirmed',
        includeExpected: 1,
        delay: 0,
      ),
    );
    await _rejects(db, "UPDATE scenarios SET name = '改名' WHERE id = 'b1'");
    await db.customStatement(_scenario('u1'));
    await db.customStatement(
      "UPDATE scenarios SET income_delay_days = 5 WHERE id = 'u1'",
    );
    await _rejects(
      db,
      "UPDATE scenarios SET kind = 'builtin_baseline' WHERE id = 'u1'",
    );
    await _rejects(db, _scenario('bad4', name: '超长延迟', delay: 181));
    await _rejects(db, _scenario('bad5', name: '负系数', incomeScale: '-1'));
    await _rejects(db, _scenario('bad6', name: '坏 JSON', overrides: '{"a":1}'));
    await _rejects(db, _scenario('bad7', name: '非 JSON', overrides: 'nope'));
    await _rejects(db, _scenario('bad8', name: '收入推迟'));
  });

  test('情景计算版本：只追加；版本号唯一；哈希与结果的格式；跨空间的情景被拒绝', () async {
    await db.customStatement(_scenario('u1'));
    await db.customStatement(_run('run1', 'u1'));
    await db.customStatement(_run('run2', 'u1', version: 2));
    await _rejects(db, _run('bad1', 'u1', version: 2));
    await _rejects(db, _run('bad2', 'u1', version: 0));
    await _rejects(db, _run('bad3', 'u1', version: 3, hash: 'ABC'));
    await _rejects(db, _run('bad4', 'u1', version: 3, result: '[1]'));
    await _rejects(
      db,
      "UPDATE scenario_runs SET result = '{}' WHERE id = 'run1'",
    );
    await db.customStatement(_scenario('u2', workspace: _w2));
    await _rejects(db, _run('bad5', 'u2', version: 1));
  });
}
