// 本地库 v4 的约束与触发器（交易、账单与追加只读的账单版本、分期、还款与分配、差异项，以及 v3 现金事件
// 的 linked_repayment_id；数据库层兜底，仓库层的规则另见 test/data/repositories/）。真实 sqlite3mc。
//
// 设环境变量 CARDFLOW_EVIDENCE=1 时逐条打印被拒绝的语句与数据库给出的消息（证据 append-only.txt）。
import 'dart:io';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/database_platform.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/common.dart' show SqliteException;

import 'db_test_support.dart';

const String _w1 = 'w1';
const String _w2 = 'w2';
const String _ts = '2026-10-18T08:00:00+08:00';
const String _fp =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

final bool _evidence = Platform.environment['CARDFLOW_EVIDENCE'] == '1';

void _log(String line) {
  if (_evidence) {
    // ignore: avoid_print
    print(line);
  }
}

/// 断言 [sql] 违反约束（SQLITE_CONSTRAINT，主结果码 19），返回数据库给出的消息。
Future<String> _rejects(GeneratedDatabase db, String sql) async {
  try {
    await db.customStatement(sql);
  } on Object catch (error) {
    final cause = unwrapRemoteError(error);
    expect(cause, isA<SqliteException>(), reason: sql);
    final e = cause as SqliteException;
    expect(e.resultCode, 19, reason: sql);
    _log('拒绝（${e.extendedResultCode}：${e.message}）：$sql');
    return e.message;
  }
  fail('应被约束拒绝：$sql');
}

Future<void> _accepts(GeneratedDatabase db, String sql) async {
  await db.customStatement(sql);
  _log('接受：$sql');
}

String _text(String? v) => v == null ? 'NULL' : "'$v'";

String _txn(
  String id, {
  String workspace = _w1,
  String account = 'c1',
  String currency = 'CNY',
  String? card = 'k1',
  String type = 'purchase',
  int amount = 10000,
  String? postedOn = '2026-10-12',
  String? parent,
  String status = 'posted',
  String? merchant,
}) =>
    'INSERT INTO transactions (id, workspace_id, currency_account_id, card_id, txn_type, '
    'amount_minor, currency, txn_at, txn_tz, time_precision, posted_on, merchant, status, '
    'parent_transaction_id, fingerprint, source_kind, confirmation_level, recorded_at, '
    "updated_at) VALUES ('$id', '$workspace', '$account', ${_text(card)}, '$type', $amount, "
    "'$currency', '2026-10-12T10:00:00+08:00', 'Asia/Shanghai', 'datetime', ${_text(postedOn)}, "
    "${_text(merchant)}, '$status', ${_text(parent)}, '$_fp', 'manual', 'user_confirmed', "
    "'$_ts', '$_ts')";

String _statement(
  String id, {
  String workspace = _w1,
  String account = 'c1',
  String date = '2026-10-10',
  String due = '2026-10-28',
  String status = 'issued',
}) =>
    'INSERT INTO statements (id, workspace_id, currency_account_id, statement_date, due_date, '
    "status, created_at, updated_at) VALUES ('$id', '$workspace', '$account', '$date', '$due', "
    "'$status', '$_ts', '$_ts')";

String _version(
  String id,
  String statement, {
  int no = 1,
  String source = 'manual',
  int newBalance = 389333,
  int? minDue = 38000,
  int? creditBalance,
  String due = '2026-10-28',
  String? reason,
}) =>
    'INSERT INTO statement_versions (id, workspace_id, statement_id, version_no, source_kind, '
    'new_balance_minor, min_due_minor, credit_balance_minor, due_date, recorded_by, reason, '
    "recorded_at) VALUES ('$id', '$_w1', '$statement', $no, '$source', $newBalance, "
    "${minDue ?? 'NULL'}, ${creditBalance ?? 'NULL'}, '$due', 'user', ${_text(reason)}, '$_ts')";

String _plan(
  String id, {
  String txn = 't1',
  int principal = 1000000,
  int periods = 12,
  String rate = '0.006',
  String feeMode = 'per_period',
  String remainder = 'last',
  String rounding = 'HALF_UP',
}) =>
    'INSERT INTO installment_plans (id, workspace_id, currency_account_id, transaction_id, '
    'principal_minor, periods, per_period_rate, fee_mode, remainder_policy, rounding, status, '
    "created_at, updated_at) VALUES ('$id', '$_w1', 'c1', '$txn', $principal, $periods, "
    "'$rate', '$feeMode', '$remainder', '$rounding', 'active', '$_ts', '$_ts')";

