import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/feedback.dart';
import '../../app/widgets/state_views.dart';
import '../../app/widgets/workspace_bound_form.dart';
import '../../data/db/app_database.dart';
import '../../data/ids.dart';
import '../../data/repositories/card_repository.dart';
import '../../data/repositories/card_wallet_reader.dart';
import '../../data/repositories/credit_account_repository.dart';
import '../../data/repositories/models.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/repository_errors.dart';
import '../../data/validation/text_rules.dart';
import 'card_formatting.dart';
import 'card_providers.dart';

/// 新建卡片后挂到哪个信用账户。
enum _AccountTarget { newAccount, existing }

/// 选择器里"其他银行"的取值。
const String _customBank = '\u0000custom';

/// P-02 的新建弹层（全屏，覆盖底部导航）：银行、产品名、别名、末四位、卡组织、持卡人、主/附、
/// 到期年月（ui-spec P-02）。
///
/// - G2：任何文本含完整卡号（≥13 位连续数字，含粘贴、全角）当场提示"卡序不保存完整卡号"，不能保存；
/// - 末四位必须恰好 4 位数字；附卡须指定主卡；G5 长度；
/// - 同银行同末四位 → "可能是同一信用账户的另一张卡"（加入既有账户 / 新建账户）；
/// - 关闭系统自动填充（`autofillHints: null`），不会弹出卡号填充；
/// - 保存同时生成信用账户（默认 CNY 子账户）与卡片，状态 draft → active；失败时表单保留，
///   「重试保存」沿用同一组 id，不会重复建卡。
class NewCardPage extends ConsumerStatefulWidget {
  const NewCardPage({super.key});

  static const String title = '添加卡片';

  /// 同银行同末四位时的提示标题。
  static const String sameAccountTitle = '可能是同一信用账户的另一张卡';

  /// 保存成功的轻提示。
  static const String savedMessage = '已添加';

  @override
  ConsumerState<NewCardPage> createState() => _NewCardPageState();
}

