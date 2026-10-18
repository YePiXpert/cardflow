// Probe (R-15): after wrong_key, "delete the database file and the keychain key, then open again"
// with the same DatabaseKeyManager reuses the cached key; after a restart the new data is key_missing.
import 'dart:io';

import 'package:cardflow/data/db/database_errors.dart';
import 'package:cardflow/data/db/database_key.dart';
import 'package:cardflow/data/db/database_location.dart';
import 'package:cardflow/data/db/database_opener.dart';
import 'package:cardflow/data/db/database_platform.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryStore implements DatabaseKeyStore {
  MemoryStore([this.value]);
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async => value = v;
  @override
  Future<bool> exists() async => value != null;
}

Future<String> outcome(Future<Object?> Function() action) async {
  try {
    await action();
    return 'opened';
  } on DatabaseOpenException catch (e) {
    return e.code.code;
  }
}

void main() {
  test('reset after wrong_key with a cached key manager', () async {
    final dir = Directory.systemTemp.createTempSync('reset_probe_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final location = DatabaseLocation(directory: dir.path);
    final path = joinDatabasePath(dir.path, appDatabaseFileName);

    // 1. a database created with key B
    final storeB = MemoryStore();
    final first = await openAppDatabase(keys: DatabaseKeyManager(storeB), location: location);
    await first.database.close();

    // 2. the keychain now holds another key A -> wrong_key (the manager has cached key A)
    final store = MemoryStore(DatabaseKey.generate().encode());
    final manager = DatabaseKeyManager(store);
    final step2 = await outcome(() => openAppDatabase(keys: manager, location: location));

    // 3. "reset": delete the database files and the keychain entry, open again with the same manager
    deleteDatabaseFiles(path);
    store.value = null;
    final reopened = await openAppDatabase(keys: manager, location: location);
    await reopened.database.customStatement('CREATE TABLE note (x TEXT)');
    await reopened.database.customStatement("INSERT INTO note VALUES ('after reset')");
    await reopened.database.close();
    final keychainAfterReset = store.value == null ? 'empty' : 'has key';

    // 4. restart: a new manager reads the keychain
    final step4 = await outcome(() async {
      final again = await openAppDatabase(keys: DatabaseKeyManager(store), location: location);
      await again.database.close();
    });
    // ignore: avoid_print
    print('step2=$step2; after reset: created=${reopened.created}, keychain $keychainAfterReset; after restart: $step4');
  });
}
