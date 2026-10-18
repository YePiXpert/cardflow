/// 业务时区：账期计算只用账户的业务时区，与手机时区无关（PRD §3 硬性语义 4、ADR-008、F-20）。
///
/// 领域包不带时区数据库（不引入 timezone 包），本期只支持**没有夏令时的固定偏移时区**（I-1a 简报）；
/// 有夏令时的时区在界面上列出但不可选，标"后续支持"。
library;

import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate, Timestamp;
import 'package:flutter/foundation.dart';

/// 一个固定偏移的业务时区。
@immutable
final class BusinessTimeZone {
  const BusinessTimeZone({
    required this.id,
    required this.offsetMinutes,
    required this.label,
  });

  /// IANA 名称，如 `Asia/Shanghai`（存在 `credit_accounts.business_tz`）。
  final String id;

  /// UTC 偏移（分钟，东正西负；全年不变）。
  final int offsetMinutes;

  /// 界面上的中文名。
  final String label;

  /// RFC 3339 的偏移写法，如 `+08:00`、`+00:00`。
  String get offsetText {
    final sign = offsetMinutes < 0 ? '-' : '+';
    final abs = offsetMinutes.abs();
    return '$sign${(abs ~/ 60).toString().padLeft(2, '0')}:'
        '${(abs % 60).toString().padLeft(2, '0')}';
  }

  /// 选择器里的一行，如"中国大陆（Asia/Shanghai，UTC+08:00）"。
  String get displayName => '$label（$id，UTC$offsetText）';

  @override
  bool operator ==(Object other) => other is BusinessTimeZone && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => id;
}

/// 默认业务时区（ui-spec P-04、A-01）。
const String defaultBusinessTimeZoneId = 'Asia/Shanghai';

/// 本期支持的业务时区：都没有夏令时，偏移全年固定。
const List<BusinessTimeZone> supportedBusinessTimeZones = <BusinessTimeZone>[
  BusinessTimeZone(id: 'Asia/Shanghai', offsetMinutes: 480, label: '中国大陆'),
  BusinessTimeZone(id: 'Asia/Hong_Kong', offsetMinutes: 480, label: '中国香港'),
  BusinessTimeZone(id: 'Asia/Macau', offsetMinutes: 480, label: '中国澳门'),
  BusinessTimeZone(id: 'Asia/Taipei', offsetMinutes: 480, label: '中国台湾'),
  BusinessTimeZone(id: 'Asia/Singapore', offsetMinutes: 480, label: '新加坡'),
  BusinessTimeZone(id: 'Asia/Tokyo', offsetMinutes: 540, label: '日本'),
  BusinessTimeZone(id: 'Asia/Seoul', offsetMinutes: 540, label: '韩国'),
  BusinessTimeZone(id: 'UTC', offsetMinutes: 0, label: '协调世界时'),
];

/// 界面上列出但暂不可选的常见时区（有夏令时，需要时区数据库）："后续支持"。
const List<String> laterSupportedTimeZoneIds = <String>[
  'America/New_York',
  'America/Los_Angeles',
  'Europe/London',
  'Europe/Paris',
  'Australia/Sydney',
];

/// 默认业务时区对象。
const BusinessTimeZone defaultBusinessTimeZone = BusinessTimeZone(
  id: 'Asia/Shanghai',
  offsetMinutes: 480,
  label: '中国大陆',
);

/// 按 IANA 名称找支持的业务时区；不支持时为 null。
BusinessTimeZone? findBusinessTimeZone(String id) {
  for (final zone in supportedBusinessTimeZones) {
    if (zone.id == id) {
      return zone;
    }
  }
  return null;
}

/// 账户的业务时区不在 [supportedBusinessTimeZones] 里（只可能来自更新版本的 App 或手工改库）。
final class UnsupportedBusinessTimeZoneException implements Exception {
  const UnsupportedBusinessTimeZoneException(this.id);

  final String id;

  @override
  String toString() => 'UnsupportedBusinessTimeZoneException($id)';
}

/// 按 IANA 名称取支持的业务时区；不支持时抛 [UnsupportedBusinessTimeZoneException]。
BusinessTimeZone businessTimeZoneOf(String id) =>
    findBusinessTimeZone(id) ??
    (throw UnsupportedBusinessTimeZoneException(id));

const int _microsPerMinute = 60 * 1000000;
const int _microsPerDay = 24 * 60 * _microsPerMinute;

/// 向下取整除法（负数也朝负无穷）。
int _floorDiv(int a, int b) {
  final q = a ~/ b;
  return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q;
}

/// 业务时区里的本地微秒数（1970-01-01T00:00 当地时间起）。
int _localMicros(int utcMicros, BusinessTimeZone zone) =>
    utcMicros + zone.offsetMinutes * _microsPerMinute;