class _NewCardPageState extends ConsumerState<NewCardPage>
    with WorkspaceBoundForm {
  final String _cardId = newUuidV4();
  final String _accountId = newUuidV4();

  final TextEditingController _bankName = TextEditingController();
  final TextEditingController _product = TextEditingController();
  final TextEditingController _alias = TextEditingController();
  final TextEditingController _last4 = TextEditingController();
  final TextEditingController _holder = TextEditingController(
    text: defaultHolderAlias,
  );
  final TextEditingController _expires = TextEditingController();

  HolderKind _kind = HolderKind.primary;
  String? _bank;
  _AccountTarget _target = _AccountTarget.newAccount;
  String? _joinAccountId;
  String? _primaryCardId;
  CardNetwork? _network;

  bool _saving = false;
  String? _saveError;
  final Map<String, String> _errors = <String, String>{};

  @override
  void dispose() {
    for (final c in <TextEditingController>[
      _bankName,
      _product,
      _alias,
      _last4,
      _holder,
      _expires,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? get _effectiveBank =>
      _bank == _customBank ? _bankName.text.trim() : _bank;

  /// 逐字段校验（输入时与保存时都调用）；返回是否全部通过。
  bool _validate() {
    final errors = <String, String>{};
    void check(String field, String? problem) {
      if (problem != null) {
        errors[field] = problem;
      }
    }

    check('last4', validateLast4(_last4.text));
    check('alias', validateFreeText(_alias.text, fieldName: '别名'));
    check('productName', validateFreeText(_product.text, fieldName: '产品名'));
    check(
      'holderAlias',
      validateFreeText(_holder.text, required: true, fieldName: '持卡人'),
    );
    final expires = _expires.text.trim();
    if (looksLikeFullCardNumber(expires)) {
      errors['expiresYm'] = fullCardNumberMessage;
    } else if (expires.isNotEmpty &&
        !RegExp(r'^[0-9]{4}-(0[1-9]|1[0-2])$').hasMatch(expires)) {
      errors['expiresYm'] = '到期年月格式应为 YYYY-MM，如 2030-12';
    }
    if (_kind == HolderKind.supplementary) {
      if (_primaryCardId == null) {
        errors['primaryCard'] = '附属卡须指定主卡';
      }
    } else {
      if (_bank == _customBank) {
        check(
          'bank',
          validateFreeText(_bankName.text, required: true, fieldName: '银行名称'),
        );
      } else if (_bank == null) {
        errors['bank'] = '请选择银行';
      }
      if (_target == _AccountTarget.existing && _joinAccountId == null) {
        errors['account'] = '请选择要加入的信用账户';
      }
    }
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
    });
    return errors.isEmpty;
  }

  /// 输入时只显示"完整卡号"这一类即时错误（其余在保存时提示），粘贴整段卡号立刻拦下。
  void _onTextChanged() {
    final g2 = <String, String>{};
    for (final (field, controller) in <(String, TextEditingController)>[
      ('last4', _last4),
      ('alias', _alias),
      ('productName', _product),
      ('holderAlias', _holder),
      ('bank', _bankName),
      ('expiresYm', _expires),
    ]) {
      if (looksLikeFullCardNumber(controller.text)) {
        g2[field] = fullCardNumberMessage;
      }
    }
    setState(() {
      _errors.removeWhere((field, message) => message == fullCardNumberMessage);
      _errors.addAll(g2);
    });
  }

  Future<void> _save(WalletView wallet) async {
    if (_saving || !_validate()) {
      return;
    }
    var joinAccountId = _target == _AccountTarget.existing
        ? _joinAccountId
        : null;
    final CardRepository repo;
    try {
      repo = await boundRepository(cardRepositoryProvider.future);
    } on RepositoryException catch (error) {
      if (mounted) {
        setState(() => _saveError = error.message);
      }
      return;
    }
    if (!mounted) {
      return;
    }
    if (_kind == HolderKind.primary && joinAccountId == null) {
      final hits = await repo.sameBankSameLast4(
        bankName: _effectiveBank!,
        last4: _last4.text,
      );
      if (!mounted) {
        return;
      }
      if (hits.isNotEmpty) {
        final choice = await _askSameAccount();
        if (!mounted || choice == null) {
          return;
        }
        if (choice) {
          joinAccountId = hits.first.creditAccountId;
        }
      }
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await repo.create(
        NewCardDraft(
          cardId: _cardId,
          newAccountId: _accountId,
          bankName: _kind == HolderKind.primary ? _effectiveBank : null,
          productName: _product.text,
          alias: _alias.text,
          last4: _last4.text,
          network: _network,
          holderAlias: _holder.text,
          holderKind: _kind,
          primaryCardId: _kind == HolderKind.supplementary
              ? _primaryCardId
              : null,
          joinAccountId: joinAccountId,
          expiresYm: _expires.text,
        ),
      );
      router.go(AppRoutes.cards);
      showFeedback(
        messenger,
        NewCardPage.savedMessage,
        action: SnackBarAction(
          label: '设置账期',
          onPressed: () => router.go(
            AppRoutes.accountSettings(result.creditAccountId, section: 'rule'),
          ),
        ),
      );
    } on ValidationException catch (error) {
      if (mounted) {
        setState(() {
          _errors[error.field] = error.message;
          _saveError = error.message;
        });
      }
    } on RepositoryException catch (error) {
      if (mounted) {
        setState(() => _saveError = error.message);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _saveError = '保存失败（${error.runtimeType}）');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  /// true = 加入既有账户；false = 新建账户；null = 取消。
  Future<bool?> _askSameAccount() => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text(NewCardPage.sameAccountTitle),
      content: const Text(
        '这家银行已有一张同样末四位的卡。如果它们是同一授信（例如主卡与附属卡、补发的卡），请加入既有账户，账单只会有一份。',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('新建账户'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('加入既有账户'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletProvider);
    final banks = ref.watch(bankChoicesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(NewCardPage.title),
        leading: IconButton(
          tooltip: '取消',
          icon: const Icon(Icons.close),
          onPressed: () => context.go(AppRoutes.cards),
        ),
      ),
      body: switch ((wallet, banks)) {
        (AsyncData(value: final w), AsyncData(value: final b)) => _form(
          context,
          w,
          b.map((c) => c.name).toList(),
        ),
        (AsyncError(:final error), _) ||
        (_, AsyncError(:final error)) => ErrorBlock(
          title: '读取失败',
          code: '${error.runtimeType}',
          onRetry: () => ref
            ..invalidate(walletProvider)
            ..invalidate(bankChoicesProvider),
        ),
        _ => const LoadingSkeleton(rows: 4),
      },
    );
  }

  Widget _form(BuildContext context, WalletView wallet, List<String> banks) {
    final theme = Theme.of(context);
    final colors = CardFlowColors.of(context);
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: colors.textSecondary,
    );
    final primaryCards = <(AccountView, CardRow)>[
      for (final account in wallet.accounts)
        for (final card in account.activeCards)
          if (card.kind == HolderKind.primary) (account, card),
    ];
    final bankAccounts = wallet.accounts
        .where((a) => !a.isInactive && a.bank.name == _effectiveBank)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(CfSpace.md),
      children: <Widget>[
        Text('卡片类型', style: theme.textTheme.titleMedium),
        const SizedBox(height: CfSpace.xs),
        Wrap(
          spacing: CfSpace.xs,
          runSpacing: CfSpace.xs,
          children: <Widget>[
            for (final kind in HolderKind.values)
              ChoiceChip(
                label: Text(kind.label),
                selected: _kind == kind,
                onSelected: (_) => setState(() => _kind = kind),
              ),
          ],
        ),
        const SizedBox(height: CfSpace.md),
        if (_kind == HolderKind.supplementary) ...<Widget>[
          if (primaryCards.isEmpty)
            const NoticeCard(
              icon: Icons.info_outline,
              tone: NoticeTone.unknown,
              text: '还没有主卡。附属卡须挂在一张主卡上，请先添加主卡。',
            )
          else
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _primaryCardId,
              decoration: InputDecoration(
                labelText: '主卡',
                errorText: _errors['primaryCard'],
                border: const OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<String>>[
                for (final (account, card) in primaryCards)
                  DropdownMenuItem<String>(
                    value: card.id,
                    child: Text(
                      '${account.displayName} · ${account.bank.name} · ${cardTail(card)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _primaryCardId = value),
            ),
        ] else ...<Widget>[
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _bank,
            decoration: InputDecoration(
              labelText: '银行',
              errorText: _bank == _customBank ? null : _errors['bank'],
              border: const OutlineInputBorder(),
            ),
            items: <DropdownMenuItem<String>>[
              for (final name in banks)
                DropdownMenuItem<String>(
                  value: name,
                  child: Text(name, overflow: TextOverflow.ellipsis),
                ),
              const DropdownMenuItem<String>(
                value: _customBank,
                child: Text('其他银行（手动输入）', overflow: TextOverflow.ellipsis),
              ),
            ],
            onChanged: (value) => setState(() {
              _bank = value;
              _joinAccountId = null;
            }),
          ),
          if (_bank == _customBank) ...<Widget>[
            const SizedBox(height: CfSpace.sm),
            _textField(_bankName, label: '银行名称', field: 'bank'),
          ],
          const SizedBox(height: CfSpace.md),
          Text('所属信用账户', style: theme.textTheme.titleMedium),
          const SizedBox(height: CfSpace.xs),
          Wrap(
            spacing: CfSpace.xs,
            runSpacing: CfSpace.xs,
            children: <Widget>[
              ChoiceChip(
                label: const Text('新建信用账户'),
                selected: _target == _AccountTarget.newAccount,
                onSelected: (_) =>
                    setState(() => _target = _AccountTarget.newAccount),
              ),
              ChoiceChip(
                label: const Text('加入已有账户'),
                selected: _target == _AccountTarget.existing,
                onSelected: (_) =>
                    setState(() => _target = _AccountTarget.existing),
              ),
            ],
          ),
          const SizedBox(height: CfSpace.xxs),
          Text('同一授信的另一张卡（主卡与附属卡、换发的卡）加入已有账户，账单只有一份。', style: secondary),
          if (_target == _AccountTarget.existing) ...<Widget>[
            const SizedBox(height: CfSpace.sm),
            if (bankAccounts.isEmpty)
              Text(
                _effectiveBank == null || _effectiveBank!.isEmpty
                    ? '先选择银行。'
                    : '这家银行还没有信用账户。',
                style: secondary,
              )
            else
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _joinAccountId,
                decoration: InputDecoration(
                  labelText: '信用账户',
                  errorText: _errors['account'],
                  border: const OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<String>>[
                  for (final account in bankAccounts)
                    DropdownMenuItem<String>(
                      value: account.id,
                      child: Text(
                        account.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _joinAccountId = value),
              ),
          ],
          const SizedBox(height: CfSpace.md),
          _textField(_product, label: '产品名（可选）', field: 'productName'),
        ],
        const SizedBox(height: CfSpace.md),
        _textField(_alias, label: '别名（可选）', field: 'alias'),
        const SizedBox(height: CfSpace.md),
        _textField(
          _last4,
          label: '末四位',
          field: 'last4',
          keyboardType: TextInputType.number,
          helper: '只填卡号最后 4 位；卡序不保存完整卡号',
        ),
        const SizedBox(height: CfSpace.md),
        DropdownButtonFormField<CardNetwork?>(
          isExpanded: true,
          initialValue: _network,
          decoration: const InputDecoration(
            labelText: '卡组织（可选）',
            border: OutlineInputBorder(),
          ),
          items: <DropdownMenuItem<CardNetwork?>>[
            const DropdownMenuItem<CardNetwork?>(child: Text('不填')),
            for (final network in CardNetwork.values)
              DropdownMenuItem<CardNetwork?>(
                value: network,
                child: Text(network.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) => setState(() => _network = value),
        ),
        const SizedBox(height: CfSpace.md),
        _textField(
          _holder,
          label: '持卡人',
          field: 'holderAlias',
          helper: '称呼即可，如"本人""配偶"',
        ),
        const SizedBox(height: CfSpace.md),
        _textField(
          _expires,
          label: '到期年月（可选）',
          field: 'expiresYm',
          helper: '如 2030-12',
        ),
        if (_saveError != null) ...<Widget>[
          const SizedBox(height: CfSpace.md),
          NoticeCard(
            icon: Icons.error_outline,
            tone: NoticeTone.danger,
            text: '保存失败：$_saveError。表单已保留，可以修改后重试。',
          ),
        ],
        const SizedBox(height: CfSpace.lg),
        FilledButton(
          onPressed: _saving ? null : () => unawaited(_save(wallet)),
          child: Text(_saving ? '正在保存…' : (_saveError == null ? '保存' : '重试保存')),
        ),
      ],
    );
  }

  Widget _textField(
    TextEditingController controller, {
    required String label,
    required String field,
    TextInputType keyboardType = TextInputType.text,
    String? helper,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      // 关闭系统自动填充（包括卡号填充）与输入法学习：这些字段可能被误填卡号。
      autofillHints: null,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      onChanged: (_) => _onTextChanged(),
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 3,
        errorText: _errors[field],
        errorMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
