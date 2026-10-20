// 审查 R-04（分期成本的有理数 IRR 在界面线程上算，60 期约 2 秒）改写的正式测试：成本按计划 id 记忆化、
// 一律在后台 isolate 里算（原生平台 Isolate.run），转分期表单的预览去抖 ≥ 300 ms；界面线程（主 isolate）
// 上不做 IRR。`installmentCostEvaluations` 只数当前 isolate 里的 IRR 调用，后台 isolate 的不计入。
import 'dart:async';

import 'package:cardflow/app/background/off_main_isolate.dart';
import 'package:cardflow/app/routes.dart';
import 'package:cardflow/data/mapping/ledger_mapping.dart';
import 'package:cardflow/data/repositories/installment_repository.dart';
import 'package:cardflow/data/repositories/ledger_models.dart';
import 'package:cardflow/data/repositories/ledger_reader.dart';
import 'package:cardflow/data/repositories/providers.dart';
import 'package:cardflow/data/repositories/workspace_scope.dart';
import 'package:cardflow/features/statements/installment_cost.dart';
import 'package:cardflow/features/statements/statement_pages.dart';
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../data/repositories/repository_test_support.dart';
import '../../test_helpers.dart';

final Rational _rate = Rational.parseDecimal('0.006');

InstallmentCostInput _input(int periods) => InstallmentCostInput(
  principalMinor: 1200000,
  perPeriodRate: _rate,
  periods: installmentPeriodsOf(
    principalMinor: 1200000,
    periods: periods,
    perPeriodRate: _rate,
    feeMode: InstallmentFeeMode.perPeriod,
    remainderTo: RemainderTo.last,
  ),
);

/// 卡 A：10-10 账单；10-05 的 12,000"家电"转 60 期（每期 0.6%）；10-12 的 5,000"手机"还没转分期。
Future<void> _seed(WorkspaceScope scope) async {
  final card = await createTestCard(scope, alias: '卡 A');
  await declareTestRule(scope, card.creditAccountId);
  final sub = (await primaryCurrencyAccount(scope, card.creditAccountId)).id;
  await recordTestStatement(scope, sub, newBalance: 50000, minDue: 5000);
  final appliance = await addTestTransaction(
    scope,
    sub,
    amount: 1200000,
    txnAt: '2026-10-05T10:00:00+08:00',
    merchant: '家电',
  );
  await InstallmentRepository(scope).create(
    InstallmentDraft(
      transactionId: appliance.id,
      periods: 60,
      perPeriodRate: _rate,
    ),
  );
  await addTestTransaction(scope, sub, amount: 500000, merchant: '手机');
}