String _period(
  String plan,
  int no, {
  int principal = 83333,
  int fee = 6000,
  String statement = '2026-10-10',
  String due = '2026-10-28',
  String status = 'scheduled',
}) =>
    'INSERT INTO installment_schedule (workspace_id, plan_id, period_no, principal_minor, '
    "fee_minor, statement_date, due_date, status) VALUES ('$_w1', '$plan', $no, $principal, "
    "$fee, '$statement', '$due', '$status')";

String _repayment(
  String id, {
  String workspace = _w1,
  String account = 'c1',
  String? cash = 'ca1',
  String currency = 'CNY',
  int amount = 100000,
  String status = 'recorded',
  String method = 'manual',
  String? initiated,
  String? debited,
  String? credited,
  String? confirmed,
}) =>
    'INSERT INTO repayments (id, workspace_id, currency_account_id, cash_account_id, '
    'amount_minor, currency, status, method, payment_initiated_at, cash_debited_at, '
    'credit_posted_at, bank_confirmed_at, created_at, updated_at) VALUES '
    "('$id', '$workspace', '$account', ${_text(cash)}, $amount, '$currency', '$status', "
    "'$method', ${_text(initiated)}, ${_text(debited)}, ${_text(credited)}, "
    "${_text(confirmed)}, '$_ts', '$_ts')";

String _allocation(
  String repayment,
  String statement,
  int amount, {
  String account = 'c1',
}) =>
    'INSERT INTO repayment_allocations (workspace_id, currency_account_id, repayment_id, '
    "statement_id, amount_minor) VALUES ('$_w1', '$account', '$repayment', '$statement', "
    '$amount)';

String _cashEvent(
  String id, {
  String workspace = _w1,
  String account = 'ca1',
  String? repayment,
}) =>
    'INSERT INTO cash_events (id, workspace_id, cash_account_id, event_on, amount_minor, cls, '
    'category, linked_repayment_id, created_at, updated_at) VALUES '
    "('$id', '$workspace', '$account', '2026-10-20', -100000, 'planned', 'repayment', "
    "${_text(repayment)}, '$_ts', '$_ts')";

String _item(
  String id, {
  String kind = 'duplicate_repayment',
  String refs = '{"repayment_ids":["r1","r2"]}',
}) =>
    'INSERT INTO reconciliation_items (id, workspace_id, kind, refs, created_at, updated_at) '
    "VALUES ('$id', '$_w1', '$kind', '$refs', '$_ts', '$_ts')";

