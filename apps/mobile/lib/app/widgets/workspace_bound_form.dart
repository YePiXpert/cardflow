import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../data/repositories/providers.dart';
import '../../data/repositories/repository_errors.dart';

/// 全屏表单绑定打开时的工作空间（审查 R-15）：打开时记下当前工作空间 id，保存时用 [boundRepository] 取仓库——
/// 当前工作空间已经不是打开时的那个（进入/退出演示、切换空间之后表单还留在屏幕上）就抛
/// [WorkspaceChangedException]，表单把它当作保存失败显示，不会写进另一个空间。
///
/// 切换空间时路由也会回到首页并清空页面栈（`appRouterProvider`、`HomeShell`），这里是第二道防线。
mixin WorkspaceBoundForm<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  String? _openedIn;

  /// 打开表单时的工作空间 id（测试用）。
  String? get openedInWorkspace => _openedIn;

  @override
  void initState() {
    super.initState();
    _openedIn = ref.read(currentWorkspaceProvider).value?.id;
  }

  /// 保存前取仓库：当前工作空间与打开表单时相同才返回，否则抛 [WorkspaceChangedException]。
  Future<R> boundRepository<R>(ProviderListenable<Future<R>> provider) async {
    final repository = await ref.read(provider);
    final scope = await ref.read(workspaceScopeProvider.future);
    if (_openedIn == null || scope.workspaceId != _openedIn) {
      throw const WorkspaceChangedException();
    }
    return repository;
  }
}
