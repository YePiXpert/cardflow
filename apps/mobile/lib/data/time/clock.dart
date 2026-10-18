import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate;
import 'package:flutter/foundation.dart';

import 'business_tz.dart';

/// "现在"的来源。真实空间用系统时间；演示空间固定为 [demoNow]（ui-spec §4.2：演示的"今天"
/// 固定为 2026-10-16，不判陈旧）。页面与仓库一律经 `clockProvider` 取，不直接调用
/// `DateTime.now()`，测试里可以替换。
abstract interface class AppClock {
  /// 当前绝对时刻（UTC）。
  DateTime now();

  /// 是否为固定时钟（演示空间）：陈旧判定不触发。
  bool get isFixed;
}

/// 系统时钟。
final class SystemClock implements AppClock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();

  @override
  bool get isFixed => false;
}

/// 固定时钟（演示空间、测试）。
@immutable
final class FixedClock implements AppClock {
  const FixedClock(this.instant);

  final DateTime instant;

  @override
  DateTime now() => instant.toUtc();

  @override
  bool get isFixed => true;
}

/// 演示空间的"现在"：2026-10-16 12:00（北京时间，UTC 04:00）。
final DateTime demoNow = DateTime.utc(2026, 10, 16, 4);

/// 演示空间的时钟。
final FixedClock demoClock = FixedClock(demoNow);

/// 便捷方法。
extension AppClockDates on AppClock {
  /// 业务时区 [zone] 里的"今天"。
  LocalDate today(BusinessTimeZone zone) => businessDateOfInstant(now(), zone);

  /// "现在"写成业务时区偏移的 RFC 3339 文本（存库用）。
  String nowText([BusinessTimeZone zone = defaultBusinessTimeZone]) =>
      timestampTextIn(now(), zone);
}
