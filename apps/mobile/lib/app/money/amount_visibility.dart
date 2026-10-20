import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/repositories/providers.dart';
import '../../data/repositories/workspace_repository.dart';
import 'money_format.dart';

part 'amount_visibility.g.dart';

/// 全局"金额隐藏"开关（ui-spec §3.6，R-SYS-03；简报 U-1 §9 R-09）：开启后 [MoneyText] 一律显示固定 4 个"•"，
/// 读屏读"金额已隐藏"。"我的"页有开关；状态存在 `app_settings`（键 [amountsHiddenSettingKey]，两个空间共用），
/// 启动时由 [amountsHiddenRestoredProvider] 读回一次。
@Riverpod(keepAlive: true)
class AmountsHidden extends _$AmountsHidden {
  @override
  bool build() => false;

  /// 设置是否隐藏金额，并记下来（写失败不影响这次运行里的开关）。
  void setHidden(bool hidden) {
    state = hidden;
    unawaited(_save(hidden));
  }

  /// 切换隐藏/显示。
  void toggle() => setHidden(!state);

  /// 读回记下的开关：记着"1"为隐藏，其余（含从没记过、重置本地数据之后的新库）为不隐藏。读不到时保持
  /// 当前值。[repository] 为空时取当前的仓库。
  Future<void> restore([WorkspaceRepository? repository]) async {
    try {
      final repo = await (repository == null
          ? ref.read(workspaceRepositoryProvider.future)
          : Future<WorkspaceRepository>.value(repository));
      final value = await repo.setting(amountsHiddenSettingKey);
      if (ref.mounted) {
        state = value == '1';
      }
    } on Object {
      // 读不到（数据库还没打开、测试替身）：保持当前值。
    }
  }

  Future<void> _save(bool hidden) async {
    try {
      final repo = await ref.read(workspaceRepositoryProvider.future);
      await repo.setSetting(amountsHiddenSettingKey, hidden ? '1' : '0');
    } on Object {
      // 写不进去时这次运行里照样隐藏；下次启动按库里的值。
    }
  }
}

/// 读回"隐藏金额"开关：启动时一次，本机数据库重新打开（重置本地数据、重试打开）之后再一次。启动分流
/// （`app_gate.dart`）等它完成才进入主导航：打开隐藏后冷启动，页面不会先露出金额。读不到时照常完成。
@Riverpod(keepAlive: true)
Future<void> amountsHiddenRestored(Ref ref) async {
  final WorkspaceRepository repo;
  try {
    repo = await ref.watch(workspaceRepositoryProvider.future);
  } on Object {
    // 数据库打不开：启动分流显示错误页；重新打开后这里会再运行。
    return;
  }
  await ref.read(amountsHiddenProvider.notifier).restore(repo);
}

/// 不经 [MoneyText] 的文字里的金额（句子里的"支出 30.00"一类）：隐藏时换成固定 4 个"•"。
String amountInText(String text, {required bool hidden}) =>
    hidden ? hiddenAmountText : text;