/// 把还款 [id] 的状态改为 [to]（同时补齐该状态要求的时点）。
String _move(String id, String to) =>
    "UPDATE repayments SET status = '$to', "
    "payment_initiated_at = COALESCE(payment_initiated_at, '$_ts'), "
    "cash_debited_at = CASE WHEN '$to' IN ('cash_debited', 'credit_posted') "
    "THEN COALESCE(cash_debited_at, '$_ts') ELSE cash_debited_at END, "
    "credit_posted_at = CASE WHEN '$to' = 'credit_posted' "
    "THEN COALESCE(credit_posted_at, '$_ts') ELSE credit_posted_at END, "
    "bank_confirmed_at = CASE WHEN '$to' IN ('bank_confirmed', 'reversed') "
    "THEN COALESCE(bank_confirmed_at, '$_ts') ELSE bank_confirmed_at END "
    "WHERE id = '$id'";

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
      "INSERT INTO banks (id, workspace_id, name, created_at) VALUES ('bx', '$_w2', '招商银行', '$_ts')",
      for (final (id, ws, bank) in <(String, String, String)>[
        ('a1', _w1, 'b1'),
        ('a2', _w1, 'b1'),
        ('ax', _w2, 'bx'),
      ])
        'INSERT INTO credit_accounts (id, workspace_id, bank_id, holder_alias, created_at, '
            "updated_at) VALUES ('$id', '$ws', '$bank', '本人', '$_ts', '$_ts')",
      for (final (id, ws, account, currency, primary)
          in <(String, String, String, String, int)>[
            ('c1', _w1, 'a1', 'CNY', 1),
            ('cu', _w1, 'a1', 'USD', 0),
            ('c2', _w1, 'a2', 'CNY', 1),
            ('cx', _w2, 'ax', 'CNY', 1),
          ])
        'INSERT INTO currency_accounts (id, workspace_id, credit_account_id, currency, '
            "is_primary, created_at) VALUES ('$id', '$ws', '$account', '$currency', $primary, "
            "'$_ts')",
      for (final (id, account, last4) in <(String, String, String)>[
        ('k1', 'a1', '1001'),
        ('k2', 'a2', '2001'),
      ])
        'INSERT INTO cards (id, workspace_id, credit_account_id, last4, holder_kind, status, '
            "created_at, updated_at) VALUES ('$id', '$_w1', '$account', '$last4', 'primary', "
            "'active', '$_ts', '$_ts')",
      for (final (id, ws, name, currency) in <(String, String, String, String)>[
        ('ca1', _w1, '工资卡', 'CNY'),
        ('cau', _w1, '美元户', 'USD'),
        ('cax', _w2, '工资卡', 'CNY'),
      ])
        'INSERT INTO cash_accounts (id, workspace_id, name, currency, kind, created_at, '
            "updated_at) VALUES ('$id', '$ws', '$name', '$currency', 'bank', '$_ts', '$_ts')",
    ]) {
      await db.customStatement(sql);
    }
  });

  group('账单版本追加只读（R-STMT-07）', () {
    setUp(() async {
      await _accepts(db, _statement('s1'));
      await _accepts(db, _version('v1', 's1'));
      await _accepts(
        db,
        "UPDATE statements SET current_version_id = 'v1' WHERE id = 's1'",
      );
    });

    test('直接 UPDATE 任何金额列、到期日或其他列都被触发器拒绝（RAISE(ABORT)）；行不变', () async {
      for (final column in <String>[
        'previous_balance_minor',
        'new_balance_minor',
        'min_due_minor',
        'payments_minor',
        'credits_minor',
        'fees_minor',
        'interest_minor',
        'installment_due_minor',
        'credit_balance_minor',
      ]) {
        final message = await _rejects(
          db,
          "UPDATE statement_versions SET $column = 1 WHERE id = 'v1'",
        );
        expect(
          message,
          contains('statement_versions: append only; insert a new version'),
        );
      }
      for (final set in <String>[
        "due_date = '2026-10-29'",
        "reason = '改原值'",
        "source_kind = 'import'",
        'version_no = 2',
        "recorded_at = '$_ts'",
      ]) {
        await _rejects(
          db,
          "UPDATE statement_versions SET $set WHERE id = 'v1'",
        );
      }
      final row = await db
          .customSelect(
            "SELECT new_balance_minor, min_due_minor FROM statement_versions WHERE id = 'v1'",
          )
          .getSingle();
      expect(row.data, <String, Object?>{
        'new_balance_minor': 389333,
        'min_due_minor': 38000,
      });
    });

    test('更正 = 新版本：版本号紧接最新（不跳号、不复用），人工修正理由必填，v1 不能是修正', () async {
      await _rejects(
        db,
        _version('bad1', 's1', no: 3, source: 'correction', reason: '跳号'),
      );
      await _rejects(db, _version('bad2', 's1', no: 1));
      await _rejects(db, _version('bad3', 's1', no: 2, source: 'correction'));
      await _accepts(
        db,
        _version(
          'v2',
          's1',
          no: 2,
          source: 'correction',
          minDue: 38933,
          reason: '最低还款额抄错，按账单更正',
        ),
      );
      await _accepts(
        db,
        _statement('s2', date: '2026-11-10', due: '2026-11-28'),
      );
      await _rejects(
        db,
        _version('bad4', 's2', source: 'correction', reason: '第一版不能是修正'),
      );
      await _rejects(
        db,
        _version(
          'bad5',
          's1',
          no: 3,
          source: 'correction',
          reason: '卡号6222020200112',
        ),
      );
      final versions = await db
          .customSelect(
            "SELECT version_no, min_due_minor FROM statement_versions WHERE statement_id = 's1' "
            'ORDER BY version_no',
          )
          .get();
      expect(versions.map((r) => r.data).toList(), <Map<String, Object?>>[
        <String, Object?>{'version_no': 1, 'min_due_minor': 38000},
        <String, Object?>{'version_no': 2, 'min_due_minor': 38933},
      ]);
    });

    test('当前版本只能前移；到期日须晚于账单日；贷方余额与正的新余额不能并存；最低还款不超过新余额', () async {
      await _accepts(
        db,
        _version('v2', 's1', no: 2, source: 'correction', reason: '更正'),
      );
      await _accepts(
        db,
        "UPDATE statements SET current_version_id = 'v2' WHERE id = 's1'",
      );
      await _rejects(
        db,
        "UPDATE statements SET current_version_id = 'v1' WHERE id = 's1'",
      );
      await _rejects(
        db,
        "UPDATE statements SET current_version_id = NULL WHERE id = 's1'",
      );
      await _rejects(
        db,
        _version(
          'bad1',
          's1',
          no: 3,
          source: 'correction',
          reason: '到期早于账单日',
          due: '2026-10-10',
        ),
      );
      await _rejects(
        db,
        _version(
          'bad2',
          's1',
          no: 3,
          source: 'correction',
          reason: '贷方余额',
          creditBalance: 100,
          newBalance: 100,
        ),
      );
      await _rejects(
        db,
        _version(
          'bad3',
          's1',
          no: 3,
          source: 'correction',
          reason: '最低还款',
          newBalance: 100,
          minDue: 101,
        ),
      );
      // F-38：溢缴款——新余额为负、贷方余额为正，最低还款为 0。
      await _accepts(
        db,
        _version(
          'v3',
          's1',
          no: 3,
          source: 'correction',
          reason: '溢缴款',
          creditBalance: 10000,
          newBalance: -10000,
          minDue: 0,
        ),
      );
      // 当前版本指向别的账单的版本：延迟检查的复合外键在提交时拒绝。
      await _accepts(
        db,
        _statement('s2', date: '2026-11-10', due: '2026-11-28'),
      );
      await _accepts(db, _version('w1v', 's2', due: '2026-11-28'));
      await _rejects(
        db,
        "UPDATE statements SET current_version_id = 'w1v' WHERE id = 's1'",
      );
    });
  });

  test('账单：同一币种子账户同一账单日只有一份（F-21）；状态机（PRD §6.2）；账单日与归属不可改', () async {
    await _accepts(db, _statement('s1'));
    await _rejects(db, _statement('dup'));
    await _accepts(db, _statement('s2', account: 'cu'));
    await _rejects(db, _statement('bad1', due: '2026-10-10'));
    await _rejects(db, _statement('bad2', status: 'closed'));
    await _rejects(
      db,
      "UPDATE statements SET statement_date = '2026-10-11' WHERE id = 's1'",
    );
    await _rejects(
      db,
      "UPDATE statements SET currency_account_id = 'c2' WHERE id = 's1'",
    );
    // 合法：issued → amended → partially_settled → overdue → settled。
    for (final to in <String>[
      'amended',
      'partially_settled',
      'overdue',
      'settled',
    ]) {
      await _accepts(
        db,
        "UPDATE statements SET status = '$to' WHERE id = 's1'",
      );
    }
    // settled 是终态。
    for (final to in <String>['issued', 'amended', 'overdue']) {
      final message = await _rejects(
        db,
        "UPDATE statements SET status = '$to' WHERE id = 's1'",
      );
      expect(message, contains('statements: status transition not allowed'));
    }
    await _accepts(db, _statement('s3', date: '2026-11-10', due: '2026-11-28'));
    await _rejects(
      db,
      "UPDATE statements SET status = 'predicted' WHERE id = 's3'",
    );
    await _accepts(
      db,
      "UPDATE statements SET status = 'partially_settled' WHERE id = 's3'",
    );
    await _rejects(
      db,
      "UPDATE statements SET status = 'amended' WHERE id = 's3'",
    );
  });

  test('交易：按类型定符号、非零有界；卡片须属于该子账户的信用账户；币种与子账户一致；归属与类型不可改', () async {
    await _accepts(db, _txn('t1'));
    await _accepts(db, _txn('t2', type: 'refund', amount: -1500, parent: 't1'));
    await _accepts(db, _txn('t3', type: 'adjustment', amount: -1));
    await _accepts(db, _txn('t4', type: 'transfer', amount: 2));
    await _accepts(
      db,
      _txn('t5', card: null, postedOn: null, status: 'pending'),
    );
    await _rejects(db, _txn('bad1', amount: -100));
    await _rejects(db, _txn('bad2', type: 'refund', amount: 100));
    await _rejects(db, _txn('bad3', type: 'repayment', amount: 100));
    await _rejects(db, _txn('bad4', type: 'fee', amount: 0));
    await _rejects(db, _txn('bad5', amount: 10000000000001));
    await _rejects(db, _txn('bad6', type: 'cash_advance'));
    // 卡片 k2 属于另一个信用账户。
    final message = await _rejects(db, _txn('bad7', card: 'k2'));
    expect(message, contains('transactions: card not in the credit account'));
    // 子账户是 CNY，交易写 USD：复合外键拒绝。
    await _rejects(db, _txn('bad8', currency: 'USD'));
    // 原交易必须在同一币种子账户。
    await _rejects(
      db,
      _txn(
        'bad9',
        account: 'c2',
        card: 'k2',
        type: 'refund',
        amount: -1,
        parent: 't1',
      ),
    );
    await _rejects(db, _txn('bad10', merchant: '卡号6222020200112'));
    await _rejects(db, _txn('bad11', workspace: _w2, account: 'c1'));
    await _rejects(
      db,
      "UPDATE transactions SET currency_account_id = 'c2' WHERE id = 't1'",
    );
    await _rejects(
      db,
      "UPDATE transactions SET card_id = NULL WHERE id = 't1'",
    );
    await _rejects(
      db,
      "UPDATE transactions SET txn_type = 'fee' WHERE id = 't1'",
    );
    await _accepts(
      db,
      "UPDATE transactions SET deleted_at = '$_ts' WHERE id = 't4'",
    );
    await _rejects(
      db,
      "UPDATE transactions SET status = 'reversed' WHERE id = 't4'",
    );
  });

  test('分期：条款不可改、状态只能从进行中离开；各期只改状态（未出账 → 已出账 → 已结清）、期号不超过期数', () async {
    await _accepts(db, _txn('t1', amount: 1000000));
    await _accepts(db, _plan('p1'));
    await _rejects(db, _plan('dup'));
    await _accepts(db, _txn('t2', amount: 50000));
    for (final bad in <String>[
      _plan('bad1', txn: 't2', rate: '0.0060'),
      _plan('bad2', txn: 't2', rate: '1.5'),
      _plan('bad3', txn: 't2', rate: '-0.01'),
      _plan('bad4', txn: 't2', rate: '0.01x'),
      _plan('bad5', txn: 't2', periods: 0),
      _plan('bad6', txn: 't2', periods: 61),
      _plan('bad7', txn: 't2', feeMode: 'monthly'),
      _plan('bad8', txn: 't2', remainder: 'middle'),
      _plan('bad9', txn: 't2', rounding: 'DOWN'),
      _plan('bad10', txn: 't2', principal: 0),
    ]) {
      await _rejects(db, bad);
    }
    await _accepts(db, _plan('p2', txn: 't2', rate: '0', periods: 3));
    for (final set in <String>[
      'principal_minor = 1',
      'periods = 6',
      "per_period_rate = '0.007'",
      "fee_mode = 'upfront'",
      "remainder_policy = 'first'",
    ]) {
      await _rejects(db, "UPDATE installment_plans SET $set WHERE id = 'p1'");
    }
    await _rejects(
      db,
      "UPDATE installment_plans SET status = 'early_settled' WHERE id = 'p1'",
    );
    await _accepts(
      db,
      "UPDATE installment_plans SET status = 'early_settled', early_settled_at = '$_ts' "
      "WHERE id = 'p2'",
    );
    await _rejects(
      db,
      "UPDATE installment_plans SET status = 'active', early_settled_at = NULL WHERE id = 'p2'",
    );

    await _accepts(db, _period('p1', 1));
    await _accepts(
      db,
      _period('p1', 2, statement: '2026-11-10', due: '2026-11-28'),
    );
    await _rejects(db, _period('p1', 13));
    await _rejects(db, _period('p1', 3, due: '2026-10-10'));
    await _rejects(
      db,
      "UPDATE installment_schedule SET principal_minor = 1 WHERE plan_id = 'p1' AND period_no = 1",
    );
    await _rejects(
      db,
      "UPDATE installment_schedule SET status = 'settled' WHERE plan_id = 'p1' AND period_no = 1",
    );
    await _accepts(
      db,
      "UPDATE installment_schedule SET status = 'billed' WHERE plan_id = 'p1' AND period_no = 1",
    );
    await _accepts(
      db,
      "UPDATE installment_schedule SET status = 'settled' WHERE plan_id = 'p1' AND period_no = 1",
    );
    await _rejects(
      db,
      "UPDATE installment_schedule SET status = 'scheduled' WHERE plan_id = 'p1' AND period_no = 1",
    );
  });

  group('还款', () {
    const all = <String>[
      'recorded',
      'processing',
      'cash_debited',
      'credit_posted',
      'bank_confirmed',
      'failed',
      'user_marked_paid',
      'needs_review',
      'reversed',
    ];
    const allowed = <String, Set<String>>{
      'recorded': <String>{'processing', 'user_marked_paid'},
      'processing': <String>{'cash_debited', 'failed'},
      'cash_debited': <String>{'credit_posted'},
      'credit_posted': <String>{'bank_confirmed'},
      'failed': <String>{'recorded'},
      'user_marked_paid': <String>{'bank_confirmed', 'needs_review'},
      'needs_review': <String>{'bank_confirmed'},
      'bank_confirmed': <String>{'reversed'},
      'reversed': <String>{},
    };

    test('状态机（PRD §6.3）：每个状态到其余 8 个状态，只有登记的转移被接受', () async {
      var n = 0;
      for (final from in all) {
        for (final to in all) {
          if (from == to) {
            continue;
          }
          final id = 'r${n++}';
          await db.customStatement(
            _repayment(
              id,
              status: from,
              initiated: _ts,
              debited:
                  const <String>{'cash_debited', 'credit_posted'}.contains(from)
                  ? _ts
                  : null,
              credited: from == 'credit_posted' ? _ts : null,
              confirmed:
                  const <String>{'bank_confirmed', 'reversed'}.contains(from)
                  ? _ts
                  : null,
            ),
          );
          if (allowed[from]!.contains(to)) {
            await _accepts(db, _move(id, to));
          } else {
            final message = await _rejects(db, _move(id, to));
            expect(
              message,
              contains('repayments: status transition not allowed'),
              reason: '$from → $to',
            );
          }
        }
      }
      expect(n, 72);
    });

    test('状态要求的时点；金额、方式、归属与币种不可改；现金账户的币种须与还款一致；跨空间的现金账户被拒', () async {
      await _rejects(db, _repayment('bad1', status: 'processing'));
      await _rejects(
        db,
        _repayment('bad2', status: 'cash_debited', initiated: _ts),
      );
      await _rejects(
        db,
        _repayment('bad3', status: 'bank_confirmed', initiated: _ts),
      );
      await _rejects(db, _repayment('bad4', amount: 0));
      await _rejects(db, _repayment('bad5', method: 'cash'));
      await _rejects(db, _repayment('bad6', cash: 'cau'));
      await _rejects(db, _repayment('bad7', cash: 'cax'));
      await _rejects(db, _repayment('bad8', currency: 'USD'));
      await _accepts(db, _repayment('r1'));
      await _accepts(
        db,
        _repayment('r2', account: 'cu', currency: 'USD', cash: 'cau'),
      );
      await _accepts(db, _repayment('r3', cash: null));
      for (final set in <String>[
        'amount_minor = 1',
        "method = 'auto_debit'",
        "currency_account_id = 'c2'",
        "currency = 'USD'",
      ]) {
        await _rejects(db, "UPDATE repayments SET $set WHERE id = 'r1'");
      }
      await _accepts(
        db,
        "UPDATE repayments SET deleted_at = '$_ts' WHERE id = 'r3'",
      );
      await _rejects(
        db,
        "UPDATE repayments SET evidence_note = '已作废' WHERE id = 'r3'",
      );
    });

    test('分配：Σ ≤ 还款额（触发器兜底）；分配行不改只删了重写；还款与账单须同一币种子账户', () async {
      await _accepts(db, _statement('s1'));
      await _accepts(
        db,
        _statement('s2', date: '2026-11-10', due: '2026-11-28'),
      );
      await _accepts(db, _statement('sc2', account: 'c2'));
      await _accepts(db, _repayment('r1', amount: 100000));
      await _accepts(db, _allocation('r1', 's1', 60000));
      await _accepts(db, _allocation('r1', 's2', 40000));
      await _rejects(db, _allocation('r1', 'sc2', 1));
      await db.customStatement(
        "DELETE FROM repayment_allocations WHERE repayment_id = 'r1' AND statement_id = 's2'",
      );
      final message = await _rejects(db, _allocation('r1', 's2', 40001));
      expect(
        message,
        contains('repayment_allocations: total exceeds the repayment'),
      );
      await _rejects(
        db,
        "UPDATE repayment_allocations SET amount_minor = 1 WHERE repayment_id = 'r1'",
      );
      // 账单在另一个币种子账户：携带账户列的复合外键拒绝。
      await _rejects(db, _allocation('r1', 'sc2', 1, account: 'c2'));
    });
  });

  test('cash_events.linked_repayment_id（简报 §6 第 2 条）：插入与改写只能指向同一空间的还款；'
      '还款在仍有未删除的现金事件指向它时不能删除或作废', () async {
    await _accepts(db, _repayment('r1'));
    await _accepts(
      db,
      _repayment('rx', workspace: _w2, account: 'cx', cash: 'cax'),
    );
    final message = await _rejects(db, _cashEvent('bad1', repayment: 'nope'));
    expect(message, contains('cash_events: linked repayment not in workspace'));
    await _rejects(db, _cashEvent('bad2', repayment: 'rx'));
    await _accepts(db, _cashEvent('e1', repayment: 'r1'));
    await _accepts(db, _cashEvent('e2'));
    await _rejects(
      db,
      "UPDATE cash_events SET linked_repayment_id = 'rx' WHERE id = 'e2'",
    );
    await _rejects(
      db,
      "UPDATE cash_events SET linked_repayment_id = 'nope' WHERE id = 'e2'",
    );
    final deleted = await _rejects(
      db,
      "DELETE FROM repayments WHERE id = 'r1'",
    );
    expect(deleted, contains('repayments: live cash events still point to it'));
    await _rejects(
      db,
      "UPDATE repayments SET deleted_at = '$_ts' WHERE id = 'r1'",
    );
    // 事件作废（tombstone）之后才能删除或作废还款。
    await _accepts(
      db,
      "UPDATE cash_events SET deleted_at = '$_ts' WHERE id = 'e1'",
    );
    await _accepts(
      db,
      "UPDATE repayments SET deleted_at = '$_ts' WHERE id = 'r1'",
    );
    await _accepts(db, "DELETE FROM repayments WHERE id = 'r1'");
  });

  test('差异项：类型、refs 为 JSON 对象、同类同引用一条；只有未处理的能处理一次，不重开', () async {
    await _accepts(db, _item('i1'));
    await _rejects(db, _item('dup'));
    await _rejects(db, _item('bad1', kind: 'missing'));
    await _rejects(db, _item('bad2', refs: '[1, 2]'));
    await _rejects(db, _item('bad3', refs: 'not json'));
    await _accepts(
      db,
      _item('i2', kind: 'refund_pending', refs: '{"transaction_id":"t2"}'),
    );
    await _rejects(
      db,
      "UPDATE reconciliation_items SET status = 'resolved' WHERE id = 'i1'",
    );
    await _rejects(
      db,
      "UPDATE reconciliation_items SET status = 'resolved', resolution = 'maybe', "
      "resolved_by = 'user', resolved_at = '$_ts' WHERE id = 'i1'",
    );
    await _accepts(
      db,
      "UPDATE reconciliation_items SET status = 'resolved', resolution = 'distinct', "
      "resolved_by = 'user', resolved_at = '$_ts' WHERE id = 'i1'",
    );
    final message = await _rejects(
      db,
      "UPDATE reconciliation_items SET status = 'open', resolution = NULL, "
      "resolved_by = NULL, resolved_at = NULL WHERE id = 'i1'",
    );
    expect(
      message,
      contains('reconciliation_items: only an open item can be resolved once'),
    );
    await _rejects(
      db,
      "UPDATE reconciliation_items SET refs = '{}' WHERE id = 'i2'",
    );
  });
}
