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

  /// 读回记下的开关。读不到时保持当前值。
  Future<void> restore() async {
    try {
      final repo = await ref.read(workspaceRepositoryProvider.future);
      final value = await repo.setting(amountsHiddenSettingKey);
      if (ref.mounted && value != null) {
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

/// 启动时读回"隐藏金额"开关一次。启动分流（`app_gate.dart`）等它完成才进入主导航：打开隐藏后冷启动，页面
/// 不会先露出金额。读不到时照常完成（按当前值，即不隐藏）。
@Riverpod(keepAlive: true)
Future<void> amountsHiddenRestored(Ref ref) =>
    ref.read(amountsHiddenProvider.notifier).restore();

/// 不经 [MoneyText] 的文字里的金额（句子里的"支出 30.00"一类）：隐藏时换成固定 4 个"•"。
String amountInText(String text, {required bool hidden}) =>
    hidden ? hiddenAmountText : text;
