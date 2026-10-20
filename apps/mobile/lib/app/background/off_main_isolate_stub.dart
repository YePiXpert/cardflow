/// Web（只作编译烟雾测试）：没有 isolate，就地计算。
Future<R> runOffMainIsolate<R>(R Function() computation) async => computation();
