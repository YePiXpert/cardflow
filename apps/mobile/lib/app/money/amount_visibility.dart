import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'amount_visibility.g.dart';

/// 全局"金额隐藏"开关（ui-spec §3.6，R-SYS-03）。[MoneyText] 默认跟随它。
///
/// 本阶段只保存在内存中；"我的"页的开关与持久化随 I-4（应用锁、金额隐藏、遮罩）接入。
@Riverpod(keepAlive: true)
class AmountsHidden extends _$AmountsHidden {
  @override
  bool build() => false;

  /// 设置是否隐藏金额。
  void setHidden(bool hidden) => state = hidden;

  /// 切换隐藏/显示。
  void toggle() => state = !state;
}
