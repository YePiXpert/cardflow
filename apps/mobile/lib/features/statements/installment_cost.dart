/// 分期成本（有理数 IRR）的取用（审查 R-04）：条款建好后不可改（触发器），成本按计划 id 算一次并缓存
/// （[installmentCostProvider]，keepAlive）；计算一律经 [installmentCostRunnerProvider] 放到后台 isolate，
/// 界面线程上不做 IRR。转分期表单的预览同样经它，并去抖（[installmentCostDebounce]）。
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/background/off_main_isolate.dart';
import '../../data/db/database_providers.dart';
import '../../data/mapping/ledger_mapping.dart';
import '../../data/repositories/installment_repository.dart';
import '../../data/repositories/providers.dart';

part 'installment_cost.g.dart';

/// 转分期表单改了期数、费率、收费方式或尾差之后，等这么久没有再改才算一次成本（≥ 300 ms）。
const Duration installmentCostDebounce = Duration(milliseconds: 300);

/// 算分期成本的方式。
typedef InstallmentCostRunner = Future<InstallmentCost> Function(
  InstallmentCostInput input,
);

/// 默认放到后台 isolate（原生平台 `Isolate.run`）。组件测试在伪时钟里等不到 isolate，`pumpCardFlowApp`
/// 默认换成就地计算；R-04 的测试用真正的后台 isolate。
@Riverpod(keepAlive: true)
InstallmentCostRunner installmentCostRunner(Ref ref) =>
    (input) => runOffMainIsolate(input.compute);

/// 某分期计划的成本：按计划 id 记忆化（条款与各期金额都不可改），第一次用到时在后台 isolate 里算。
@Riverpod(keepAlive: true, retry: noDatabaseRetry)
Future<InstallmentCost> installmentCost(Ref ref, String planId) async {
  final scope = await ref.read(workspaceScopeProvider.future);
  final repo = InstallmentRepository(scope);
  final input = InstallmentCostInput.ofPlan(
    await repo.require(planId),
    await repo.schedule(planId),
  );
  return ref.read(installmentCostRunnerProvider)(input);
}
