import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/db/database_errors.dart';
import '../../data/db/database_providers.dart';
import '../routes.dart';
import '../theme/tokens.dart';
import '../widgets/state_views.dart';
import 'app_gate.dart';

/// 打开失败时的说明（不含路径与正文）。
String describeDatabaseError(DatabaseErrorCode code) => switch (code) {
  DatabaseErrorCode.cipherUnavailable =>
    '安装包里的加密组件没有加载。为保护数据，卡序不会以明文方式打开本机数据。请重新安装，或把诊断信息发给开发者。',
  DatabaseErrorCode.plaintextDatabase => '本机数据库文件不是加密格式，已拒绝打开。请把诊断信息发给开发者。',
  DatabaseErrorCode.keyMissing =>
    '钥匙串里没有本机数据库的密钥（例如把设备备份恢复到了新手机）。原来的数据无法读取；可以重置本地数据后重新开始。',
  DatabaseErrorCode.keyInvalid => '钥匙串里的数据库密钥格式不对。请把诊断信息发给开发者。',
  DatabaseErrorCode.keyStoreFailed => '暂时读不到钥匙串（例如设备还没有解锁）。解锁后点「重试」。',
  DatabaseErrorCode.keyApplyFailed => '设置数据库密钥失败。请点「重试」；仍失败请把诊断信息发给开发者。',
  DatabaseErrorCode.wrongKey =>
    '钥匙串里的密钥打不开本机数据库（密钥不匹配或文件损坏）。原来的数据无法读取；可以重置本地数据后重新开始。',
  DatabaseErrorCode.schemaTooNew => '本机数据来自更新版本的卡序，请安装最新版本后再打开。',
  DatabaseErrorCode.migrationFailed => '升级本机数据库失败，升级已整体回滚，数据没有改动。可以点「重试」。',
  DatabaseErrorCode.foreignKeysUnavailable =>
    '数据库的关联检查没有生效，为避免数据错乱已拒绝打开。请把诊断信息发给开发者。',
  DatabaseErrorCode.resetFailed => '重置时删不掉数据库文件。请点「重试」。',
  DatabaseErrorCode.locationUnavailable => '取不到 App 的数据目录。请点「重试」。',
  DatabaseErrorCode.openFailed => '打开本机数据库失败。请点「重试」；仍失败请把诊断信息发给开发者。',
  DatabaseErrorCode.unsupportedPlatform => '当前平台没有本机加密数据库（只支持 iOS）。',
};

/// 可以在原页面「重试」的错误（审查 §4 第 7 条：不要求重启 App）。
const Set<DatabaseErrorCode> retryableDatabaseErrors = <DatabaseErrorCode>{
  DatabaseErrorCode.keyStoreFailed,
  DatabaseErrorCode.keyApplyFailed,
  DatabaseErrorCode.locationUnavailable,
  DatabaseErrorCode.openFailed,
  DatabaseErrorCode.migrationFailed,
  DatabaseErrorCode.resetFailed,
};

/// 提供「重置本地数据」的错误（BL-07）：数据已无法读取。
const Set<DatabaseErrorCode> resettableDatabaseErrors = <DatabaseErrorCode>{
  DatabaseErrorCode.keyMissing,
  DatabaseErrorCode.wrongKey,
};

/// 启动页：本机加密数据库打开中，或打开失败（错误码、说明、「重试」「重置本地数据」「诊断信息」）。
class StartupPage extends ConsumerWidget {
  const StartupPage({super.key});

  static const String title = '卡序';

  /// 打开中的文案。
  static const String loadingMessage = '正在打开本机加密数据…';

  /// 打开失败的标题。
  static const String errorTitle = '本机数据无法打开';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(appGateProvider);
    final recovery = ref.watch(databaseRecoveryProvider);
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: switch (gate) {
        GateDatabaseError(:final error) => ListView(
          children: <Widget>[
            ErrorBlockBody(
              title: errorTitle,
              code: error.code.code,
              detail: describeDatabaseError(error.code),
            ),
            if (recovery is DatabaseRecoveryFailed)
              NoticeCard(
                icon: Icons.error_outline,
                tone: NoticeTone.danger,
                text:
                    '重置没有完成（错误码：${recovery.code.code}）：${describeDatabaseError(recovery.code)}',
              ),
            Padding(
              padding: const EdgeInsets.all(CfSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (retryableDatabaseErrors.contains(error.code) ||
                      recovery is DatabaseRecoveryFailed) ...<Widget>[
                    FilledButton(
                      onPressed: () =>
                          ref.read(databaseRecoveryProvider.notifier).retry(),
                      child: const Text('重试'),
                    ),
                    const SizedBox(height: CfTouch.minGap),
                  ],
                  if (resettableDatabaseErrors.contains(
                    error.code,
                  )) ...<Widget>[
                    OutlinedButton(
                      onPressed: () => context.go(AppRoutes.resetLocalData),
                      child: const Text('重置本地数据'),
                    ),
                    const SizedBox(height: CfTouch.minGap),
                  ],
                  TextButton(
                    onPressed: () => context.go(AppRoutes.diagnostics),
                    child: const Text('诊断信息'),
                  ),
                ],
              ),
            ),
          ],
        ),
        _ => ListView(
          padding: const EdgeInsets.all(CfSpace.md),
          children: <Widget>[
            const SizedBox(height: CfSpace.xl),
            ExcludeSemantics(
              child: Icon(
                Icons.lock_outline,
                size: CfIconSize.emptyState,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: CfSpace.md),
            Text(
              loadingMessage,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      },
    );
  }
}