/// 时刻 [instant]（自带任意偏移）在业务时区 [zone] 里的日历日期。
///
/// 只取决于绝对时刻与账户时区：同一瞬间写成 `+08:00`、`+00:00`、`-07:00` 得到同一个业务日期
/// （F-20）；手机时区不参与。
LocalDate businessDateOf(Timestamp instant, BusinessTimeZone zone) =>
    LocalDate.fromEpochDay(
      _floorDiv(_localMicros(instant.utcMicros, zone), _microsPerDay),
    );

/// [businessDateOf] 的 [DateTime] 版本（[instant] 是绝对时刻，本地/UTC 表示都可以）。
LocalDate businessDateOfInstant(DateTime instant, BusinessTimeZone zone) =>
    LocalDate.fromEpochDay(
      _floorDiv(
        _localMicros(instant.toUtc().microsecondsSinceEpoch, zone),
        _microsPerDay,
      ),
    );

/// 业务时区里的当天时刻（当地 0 点起的微秒数）。
int _microsOfDay(int utcMicros, BusinessTimeZone zone) {
  final local = _localMicros(utcMicros, zone);
  return local - _floorDiv(local, _microsPerDay) * _microsPerDay;
}

/// 规则的截止时点 `cutoff_time`（业务时区里的 `HH:MM`）。
@immutable
final class CutoffTime {
  const CutoffTime(this.hour, this.minute)
    : assert(hour >= 0 && hour <= 23, 'hour 0..23'),
      assert(minute >= 0 && minute <= 59, 'minute 0..59');

  /// 解析 `HH:MM`（两位小时 00–23、两位分钟 00–59）；格式不对抛 [FormatException]。
  factory CutoffTime.parse(String text) {
    final m = _pattern.firstMatch(text);
    if (m == null) {
      throw const FormatException('cutoff_time must be HH:MM');
    }
    final hour = int.parse(m.group(1)!);
    final minute = int.parse(m.group(2)!);
    if (hour > 23 || minute > 59) {
      throw const FormatException('cutoff_time out of range');
    }
    return CutoffTime(hour, minute);
  }

  static final RegExp _pattern = RegExp(r'^([0-9]{2}):([0-9]{2})$');

  final int hour;
  final int minute;

  int get _micros => (hour * 60 + minute) * _microsPerMinute;

  @override
  bool operator ==(Object other) =>
      other is CutoffTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  /// `HH:MM`。
  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// 银行入账时点 [postedAt] 对应的入账日（F-19，数据层推导；领域包只接收入账日）。
///
/// 先按账户业务时区 [zone] 换算成当地日期；规则有截止时点 [cutoff] 且当地时刻**晚于**它
/// （严格大于；恰好等于截止时点仍算当天）时，入账日加一天。
///
/// Python 引擎（`billing.py`）只接收入账日，没有 cutoff 语义（服务端表只有 `cutoff_time`/
/// `cutoff_tz` 两列，没有任何计算），所以这里按 I-1a 简报实现（偏离登记见 README）。
LocalDate postingDateOf(
  Timestamp postedAt,
  BusinessTimeZone zone, {
  CutoffTime? cutoff,
}) {
  final date = businessDateOf(postedAt, zone);
  if (cutoff == null) {
    return date;
  }
  return _microsOfDay(postedAt.utcMicros, zone) > cutoff._micros
      ? date.addDays(1)
      : date;
}

/// 把绝对时刻 [instant] 写成业务时区偏移的 RFC 3339 文本（存库用），如
/// `2026-10-16T12:00:00+08:00`；有微秒时写 6 位小数。结果能被 `Timestamp.parse` 读回，且
/// `businessDateOf` 读回的日期就是当地日期。
String timestampTextIn(DateTime instant, BusinessTimeZone zone) {
  final local = _localMicros(instant.toUtc().microsecondsSinceEpoch, zone);
  final date = LocalDate.fromEpochDay(_floorDiv(local, _microsPerDay));
  var rest = local - date.epochDay * _microsPerDay;
  final micro = rest % 1000000;
  rest ~/= 1000000;
  final second = rest % 60;
  rest ~/= 60;
  final minute = rest % 60;
  final hour = rest ~/ 60;
  String two(int v) => v.toString().padLeft(2, '0');
  final fraction = micro == 0 ? '' : '.${micro.toString().padLeft(6, '0')}';
  return '${date}T${two(hour)}:${two(minute)}:${two(second)}$fraction'
      '${zone.offsetText}';
}

/// 业务时区里某一天某个时刻的绝对时刻（UTC）。
DateTime instantAt(
  LocalDate date,
  BusinessTimeZone zone, {
  int hour = 0,
  int minute = 0,
}) => DateTime.fromMicrosecondsSinceEpoch(
  (date.epochDay * 24 * 60 + hour * 60 + minute - zone.offsetMinutes) *
      _microsPerMinute,
  isUtc: true,
);
