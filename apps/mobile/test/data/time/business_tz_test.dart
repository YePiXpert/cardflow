// 业务时区与入账日（lib/data/time/business_tz.dart）：F-19（截止时点）、F-20（与写入偏移、
// 手机时区无关）、存库文本往返。
import 'package:cardflow/data/time/business_tz.dart';
import 'package:cardflow/data/time/clock.dart';
import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate, Timestamp;
import 'package:flutter_test/flutter_test.dart';

Timestamp ts(String text) => Timestamp.parse(text);

final BusinessTimeZone shanghai = businessTimeZoneOf('Asia/Shanghai');
final BusinessTimeZone tokyo = businessTimeZoneOf('Asia/Tokyo');
final BusinessTimeZone utc = businessTimeZoneOf('UTC');

void main() {
  group('支持的时区', () {
    test('只有固定偏移（无夏令时）的 8 个；默认 Asia/Shanghai；"后续支持"的不可取', () {
      expect(supportedBusinessTimeZones.map((z) => z.id), <String>[
        'Asia/Shanghai',
        'Asia/Hong_Kong',
        'Asia/Macau',
        'Asia/Taipei',
        'Asia/Singapore',
        'Asia/Tokyo',
        'Asia/Seoul',
        'UTC',
      ]);
      expect(
        findBusinessTimeZone(defaultBusinessTimeZoneId),
        defaultBusinessTimeZone,
      );
      expect(defaultBusinessTimeZone.offsetText, '+08:00');
      expect(tokyo.offsetText, '+09:00');
      expect(utc.offsetText, '+00:00');
      for (final id in laterSupportedTimeZoneIds) {
        expect(findBusinessTimeZone(id), isNull, reason: id);
        expect(
          () => businessTimeZoneOf(id),
          throwsA(isA<UnsupportedBusinessTimeZoneException>()),
        );
      }
    });
  });

  group('F-20：业务日期只取决于账户时区', () {
    // 同一瞬间（UTC 2026-10-16 17:30）的三种写法。
    const sameInstant = <String>[
      '2026-10-17T01:30:00+08:00',
      '2026-10-16T17:30:00+00:00',
      '2026-10-16T10:30:00-07:00',
    ];

    test(
      '三种偏移写入，按 Asia/Shanghai 都是 10-17，按 UTC 都是 10-16，按 Asia/Tokyo 都是 10-17',
      () {
        for (final text in sameInstant) {
          expect(
            businessDateOf(ts(text), shanghai),
            LocalDate(2026, 10, 17),
            reason: text,
          );
          expect(
            businessDateOf(ts(text), utc),
            LocalDate(2026, 10, 16),
            reason: text,
          );
          expect(
            businessDateOf(ts(text), tokyo),
            LocalDate(2026, 10, 17),
            reason: text,
          );
        }
        // 时间戳自身的日期（领域包 Timestamp.date，按它自己的偏移）各不相同——账期不能用它。
        expect(
          sameInstant.map((t) => ts(t).date.toString()).toSet(),
          hasLength(2),
        );
      },
    );

    test('DateTime 版本：本地或 UTC 表示的同一时刻结果相同（手机时区不参与）', () {
      final instant = DateTime.utc(2026, 10, 16, 17, 30);
      expect(businessDateOfInstant(instant, shanghai), LocalDate(2026, 10, 17));
      expect(
        businessDateOfInstant(instant.toLocal(), shanghai),
        LocalDate(2026, 10, 17),
      );
      expect(businessDateOfInstant(instant, utc), LocalDate(2026, 10, 16));
    });

    test('跨年、跨月与 1970 年以前的时刻（负的 epoch 微秒）', () {
      expect(
        businessDateOf(ts('2026-12-31T16:00:00Z'), shanghai),
        LocalDate(2027, 1, 1),
      );
      expect(
        businessDateOf(ts('2026-12-31T15:59:59Z'), shanghai),
        LocalDate(2026, 12, 31),
      );
      expect(
        businessDateOfInstant(DateTime.utc(1969, 12, 31, 20), shanghai),
        LocalDate(1970, 1, 1),
      );
    });
  });

  group('F-19：截止时点（cutoff_time）', () {
    final cutoff = CutoffTime.parse('17:00');

    test('同一业务日的两笔：截止前当天入账，截止后入账日 +1', () {
      final before = postingDateOf(
        ts('2026-10-16T16:59:59+08:00'),
        shanghai,
        cutoff: cutoff,
      );
      final after = postingDateOf(
        ts('2026-10-16T17:00:01+08:00'),
        shanghai,
        cutoff: cutoff,
      );
      expect(before, LocalDate(2026, 10, 16));
      expect(after, LocalDate(2026, 10, 17));
      expect(after.differenceInDays(before), 1);
    });

    test('恰好等于截止时点算当天（"晚于"才加一天）；没有截止时点不加', () {
      expect(
        postingDateOf(
          ts('2026-10-16T17:00:00+08:00'),
          shanghai,
          cutoff: cutoff,
        ),
        LocalDate(2026, 10, 16),
      );
      expect(
        postingDateOf(ts('2026-10-16T23:59:59+08:00'), shanghai),
        LocalDate(2026, 10, 16),
      );
    });

    test('截止时点按业务时区判断：同一笔用 UTC 写入，结论不变', () {
      // 2026-10-16T09:30Z = 北京时间 17:30（晚于 17:00）→ 10-17；同一瞬间按 UTC 账户是 09:30 → 当天。
      final instant = ts('2026-10-16T09:30:00Z');
      expect(
        postingDateOf(instant, shanghai, cutoff: cutoff),
        LocalDate(2026, 10, 17),
      );
      expect(
        postingDateOf(instant, utc, cutoff: cutoff),
        LocalDate(2026, 10, 16),
      );
      expect(
        postingDateOf(
          ts('2026-10-16T02:30:00-07:00'),
          shanghai,
          cutoff: cutoff,
        ),
        LocalDate(2026, 10, 17),
      );
    });

    test('cutoff_time 只接受 HH:MM', () {
      expect(CutoffTime.parse('00:00').toString(), '00:00');
      expect(CutoffTime.parse('23:59').toString(), '23:59');
      for (final bad in <String>['24:00', '7:00', '17:60', '17:00:00', '']) {
        expect(() => CutoffTime.parse(bad), throwsFormatException, reason: bad);
      }
    });
  });

  group('存库文本', () {
    test('timestampTextIn 写成业务时区偏移，能被 Timestamp.parse 读回且是同一时刻', () {
      final instant = DateTime.utc(2026, 10, 16, 4, 5, 6);
      final text = timestampTextIn(instant, shanghai);
      expect(text, '2026-10-16T12:05:06+08:00');
      expect(ts(text).utcMicros, instant.microsecondsSinceEpoch);
      expect(timestampTextIn(instant, utc), '2026-10-16T04:05:06+00:00');
      final micro = DateTime.utc(2026, 10, 16, 4, 5, 6, 7, 8);
      expect(timestampTextIn(micro, tokyo), '2026-10-16T13:05:06.007008+09:00');
      expect(
        ts(timestampTextIn(micro, tokyo)).utcMicros,
        micro.microsecondsSinceEpoch,
      );
    });

    test('instantAt 与演示时钟', () {
      expect(
        instantAt(LocalDate(2026, 10, 16), shanghai, hour: 12),
        DateTime.utc(2026, 10, 16, 4),
      );
      expect(demoClock.isFixed, isTrue);
      expect(demoClock.today(shanghai), LocalDate(2026, 10, 16));
      expect(demoClock.nowText(shanghai), '2026-10-16T12:00:00+08:00');
      expect(const SystemClock().isFixed, isFalse);
    });
  });
}
