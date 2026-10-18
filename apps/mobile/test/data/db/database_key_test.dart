// 设备数据库密钥的生成与存放（lib/data/db/database_key.dart）。
import 'dart:math';

import 'package:cardflow/data/db/database_errors.dart';
import 'package:cardflow/data/db/database_key.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'db_test_support.dart';

/// flutter_secure_storage 的平台通道（iOS 原生实现在另一端）。
const MethodChannel _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DatabaseKeyManager', () {
    test('首次启动（无密钥、无数据库）生成一次 32 字节密钥并保存；之后只读不写', () async {
      final store = InMemoryDatabaseKeyStore();
      final manager = DatabaseKeyManager(store);

      final first = await manager.obtain(databaseHasData: false);
      expect(store.writes, 1);
      expect(store.value, first.encode());
      expect(store.value, matches(RegExp(r'^[0-9a-f]{64}$')));

      // 同一进程再取：沿用。
      expect(
        (await manager.obtain(databaseHasData: true)).encode(),
        store.value,
      );
      // "重启"（新的管理器、同一个钥匙串）：读到同一把密钥，不再写。
      final restarted = DatabaseKeyManager(store);
      expect(
        (await restarted.obtain(databaseHasData: true)).encode(),
        first.encode(),
      );
      expect(store.writes, 1);
    });

    test('并发调用只生成一把密钥', () async {
      final store = InMemoryDatabaseKeyStore();
      final manager = DatabaseKeyManager(store);
      final keys = await Future.wait(<Future<DatabaseKey>>[
        for (var i = 0; i < 5; i++) manager.obtain(databaseHasData: false),
      ]);
      expect(store.writes, 1);
      expect(keys.map((k) => k.encode()).toSet(), hasLength(1));
    });

    test('钥匙串已有密钥、数据库文件不存在（例如重装后）：沿用已有密钥', () async {
      final store = InMemoryDatabaseKeyStore(value: testKeyHex);
      final key = await DatabaseKeyManager(store)
          .obtain(databaseHasData: false);
      expect(key.encode(), testKeyHex);
      expect(store.writes, 0);
    });

    test('数据库已有数据而钥匙串没有密钥 → key_missing，不生成新密钥', () async {
      final store = InMemoryDatabaseKeyStore();
      await expectOpenError(
        () => DatabaseKeyManager(store).obtain(databaseHasData: true),
        DatabaseErrorCode.keyMissing,
      );
      expect(store.writes, 0);
      expect(store.value, isNull);
    });

    test('钥匙串里的内容格式不对 → key_invalid，不覆盖', () async {
      final store = InMemoryDatabaseKeyStore(value: 'not-a-key');
      await expectOpenError(
        () => DatabaseKeyManager(store).obtain(databaseHasData: false),
        DatabaseErrorCode.keyInvalid,
      );
      expect(store.value, 'not-a-key');
      expect(store.writes, 0);
    });

    test('钥匙串不可用 → key_store_failed，消息里没有平台异常正文；之后可重试', () async {
      final store = InMemoryDatabaseKeyStore()..failAll = true;
      final manager = DatabaseKeyManager(store);
      final error = await expectOpenError(
        () => manager.obtain(databaseHasData: false),
        DatabaseErrorCode.keyStoreFailed,
      );
      expect(error.toString(), isNot(contains('secret detail')));

      store.failAll = false;
      final key = await manager.obtain(databaseHasData: false);
      expect(store.value, key.encode());
    });

    test('写入后读回不一致 → key_store_failed（此时不会建库）', () async {
      final store = InMemoryDatabaseKeyStore()..dropWrites = true;
      await expectOpenError(
        () => DatabaseKeyManager(store).obtain(databaseHasData: false),
        DatabaseErrorCode.keyStoreFailed,
      );
    });

    test('用注入的随机源生成（默认是 Random.secure）', () async {
      final a = InMemoryDatabaseKeyStore();
      final b = InMemoryDatabaseKeyStore();
      await DatabaseKeyManager(
        a,
        random: Random(7),
      ).obtain(databaseHasData: false);
      await DatabaseKeyManager(
        b,
        random: Random(7),
      ).obtain(databaseHasData: false);
      expect(a.value, b.value);
    });

    test('缓存：取到的密钥在进程内沿用，钥匙串被清空也不变；forget 后重新读钥匙串（R-15）', () async {
      final store = InMemoryDatabaseKeyStore(value: testKeyHex);
      final manager = DatabaseKeyManager(store);
      expect(
        (await manager.obtain(databaseHasData: true)).encode(),
        testKeyHex,
      );

      store.value = null;
      expect(
        (await manager.obtain(databaseHasData: false)).encode(),
        testKeyHex,
        reason: '这就是 R-15 的陷阱：不忘掉缓存就会用旧密钥建新库',
      );

      manager.forget();
      final fresh = await manager.obtain(databaseHasData: false);
      expect(fresh.encode(), isNot(testKeyHex));
      expect(store.value, fresh.encode());
    });

    test('deleteKey：删除钥匙串条目并忘掉缓存；之后首次启动重新生成', () async {
      final store = InMemoryDatabaseKeyStore(value: testKeyHex);
      final manager = DatabaseKeyManager(store);
      await manager.obtain(databaseHasData: true);

      await manager.deleteKey();
      expect(store.value, isNull);
      expect(store.deletes, 1);
      expect(await manager.hasKey(), isFalse);

      final regenerated = await manager.obtain(databaseHasData: false);
      expect(regenerated.encode(), isNot(testKeyHex));
      expect(store.value, regenerated.encode());
    });

    test('deleteKey 时钥匙串不可用 → key_store_failed，缓存已忘掉，可重试', () async {
      final store = InMemoryDatabaseKeyStore(value: testKeyHex);
      final manager = DatabaseKeyManager(store);
      await manager.obtain(databaseHasData: true);
      store.failAll = true;
      await expectOpenError(
        manager.deleteKey,
        DatabaseErrorCode.keyStoreFailed,
      );
      store.failAll = false;
      await manager.deleteKey();
      expect(store.value, isNull);
    });

    test('hasKey 只看是否存在', () async {
      expect(
        await DatabaseKeyManager(InMemoryDatabaseKeyStore()).hasKey(),
        isFalse,
      );
      expect(
        await DatabaseKeyManager(InMemoryDatabaseKeyStore(value: testKeyHex))
            .hasKey(),
        isTrue,
      );
    });
  });

  group('SecureStorageDatabaseKeyStore（iOS 钥匙串参数）', () {
    final data = <String, String>{};
    final calls = <MethodCall>[];

    setUp(() {
      data.clear();
      calls.clear();
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_secureStorageChannel, (call) async {
            calls.add(call);
            final arguments = call.arguments as Map<Object?, Object?>;
            final key = arguments['key'] as String?;
            return switch (call.method) {
              'write' => data[key!] = arguments['value']! as String,
              'read' => data[key!],
              'containsKey' => data.containsKey(key),
              'delete' => data.remove(key),
              _ => null,
            };
          });
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_secureStorageChannel, null);
    });

    test('WhenUnlockedThisDeviceOnly、不同步 iCloud、不设 access group', () async {
      const store = SecureStorageDatabaseKeyStore();
      expect(await store.exists(), isFalse);
      await store.write(testKeyHex);
      expect(await store.read(), testKeyHex);
      expect(await store.exists(), isTrue);
      await store.delete();
      expect(await store.exists(), isFalse);

      expect(calls.map((c) => c.method), <String>[
        'containsKey',
        'write',
        'read',
        'containsKey',
        'delete',
        'containsKey',
      ]);
      for (final call in calls) {
        final arguments = call.arguments as Map<Object?, Object?>;
        expect(arguments['key'], SecureStorageDatabaseKeyStore.entryName);
        final options = (arguments['options']! as Map<Object?, Object?>)
            .cast<String, String>();
        expect(options['accessibility'], 'unlocked_this_device');
        expect(options['synchronizable'], 'false');
        expect(options.containsKey('groupId'), isFalse);
        expect(options.containsKey('accessControlFlags'), isFalse);
      }
    });
  });
}
