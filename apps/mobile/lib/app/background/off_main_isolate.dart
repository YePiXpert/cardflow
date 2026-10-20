/// 把耗时的纯计算放到界面线程之外（审查 R-04：分期成本的有理数 IRR 不在界面线程上算）。
///
/// 原生平台（iOS）用 `Isolate.run`：新开一个 isolate 算完把结果传回来，[computation] 只能捕获可以在 isolate
/// 之间传递的值（整数、BigInt、有理数、记录与列表）。Web 只作 CI 的编译烟雾测试，没有 isolate，就地计算。
library;

export 'off_main_isolate_stub.dart'
    if (dart.library.io) 'off_main_isolate_io.dart';
