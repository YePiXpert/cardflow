import 'dart:async';

import 'package:cardflow_domain/cardflow_domain.dart' show fromMinorText;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/cf_layout.dart';
import '../../app/widgets/feedback.dart';
import '../../app/widgets/money_text.dart';
import '../../app/widgets/state_views.dart';
import '../../data/db/app_database.dart';
import '../../data/mapping/domain_mapping.dart';
import '../../data/repositories/card_repository.dart';
import '../../data/repositories/card_wallet_reader.dart';
import '../../data/repositories/ledger_home.dart';
import '../../data/repositories/ledger_reader.dart';
import '../../data/repositories/models.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/repository_errors.dart';
import '../../data/time/business_tz.dart';
import '../home/quick_statement_sheet.dart';
import '../statements/ledger_formatting.dart';
import 'card_detail_sections.dart';
import 'card_dialogs.dart';
import 'card_formatting.dart';

/// 卡片详情（P-03，简报 U-1 §3；设计稿 `card-dark.png`）：卡面（银行色、额度条）、本期进度、待还与最低还款、本期
/// 账单与未出账、三个主按钮（登记还款、记一笔、更新额度），下面依次是账单历史、分期摘要、可折叠的负债明细（原
/// 负债四分法）、卡片列表、额度详情、账期规则与授信池。"⋯"菜单放记本期账单、录入正式账单、人工修正、去还款的
/// 操作说明、换卡/补卡、冻结、销卡、账期设置。快捷"记本期账单""还清本期"是底部弹层。
///
/// 四态：加载（骨架）、错误（「重试」）、已不存在、成功；"首次空白"即还没有已出账单（本期进度写下期的预测账期）。
class AccountDetailPage extends ConsumerStatefulWidget {
  const AccountDetailPage({super.key, required this.accountId});

  final String accountId;

  /// 首次空白（还没有任何账单）的说明。
  static const String noStatementsNote = '还没有已出账单';

  /// 规则非法时的文案。
  static const String invalidRuleText = '规则非法，无法计算账期';

  /// 没有已核验官方链接时「去还款」显示的操作说明（ui-spec §4.1）。
  static const String instructions =
      '没有已核验的官方还款链接：请通过发卡行官方 App、官网或客服办理。卡序不会代你付款，也不会跳转。'
      '办完后回来「登记还款」，并在银行入账后补充证据。';

  @override
  ConsumerState<AccountDetailPage> createState() => _AccountDetailPageState();
}

