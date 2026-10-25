import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../app/widgets/calm_panel.dart';
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

/// 欢迎与演示模式页面；底部是公测说明（与「关于」同一段）。
class WelcomePage extends ConsumerStatefulWidget {
  const WelcomePage({super.key, this.firstRun = false});

  final bool firstRun;

  /// 页名。
  static const String title = '欢迎使用卡序';

  /// 核心功能说明。
  static const List<String> boundaries = <String>[
    '按账单日与还款日，自动排出免息期最长的卡片',
    '单卡额度不足时，自动生成多张卡组合拆分方案',
    '账单日前夕智能提示“再等几天刷，多压一个月账期”',
    '数据纯本机加密保存，无需注册，不联网、不发起支付',
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
          CalmPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('核心功能', style: theme.textTheme.titleMedium),
                const SizedBox(height: CfSpace.sm),
                for (final item in WelcomePage.boundaries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: CfSpace.xxs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ExcludeSemantics(
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: CfSpace.xxs / 2,
                            ),
                            child: Icon(
                              Icons.check_circle_rounded,
                              size: CfIconSize.md,
                              color: colors.action,
                            ),
                          ),
                        ),
                        const SizedBox(width: CfSpace.xs),
                        Expanded(
                          child: Text(item, style: theme.textTheme.bodyLarge),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: CfSpace.md),
          CalmPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('开始使用', style: theme.textTheme.titleMedium),
                const SizedBox(height: CfSpace.sm),
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
                Text(
                  '演示模式预置了多张示例卡片与账期规则，与你的真实卡片数据完全独立，可随时退出。',
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
              ],
            ),
          ),
          if (_demoRunning) ...<Widget>[
            const SizedBox(height: CfSpace.sm),
            const NoticeCard(
              icon: Icons.hourglass_empty,
              tone: NoticeTone.unknown,
              text: WelcomePage.demoLoading,
            ),
          ],
          if (_demoError != null) ...<Widget>[
            const SizedBox(height: CfSpace.sm),
            NoticeCard(
              icon: Icons.error_outline,
              tone: NoticeTone.danger,
              text: '${WelcomePage.demoFailed}（${_demoError.runtimeType}）',
              action: TextButton(
                onPressed: () => unawaited(_startDemo()),
                child: const Text('重试生成'),
              ),
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
