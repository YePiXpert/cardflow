// 审查 R-I1 探针：大数据量下首页（总览）、账单读模型与资金日历的计算耗时（真实 sqlite3mc 加密库，
// flutter test 的 JIT/调试模式，数字偏保守）。全部合成数据。
// 运行：cd apps/mobile && flutter test ../../evidence/i1/review-i1/scripts/perf_probe_test.dart
import 'dart:math';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/ids.dart';
import 'package:cardflow/data/repositories/card_wallet_reader.dart';
import 'package:cardflow/data/repositories/cash_event_repository.dart';
import 'package:cardflow/data/repositories/cash_forecast_reader.dart';
import 'package:cardflow/data/repositories/cash_models.dart';
import 'package:cardflow/data/repositories/installment_repository.dart';
import 'package:cardflow/data/repositories/ledger_reader.dart';
import 'package:cardflow/data/repositories/recurring_item_repository.dart';
import 'package:cardflow/data/repositories/statement_repository.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../apps/mobile/test/data/repositories/repository_test_support.dart';

Future<int> _ms(Future<Object?> Function() f) async {
  final sw = Stopwatch()..start();
  await f();
  return sw.elapsedMilliseconds;
}

String _hex(Random r) =>
    List<String>.generate(64, (_) => r.nextInt(16).toRadixString(16)).join();

