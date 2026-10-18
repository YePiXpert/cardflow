import 'package:flutter/foundation.dart';

/// 本机数据库文件放在哪里。
@immutable
final class DatabaseLocation {
  const DatabaseLocation({required this.directory, this.tempDirectory});

  /// 存放数据库文件的目录。iOS：`Library/Application Support`（"文件"App 里看不到）。
  final String directory;

  /// sqlite3 的临时文件目录，也是"数据库基准"临时库的目录。iOS：`Library/Caches`。
  /// 为 null 时不改 sqlite3 的设置，基准临时库放在 [directory]。
  final String? tempDirectory;

  /// "数据库基准"临时库所在目录。
  String get scratchDirectory => tempDirectory ?? directory;
}
