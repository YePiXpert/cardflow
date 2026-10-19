// 审查 R-I1 探针：日期边界性质（随机 + 边界），与独立写法逐一比较。
// 1) 周期事项展开 recurringOccurrences：按天枚举的暴力判定（月末、闰年、世纪年、跨年、起止日）；
// 2) 业务日期 businessDateOf / 截止时点 postingDateOf / timestampTextIn：用 DateTime(UTC+偏移) 独立计算。
// 运行：cd apps/mobile && flutter test ../../evidence/i1/review-i1/scripts/date_props_probe_test.dart
import 'dart:math';

import 'package:cardflow/data/repositories/cash_models.dart';
import 'package:cardflow/data/repositories/recurring_item_repository.dart';
import 'package:cardflow/data/time/business_tz.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter_test/flutter_test.dart';

bool _isOccurrence(RecurringSchedule s, LocalDate d) {
  final a = s.anchorOn;
  if (d < a) {
    return false;
  }
  switch (s.frequency) {
    case RecurringFrequency.weekly:
      return d.differenceInDays(a) % 7 == 0;
    case RecurringFrequency.biweekly:
      return d.differenceInDays(a) % 14 == 0;
    case RecurringFrequency.monthly:
      final dim = daysInMonth(d.year, d.month);
      final target = s.dayRule == DayRule.monthEnd ? dim : min(a.day, dim);
      return d.day == target &&
          (d.year * 12 + d.month) >= (a.year * 12 + a.month);
    case RecurringFrequency.yearly:
      if (d.month != a.month) {
        return false;
      }
      final dim = daysInMonth(d.year, d.month);
      final target = s.dayRule == DayRule.monthEnd ? dim : min(a.day, dim);
      return d.day == target && d.year >= a.year;
  }
}

void main() {
  test('recurringOccurrences 与按天暴力判定一致（20,000 组随机规则）', () {
    final rnd = Random(7);
    var checked = 0;
    var occurrences = 0;
    var mismatches = 0;
    LocalDate randomDate() {
      final y = 1999 + rnd.nextInt(103); // 1999..2101（含 2000 闰年、2100 平年）
      final m = 1 + rnd.nextInt(12);
      final dim = daysInMonth(y, m);
      // 偏向月末与 2 月 28/29
      final d = rnd.nextInt(3) == 0 ? dim - rnd.nextInt(3) : 1 + rnd.nextInt(dim);
      return LocalDate(y, m, d);
    }

    for (var i = 0; i < 20000; i++) {
      final freq = RecurringFrequency.values[rnd.nextInt(4)];
      final monthEndOk = freq == RecurringFrequency.monthly || freq == RecurringFrequency.yearly;
      final rule = monthEndOk && rnd.nextBool() ? DayRule.monthEnd : DayRule.anchorDay;
      final anchor = randomDate();
      final start = anchor.addDays(rnd.nextInt(400));
      final end = rnd.nextBool() ? null : start.addDays(rnd.nextInt(900));
      final from = anchor.addDays(-200 + rnd.nextInt(1200));
      final to = from.addDays(rnd.nextInt(800));
      final s = RecurringSchedule(
        frequency: freq,
        anchorOn: anchor,
        startOn: start,
        dayRule: rule,
        endOn: end,
      );
      final got = recurringOccurrences(s, from, to);
      final expected = <LocalDate>[];
      final low = start > from ? start : from;
      final high = end != null && end < to ? end : to;
      for (var d = low; d <= high; d = d.addDays(1)) {
        if (_isOccurrence(s, d)) {
          expected.add(d);
        }
      }
      checked++;
      occurrences += expected.length;
      if (got.toString() != expected.toString()) {
        mismatches++;
        if (mismatches <= 5) {
          // ignore: avoid_print
          print('MISMATCH $freq $rule anchor=$anchor start=$start end=$end from=$from to=$to\n  got=$got\n  exp=$expected');
        }
      }
    }
    // ignore: avoid_print
    print('recurringOccurrences：$checked 组，期次合计 $occurrences，不一致 $mismatches');
    expect(mismatches, 0);
  });

  test('businessDateOf / postingDateOf / timestampTextIn 与 DateTime 独立计算一致（200,000 个时刻）', () {
    final rnd = Random(11);
    var mismatches = 0;
    for (var i = 0; i < 200000; i++) {
      // 1990..2100 之间的任意微秒时刻，另外 1/4 落在当地午夜附近 ±2 秒
      var micros = (DateTime.utc(1990).microsecondsSinceEpoch +
          (rnd.nextDouble() * (DateTime.utc(2100).microsecondsSinceEpoch -
                  DateTime.utc(1990).microsecondsSinceEpoch))
              .floor());
      final zone = supportedBusinessTimeZones[rnd.nextInt(supportedBusinessTimeZones.length)];
      if (rnd.nextInt(4) == 0) {
        final local = micros + zone.offsetMinutes * 60000000;
        final midnight = local - local % 86400000000;
        micros = midnight - zone.offsetMinutes * 60000000 + (rnd.nextInt(4000001) - 2000000);
      }
      final instant = DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
      // 用任意偏移写出同一瞬间（F-20：只取决于绝对时刻）
      final writeOffset = (rnd.nextInt(57) - 28) * 30; // -14:00..+14:00，半小时步长
      final shifted = instant.add(Duration(minutes: writeOffset));
      String two(int v) => v.toString().padLeft(2, '0');
      final sign = writeOffset < 0 ? '-' : '+';
      final off = writeOffset.abs();
      final text = '${shifted.year.toString().padLeft(4, '0')}-${two(shifted.month)}-${two(shifted.day)}'
          'T${two(shifted.hour)}:${two(shifted.minute)}:${two(shifted.second)}.'
          '${(shifted.millisecond * 1000 + shifted.microsecond).toString().padLeft(6, '0')}'
          '$sign${two(off ~/ 60)}:${two(off % 60)}';
      final ts = Timestamp.parse(text);
      final local = instant.add(Duration(minutes: zone.offsetMinutes));
      final expectDate = LocalDate(local.year, local.month, local.day);
      final cutoff = CutoffTime(rnd.nextInt(24), rnd.nextInt(60));
      final secondsOfDay = local.hour * 3600 + local.minute * 60 + local.second;
      final after = secondsOfDay > cutoff.hour * 3600 + cutoff.minute * 60 ||
          (secondsOfDay == cutoff.hour * 3600 + cutoff.minute * 60 &&
              (local.millisecond > 0 || local.microsecond > 0));
      final expectPosting = after ? expectDate.addDays(1) : expectDate;
      final written = timestampTextIn(instant, zone);
      final ok = businessDateOf(ts, zone) == expectDate &&
          postingDateOf(ts, zone, cutoff: cutoff) == expectPosting &&
          Timestamp.parse(written).utcMicros == micros &&
          Timestamp.parse(written).date == expectDate;
      if (!ok) {
        mismatches++;
        if (mismatches <= 5) {
          // ignore: avoid_print
          print('MISMATCH $text zone=${zone.id} cutoff=$cutoff got=${businessDateOf(ts, zone)}/${postingDateOf(ts, zone, cutoff: cutoff)} '
              'exp=$expectDate/$expectPosting written=$written');
        }
      }
    }
    // ignore: avoid_print
    print('businessDateOf/postingDateOf/timestampTextIn：200000 个时刻，不一致 $mismatches');
    expect(mismatches, 0);
  });
}
