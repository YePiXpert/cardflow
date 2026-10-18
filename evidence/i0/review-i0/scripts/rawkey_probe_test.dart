// Probe: does sqlite3mc treat PRAGMA key = "x'<64 hex>'" as a raw key (no KDF)?
import 'dart:io';

import 'package:cardflow/data/db/database_key.dart';
import 'package:cardflow/data/db/encryption.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

String q(Database db, String sql) => firstValueOf(db.select(sql));

void main() {
  test('raw key probe', () {
    final dir = Directory.systemTemp.createTempSync('rawkey_probe_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/p.sqlite';
    final key = DatabaseKey.decode('00112233445566778899aabbccddeeff102132435465768798a9bacbdcedfe0f');
    var db = sqlite3.open(path);
    final sw = Stopwatch()..start();
    applyEncryption(db, key.rawKeyLiteral());
    final rawMs = sw.elapsedMicroseconds;
    db.execute('CREATE TABLE t(x)');
    db.execute('INSERT INTO t VALUES (42)');
    db.close();

    // Reopen with a different KDF iteration count: a raw key ignores it, a passphrase does not.
    db = sqlite3.open(path);
    final kdf = q(db, 'PRAGMA kdf_iter = 1');
    String result;
    try {
      applyEncryption(db, key.rawKeyLiteral());
      result = 'opened with kdf_iter=1 (value ${q(db, 'SELECT x FROM t')}) -> raw key, no KDF';
    } on Object catch (e) {
      result = 'failed with kdf_iter=1 ($e) -> passphrase + KDF';
    }
    db.close();

    // A passphrase that is the same hex text without x'' must not open it.
    db = sqlite3.open(path);
    String asPassphrase;
    try {
      q(db, 'PRAGMA cipher = \'chacha20\'');
      q(db, 'PRAGMA key = "${key.encode()}"');
      q(db, 'SELECT count(*) FROM sqlite_master');
      asPassphrase = 'hex text as passphrase OPENED (unexpected)';
    } on Object catch (e) {
      asPassphrase = 'hex text as passphrase rejected (${e.runtimeType})';
    }
    db.close();

    // Timing of a passphrase key (PBKDF2) for comparison.
    final p2 = '${dir.path}/q.sqlite';
    db = sqlite3.open(p2);
    q(db, 'PRAGMA cipher = \'chacha20\'');
    final sw2 = Stopwatch()..start();
    q(db, 'PRAGMA key = "some passphrase"');
    q(db, 'CREATE TABLE t(x)');
    final passMs = sw2.elapsedMicroseconds;
    db.close();
    // ignore: avoid_print
    print('kdf_iter pragma -> "$kdf"; $result; $asPassphrase; '
        'raw key apply+check ${rawMs}us; passphrase key+first write ${passMs}us; '
        'library ${sqlite3.version}');
  });
}
