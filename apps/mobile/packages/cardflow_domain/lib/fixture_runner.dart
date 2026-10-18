/// golden fixture 运行器与严格 Fixture 读取（依赖 dart:io，不由 `cardflow_domain.dart` 导出，
/// App 不引用它）。命令行入口：`dart run cardflow_domain:run_fixtures`。
library;

export 'src/fixtures/fixture.dart';
export 'src/fixtures/runner.dart';
