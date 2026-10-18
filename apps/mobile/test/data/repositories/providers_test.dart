// 数据层 provider（真实 sqlite3mc）：当前工作空间的切换、时钟（演示空间固定今天）、读模型随写入
// 自动重算、切换后读到的永远是当前工作空间、诊断日志只记事件（不含金额、卡号、别名）。
import 'package:cardflow/app/diagnostics/diagnostic_log.dart';
import 'package:cardflow/data/db/database_location.dart';
import 'package:cardflow/data/db/database_providers.dart';
import 'package:cardflow/data/ids.dart';
import 'package:cardflow/data/repositories/card_repository.dart';
import 'package:cardflow/data/repositories/models.dart';
import 'package:cardflow/data/repositories/providers.dart';
import 'package:cardflow/data/time/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/sensitive_text.dart';
import '../db/db_test_support.dart';
import 'repository_test_support.dart';

ProviderContainer _launch(
  DatabaseLocation location,
  InMemoryDatabaseKeyStore store,
) => ProviderContainer.test(
  overrides: [
    databaseKeyStoreProvider.overrideWithValue(store),
    databaseLocationProvider.overrideWith((ref) async => location),
  ],
);

Future<void> _quit(ProviderContainer container) async {
  await (await container.read(databaseProvider.future)).close();
  container.dispose();
}

/// 等读模型反映最新写入（写入后 drift 的表更新通知是异步的）。
Future<int> _accountCount(ProviderContainer container) async {
  await Future<void>.delayed(Duration.zero);
  return (await container.read(walletProvider.future)).accounts.length;
}

void main() {
  late DatabaseLocation location;
  late InMemoryDatabaseKeyStore store;

  setUp(() {
    location = createTempLocation();
    store = InMemoryDatabaseKeyStore();
  });

  test('首次启动没有工作空间；进入真实空间后跨重启保持', () async {
    final first = _launch(location, store);
    expect(await first.read(currentWorkspaceProvider.future), isNull);
    expect(first.read(clockProvider), isA<SystemClock>());
    await expectLater(
      first.read(workspaceScopeProvider.future),
      throwsA(isA<NoCurrentWorkspaceException>()),
    );
    final real = await first
        .read(currentWorkspaceProvider.notifier)
        .enterReal();
    expect(real.kind, WorkspaceKind.real);
    await _quit(first);

    final second = _launch(location, store);
    expect((await second.read(currentWorkspaceProvider.future))!.id, real.id);
    await _quit(second);
  });

  test('演示空间：合成数据、固定今天；退出回到真实空间；两空间的读模型互不可见', () async {
    final container = _launch(location, store);
    final workspace = container.read(currentWorkspaceProvider.notifier);
    await container.read(currentWorkspaceProvider.future);
    await workspace.enterReal();
    final repo = await container.read(cardRepositoryProvider.future);
    await repo.create(
      NewCardDraft(
        cardId: newUuidV4(),
        newAccountId: newUuidV4(),
        bankName: '招商银行',
        last4: '4321',
        alias: '我的工资卡',
      ),
    );
    expect(await _accountCount(container), 1);

    final demo = await workspace.enterDemo();
    expect(demo.isDemo, isTrue);
    expect(container.read(clockProvider), same(demoClock));
    final demoWallet = await container.read(walletProvider.future);
    expect(demoWallet.accounts.map((a) => a.displayName), contains('卡 A'));
    expect(
      demoWallet.accounts.map((a) => a.displayName),
      isNot(contains('我的工资卡')),
    );

    await workspace.exitDemo();
    expect(
      (await container.read(currentWorkspaceProvider.future))!.kind,
      WorkspaceKind.real,
    );
    expect(container.read(clockProvider), isA<SystemClock>());
    final realWallet = await container.read(walletProvider.future);
    expect(realWallet.accounts.map((a) => a.displayName), <String>['我的工资卡']);

    // 诊断日志：只有事件与 real/demo，没有别名、末四位以外的数字、金额。
    // 只看日志的内容部分（事件与 detail）；每行开头的时间戳是日志自己的，不是用户数据。
    final lines = container
        .read(diagnosticLogProvider)
        .entries
        .map((e) => '${e.category}/${e.event} ${e.detail ?? ''}'.trim())
        .toList();
    expect(lines.where((l) => l.startsWith('workspace/')), <String>[
      'workspace/started real',
      'workspace/switched real',
      'workspace/started demo',
      'workspace/switched demo',
      'workspace/switched real',
    ]);
    for (final line in lines) {
      expect(containsUserText(line, '我的工资卡'), isFalse, reason: line);
      expect(containsAmount(line, 800000, 'CNY'), isFalse, reason: line);
      expect(
        containsCardDigits(line, '6222020200114321'),
        isFalse,
        reason: line,
      );
    }
    await _quit(container);
  });

  test('写入后读模型自动重算（不需要手动刷新）', () async {
    final container = _launch(location, store);
    await container.read(currentWorkspaceProvider.future);
    await container.read(currentWorkspaceProvider.notifier).enterReal();
    final subscription = container.listen(walletProvider, (_, _) {});
    addTearDown(subscription.close);
    expect(await _accountCount(container), 0);
    final scope = await container.read(workspaceScopeProvider.future);
    await createTestCard(scope, last4: '1111');
    expect(await _accountCount(container), 1);
    await createTestCard(scope, last4: '2222');
    expect(await _accountCount(container), 2);
    await _quit(container);
  });

  test('清除演示数据：在演示空间里清除 → 回到真实空间；没有真实空间 → 没有当前工作空间', () async {
    final container = _launch(location, store);
    final workspace = container.read(currentWorkspaceProvider.notifier);
    await container.read(currentWorkspaceProvider.future);
    await workspace.enterDemo();
    await workspace.clearDemo();
    expect(await container.read(currentWorkspaceProvider.future), isNull);

    await workspace.enterReal();
    await workspace.enterDemo();
    await workspace.clearDemo();
    final current = await container.read(currentWorkspaceProvider.future);
    expect(current!.kind, WorkspaceKind.real);
    expect(
      container
          .read(diagnosticLogProvider)
          .entries
          .where((e) => e.event == 'demo_cleared'),
      hasLength(2),
    );
    await _quit(container);
  });
}