class _AccountDetailPageState extends ConsumerState<AccountDetailPage> {
  String? _currency;

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletProvider);
    final ledger = ref.watch(ledgerProvider);
    final workspace = ref.watch(currentWorkspaceProvider).value;
    final account = wallet.value?.account(widget.accountId);
    final data = ledger.value;
    final sub = account?.currencies.firstWhere(
      (c) => c.currency == _currency,
      orElse: () => account.primaryCurrency,
    );
    final row = account == null || sub == null || data == null
        ? null
        : ledgerRowOf(data, account, sub);
    return Scaffold(
      appBar: AppBar(
        title: Text(row?.title ?? account?.displayName ?? '卡片'),
        actions: <Widget>[
          if (row != null)
            CircleIconButton(
              icon: Icons.more_horiz,
              tooltip: '更多操作',
              onPressed: () => unawaited(_showMenu(context, row)),
            ),
          const SizedBox(width: CfSpace.xs),
        ],
      ),
      body: switch ((wallet, ledger)) {
        (AsyncData(), _) when account == null => ErrorBlock(
          title: '已不存在',
          detail: '这个信用账户不在当前空间里（可能已切换空间）。',
          onRetry: () => context.go(AppRoutes.home),
          retryLabel: '回到卡账',
        ),
        (AsyncData(:final value), AsyncData(value: final ledgerData))
            when row != null =>
          _CardDetail(
            row: row,
            data: ledgerData,
            pool: value.poolOf(account!.id),
            demo: workspace?.isDemo ?? false,
            onCurrency: (c) => setState(() => _currency = c),
          ),
        (AsyncError(:final error), _) ||
        (_, AsyncError(:final error)) => ErrorBlock(
          title: '读取失败',
          code: '${error.runtimeType}',
          detail: '本机数据没有改动。',
          onRetry: () => ref
            ..invalidate(walletProvider)
            ..invalidate(ledgerProvider),
        ),
        _ => const LoadingSkeleton(rows: 4),
      },
    );
  }

  /// "⋯"菜单。
  Future<void> _showMenu(BuildContext context, CardLedgerRow row) async {
    final account = row.account;
    final current = row.current;
    final main = account.activeCards.isEmpty
        ? null
        : account.activeCards.firstWhere(
            (c) => c.kind == HolderKind.primary,
            orElse: () => account.activeCards.first,
          );
    final items = <(IconData, String, Future<void> Function())>[
      (
        Icons.edit_note,
        QuickStatementSheet.title,
        () => showQuickStatementSheet(context, account: account, sub: row.sub),
      ),
      (
        Icons.receipt_long_outlined,
        '录入正式账单（完整）',
        () async => context.go(
          AppRoutes.newStatement(
            accountId: account.id,
            currencyAccountId: row.currencyAccountId,
          ),
        ),
      ),
      if (current != null)
        (
          Icons.edit_outlined,
          '人工修正本期账单',
          () async => context.go(
            AppRoutes.correctStatement(
              current.statement.id,
              accountId: account.id,
            ),
          ),
        ),
      (Icons.help_outline, '去还款：查看操作说明', () => _showInstructions(context, row)),
      if (main != null && main.cardStatus.canBecome(CardStatus.replaced))
        (
          Icons.autorenew,
          '换卡/补卡（${cardTail(main)}）',
          () => replaceCardFlow(context, ref, main, account),
        ),
      if (main != null && main.cardStatus == CardStatus.active)
        (
          Icons.ac_unit,
          '冻结（${cardTail(main)}）',
          () => runCardAction(context, ref, (r) => r.freeze(main.id), '已冻结'),
        ),
      if (main != null && main.cardStatus == CardStatus.frozen)
        (
          Icons.lock_open,
          '解冻（${cardTail(main)}）',
          () => runCardAction(context, ref, (r) => r.unfreeze(main.id), '已解冻'),
        ),
      if (main != null && main.cardStatus.canBecome(CardStatus.closed))
        (
          Icons.block,
          '销卡（${cardTail(main)}）',
          () => closeCardFlow(context, ref, main, account),
        ),
      (
        Icons.event_repeat,
        '账期设置',
        () async =>
            context.go(AppRoutes.accountSettings(account.id, section: 'rule')),
      ),
      (
        Icons.tune,
        '账户设置（额度、币种、授信池）',
        () async => context.go(AppRoutes.accountSettings(account.id)),
      ),
    ];
    final chosen = await showModalBottomSheet<int>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var i = 0; i < items.length; i++)
                ListTile(
                  leading: Icon(items[i].$1),
                  title: Text(items[i].$2),
                  onTap: () => Navigator.of(sheetContext).pop(i),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null && context.mounted) {
      await items[chosen].$3();
    }
  }

  Future<void> _showInstructions(
    BuildContext context,
    CardLedgerRow row,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final card = row.account.activeCards.isEmpty
        ? null
        : row.account.activeCards.first;
    final remaining = row.remaining;
    Future<void> copy(String text, String what) async {
      await Clipboard.setData(ClipboardData(text: text));
      showFeedback(messenger, '已复制$what');
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('查看操作说明'),
        content: const SingleChildScrollView(
          child: Text(AccountDetailPage.instructions),
        ),
        actions: <Widget>[
          if (remaining != null && remaining > 0)
            TextButton(
              onPressed: () =>
                  unawaited(copy(fromMinorText(remaining, row.currency), '金额')),
              child: const Text('复制金额'),
            ),
          if (card != null)
            TextButton(
              onPressed: () => unawaited(copy(card.last4, '末四位')),
              child: const Text('复制末四位'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

class _CardDetail extends StatelessWidget {
  const _CardDetail({
    required this.row,
    required this.data,
    required this.pool,
    required this.demo,
    required this.onCurrency,
  });

  final CardLedgerRow row;
  final LedgerData data;
  final PoolView? pool;
  final bool demo;
  final ValueChanged<String> onCurrency;

  @override
  Widget build(BuildContext context) {
    final account = row.account;
    final sub = row.sub;
    final liability = data.liabilities[sub.row.id];
    final unreleased = LedgerReader.unreleasedRepayments(data, sub.row.id);
    const side = EdgeInsets.symmetric(horizontal: CfSpace.md);
    return ListView(
      padding: const EdgeInsets.only(top: CfSpace.xxs, bottom: CfSpace.xl),
      children: <Widget>[
        if (account.currencies.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CfSpace.md,
              0,
              CfSpace.md,
              CfSpace.sm,
            ),
            child: Wrap(
              spacing: CfSpace.xs,
              runSpacing: CfSpace.xs,
              children: <Widget>[
                for (final c in account.currencies)
                  ChoiceChip(
                    label: Text(currencyLabel(c.currency)),
                    selected: c.currency == sub.currency,
                    onSelected: (_) => onCurrency(c.currency),
                  ),
              ],
            ),
          ),
        Padding(
          padding: side,
          child: CardFace(row: row),
        ),
        const SizedBox(height: CfSpace.sm),
        Padding(
          padding: side,
          child: CycleCard(row: row),
        ),
        const SizedBox(height: CfSpace.sm),
        Padding(
          padding: side,
          child: AmountGrid(row: row, liability: liability),
        ),
        const SizedBox(height: CfSpace.sm),
        Padding(
          padding: side,
          child: DetailActions(row: row),
        ),
        StatementHistory(row: row, data: data),
        InstallmentSummary(row: row, data: data),
        if (unreleased > 0) ...<Widget>[
          LedgerAmountRow(
            label: '已银行入账、尚未计入额度的还款',
            minor: unreleased,
            currency: sub.currency,
          ),
          const NoticeCard(
            icon: Icons.schedule,
            tone: NoticeTone.unknown,
            text: '额度释放时滞未知：银行入账后暂不计入可用容量，以新的额度快照为准。',
          ),
        ],
        const SectionTitle('卡片'),
        GroupCard(
          children: <Widget>[
            for (final card in account.activeCards)
              _CardRowTile(card: card, account: account),
          ],
        ),
        if (account.inactiveCards.isNotEmpty)
          ExpansionTile(
            title: Text('已停用的卡（${account.inactiveCards.length}）'),
            children: <Widget>[
              for (final card in account.inactiveCards)
                _CardRowTile(card: card, account: account),
            ],
          ),
        const SectionTitle('更多信息'),
        GroupCard(
          dividerIndent: 0,
          children: <Widget>[
            if (liability != null)
              ExpansionTile(
                title: const Text('负债明细'),
                subtitle: const Text('负债四分法：本期应还、未出账、未来分期本金'),
                children: <Widget>[LiabilitySection.of(liability)],
              ),
            ExpansionTile(
              title: const Text('额度详情'),
              subtitle: Text(
                sub.latestSnapshot == null
                    ? '还没有额度快照'
                    : '快照 ${ageText(sub.snapshotAgeDays ?? 0)}',
              ),
              children: <Widget>[_LimitSection(sub: sub)],
            ),
            ExpansionTile(
              title: Text(demo ? '账期规则（仅示例）' : '账期规则'),
              subtitle: Text(_ruleSummary(row)),
              children: <Widget>[
                _RuleExplanation(account: account, sub: sub),
                Padding(
                  padding: const EdgeInsets.all(CfSpace.md),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton(
                      onPressed: () => context.go(
                        AppRoutes.accountSettings(account.id, section: 'rule'),
                      ),
                      child: const Text('修改账期规则'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        if (pool != null)
          NoticeCard(
            icon: Icons.account_tree_outlined,
            tone: NoticeTone.unknown,
            text: '授信池「${pool!.pool.name}」：与同池账户共享额度，池内账户可用合计不超过池可用。',
          ),
        const NoticeCard(
          icon: Icons.schedule,
          tone: NoticeTone.unknown,
          text: '本账户的活动、权益、积分与年费在后续版本提供。',
        ),
      ],
    );
  }

  static String _ruleSummary(CardLedgerRow row) => switch (row.forecast) {
    ForecastNoRule() => '未设置',
    ForecastInvalid() => AccountDetailPage.invalidRuleText,
    ForecastPredicted() => () {
      final versions = row.sub.ruleVersions;
      final rule = versions.isEmpty ? null : versions.last;
      return rule == null
          ? '已设置'
          : '${describeStatementDay(rule.statementDay)}出账 · ${describeDue(dueOf(rule))}到期';
    }(),
  };
}

/// 换卡/补卡：新末四位 + 生效日，旧卡 replaced、新卡 active。
Future<void> replaceCardFlow(
  BuildContext context,
  WidgetRef ref,
  CardRow card,
  AccountView account,
) async {
  final input = await showReplaceCardDialog(
    context,
    oldTail: cardTail(card),
    today: account.today,
  );
  if (input == null || !context.mounted) {
    return;
  }
  await runCardAction(
    context,
    ref,
    (repo) => repo.replace(
      card.id,
      newLast4: input.last4,
      effectiveFrom: input.effectiveFrom,
    ),
    '已换卡，历史不变',
  );
}

/// 销卡：销卡日不晚于今天。
Future<void> closeCardFlow(
  BuildContext context,
  WidgetRef ref,
  CardRow card,
  AccountView account,
) async {
  final closedOn = await showCloseCardDialog(
    context,
    tail: cardTail(card),
    today: account.today,
  );
  if (closedOn == null || !context.mounted) {
    return;
  }
  await runCardAction(
    context,
    ref,
    (repo) => repo.close(card.id, closedOn: closedOn),
    '已销卡',
  );
}

/// 调用卡片仓库并给出轻提示（失败时显示仓库的说明）。
Future<void> runCardAction(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function(CardRepository repo) action,
  String success,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final repo = await ref.read(cardRepositoryProvider.future);
    await action(repo);
    showFeedback(messenger, success);
  } on RepositoryException catch (error) {
    showFeedback(messenger, error.message);
  }
}

/// 额度区：固定/临时/专项、银行可用原值（可负，"超限"）、是否已含预授权、可用容量、快照时点。
class _LimitSection extends StatelessWidget {
  const _LimitSection({required this.sub});

  final CurrencyAccountView sub;

  @override
  Widget build(BuildContext context) {
    final snapshot = sub.latestSnapshot;
    if (snapshot == null) {
      return const NoticeCard(
        icon: Icons.checklist,
        text: '还没有额度快照：可用容量未知（不以 0 代替）。点「更新额度」记录。',
      );
    }
    final c = sub.currency;
    final expires = parseOptionalDate(snapshot.tempExpiresOn);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LabeledValue(
          label: '固定额度',
          value: MoneyText(
            minor: snapshot.fixedMinor,
            currency: c,
            semanticsPrefix: '固定额度',
          ),
        ),
        if (snapshot.tempMinor > 0)
          LabeledValue(
            label: expires == null ? '临时额度' : '临时额度（${formatDate(expires)} 到期）',
            value: MoneyText(
              minor: snapshot.tempMinor,
              currency: c,
              semanticsPrefix: '临时额度',
            ),
          ),
        if (snapshot.specialMinor > 0)
          LabeledValue(
            label: '专项额度（${snapshot.specialPurpose ?? ''}，不用于普通消费）',
            value: MoneyText(
              minor: snapshot.specialMinor,
              currency: c,
              semanticsPrefix: '专项额度',
            ),
          ),
        LabeledValue(
          label: '已用',
          value: MoneyText(
            minor: snapshot.usedMinor,
            currency: c,
            semanticsPrefix: '已用',
          ),
        ),
        LabeledValue(
          label: '银行可用（原值）',
          value: MoneyText(
            minor: snapshot.availableRawMinor,
            currency: c,
            negativeLabel: '超限',
            semanticsPrefix: '银行可用',
          ),
        ),
        LabeledValue(
          label: '预授权',
          value: Text(
            snapshot.includesHolds ? '已含在银行可用里，不再扣减' : '未含在银行可用里，按已知金额扣减',
          ),
        ),
        if (!snapshot.includesHolds && snapshot.holdsMinor > 0)
          LabeledValue(
            label: '预授权金额',
            value: MoneyText(
              minor: snapshot.holdsMinor,
              currency: c,
              semanticsPrefix: '预授权',
            ),
          ),
        LabeledValue(
          label: '可用容量',
          value: MoneyText(
            minor: sub.capacity,
            currency: c,
            semanticsPrefix: '可用容量',
          ),
        ),
        if (sub.overLimit)
          const NoticeCard(
            icon: Icons.warning_amber_outlined,
            tone: NoticeTone.danger,
            text: '超限：银行可用额为负（原值保留），可供新增消费的容量为 0。',
          ),
        LabeledValue(
          label: '快照时点',
          value: Text(
            '${snapshot.balanceAsOf.substring(0, 16).replaceFirst('T', ' ')} · ${ageText(sub.snapshotAgeDays ?? 0)}',
          ),
        ),
        if (sub.stale)
          const NoticeCard(
            icon: Icons.schedule,
            text: '额度快照已超过 7 天，可用容量只是假设分析。',
          ),
      ],
    );
  }
}

/// 一张卡与它的操作（换卡/补卡、冻结/解冻、销卡）。
class _CardRowTile extends ConsumerWidget {
  const _CardRowTile({required this.card, required this.account});

  final CardRow card;
  final AccountView account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = card.cardStatus;
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: CardFlowColors.of(context).textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CfSpace.md,
        CfSpace.sm,
        CfSpace.md,
        CfSpace.xxs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(cardSummary(card), style: theme.textTheme.bodyLarge),
          if (card.alias != null) Text(card.alias!, style: secondary),
          if (card.effectiveFrom != null)
            Text('生效日 ${card.effectiveFrom}', style: secondary),
          if (card.closedOn != null)
            Text('销卡日 ${card.closedOn}', style: secondary),
          if (!status.isInactive)
            Wrap(
              spacing: CfSpace.xs,
              children: <Widget>[
                if (status.canBecome(CardStatus.replaced))
                  TextButton(
                    onPressed: () =>
                        unawaited(replaceCardFlow(context, ref, card, account)),
                    child: const Text('换卡/补卡'),
                  ),
                if (status == CardStatus.active)
                  TextButton(
                    onPressed: () => unawaited(
                      runCardAction(
                        context,
                        ref,
                        (r) => r.freeze(card.id),
                        '已冻结',
                      ),
                    ),
                    child: const Text('冻结'),
                  ),
                if (status == CardStatus.frozen)
                  TextButton(
                    onPressed: () => unawaited(
                      runCardAction(
                        context,
                        ref,
                        (r) => r.unfreeze(card.id),
                        '已解冻',
                      ),
                    ),
                    child: const Text('解冻'),
                  ),
                if (status.canBecome(CardStatus.closed))
                  TextButton(
                    onPressed: () =>
                        unawaited(closeCardFlow(context, ref, card, account)),
                    child: const Text('销卡'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 规则说明：当天归属、到期、顺延、入账延迟、截止时点、业务时区（ui-spec P-03）。
class _RuleExplanation extends StatelessWidget {
  const _RuleExplanation({required this.account, required this.sub});

  final AccountView account;
  final CurrencyAccountView sub;

  @override
  Widget build(BuildContext context) {
    final forecast = sub.forecast;
    BillingRuleVersionRow? rule;
    if (forecast is ForecastPredicted) {
      rule = sub.ruleVersions.firstWhere((r) => r.id == forecast.ruleVersionId);
    } else if (sub.ruleVersions.isNotEmpty) {
      rule = sub.ruleVersions.last;
    }
    if (rule == null) {
      return const NoticeCard(icon: Icons.checklist, text: '账期规则未设置。');
    }
    final lines = <(String, String)>[
      ('账单日', describeStatementDay(rule.statementDay)),
      ('当天归属', describeInclusive(rule.statementDayInclusive)),
      ('到期', describeDue(dueOf(rule))),
      ('顺延', describeRollover(rule.holidayRollover)),
      (
        '入账延迟',
        describePostingDelay(
          rule.postingDelayMinDays,
          rule.postingDelayMaxDays,
        ),
      ),
      ('截止时点', describeCutoff(rule.cutoffTime)),
      ('业务时区', describeZone(account.account.businessTz)),
      ('规则版本', '第 ${rule.version} 版 · ${describeEffectiveRange(rule)}'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final (label, value) in lines)
          LabeledValue(label: label, value: Text(value)),
        if (findBusinessTimeZone(account.account.businessTz) == null)
          const NoticeCard(icon: Icons.public, text: '该时区本期不支持。'),
      ],
    );
  }
}
