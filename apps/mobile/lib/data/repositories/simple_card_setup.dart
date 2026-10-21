import 'package:cardflow_domain/cardflow_domain.dart';

import '../time/clock.dart';
import 'billing_rule_repository.dart';
import 'card_repository.dart';
import 'credit_account_repository.dart';
import 'limit_snapshot_repository.dart';
import 'models.dart';
import 'repository_errors.dart';
import 'workspace_scope.dart';

/// 卡片、账期和额度作为一次保存提交，失败不留下半张卡；重试使用同一 cardId。
Future<void> createSimpleCard(
  WorkspaceScope scope, {
  required String cardId,
  required String accountId,
  required String name,
  required String last4,
  required int available,
  required int statementDay,
  required int dueDay,
}) => scope.db.transaction(() async {
  final cards = CardRepository(scope);
  if (await cards.byId(cardId) != null) return;
  if ((await cards.sameBankSameLast4(
    bankName: name,
    last4: last4,
  )).isNotEmpty) {
    throw const ValidationException('last4', '这张卡已添加，请直接更新额度');
  }
  await cards.create(
    NewCardDraft(
      cardId: cardId,
      newAccountId: accountId,
      bankName: name,
      alias: name,
      last4: last4,
    ),
  );
  await BillingRuleRepository(scope).saveVersion(
    RuleSubject.creditAccount(accountId),
    BillingRuleDraft(
      statementDay: statementDay,
      due: DueRule.fixedDay(
        day: dueDay,
        monthOffset: dueDay <= statementDay ? 1 : 0,
      ),
    ),
    effect: const RuleCorrection(),
  );
  final sub = (await CreditAccountRepository(scope).currencyAccounts(accountId))
      .single;
  final now = Timestamp.parse(scope.clock.nowText());
  await LimitSnapshotRepository(scope).record(
    LimitSnapshotDraft(
      currencyAccountId: sub.id,
      // 未采集总额度和已用额；独立账户的消费容量只读取银行可用额。
      fixedMinor: 0,
      usedMinor: 0,
      availableRawMinor: available,
      includesHolds: true,
      source: SnapshotSource.user,
      balanceAsOf: now,
      observedAt: now,
    ),
  );
});
