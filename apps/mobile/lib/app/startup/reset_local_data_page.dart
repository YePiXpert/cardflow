import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/db/database_providers.dart';
import '../../data/repositories/models.dart';
import '../../data/repositories/providers.dart';
import '../routes.dart';
import '../theme/tokens.dart';
import '../widgets/state_views.dart';

/// 从"我的"进入时的影响说明：数据库能读，写明两个空间各有多少数据（ui-spec §4.5"确认页写明影响数量"）。
final resetImpactProvider = FutureProvider.autoDispose<String>((ref) async {
  final repo = await ref.watch(workspaceRepositoryProvider.future);
  final real = await repo.live(WorkspaceKind.real);
  final demo = await repo.live(WorkspaceKind.demo);
  final realRows = real == null ? null : await repo.countRows(real.id);
  final demoRows = demo == null ? null : await repo.countRows(demo.id);
  int n(Map<String, int>? rows, String table) => rows?[table] ?? 0;
  final demoTotal = demoRows?.values.fold<int>(0, (a, b) => a + b) ?? 0;
  return '将删除这台 iPhone 上的全部卡序数据：真实空间里 ${n(realRows, 'credit_accounts')} 个信用账户、'
      '${n(realRows, 'cards')} 张卡片；'
      '${demo == null ? '' : '演示空间的 $demoTotal 条示例数据；'}以及钥匙串里的数据库密钥。'
      '${ResetLocalDataPage.irreversible}';
});

/// "重置本地数据"的确认页（BL-07，ui-spec §4.5）：写明影响，输入"删除"才能执行。数据库打不开时从启动页进入
/// （无法统计条数）；正常使用时从"我的"进入（[fromSettings]，写明两个空间各有多少数据；简报 U-1 §9 R-10）。
/// 抹除前的设备认证在后续版本（BL-20）。
///
/// 执行：关闭连接 → 删除数据库文件与钥匙串里的数据库密钥 → 密钥管理器忘掉缓存（R-15）→
/// 重新打开（按首次使用建新库），随后路由自动进入 P-22。诊断日志只记 `db/reset`。
class ResetLocalDataPage extends ConsumerStatefulWidget {
  const ResetLocalDataPage({super.key, this.fromSettings = false});

  /// 从"我的"进入（数据库能读）。
  final bool fromSettings;

  static const String title = '重置本地数据';

  /// 影响说明的后半句（两种入口相同）。
  static const String irreversible =
      '删除后无法恢复：卡序还没有自己的备份与导出；iPhone 自身的备份里可能留有加密副本，但换到别的手机无法打开。'
      '重置后按首次使用重新开始。';

  /// 必须输入的确认词。
  static const String confirmWord = '删除';

  /// 影响说明。
  static const String impact =
      '将删除这台设备上的全部卡序数据：真实空间与演示空间里的卡片、信用账户、账期规则、额度快照等'
      '（数据库已无法读取，无法统计条数），以及钥匙串里的数据库密钥。删除后无法恢复（本期还没有备份功能）。'
      '重置后按首次使用重新开始。';

  @override
  ConsumerState<ResetLocalDataPage> createState() => _ResetLocalDataPageState();
}

class _ResetLocalDataPageState extends ConsumerState<ResetLocalDataPage> {
  final TextEditingController _confirm = TextEditingController();

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(databaseRecoveryProvider);
    final running = recovery is DatabaseRecoveryRunning;
    final theme = Theme.of(context);
    final impact = widget.fromSettings
        ? switch (ref.watch(resetImpactProvider)) {
            AsyncData(:final value) => value,
            AsyncError() =>
              '将删除这台 iPhone 上的全部卡序数据（条数读取失败）以及钥匙串里的数据库密钥。'
                  '${ResetLocalDataPage.irreversible}',
            _ => '正在统计会删除的数据…',
          }
        : ResetLocalDataPage.impact;
    return Scaffold(
      appBar: AppBar(
        title: const Text(ResetLocalDataPage.title),
        leading: BackButton(
          onPressed: () => widget.fromSettings
              ? (context.canPop()
                    ? context.pop()
                    : context.go(AppRoutes.settings))
              : context.go(AppRoutes.startup),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(CfSpace.md),
        children: <Widget>[
          NoticeCard(
            icon: Icons.warning_amber_outlined,
            tone: NoticeTone.danger,
            text: impact,
          ),
          const SizedBox(height: CfSpace.md),
          Text(
            '请输入"${ResetLocalDataPage.confirmWord}"以确认',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: CfSpace.xs),
          TextField(
            controller: _confirm,
            enabled: !running,
            autofillHints: null,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: '确认词',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (recovery is DatabaseRecoveryFailed) ...<Widget>[
            const SizedBox(height: CfSpace.sm),
            NoticeCard(
              icon: Icons.error_outline,
              tone: NoticeTone.danger,
              text: '重置没有完成（错误码：${recovery.code.code}），可以再试一次。',
            ),
          ],
          const SizedBox(height: CfSpace.md),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed:
                running ||
                    _confirm.text.trim() != ResetLocalDataPage.confirmWord
                ? null
                : () => unawaited(
                    ref.read(databaseRecoveryProvider.notifier).reset(),
                  ),
            child: Text(running ? '正在重置…' : ResetLocalDataPage.title),
          ),
        ],
      ),
    );
  }
}
