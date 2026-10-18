import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/db/database_providers.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/scenario_repository.dart';

part 'calendar_providers.g.dart';

/// 资金日历的情景选择：用户压力情景（内置两条由口径直接选）。
@immutable
final class ScenarioChoices {
  const ScenarioChoices(this.stress);

  final List<ScenarioView> stress;
}

/// 当前工作空间的压力情景（P-07 控制条"情景选择"）。
@Riverpod(retry: noDatabaseRetry)
Future<ScenarioChoices> scenarioChoices(Ref ref) async {
  ref.watch(localDataRevisionProvider);
  final repo = await ref.watch(scenarioRepositoryProvider.future);
  return ScenarioChoices(<ScenarioView>[
    for (final s in await repo.list())
      if (!s.isBuiltin) s,
  ]);
}
