// time 模块：LocalDate（公历算术，以 Dart DateTime.utc 为独立对照）、月末截断与跨年、
// Timestamp（自身偏移的日期、绝对时刻排序、Python isoformat 写法）。
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:test/test.dart';

void main() {
  group('LocalDate', () {
    test('epoch days agree with DateTime.utc for every day of 1900..2100 and the range ends', () {
      var day = DateTime.utc(1900);
      final end = DateTime.utc(2101);
      while (day.isBefore(end)) {
        final epochDay = day.millisecondsSinceEpoch ~/ 86400000;
        final date = LocalDate(day.year, day.month, day.day);
        expect(date.epochDay, epochDay);
        final back = LocalDate.fromEpochDay(epochDay);
        expect(
          (back.year, back.month, back.day),
          (day.year, day.month, day.day),
        );
        expect(date.isoWeekday, day.weekday);
        day = day.add(const Duration(days: 1));
      }
      expect(LocalDate(1, 1, 1).toString(), '0001-01-01');
      expect(
        LocalDate.fromEpochDay(LocalDate(9999, 12, 31).epochDay).toString(),
        '9999-12-31',
      );
    });

    test(
      'leaving 0001..9999 is a DateRangeError, like Python OverflowError',
      () {
        expect(
          () => LocalDate(9999, 12, 31).addDays(1),
          throwsA(isA<DateRangeError>()),
        );
        expect(
          () => LocalDate(1, 1, 1).addDays(-1),
          throwsA(isA<DateRangeError>()),
        );
        expect('${DateRangeError()}', 'date value out of range');
      },
    );

    test('strict ISO parsing and real calendar days', () {
      expect(LocalDate.parse('2024-02-29'), LocalDate(2024, 2, 29));
      for (final bad in [
        '2026-02-30',
        '2025-02-29',
        '20261016',
        '2026-1-01',
        '2026-10-16T00:00:00Z',
        ' 2026-10-16',
      ]) {
        expect(() => LocalDate.parse(bad), throwsFormatException, reason: bad);
      }
      expect(() => LocalDate(2026, 13, 1), throwsArgumentError);
    });

    test('leap years, month lengths, clamping and month addition', () {
      expect([2000, 2024, 1900, 2100, 2026].map(isLeapYear), [
        true,
        true,
        false,
        false,
        false,
      ]);
      expect(daysInMonth(2024, 2), 29);
      expect(daysInMonth(2025, 2), 28);
      expect(clampDay(2026, 4, 31), LocalDate(2026, 4, 30));
      expect(clampDay(2024, 2, 31), LocalDate(2024, 2, 29));
      expect(addMonths(LocalDate(2026, 12, 26), 1), (2027, 1));
      expect(addMonths(LocalDate(2026, 11, 26), 2), (2027, 1));
      expect(addMonths(LocalDate(2026, 1, 5), -1), (2025, 12));
    });

    test('ordering and differences', () {
      final a = LocalDate(2026, 10, 16);
      final b = LocalDate(2026, 11, 28);
      expect(b.differenceInDays(a), 43);
      expect(a < b && b > a && a <= a && a.compareTo(b) < 0, isTrue);
      expect(a.laterOf(b), b);
      expect(LocalDate(2026, 10, 10).isoWeekday, 6); // 周六
      expect(LocalDate(2026, 10, 11).isoWeekday, 7); // 周日
    });
  });

  group('Timestamp', () {
    test('the date is taken in the timestamp\'s own offset (R3E-14)', () {
      final t = Timestamp.parse('2026-10-27T23:30:00-05:00');
      expect(t.date, LocalDate(2026, 10, 27)); // UTC 已是 10-28
      expect(t.offsetMinutes, -300);
      expect(
        Timestamp.parse('2026-10-28T00:00:00+08:00').date,
        LocalDate(2026, 10, 28),
      );
    });

    test('ordering is by absolute instant; equal instants compare equal', () {
      final a = Timestamp.parse('2026-11-08T09:00:00+08:00'); // 01:00Z
      final b = Timestamp.parse('2026-11-08T02:00:00Z');
      final c = Timestamp.parse('2026-11-08T01:00:00Z');
      expect(a.compareTo(b) < 0, isTrue);
      expect(a.compareTo(c), 0);
      expect(a == c, isTrue);
      expect(
        Timestamp.parse('2026-10-16T09:00:00.000001Z').utcMicros -
            Timestamp.parse('2026-10-16T09:00:00Z').utcMicros,
        1,
      );
    });

    test('isoformat is Python datetime.isoformat()', () {
      expect(
        Timestamp.parse('2026-10-16T09:00:00Z').isoformat(),
        '2026-10-16T09:00:00+00:00',
      );
      expect(
        Timestamp.parse('2026-10-16T09:00:00.1Z').isoformat(),
        '2026-10-16T09:00:00.100000+00:00',
      );
      expect(
        Timestamp.parse('2026-10-16T09:00:00+23:59').isoformat(),
        '2026-10-16T09:00:00+23:59',
      );
      expect(
        Timestamp.parse('2026-10-16T09:00:00-05:30').isoformat(),
        '2026-10-16T09:00:00-05:30',
      );
    });

    test('rejects what RFC 3339 / protocol v1 rejects', () {
      for (final bad in [
        '2026-10-16T09:00:00',
        '2026-10-16T24:00:00Z',
        '2026-10-16T23:59:60Z',
        '2026-10-16T09:60:00Z',
        '2026-10-16T09:00:00+24:00',
        '2026-02-30T09:00:00Z',
        '2026-10-16T09:00:00.1234567Z',
        '2026-10-16t09:00:00z',
      ]) {
        expect(() => Timestamp.parse(bad), throwsFormatException, reason: bad);
      }
    });
  });
}