void main() {
  test('20 张卡、两年交易（每卡每天 1 笔 = 14,600 笔）、480 期账单、10 个分期、500 条现金事件', () async {
    final rnd = Random(20261019);
    final db = await openRealTestDatabase();
    final scope = await createTestWorkspace(db);
    final ws = scope.workspaceId;
    final subs = <String>[];
    final setup = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      final card = await createTestCard(scope, bank: '合成银行$i', last4: '${1000 + i}');
      await declareTestRule(
        scope,
        card.creditAccountId,
        statementDay: 3 + i,
        due: const DueRule.daysAfterStatement(days: 18),
      );
      final sub = (await primaryCurrencyAccount(scope, card.creditAccountId)).id;
      subs.add(sub);
      await recordTestSnapshot(scope, sub, fixed: 5000000, used: 1000000);
    }
    // 两年交易：2024-10-19 .. 2026-10-18，每卡每天一笔（原始 SQL 批量写入，字段与仓库写法相同）。
    final start = LocalDate(2024, 10, 19);
    await db.transaction(() async {
      for (var i = 0; i < 20; i++) {
        for (var d = 0; d < 730; d++) {
          final day = start.addDays(d);
          final id = newUuidV4();
          await db.customStatement(
            'INSERT INTO transactions (id, workspace_id, currency_account_id, txn_type, amount_minor, '
            'currency, txn_at, txn_tz, time_precision, posted_on, status, fingerprint, source_kind, '
            'confirmation_level, recorded_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            <Object>[
              id, ws, subs[i], 'purchase', 1000 + rnd.nextInt(90000), 'CNY',
              '${day}T12:00:00+08:00', 'Asia/Shanghai', 'datetime', day.toString(), 'posted',
              _hex(rnd), 'manual', 'user_confirmed', '${day}T12:00:00+08:00', '${day}T12:00:00+08:00',
            ],
          );
        }
      }
    });
    // 每卡 24 期账单（经仓库录入），较早的 23 期用一笔银行确认的还款结清（原始 SQL）。
    final statements = StatementRepository(scope);
    for (var i = 0; i < 20; i++) {
      for (var m = 0; m < 24; m++) {
        final (y, mo) = addMonths(LocalDate(2024, 11, 1), m);
        final sd = LocalDate(y, mo, 3 + i);
        if (sd > LocalDate(2026, 10, 18)) {
          continue;
        }
        final s = await statements.recordIssued(
          StatementEntryDraft(
            currencyAccountId: subs[i],
            statementDate: sd,
            dueDate: sd.addDays(18),
            figures: StatementFigures(newBalanceMinor: 1500000 + m, minDueMinor: 150000),
          ),
        );
        if (sd.addDays(18) < LocalDate(2026, 10, 1)) {
          final rid = newUuidV4();
          final ts = '${sd.addDays(15)}T10:00:00+08:00';
          await db.customStatement(
            'INSERT INTO repayments (id, workspace_id, currency_account_id, amount_minor, currency, status, '
            'method, payment_initiated_at, cash_debited_at, credit_posted_at, bank_confirmed_at, created_at, '
            "updated_at) VALUES (?, ?, ?, ?, 'CNY', 'bank_confirmed', 'manual', ?, ?, ?, ?, ?, ?)",
            <Object>[rid, ws, subs[i], 1500000 + m, ts, ts, ts, ts, ts, ts],
          );
          await db.customStatement(
            'INSERT INTO repayment_allocations (workspace_id, currency_account_id, repayment_id, statement_id, '
            'amount_minor) VALUES (?, ?, ?, ?, ?)',
            <Object>[ws, subs[i], rid, s.id, 1500000 + m],
          );
          await db.customStatement(
            "UPDATE statements SET status = 'settled' WHERE id = ?",
            <Object>[s.id],
          );
        }
      }
    }
    // 10 个分期（5 个 12 期、3 个 24 期、2 个 36 期），各由一笔最近的大额消费转成。
    final installments = InstallmentRepository(scope);
    final periodsList = <int>[12, 12, 12, 12, 12, 24, 24, 24, 36, 36];
    for (var k = 0; k < periodsList.length; k++) {
      final txn = await addTestTransaction(
        scope,
        subs[k],
        amount: 2400000 + k,
        txnAt: '2026-10-17T10:00:00+08:00',
      );
      await installments.create(
        InstallmentDraft(
          transactionId: txn.id,
          periods: periodsList[k],
          perPeriodRate: Rational.parseDecimal('0.006'),
        ),
      );
    }
    // 现金：3 个账户、今天的快照、500 条收支（-20..+180 天）、3 个周期事项。
    final cashIds = <String>[];
    for (var c = 0; c < 3; c++) {
      final a = await createTestCashAccount(scope, name: '合成现金$c', reserve: 100000);
      cashIds.add(a.id);
    }
    final events = CashEventRepository(scope);
    final today = LocalDate(2026, 10, 18);
    for (var e = 0; e < 500; e++) {
      final on = today.addDays(-20 + rnd.nextInt(200));
      final income = rnd.nextInt(5) == 0;
      await events.create(
        CashEventDraft(
          cashAccountId: cashIds[e % 3],
          type: income ? CashPlanType.income : CashPlanType.living,
          cls: on < today ? CashEventClass.confirmed : CashEventClass.expected,
          on: on,
          amountMinor: income ? 500000 + rnd.nextInt(500000) : 1000 + rnd.nextInt(200000),
        ),
      );
    }
    for (var c = 0; c < 3; c++) {
      await recordTestCashSnapshot(scope, cashIds[c], today, 8000000, observedAt: '2026-10-18T09:00:00+08:00');
      await RecurringItemRepository(scope).create(
        RecurringItemDraft(
          cashAccountId: cashIds[c],
          label: '合成周期$c',
          type: CashPlanType.living,
          cls: CashEventClass.confirmed,
          amountMinor: 300000,
          frequency: RecurringFrequency.monthly,
          startOn: LocalDate(2026, 10, 27),
        ),
      );
    }
    setup.stop();
    print('PERF 数据准备完成（${setup.elapsedMilliseconds} ms）：'
        'transactions=${(await db.customSelect('SELECT COUNT(*) AS n FROM transactions').getSingle()).read<int>('n')} '
        'statements=${(await db.customSelect('SELECT COUNT(*) AS n FROM statements').getSingle()).read<int>('n')} '
        'repayments=${(await db.customSelect('SELECT COUNT(*) AS n FROM repayments').getSingle()).read<int>('n')} '
        'installment_periods=${(await db.customSelect('SELECT COUNT(*) AS n FROM installment_schedule').getSingle()).read<int>('n')} '
        'cash_events=${(await db.customSelect('SELECT COUNT(*) AS n FROM cash_events').getSingle()).read<int>('n')}');

    for (var run = 1; run <= 3; run++) {
      final wallet = await _ms(() => CardWalletReader(scope).load());
      late LedgerData data;
      final ledger = await _ms(() async => data = await LedgerReader(scope).load());
      final c30 = await _ms(() => CashForecastReader(scope).forecast(const CashForecastQuery()));
      final c180 = await _ms(
        () => CashForecastReader(scope).forecast(const CashForecastQuery(windowDays: 180)),
      );
      final board = await _ms(() => ScenarioBoard.load(scope));
      final sw = Stopwatch()..start();
      for (final p in data.plans) {
        data.costOf(p);
      }
      final costs = sw.elapsedMilliseconds;
      sw.reset();
      for (final s in data.statements) {
        data.transactionsOf(s.id);
        data.openItemsOf(s.id);
      }
      final perStatement = sw.elapsedMilliseconds;
      print('PERF 第 $run 次：CardWalletReader.load=$wallet ms；LedgerReader.load=$ledger ms；'
          '资金日历 30 天=$c30 ms；180 天=$c180 ms；ScenarioBoard.load=$board ms；'
          '10 个分期成本（IRR）=$costs ms；480 期账单逐期取交易与差异=$perStatement ms');
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
