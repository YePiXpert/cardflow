import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/calm_panel.dart';
import '../../app/widgets/feedback.dart';
import '../../app/widgets/workspace_bound_form.dart';
import '../../data/ids.dart';
import '../../data/repositories/providers.dart';
import '../../data/repositories/repository_errors.dart';
import '../../data/repositories/simple_card_setup.dart';
import '../../data/validation/text_rules.dart';
import 'amount_input.dart';

class NewCardPage extends ConsumerStatefulWidget {
  const NewCardPage({super.key});
  static const title = '添加卡片';
  static const savedMessage = '已添加';
  @override
  ConsumerState<NewCardPage> createState() => _NewCardPageState();
}

class _NewCardPageState extends ConsumerState<NewCardPage>
    with WorkspaceBoundForm {
  final _name = TextEditingController();
  final _available = TextEditingController();
  final _tail = TextEditingController();
  final _cardId = newUuidV4();
  final _accountId = newUuidV4();
  int? _statement;
  int? _due;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _available, _tail]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final (amount, amountError) = parseAmountMinor(
      _available.text,
      'CNY',
      allowNegative: true,
    );
    final error =
        validateFreeText(_name.text, required: true, fieldName: '卡名') ??
        (_name.text.trim().length > 20 ? '卡名最多 20 个字' : null) ??
        validateLast4(_tail.text) ??
        amountError ??
        (_statement == null || _due == null ? '请选择账单日和还款日' : null);
    setState(() => _error = error);
    if (error != null) return;
    setState(() => _saving = true);
    try {
      final scope = await boundRepository(workspaceScopeProvider.future);
      await createSimpleCard(
        scope,
        cardId: _cardId,
        accountId: _accountId,
        name: _name.text.trim(),
        last4: _tail.text,
        available: amount!,
        statementDay: _statement!,
        dueDay: _due!,
      );
      if (!mounted) return;
      showFeedback(ScaffoldMessenger.of(context), NewCardPage.savedMessage);
      context.go(AppRoutes.home);
    } on RepositoryException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败，请重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool number = false,
    String? helper,
  }) => TextField(
    controller: controller,
    autofillHints: null,
    keyboardType: number
        ? const TextInputType.numberWithOptions(decimal: true, signed: true)
        : TextInputType.text,
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 3,
    ),
    onChanged: (value) {
      setState(
        () => _error = looksLikeFullCardNumber(value)
            ? fullCardNumberMessage
            : null,
      );
    },
  );

  Widget _day(String label, int? value, ValueChanged<int?> changed) =>
      DropdownButtonFormField<int>(
        isExpanded: true,
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          for (var day = 1; day <= 31; day++)
            DropdownMenuItem(value: day, child: Text('每月 $day 日')),
        ],
        onChanged: changed,
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text(NewCardPage.title)),
    body: ListView(
      padding: const EdgeInsets.all(CfSpace.md),
      children: [
        CalmPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(_name, '卡名', helper: '例如：招行生活卡'),
              const SizedBox(height: CfSpace.md),
              _field(_tail, '末四位', number: true, helper: '只填卡号最后 4 位'),
              const SizedBox(height: CfSpace.md),
              _field(
                _available,
                '当前可用额度',
                number: true,
                helper: '填写银行 App 当前显示的可用额度',
              ),
              const SizedBox(height: CfSpace.md),
              _day('账单日', _statement, (v) => setState(() => _statement = v)),
              const SizedBox(height: CfSpace.md),
              _day('还款日', _due, (v) => setState(() => _due = v)),
              if (_statement != null && _due != null) ...[
                const SizedBox(height: CfSpace.sm),
                Text(
                  '每月 $_statement 日出账，${_due! <= _statement! ? '次月' : '当月'} $_due 日还款。',
                ),
              ],
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: CfSpace.md),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: CfSpace.lg),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '正在保存…' : '保存'),
        ),
      ],
    ),
  );
}
