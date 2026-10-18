import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/models.dart';
import '../../data/repositories/providers.dart';
import '../theme/tokens.dart';
import 'state_views.dart';

/// 顶栏空间标识：真实 / 演示（ui-spec §1.3）。
class WorkspaceBadge extends ConsumerWidget {
  const WorkspaceBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(currentWorkspaceProvider).value;
    if (workspace == null) {
      return const SizedBox.shrink();
    }
    final demo = workspace.kind == WorkspaceKind.demo;
    return Semantics(
      label: '当前空间：${workspace.kind.label}',
      child: ExcludeSemantics(
        child: StatusBadge(
          label: workspace.kind.label,
          icon: demo ? Icons.science_outlined : Icons.person_outline,
          tone: demo ? NoticeTone.unknown : NoticeTone.neutral,
        ),
      ),
    );
  }
}

/// 顶栏状态胶囊：纯本地（未连接服务器；ui-spec §1.3）。
class LocalOnlyPill extends StatelessWidget {
  const LocalOnlyPill({super.key});

  static const String label = '纯本地';

  @override
  Widget build(BuildContext context) {
    return const StatusBadge(
      label: label,
      icon: Icons.cloud_off_outlined,
      tone: NoticeTone.neutral,
    );
  }
}

/// 根页顶部的空间标识 + 纯本地（放在页面内容的第一行而不是 AppBar 的 actions：
/// 文字放大到 3 倍时可以换行，不会挤掉页名）。
class RootPageBadges extends StatelessWidget {
  const RootPageBadges({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(CfSpace.md, CfSpace.xs, CfSpace.md, 0),
      child: Wrap(
        spacing: CfSpace.xs,
        runSpacing: CfSpace.xxs,
        children: <Widget>[WorkspaceBadge(), LocalOnlyPill()],
      ),
    );
  }
}
