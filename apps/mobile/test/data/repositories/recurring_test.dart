// 周期事项（R-CASH-02，真实 sqlite3mc）：各期的生成（每月/每年的月末截断与闰年、每周/每两周、起止日）、
// 按需展开到"今天 + 180 天"（幂等，没有要补的期时不写库；早于最新快照日的期不展开）、单期覆盖/跳过/
// 恢复不影响他期、修改（同一规则就地更新；改规则重新展开）、停用与重新启用、已发生的期不能再改。
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/mapping/cash_mapping.dart';
import 'package:cardflow/data/repositories/cash_event_repository.dart';
import 'package:cardflow/data/repositories/cash_forecast_reader.dart';
import 'package:cardflow/data/repositories/cash_models.dart';
import 'package:cardflow/data/repositories/recurring_item_repository.dart';
import 'package:cardflow/data/repositories/repository_errors.dart';
import 'package:cardflow/data/repositories/scenario_repository.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repository_test_support.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

List<String> dates(Iterable<LocalDate> list) => [for (final x in list) '$x'];

void main() {
  group('各期的生成', () {
    test('每月"同一日"：小月截到月末，闰年 2 月 29 日', () {
      final schedule = RecurringSchedule(
        frequency: RecurringFrequency.monthly,
        anchorOn: d(2027, 12, 31),
        startOn: d(2027, 12, 31),
      );
      expect(
        dates(recurringOccurrences(schedule, d(2027, 12, 1), d(2028, 5, 1))),
        ['2027-12-31', '2028-01-31', '2028-02-29', '2028-03-31', '2028-04-30'],
      );
    });

    test('每月"最后一天"；每年（2 月 29 日在平年是 2 月 28 日）', () {
      final monthEnd = RecurringSchedule(
        frequency: RecurringFrequency.monthly,
        anchorOn: d(2026, 1, 15),
        startOn: d(2026, 1, 15),
        dayRule: DayRule.monthEnd,
      );
      expect(
        dates(recurringOccurrences(monthEnd, d(2026, 1, 1), d(2026, 4, 30))),
        ['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30'],
      );
      final yearly = RecurringSchedule(
        frequency: RecurringFrequency.yearly,
        anchorOn: d(2024, 2, 29),
        startOn: d(2024, 2, 29),
      );
      expect(
        dates(recurringOccurrences(yearly, d(2025, 1, 1), d(2028, 12, 31))),
        ['2025-02-28', '2026-02-28', '2027-02-28', '2028-02-29'],
      );
    });

    test('每周/每两周从锚定日起；只取 [起始日, 结束日] 与查询区间的交集', () {
      final weekly = RecurringSchedule(
        frequency: RecurringFrequency.weekly,
        anchorOn: d(2026, 10, 2),
        startOn: d(2026, 10, 2),
      );
      expect(
        dates(recurringOccurrences(weekly, d(2026, 10, 10), d(2026, 10, 31))),
        ['2026-10-16', '2026-10-23', '2026-10-30'],
      );
      final biweekly = RecurringSchedule(
        frequency: RecurringFrequency.biweekly,
        anchorOn: d(2026, 10, 2),
        startOn: d(2026, 10, 16),
        endOn: d(2026, 11, 13),
      );
      expect(
        dates(recurringOccurrences(biweekly, d(2026, 9, 1), d(2026, 12, 31))),
        ['2026-10-16', '2026-10-30', '2026-11-13'],
      );
      expect(
        recurringOccurrences(biweekly, d(2026, 12, 1), d(2026, 12, 31)),
        isEmpty,
      );
    });
  });

  group('展开与单期例外', () {
    late AppDatabase db;
    late WorkspaceScope scope;
    late RecurringItemRepository items;
    late CashAccountRow account;

    setUp(() async {
      db = await openRealTestDatabase();
      scope = await createTestWorkspace(db);
      items = RecurringItemRepository(scope);
      account = await createTestCashAccount(scope);
    });

    RecurringItemDraft rent({
      int amount = 100000,
      LocalDate? start,
      RecurringFrequency frequency = RecurringFrequency.monthly,
      DayRule dayRule = DayRule.anchorDay,
      CashEventClass cls = CashEventClass.confirmed,
      LocalDate? end,
    }) => RecurringItemDraft(
      cashAccountId: account.id,
      label: '房租',
      type: CashPlanType.living,
      cls: cls,
      amountMinor: amount,
      frequency: frequency,
      startOn: start ?? d(2026, 10, 27),
      dayRule: dayRule,
      endOn: end,
    );

    Future<List<String>> liveOccurrenceDates(String itemId) async => [
      for (final o in await items.occurrences(itemId))
        if (o.event != null) o.event!.eventOn,
    ];

    test('新建即展开到今天 + 180 天（2027-04-16）；重复展开不写库；每期的金额、类别与期键', () async {
      final item = await items.create(rent());
      expect(await liveOccurrenceDates(item.id), [
        '2026-10-27',
        '2026-11-27',
        '2026-12-27',
        '2027-01-27',
        '2027-02-27',
        '2027-03-27',
      ]);
      expect(await items.expandUntil(d(2027, 4, 16)), 0);
      expect(await items.expandUntil(d(2027, 5, 31)), 2);
      final first = (await items.occurrences(item.id)).first.event!;
      expect(
        (
          first.amountMinor,
          first.category,
          first.cls,
          first.label,
          first.occurrenceKey,
        ),
        (-100000, 'living', 'confirmed', '房租', '2026-10-27'),
      );
      // 资金日历读到的就是这些事件。
      final inputs = await CashForecastReader(scope).loadInputs();
      expect(inputs.events.where((e) => e.label == '房租'), hasLength(8));
    });

    test('早于最新快照日的期已反映在余额里，不再展开', () async {
      await recordTestCashSnapshot(scope, account.id, d(2026, 10, 16), 500000);
      final item = await items.create(
        rent(start: d(2026, 10, 2), frequency: RecurringFrequency.weekly),
      );
      final occurrences = await liveOccurrenceDates(item.id);
      expect(occurrences.first, '2026-10-16');
      expect(occurrences, isNot(contains('2026-10-09')));
    });

    test('单期跳过/覆盖/恢复只影响那一期；跳过的期不会被重新展开', () async {
      final item = await items.create(rent());
      await items.skip(item.id, d(2026, 11, 27));
      await items.overrideOccurrence(
        item.id,
        d(2026, 12, 27),
        amountMinor: 120000,
      );
      await items.overrideOccurrence(
        item.id,
        d(2027, 1, 27),
        on: d(2027, 1, 28),
        at: Timestamp.parse('2027-01-28T09:00:00+08:00'),
      );
      expect(await items.expandUntil(d(2027, 4, 16)), 0, reason: '跳过的期不再展开');
      final byKey = {
        for (final o in await items.occurrences(item.id)) '${o.key}': o,
      };
      expect(byKey['2026-11-27']!.skipped, isTrue);
      expect(byKey['2026-11-27']!.event, isNull);
      expect(byKey['2026-12-27']!.event!.amountMinor, -120000);
      expect(
        (
          byKey['2027-01-27']!.event!.eventOn,
          byKey['2027-01-27']!.event!.eventAt,
        ),
        ('2027-01-28', '2027-01-28T09:00:00+08:00'),
      );
      for (final key in ['2026-10-27', '2027-02-27', '2027-03-27']) {
        expect(byKey[key]!.event!.amountMinor, -100000, reason: key);
        expect(byKey[key]!.event!.eventOn, key);
        expect(byKey[key]!.override, isNull);
      }

      await items.restore(item.id, d(2026, 11, 27));
      await items.restore(item.id, d(2026, 12, 27));
      final restored = {
        for (final o in await items.occurrences(item.id)) '${o.key}': o,
      };
      expect(restored['2026-11-27']!.event!.amountMinor, -100000);
      expect(restored['2026-12-27']!.event!.amountMinor, -100000);
      expect(restored['2027-01-27']!.overridden, isTrue);

      // 不是周期里的一期、覆盖什么都没填：拒绝。
      await expectRepositoryError<ValidationException>(
        () => items.skip(item.id, d(2026, 11, 28)),
      );
      await expectRepositoryError<ValidationException>(
        () => items.overrideOccurrence(item.id, d(2027, 2, 27)),
      );
      // 周期事项的单期不能当普通收支删除或修改。
      final event = restored['2027-02-27']!.event!;
      await expectRepositoryError<ConflictException>(
        () => CashEventRepository(scope).delete(event.id),
      );
      await expectRepositoryError<ConflictException>(
        () => CashEventRepository(scope).update(event.id, amountMinor: 1),
      );
    });

    test('已发生的期不能跳过或覆盖', () async {
      // 有 10-16 的快照：10-17 那一期（今天之前）也要展开。
      await recordTestCashSnapshot(scope, account.id, d(2026, 10, 16), 500000);
      final item = await items.create(rent(start: d(2026, 10, 17)));
      final first = (await items.occurrences(item.id)).first;
      expect(first.key, d(2026, 10, 17));
      await CashEventRepository(scope).markPosted(first.event!.id);
      await expectRepositoryError<ConflictException>(
        () => items.skip(item.id, d(2026, 10, 17)),
      );
      await expectRepositoryError<ConflictException>(
        () =>
            items.overrideOccurrence(item.id, d(2026, 10, 17), amountMinor: 1),
      );
    });

    test('修改：同一规则时今天之后未发生、未覆盖金额的期就地更新；改规则时重新展开并清除今天之后的例外', () async {
      await recordTestCashSnapshot(scope, account.id, d(2026, 10, 16), 500000);
      final item = await items.create(rent(start: d(2026, 10, 17)));
      final first = (await items.occurrences(item.id)).first.event!;
      await items.overrideOccurrence(
        item.id,
        d(2026, 12, 17),
        amountMinor: 150000,
      );
      await items.update(item.id, rent(start: d(2026, 10, 17), amount: 110000));
      var byKey = {
        for (final o in await items.occurrences(item.id)) '${o.key}': o.event,
      };
      expect(byKey['2026-10-17']!.amountMinor, -100000, reason: '今天及以前的期不变');
      expect(byKey['2026-10-17']!.id, first.id);
      expect(byKey['2026-11-17']!.amountMinor, -110000);
      expect(byKey['2026-12-17']!.amountMinor, -150000, reason: '覆盖了金额的期保留覆盖');

      await items.update(item.id, rent(start: d(2026, 10, 20), amount: 110000));
      byKey = {
        for (final o in await items.occurrences(item.id)) '${o.key}': o.event,
      };
      expect(byKey.keys.toList()..sort(), [
        '2026-10-17',
        '2026-10-20',
        '2026-11-20',
        '2026-12-20',
        '2027-01-20',
        '2027-02-20',
        '2027-03-20',
      ]);
      expect(await items.overridesOf(item.id), isEmpty);
    });

    test('停用：今天之后未发生的期作废；重新启用后重新展开', () async {
      final item = await items.create(rent());
      await items.setActive(item.id, false);
      expect(await liveOccurrenceDates(item.id), isEmpty);
      expect(await items.expandUntil(d(2027, 4, 16)), 0);
      await items.setActive(item.id, true);
      expect(await liveOccurrenceDates(item.id), hasLength(6));
    });

    test('校验：名称必填、层级确定或预计、金额为正、按周不能选月末、结束日不早于第一期', () async {
      Future<String> field(RecurringItemDraft draft) async =>
          (await expectRepositoryError<ValidationException>(
            () => items.create(draft),
          )).field;
      expect(
        await field(
          RecurringItemDraft(
            cashAccountId: account.id,
            label: ' ',
            type: CashPlanType.living,
            cls: CashEventClass.confirmed,
            amountMinor: 1,
            frequency: RecurringFrequency.monthly,
            startOn: d(2026, 10, 27),
          ),
        ),
        'label',
      );
      expect(await field(rent(cls: CashEventClass.planned)), 'cls');
      expect(await field(rent(amount: 0)), 'amount');
      expect(
        await field(
          rent(frequency: RecurringFrequency.weekly, dayRule: DayRule.monthEnd),
        ),
        'dayRule',
      );
      expect(await field(rent(end: d(2026, 10, 26))), 'endOn');
    });

    test('情景覆盖指向的单期被跳过后"未生效"，不交给领域包', () async {
      await recordTestCashSnapshot(scope, account.id, d(2026, 10, 17), 500000);
      final item = await items.create(rent());
      final target = (await items.occurrences(item.id))[1].event!;
      final scenario = await ScenarioRepository(scope).create(
        ScenarioDraft(
          name: '房租推迟',
          eventOverrides: [
            EventOverrideSpec(eventId: target.id, on: d(2026, 12, 1)),
          ],
        ),
      );
      await items.skip(item.id, d(2026, 11, 27));
      final inputs = await CashForecastReader(scope).loadInputs();
      final forecast = forecastFrom(
        inputs,
        ScenarioView.fromRow(scenario),
        windowDays: 90,
      );
      expect(forecast.inactiveOverrides.map((o) => o.eventId), [target.id]);
      expect(forecast.assumptions.last, contains('未生效'));
    });
  });
}
