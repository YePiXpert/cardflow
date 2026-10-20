import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../routes.dart';
import '../theme/tokens.dart';

/// 未匹配到路由时的页面（ui-spec §2：NOT_FOUND →"已不存在"）。
class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  /// 页名。
  static const String title = '页面不存在';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(CfSpace.md),
        children: <Widget>[
          const SizedBox(height: CfSpace.xl),
          Text(
            '已不存在',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: CfSpace.lg),
          FilledButton(
            onPressed: () => context.go(AppRoutes.home),
            child: const Text('回到卡账'),
          ),
        ],
      ),
    );
  }
}
