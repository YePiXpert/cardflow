// 情景与情景计算版本（R-CASH-04、P-09，真实 sqlite3mc）：内置两条（未计算前不写库）只读；压力情景的
// 校验边界（延迟 0–180、收入比例 0–100%、支出比例 100%–1000%、至多 10 位小数、名称唯一且不与内置同名、
// 额度变化须账户与日期、事件覆盖、按时刻排序须所有事件有时刻）；「重算」生成新版本、旧版本保留；输入
// 变化后"过期"；两版本/两情景对比；删除情景连同版本。
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/mapping/cash_mapping.dart';
import 'package:cardflow/data/repositories/cash_forecast_reader.dart';
import 'package:cardflow/data/repositories/cash_models.dart';
import 'package:cardflow/data/repositories/repository_errors.dart';
import 'package:cardflow/data/repositories/scenario_repository.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repository_test_support.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

Rational dec(String text) => Rational.parseDecimal(text);

void main() {
  late AppDatabase db;
  late WorkspaceScope scope;
  late ScenarioRepository scenarios;

  setUp(() async {
    db = await openRealTestDatabase();
    scope = await createTestWorkspace(db);
    scenarios = ScenarioRepository(scope);
  });

  test('内置"已确认""基准预期"总在最前；第一次计算前不写库；只读', () async {
    final list = await scenarios.list();
    expect(list.map((s) => (s.kind, s.name)), [
      (ScenarioKind.builtinConfirmed, '已确认'),
      (ScenarioKind.builtinBaseline, '基准预期'),
    ]);
    expect(list.every((s) => s.row == null), isTrue);
    expect(await scenarios.rows(), isEmpty);
    expect(list[0].params.includeExpected, isFalse);
    expect(list[1].params.includeExpected, isTrue);

    final row = await scenarios.ensureBuiltin(ScenarioKind.builtinConfirmed);
    expect(
      (await scenarios.ensureBuiltin(ScenarioKind.builtinConfirmed)).id,
      row.id,
    );
    await expectRepositoryError<ConflictException>(
      () => scenarios.update(row.id, const ScenarioDraft(name: '改')),
    );
    await expectRepositoryError<ConflictException>(
      () => scenarios.delete(row.id),
    );
    expect(
      (await scenarios.byKey(
        ScenarioView.builtinKey(ScenarioKind.builtinBaseline),
      ))!.row,
      isNull,
    );
  });

  group('压力情景的校验边界', () {
    Future<String> rejected(ScenarioDraft draft) async =>
        (await expectRepositoryError<ValidationException>(
          () => scenarios.create(draft),
        )).field;

    test('收入延迟 0–180 天', () async {
      expect(
        await rejected(const ScenarioDraft(name: 'a', incomeDelayDays: -1)),
        'incomeDelayDays',
      );
      expect(
        await rejected(const ScenarioDraft(name: 'b', incomeDelayDays: 181)),
        'incomeDelayDays',
      );
      await scenarios.create(
        const ScenarioDraft(name: 'c', incomeDelayDays: 0),
      );
      await scenarios.create(
        const ScenarioDraft(name: 'd', incomeDelayDays: 180),
      );
    });

    test('收入比例 0%–100%、支出比例 100%–1000%，至多 10 位小数，存规范十进制文本', () async {
      expect(
        await rejected(ScenarioDraft(name: 'a', incomeScale: dec('-0.01'))),
        'incomeScale',
      );
      expect(
        await rejected(ScenarioDraft(name: 'b', incomeScale: dec('1.01'))),
        'incomeScale',
      );
      expect(
        await rejected(ScenarioDraft(name: 'c', expenseScale: dec('0.99'))),
        'expenseScale',
      );
      expect(
        await rejected(ScenarioDraft(name: 'd', expenseScale: dec('10.01'))),
        'expenseScale',
      );
      expect(
        await rejected(
          ScenarioDraft(name: 'e', incomeScale: dec('0.12345678901')),
        ),
        'incomeScale',
      );
      final zero = await scenarios.create(
        ScenarioDraft(name: 'f', incomeScale: dec('0')),
      );
      final edge = await scenarios.create(
        ScenarioDraft(
          name: 'g',
          incomeScale: dec('0.1234567891'),
          expenseScale: dec('10.000'),
        ),
      );
      final plain = await scenarios.create(
        ScenarioDraft(
          name: 'h',
          incomeScale: dec('0.50'),
          expenseScale: dec('1.2'),
        ),
      );
      expect((zero.incomeScale, zero.expenseScale), ('0', '1'));
      expect((edge.incomeScale, edge.expenseScale), ('0.1234567891', '10'));
      expect((plain.incomeScale, plain.expenseScale), ('0.5', '1.2'));
    });

    test('名称必填、唯一、不与内置同名', () async {
      expect(await rejected(const ScenarioDraft(name: ' ')), 'name');
      expect(await rejected(const ScenarioDraft(name: '基准预期')), 'name');
      await scenarios.create(const ScenarioDraft(name: '收入推迟'));
      await expectRepositoryError<ConflictException>(
        () => scenarios.create(const ScenarioDraft(name: '收入推迟')),
      );
    });

    test('额度变化须信用账户与日期、非零；事件覆盖须指向现存事件、一次、同号', () async {
      final card = await createTestCard(scope);
      expect(
        await rejected(
          ScenarioDraft(
            name: 'a',
            limitChanges: [
              LimitChangeSpec(
                creditAccountId: 'nope',
                on: d(2026, 11, 1),
                changeMinor: -100,
              ),
            ],
          ),
        ),
        'limitChanges',
      );
      expect(
        await rejected(
          ScenarioDraft(
            name: 'b',
            limitChanges: [
              LimitChangeSpec(
                creditAccountId: card.creditAccountId,
                on: d(2026, 11, 1),
                changeMinor: 0,
              ),
            ],
          ),
        ),
        'limitChanges',
      );
      final limited = await scenarios.create(
        ScenarioDraft(
          name: '降额',
          limitChanges: [
            LimitChangeSpec(
              creditAccountId: card.creditAccountId,
              on: d(2026, 11, 1),
              changeMinor: -500000,
            ),
          ],
        ),
      );
      expect(
        ScenarioParams.fromRow(limited).limitChanges.single.changeMinor,
        -500000,
      );

      final acc = await createTestCashAccount(scope);
      final income = await addTestCashEvent(
        scope,
        acc.id,
        d(2026, 11, 6),
        850000,
      );
      expect(
        await rejected(
          const ScenarioDraft(
            name: 'c',
            eventOverrides: [
              EventOverrideSpec(eventId: 'nope', amountMinor: 1),
            ],
          ),
        ),
        'eventOverrides',
      );
      expect(
        await rejected(
          ScenarioDraft(
            name: 'd',
            eventOverrides: [
              EventOverrideSpec(eventId: income.id, amountMinor: -1),
            ],
          ),
        ),
        'eventOverrides',
      );
      expect(
        await rejected(
          ScenarioDraft(
            name: 'e',
            eventOverrides: [
              EventOverrideSpec(eventId: income.id, amountMinor: 1),
              EventOverrideSpec(eventId: income.id, on: d(2026, 11, 9)),
            ],
          ),
        ),
        'eventOverrides',
      );
      final moved = await scenarios.create(
        ScenarioDraft(
          name: '工资推迟',
          eventOverrides: [
            EventOverrideSpec(
              eventId: income.id,
              on: d(2026, 11, 29),
              amountMinor: 0,
            ),
          ],
        ),
      );
      expect(
        ScenarioParams.fromRow(moved).eventOverrides.single,
        EventOverrideSpec(
          eventId: income.id,
          on: d(2026, 11, 29),
          amountMinor: 0,
        ),
      );
    });

    test('按时刻排序须所有收支都有时刻', () async {
      final acc = await createTestCashAccount(scope);
      await addTestCashEvent(
        scope,
        acc.id,
        d(2026, 11, 6),
        850000,
        at: Timestamp.parse('2026-11-06T09:00:00+08:00'),
      );
      await scenarios.create(
        const ScenarioDraft(
          name: '按时刻',
          sameDayOrder: SameDayOrderChoice.timestamp,
        ),
      );
      await addTestCashEvent(scope, acc.id, d(2026, 11, 8), -500000);
      final error = await expectRepositoryError<ValidationException>(
        () => scenarios.create(
          const ScenarioDraft(
            name: '按时刻 2',
            sameDayOrder: SameDayOrderChoice.timestamp,
          ),
        ),
      );
      expect(error.field, 'sameDayOrder');
      expect(error.message, contains('还有 1 笔没有时刻'));
    });
  });

  group('重算、版本与对比', () {
    late CashAccountRow acc;

    setUp(() async {
      acc = await createTestCashAccount(scope, reserve: 200000);
      await recordTestCashSnapshot(scope, acc.id, d(2026, 10, 17), 500000);
      await addTestCashEvent(scope, acc.id, d(2026, 10, 27), -100000);
      await addTestCashEvent(
        scope,
        acc.id,
        d(2026, 11, 6),
        850000,
        cls: CashEventClass.expected,
      );
      await addTestCashEvent(scope, acc.id, d(2026, 11, 8), -500000);
    });

    test('「重算」生成新版本（区间 今天 至 今天 + 180 天），旧版本保留；内置情景第一次计算时写库', () async {
      final reader = CashForecastReader(scope);
      final v1 = await reader.recompute(
        ScenarioView.builtinKey(ScenarioKind.builtinConfirmed),
      );
      expect(
        (v1.versionNo, v1.horizonFrom, v1.horizonTo),
        (1, '2026-10-18', '2027-04-16'),
      );
      final confirmedRow = (await scenarios.rows()).single;
      expect(confirmedRow.kind, 'builtin_confirmed');
      final result = CashRunResult.parse(v1.result);
      final account = result.accounts.single;
      // 已确认口径：5,000 − 1,000 − 5,000 = −1,000（11-08），预计收入不计；10-27 的 4,000 高于储备 2,000。
      expect((account.minBalance, account.minOn), (-100000, d(2026, 11, 8)));
      expect(account.breaches.map((b) => b.on), [d(2026, 11, 8)]);
      expect(result.gapCount, 1);

      await addTestCashEvent(scope, acc.id, d(2026, 10, 28), -50000);
      final v2 = await reader.recompute(confirmedRow.id);
      expect(v2.versionNo, 2);
      expect((await scenarios.runs(confirmedRow.id)).map((r) => r.versionNo), [
        2,
        1,
      ]);
      final again = CashRunResult.parse(v2.result).accounts.single;
      expect(again.minBalance, -150000);

      final rows = compareRuns(result, CashRunResult.parse(v2.result));
      expect(rows.single.name, '工资卡');
      expect(rows.single.minDelta, -50000);
      expect(rows.single.gapDelta, 0);
    });

    test('输入变化后"过期"：数据（新事件）或情景参数变了；不变时不过期（即使过了一天）', () async {
      final row = await scenarios.create(
        const ScenarioDraft(name: '收入推迟', incomeDelayDays: 3),
      );
      final reader = CashForecastReader(scope);
      final run = await reader.recompute(row.id);
      var inputs = await reader.loadInputs();
      var view = (await scenarios.byKey(row.id))!;
      expect(reader.isRunStale(inputs, view, run), isFalse);

      final tomorrow = WorkspaceScope(
        db: db,
        workspaceId: scope.workspaceId,
        clock: StaleAwareClock(DateTime.utc(2026, 10, 19, 4)),
      );
      final nextDay = CashForecastReader(tomorrow);
      expect(
        nextDay.isRunStale(await nextDay.loadInputs(), view, run),
        isFalse,
      );

      await scenarios.update(
        row.id,
        const ScenarioDraft(name: '收入推迟', incomeDelayDays: 5),
      );
      view = (await scenarios.byKey(row.id))!;
      expect(reader.isRunStale(inputs, view, run), isTrue);

      final run2 = await reader.recompute(row.id);
      inputs = await reader.loadInputs();
      expect(reader.isRunStale(inputs, view, run2), isFalse);
      await addTestCashEvent(scope, acc.id, d(2026, 12, 1), -1000);
      inputs = await reader.loadInputs();
      expect(reader.isRunStale(inputs, view, run2), isTrue);
    });

    test('两个情景并排对比：收入延迟 3 天让 11-08 的最低点变差', () async {
      final reader = CashForecastReader(scope);
      final baseline = await reader.recompute(
        ScenarioView.builtinKey(ScenarioKind.builtinBaseline),
      );
      final row = await scenarios.create(
        const ScenarioDraft(name: '收入推迟', incomeDelayDays: 3),
      );
      final stress = await reader.recompute(row.id);
      final a = CashRunResult.parse(baseline.result);
      final b = CashRunResult.parse(stress.result);
      expect(a.accounts.single.minBalance, 400000);
      expect(b.accounts.single.minBalance, -100000);
      expect(b.accounts.single.minOn, d(2026, 11, 8));
      final rows = compareRuns(a, b);
      expect(rows.single.minDelta, -500000);
      expect(rows.single.gapDelta, 1);
    });

    test('删除压力情景连同它的全部版本', () async {
      final row = await scenarios.create(
        const ScenarioDraft(name: '收入推迟', incomeDelayDays: 3),
      );
      final reader = CashForecastReader(scope);
      await reader.recompute(row.id);
      await reader.recompute(row.id);
      expect(await scenarios.delete(row.id), 2);
      expect(await scenarios.byKey(row.id), isNull);
      expect(await scenarios.allRuns(), isEmpty);
    });
  });
}
