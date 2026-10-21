import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../app/widgets/state_views.dart';
import '../../data/repositories/providers.dart';
import '../settings/public_beta.dart';
import 'workspace_actions.dart';

/// 一种开始方式。[stage] 非空表示本期不可用（按钮禁用，旁边注明所属阶段）。
@immutable
class StartOption {
  const StartOption(this.label, {this.stage});

  final String label;
  final String? stage;
}

/// P-22 首次使用/欢迎/演示模式（ui-spec §6、UF-1 步骤 1）；底部是公测说明（与「关于」同一段）。
///
/// [firstRun] 为 true：没有工作空间时的入口（任何路由都先到这里，没有返回按钮）；false：从
/// "我的 › 欢迎与开始方式"进入，可返回。
class WelcomePage extends ConsumerStatefulWidget {
  const WelcomePage({super.key, this.firstRun = false});

  final bool firstRun;

  /// 页名。
  static const String title = '欢迎使用卡序';

  /// ui-spec P-22 布局"欢迎"区的四条边界。
  static const List<String> boundaries = <String>[
    '消费前比较用哪张卡',
    '无需注册',
    '不发起支付',
    '结果可解释',
    '不实时同步银行',
  ];

  /// 开始方式：手工建卡与体验演示。
  static const List<StartOption> startOptions = <StartOption>[
    StartOption('手工建卡'),
    StartOption('体验演示'),
  ];

  /// 演示数据生成中的文案（加载态）。
  static const String demoLoading = '演示数据生成中…';

  /// 演示数据生成失败的文案（错误态）。
  static const String demoFailed = '演示数据生成失败，真实数据不受影响。';

  @override
  ConsumerState<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends ConsumerState<WelcomePage> {
  bool _demoRunning = false;
  Object? _demoError;

  Future<void> _startDemo() async {
    setState(() {
      _demoRunning = true;
      _demoError = null;
    });
    try {
      await enterDemoWorkspace(context, ref);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _demoError = error);
      }
    } finally {
      if (mounted) {
        setState(() => _demoRunning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final current = ref.watch(currentWorkspaceProvider).value;
    final demoRows = ref.watch(demoWorkspaceRowsProvider).value;
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: colors.textSecondary,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text(WelcomePage.title),
        automaticallyImplyLeading: !widget.firstRun,
      ),
      body: ListView(
        padding: const EdgeInsets.all(CfSpace.md),
        children: <Widget>[
          Text('使用边界', style: theme.textTheme.titleMedium),
          const SizedBox(height: CfSpace.xs),
          for (final item in WelcomePage.boundaries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: CfSpace.xxs),
              child: Row(
                children: <Widget>[
                  ExcludeSemantics(
                    child: Icon(
                      Icons.check_circle_outline,
                      size: CfIconSize.md,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: CfSpace.xs),
                  Expanded(child: Text(item, style: theme.textTheme.bodyLarge)),
                ],
              ),
            ),
          const SizedBox(height: CfSpace.lg),
          Text('开始方式', style: theme.textTheme.titleMedium),
          const SizedBox(height: CfSpace.xs),
          for (final option in WelcomePage.startOptions) ...<Widget>[
            _optionButton(option),
            if (option.stage != null)
              Padding(
                padding: const EdgeInsets.only(top: CfSpace.xxs),
                child: Text(
                  '${option.label}：${option.stage}',
                  style: secondary,
                ),
              ),
            const SizedBox(height: CfTouch.minGap),
          ],
          if (_demoRunning)
            const NoticeCard(
              icon: Icons.hourglass_empty,
              tone: NoticeTone.unknown,
              text: WelcomePage.demoLoading,
            ),
          if (_demoError != null)
            NoticeCard(
              icon: Icons.error_outline,
              tone: NoticeTone.danger,
              text: '${WelcomePage.demoFailed}（${_demoError.runtimeType}）',
              action: TextButton(
                onPressed: () => unawaited(_startDemo()),
                child: const Text('重试生成'),
              ),
            ),
          const SizedBox(height: CfSpace.lg),
          Text('建议', style: theme.textTheme.titleMedium),
          const SizedBox(height: CfSpace.xs),
          Text('在 iPhone 设置里开启锁屏密码；卡序自己的应用锁在后续版本提供。', style: secondary),
          const SizedBox(height: CfSpace.xxs),
          Text('提醒需要通知权限，等用到提醒时再请求。', style: secondary),
          const SizedBox(height: CfSpace.lg),
          Text('演示模式', style: theme.textTheme.titleMedium),
          const SizedBox(height: CfSpace.xs),
          Text(
            '演示空间是合成的示例数据（规则与金额仅示例），与真实数据隔离、互不可见，'
            '不同步、不导出、不合并到真实空间。进入后每一页顶部都有紫色横幅。',
            style: secondary,
          ),
          if (current != null && current.isDemo) ...<Widget>[
            const SizedBox(height: CfSpace.sm),
            OutlinedButton(
              onPressed: () => unawaited(
                ref.read(currentWorkspaceProvider.notifier).exitDemo(),
              ),
              child: const Text('退出演示'),
            ),
          ],
          if (demoRows != null) ...<Widget>[
            const SizedBox(height: CfSpace.sm),
            OutlinedButton(
              onPressed: () =>
                  unawaited(clearDemoWorkspace(context, ref, demoRows)),
              child: const Text('清除演示数据'),
            ),
          ],
          const SizedBox(height: CfSpace.lg),
          Text(PublicBeta.noteTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: CfSpace.xs),
          const PublicBetaNotice(margin: EdgeInsets.zero),
        ],
      ),
    );
  }

  Widget _optionButton(StartOption option) {
    final VoidCallback? onPressed = switch (option.label) {
      _ when option.stage != null => null,
      '手工建卡' => () => unawaited(startManualCard(context, ref)),
      '体验演示' => _demoRunning ? null : () => unawaited(_startDemo()),
      _ => null,
    };
    if (option.label == '手工建卡') {
      return FilledButton(onPressed: onPressed, child: Text(option.label));
    }
    return OutlinedButton(onPressed: onPressed, child: Text(option.label));
  }
}
