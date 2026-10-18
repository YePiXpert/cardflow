/// 运行平台信息。iOS 等原生平台经 dart:io 读取；Web（仅作编译烟雾测试）用占位实现。
library;

export 'platform_info_stub.dart' if (dart.library.io) 'platform_info_io.dart';
