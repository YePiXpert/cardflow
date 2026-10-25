import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/widgets/confirm_dialog.dart';
import '../../data/repositories/providers.dart';

/// 切换到演示空间的确认文案。
const String enterDemoConfirmMessage =
    '演示模式包含预置的示例银行与卡片，与你的真实卡片数据相互独立，可随时「退出演示」回到真实卡片。';

/// 体验演示（ui-spec §4.2）：从真实空间切换须确认；首次进入时生成合成数据；完成后转到卡账。
/// 返回是否进入了演示空间。生成失败时抛出（真实空间不受影响），由调用方显示错误与「重试生成」。
Future<bool> enterDemoWorkspace(BuildContext context, WidgetRef ref) async {
  final current = ref.read(currentWorkspaceProvider).value;
  if (current != null && !current.isDemo) {
    final confirmed = await confirmAction(
      context,
      title: '切换到演示空间？',
      message: enterDemoConfirmMessage,
      confirmLabel: '进入演示',
    );
    if (!confirmed) {
      return false;
    }
  }
  await ref.read(currentWorkspaceProvider.notifier).enterDemo();
  if (context.mounted) {
    context.go(AppRoutes.home);
  }
  return true;
}

/// 手工建卡：从演示空间切换须确认；进入真实空间（没有则新建）后打开新建卡片。
Future<void> startManualCard(BuildContext context, WidgetRef ref) async {
  final current = ref.read(currentWorkspaceProvider).value;
  if (current != null && current.isDemo) {
    final confirmed = await confirmAction(
      context,
      title: '切换到真实空间？',
      message: '将离开演示空间，在你自己的数据里建卡。演示数据保留，可在欢迎页清除。',
      confirmLabel: '切换并建卡',
    );
    if (!confirmed) {
      return;
    }
  }
  if (current == null || current.isDemo) {
    await ref.read(currentWorkspaceProvider.notifier).enterReal();
  }
  if (context.mounted) {
    context.go(AppRoutes.newCard);
  }
}

/// 清除演示数据（ui-spec §4.2、§4.5：确认框写明影响数量）。
Future<void> clearDemoWorkspace(
  BuildContext context,
  WidgetRef ref,
  Map<String, int> rows,
) async {
  final confirmed = await confirmAction(
    context,
    title: '清除演示数据？',
    message:
        '将删除演示空间的全部示例数据：${rows['credit_accounts'] ?? 0} 个信用账户、'
        '${rows['cards'] ?? 0} 张卡片、${rows['billing_rule_versions'] ?? 0} 个账期规则版本、'
        '${rows['limit_snapshots'] ?? 0} 条额度快照、${rows['credit_pools'] ?? 0} 个授信池。'
        '真实数据不受影响。之后再体验演示会重新生成。',
    confirmLabel: '清除',
    destructive: true,
  );
  if (confirmed) {
    await ref.read(currentWorkspaceProvider.notifier).clearDemo();
  }
}
