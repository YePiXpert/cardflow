import 'dart:isolate';

/// 在新的 isolate 里运行 [computation]（`Isolate.run`），界面线程不被占用。
Future<R> runOffMainIsolate<R>(R Function() computation) =>
    Isolate.run<R>(computation, debugName: 'cardflow-compute');
