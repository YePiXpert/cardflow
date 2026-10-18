/// 加密本地库的平台实现：原生平台（iOS）用 dart:io + drift_flutter（SQLite 在后台
/// isolate 中运行）；Web 只作编译烟雾测试，一律报 `unsupported_platform`。
library;

export 'database_platform_stub.dart'
    if (dart.library.io) 'database_platform_io.dart';
