import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'features/diagnostics/app_diagnostics.dart';
import 'features/diagnostics/crypto_status.dart';
import 'features/diagnostics/diagnostic_log.dart';
import 'features/diagnostics/error_hooks.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  final log = container.read(diagnosticLogProvider);
  installErrorHooks(log);
  log.info('app', 'launch', detail: currentBuildMode());
  // 启动时就在后台打开（首次启动则新建）本机加密数据库：结果写进诊断日志
  // （db/opened 或 db/open_failed），诊断页直接显示。打开失败不影响 App 其余部分。
  container.read(cryptoLibraryStatusProvider.future).ignore();
  runApp(
    UncontrolledProviderScope(container: container, child: const CardFlowApp()),
  );
}
