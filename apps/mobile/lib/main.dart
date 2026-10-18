import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'features/diagnostics/app_diagnostics.dart';
import 'features/diagnostics/diagnostic_log.dart';
import 'features/diagnostics/error_hooks.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  final log = container.read(diagnosticLogProvider);
  installErrorHooks(log);
  log.info('app', 'launch', detail: currentBuildMode());
  runApp(
    UncontrolledProviderScope(container: container, child: const CardFlowApp()),
  );
}
