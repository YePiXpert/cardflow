/// 业务日期、带偏移的时间戳与时间精度（ADR-008）。
///
/// [LocalDate] 是账户业务时区里的日历日期，没有时刻也没有时区，因而不会出现"本地/UTC 混淆"；
/// 算术按公历（与 Python `datetime.date` 相同，范围 0001-01-01 … 9999-12-31）。
/// [Timestamp] 是协议 v1 的 RFC 3339 时间戳（必须带偏移），自行解析、不引入时区数据库：
/// 它的日期按其自身偏移计算（[Timestamp.date]，R3E-14），同日排序按绝对时刻（[Timestamp.utcMicros]）。
library;

/// 日期超出 0001-01-01 … 9999-12-31（Python 的 `OverflowError: date value out of range`）。
final class DateRangeError extends Error {
  DateRangeError();

  @override
  String toString() => 'date value out of range';
}

/// 时间精度（ADR-008 `time_precision`）：精确到时刻、只到日期、只到月份。
enum TimePrecision {
  /// 精确到时刻（有时间戳）。
  datetime,

  /// 只知道日期。
  date,

  /// 只知道月份（如"10 月某天"）。
  month,
}

/// 闰年（公历）。
bool isLeapYear(int year) =>
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

/// 某月的天数。
int daysInMonth(int year, int month) {
  const days = <int>[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (month == 2 && isLeapYear(year)) {
    return 29;
  }
  return days[month - 1];
}

// 公历日期 ↔ 1970-01-01 起的天数（Howard Hinnant, "chrono-compatible low-level date
// algorithms"），只用整数运算。
int _daysFromCivil(int year, int month, int day) {
  final y = month <= 2 ? year - 1 : year;
  final era = (y >= 0 ? y : y - 399) ~/ 400;
  final yoe = y - era * 400;
  final mp = month > 2 ? month - 3 : month + 9;
  final doy = (153 * mp + 2) ~/ 5 + day - 1;
  final doe = yoe * 365 + yoe ~/ 4 - yoe ~/ 100 + doy;
  return era * 146097 + doe - 719468;
}

const int _minEpochDay = -719162; // 0001-01-01
const int _maxEpochDay = 2932896; // 9999-12-31

/// 业务日期（无时刻、无时区）。
final class LocalDate implements Comparable<LocalDate> {
  LocalDate._(this.year, this.month, this.day, this.epochDay);

  /// 公历日期；月份或日期不存在（如 2026-02-30）、年份不在 1…9999 时抛 [ArgumentError]。
  factory LocalDate(int year, int month, int day) {
    if (year < 1 || year > 9999) {
      throw ArgumentError('year $year is out of range');
    }
    if (month < 1 || month > 12) {
      throw ArgumentError('month must be in 1..12');
    }
    if (day < 1 || day > daysInMonth(year, month)) {
      throw ArgumentError('day is out of range for month');
    }
    return LocalDate._(year, month, day, _daysFromCivil(year, month, day));
  }

  /// 1970-01-01 起的第 [epochDay] 天；超出 0001…9999 年抛 [DateRangeError]。
  factory LocalDate.fromEpochDay(int epochDay) {
    if (epochDay < _minEpochDay || epochDay > _maxEpochDay) {
      throw DateRangeError();
    }
    final z = epochDay + 719468;
    final era = (z >= 0 ? z : z - 146096) ~/ 146097;
    final doe = z - era * 146097;
    final yoe = (doe - doe ~/ 1460 + doe ~/ 36524 - doe ~/ 146096) ~/ 365;
    final doy = doe - (365 * yoe + yoe ~/ 4 - yoe ~/ 100);
    final mp = (5 * doy + 2) ~/ 153;
    final day = doy - (153 * mp + 2) ~/ 5 + 1;
    final month = mp < 10 ? mp + 3 : mp - 9;
    final year = yoe + era * 400 + (month <= 2 ? 1 : 0);
    return LocalDate._(year, month, day, epochDay);
  }

  static final RegExp _iso = RegExp(r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$');

  /// 解析 `YYYY-MM-DD`（严格：4 位年、2 位月日、必须是真实日期），否则抛 [FormatException]。
  static LocalDate parse(String text) {
    final m = _iso.firstMatch(text);
    if (m == null) {
      throw const FormatException('not a YYYY-MM-DD date');
    }
    try {
      return LocalDate(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      );
    } on ArgumentError {
      throw const FormatException('not a valid calendar date');
    }
  }

  /// 年。
  final int year;

  /// 月（1–12）。
  final int month;

  /// 日（1–31）。
  final int day;

  /// 1970-01-01 起的天数（可为负）。
  final int epochDay;

  /// 加 [days] 天（可为负）；越界抛 [DateRangeError]。
  LocalDate addDays(int days) => LocalDate.fromEpochDay(epochDay + days);

  /// `this - other` 的天数。
  int differenceInDays(LocalDate other) => epochDay - other.epochDay;

  /// ISO 星期：1 = 周一 … 7 = 周日。
  int get isoWeekday => (epochDay + 3) % 7 + 1;

  /// 早于。
  bool operator <(LocalDate other) => epochDay < other.epochDay;

  /// 早于或等于。
  bool operator <=(LocalDate other) => epochDay <= other.epochDay;

  /// 晚于。
  bool operator >(LocalDate other) => epochDay > other.epochDay;

  /// 晚于或等于。
  bool operator >=(LocalDate other) => epochDay >= other.epochDay;

  /// 两者中较晚的一个。
  LocalDate laterOf(LocalDate other) => other > this ? other : this;

  @override
  int compareTo(LocalDate other) => epochDay.compareTo(other.epochDay);

  @override
  bool operator ==(Object other) =>
      other is LocalDate && other.epochDay == epochDay;

  @override
  int get hashCode => epochDay.hashCode;

  /// ISO 8601 `YYYY-MM-DD`（与 Python `date.isoformat()` 相同）。
  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}'
      '-${day.toString().padLeft(2, '0')}';
}

/// 月末截断的"某年某月第 [day] 日"：31 → 30/28/29（bank-rules-spec §3.3）。
LocalDate clampDay(int year, int month, int day) {
  final last = daysInMonth(year, month);
  return LocalDate(year, month, day < last ? day : last);
}

/// [date] 所在月加 [months] 个月后的（年, 月），跨年进位。
(int, int) addMonths(LocalDate date, int months) {
  final m0 = date.month - 1 + months;
  final yearShift = m0 >= 0 ? m0 ~/ 12 : -((-m0 + 11) ~/ 12);
  return (date.year + yearShift, m0 - yearShift * 12 + 1);
}

/// RFC 3339 时间戳（必须带偏移；`T`、`Z` 大写；小数秒至多 6 位；不接受闰秒）。
final class Timestamp implements Comparable<Timestamp> {
  Timestamp._({
    required this.text,
    required this.date,
    required this.hour,
    required this.minute,
    required this.second,
    required this.microsecond,
    required this.offsetMinutes,
  }) : utcMicros =
           (((date.epochDay * 24 + hour) * 60 + minute - offsetMinutes) * 60 +
                   second) *
               1000000 +
           microsecond;

  static final RegExp _pattern = RegExp(
    r'^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})'
    r'(?:\.([0-9]{1,6}))?(Z|([+-])([0-9]{2}):([0-9]{2}))$',
  );

  /// 解析时间戳；格式不符、字段越界（时 00–23、分秒 00–59、偏移小时 00–23）或日期不存在时
  /// 抛 [FormatException]。协议 v1 另限年份 1970–2999（由适配层的 pattern 检查）。
  static Timestamp parse(String text) {
    final m = _pattern.firstMatch(text);
    if (m == null) {
      throw const FormatException('not an RFC 3339 timestamp with an offset');
    }
    final hour = int.parse(m.group(4)!);
    final minute = int.parse(m.group(5)!);
    final second = int.parse(m.group(6)!);
    if (hour > 23 || minute > 59 || second > 59) {
      throw const FormatException('time of day out of range');
    }
    final fraction = m.group(7);
    final micro = fraction == null ? 0 : int.parse(fraction.padRight(6, '0'));
    var offset = 0;
    if (m.group(8) != 'Z') {
      final oh = int.parse(m.group(10)!);
      final om = int.parse(m.group(11)!);
      if (oh > 23 || om > 59) {
        throw const FormatException('offset out of range');
      }
      offset = (oh * 60 + om) * (m.group(9) == '-' ? -1 : 1);
    }
    final LocalDate date;
    try {
      date = LocalDate(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      );
    } on ArgumentError {
      throw const FormatException('not a valid calendar date');
    }
    return Timestamp._(
      text: text,
      date: date,
      hour: hour,
      minute: minute,
      second: second,
      microsecond: micro,
      offsetMinutes: offset,
    );
  }

  /// 原始文本。
  final String text;

  /// 按时间戳自身偏移计算的日期（R3E-14：必须等于事件的 `on`）。
  final LocalDate date;

  /// 时（本地，按自身偏移）。
  final int hour;

  /// 分。
  final int minute;

  /// 秒。
  final int second;

  /// 微秒。
  final int microsecond;

  /// UTC 偏移（分钟，东正西负）。
  final int offsetMinutes;

  /// 绝对时刻：1970-01-01T00:00:00Z 起的微秒数（同日排序按它比较）。
  final int utcMicros;

  /// Python `datetime.isoformat()` 的写法：`Z` 写成 `+00:00`，微秒非零时写 6 位。
  String isoformat() {
    String two(int v) => v.toString().padLeft(2, '0');
    final buffer = StringBuffer(
      '${date}T${two(hour)}:${two(minute)}:${two(second)}',
    );
    if (microsecond != 0) {
      buffer.write('.${microsecond.toString().padLeft(6, '0')}');
    }
    final abs = offsetMinutes.abs();
    buffer.write(
      '${offsetMinutes < 0 ? '-' : '+'}${two(abs ~/ 60)}:${two(abs % 60)}',
    );
    return buffer.toString();
  }

  @override
  int compareTo(Timestamp other) => utcMicros.compareTo(other.utcMicros);

  /// 同一绝对时刻即相等（与 Python 带时区 datetime 的比较一致）。
  @override
  bool operator ==(Object other) =>
      other is Timestamp && other.utcMicros == utcMicros;

  @override
  int get hashCode => utcMicros.hashCode;

  @override
  String toString() => text;
}