void main() {
  test(
    '默认的成本计算在后台 isolate 里（Isolate.run）：主 isolate 不调用 IRR，结果与就地计算相同（60 期）',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final before = installmentCostEvaluations;
      final background = await container.read(installmentCostRunnerProvider)(
        _input(60),
      );
      expect(installmentCostEvaluations, before, reason: '主 isolate 没有调用 IRR');
      final inline = _input(60).compute();
      expect(installmentCostEvaluations, before + 1);
      expect(background.monthlyIrr, inline.monthlyIrr);
      expect(background.effective, inline.effective);
      expect(background.nominal, _rate.timesInt(12));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('按计划 id 记忆化：同一计划读两次只算一次（条款与各期金额都不可改）', () async {
    final db = await openRealTestDatabase();
    final scope = await createTestWorkspace(db);
    await _seed(scope);
    final plan = (await InstallmentRepository(scope).plans()).single;
    var runs = 0;
    final container = ProviderContainer(
      overrides: <Override>[
        workspaceScopeProvider.overrideWith((ref) async => scope),
        installmentCostRunnerProvider.overrideWithValue((input) async {
          runs++;
          return _input(12).compute();
        }),
      ],
    );
    addTearDown(container.dispose);
    final first = await container.read(installmentCostProvider(plan.id).future);
    final again = await container.read(installmentCostProvider(plan.id).future);
    expect(identical(first, again), isTrue);
    expect(runs, 1);
  });

  testWidgets('计时：60 期的计划打开账单详情、转分期表单改费率时，主 isolate 不调用 IRR；打开详情的耗时小于在界面'
      '线程上算一次 60 期 IRR；表单停下 300 ms 之后才请求一次、算好后显示实际年化', (tester) async {
    final requests = <Future<InstallmentCost>>[];
    await pumpCardFlowApp(
      tester,
      seed: _seed,
      backgroundCosts: true,
      overrides: <Override>[
        // App 的默认做法（runOffMainIsolate = Isolate.run），只多记下请求，好在测试里等它算完；在根 zone 里
        // 发起，结果才能在 runAsync 的真实事件循环里送回（组件测试的伪时钟 zone 只在 pump 时处理异步）。
        installmentCostRunnerProvider.overrideWithValue((input) {
          final future = Zone.root.run(() => runOffMainIsolate(input.compute));
          requests.add(future);
          return future;
        }),
      ],
    );
    final ledger = await withCurrentScope(
      tester,
      (scope) => LedgerReader(scope).load(),
    );
    final statement = ledger.statements.single;
    final before = installmentCostEvaluations;

    final open = Stopwatch()..start();
    await goTo(tester, AppRoutes.statement(statement.id));
    await tester.scrollUntilVisible(
      find.text('实际年化（复利，按各期现金流 IRR）'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    open.stop();
    expect(
      installmentCostEvaluations,
      before,
      reason: '打开详情：主 isolate 没有调用 IRR',
    );
    expect(find.text(InstallmentPlanCard.computingText), findsWidgets);
    expect(requests, hasLength(1));
    // 等后台 isolate 算完（真实时间），实际年化出现。
    await tester.runAsync(() => Future.wait(requests));
    await tester.pumpAndSettle();
    expect(find.text(InstallmentPlanCard.computingText), findsNothing);
    expect(installmentCostEvaluations, before);
    // 同一计划再进一次详情：记忆化，不再请求。
    await goTo(tester, AppRoutes.statements());
    await goTo(tester, AppRoutes.statement(statement.id));
    expect(requests, hasLength(1));

    // 转分期表单：期数 60、改两次费率；停下 300 ms 之前不请求，之后只请求一次，主 isolate 不算 IRR。
    final phone = ledger.transactions.firstWhere((t) => t.merchant == '手机');
    await goTo(tester, AppRoutes.newInstallment(phone.id));
    final edit = Stopwatch()..start();
    await tester.enterText(find.widgetWithText(TextField, '期数（1–60）'), '60');
    await tester.enterText(
      find.widgetWithText(TextField, '每期费率（%，如 0.6）'),
      '0.5',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.widgetWithText(TextField, '每期费率（%，如 0.6）'),
      '0.6',
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(requests, hasLength(1), reason: '还没停下 300 ms');
    await tester.pump(installmentCostDebounce);
    edit.stop();
    expect(requests, hasLength(2), reason: '停下之后只请求一次');
    expect(
      installmentCostEvaluations,
      before,
      reason: '改费率：主 isolate 没有调用 IRR',
    );
    await tester.runAsync(() => requests.last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('实际年化（复利，按各期现金流 IRR）'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(InstallmentPlanCard.computingText), findsNothing);
    expect(find.text('7.2%'), findsOneWidget, reason: '名义年化当场算');

    // 对照：在界面线程上算一次 60 期 IRR 要多久。
    final inline = Stopwatch()..start();
    _input(60).compute();
    inline.stop();
    // ignore: avoid_print
    print(
      'R-04 计时：打开账单详情 ${open.elapsedMilliseconds} ms；表单改期数与两次费率并等去抖 '
      '${edit.elapsedMilliseconds} ms；对照——在主 isolate 上算一次 60 期 IRR ${inline.elapsedMilliseconds} ms',
    );
    expect(open.elapsed, lessThan(inline.elapsed));
    expect(edit.elapsed, lessThan(inline.elapsed));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
