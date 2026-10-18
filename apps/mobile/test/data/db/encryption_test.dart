// 加密层（lib/data/db/encryption.dart）在真实 SQLite3MultipleCiphers 上的行为。
import 'dart:io';

import 'package:cardflow/data/db/database_errors.dart';
import 'package:cardflow/data/db/database_key.dart';
import 'package:cardflow/data/db/encryption.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'db_test_support.dart';

String _query(Database db, String sql) => firstValueOf(db.select(sql));

/// 用 [key] 新建一个加密库（一张空表），然后关闭。
void createEncryptedDatabase(String path, DatabaseKey key) {
  final db = sqlite3.open(path);
  try {
    applyEncryption(db, key.rawKeyLiteral());
    db.execute('CREATE TABLE t(x)');
  } finally {
    db.close();
  }
}

void main() {
  late String path;

  setUp(() {
    final location = createTempLocation();
    path = databasePathIn(location, 'encryption.sqlite');
  });

  group('构建钩子加载的是 SQLite3MultipleCiphers', () {
    test('sqlite3mc_version() 与 PRAGMA cipher 非空（否则说明钩子没有选中 sqlite3mc）', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      final info = requireCipher((sql) => _query(db, sql));
      expect(
        info.library,
        startsWith('SQLite3 Multiple Ciphers '),
        reason:
            'sqlite3 构建钩子没有加载 sqlite3mc：检查 pubspec.yaml 的 '
            'hooks.user_defines.sqlite3.source 与网络（钩子从 GitHub release 下载预编译库）',
      );
      expect(info.cipher, pinnedCipher);
    });

    test('已知差异：PRAGMA cipher_version 是 SQLCipher 的 PRAGMA，sqlite3mc 返回空', () {
      // 规划文档要求"cipher_version 为空即拒绝"；照字面执行会让 sqlite3mc 永远打不开。
      // 因此 requireCipher 改用 PRAGMA cipher + sqlite3mc_version()（见 encryption.dart）。
      // 如果将来某个版本开始返回非空，这条测试会提醒我们重新评估。
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      expect(_query(db, 'PRAGMA cipher_version'), isEmpty);
      expect(requireCipher((sql) => _query(db, sql)).cipherVersionPragma, '');
    });
  });

  group('requireCipher：不是加密构建就拒绝（失败即止）', () {
    test(
      '普通 SQLite（未知 PRAGMA 返回空、没有 sqlite3mc_version()）→ cipher_unavailable',
      () {
        String plainSqlite(String sql) {
          if (sql.contains('sqlite3mc_version')) {
            throw SqliteException(
              extendedResultCode: 1,
              message: 'no such function: sqlite3mc_version',
            );
          }
          return '';
        }

        expect(
          () => requireCipher(plainSqlite),
          throwsA(
            const DatabaseOpenException(DatabaseErrorCode.cipherUnavailable),
          ),
        );
      },
    );

    test('只有 PRAGMA cipher 或只有版本函数都不够', () {
      expect(
        () => cipherInfoFromValues(
          cipher: 'chacha20',
          library: '',
          cipherVersionPragma: '',
        ),
        throwsA(isA<DatabaseOpenException>()),
      );
      expect(
        () => cipherInfoFromValues(
          cipher: '',
          library: 'SQLite3 Multiple Ciphers 2.6.1',
          cipherVersionPragma: '4.6.1 community',
        ),
        throwsA(isA<DatabaseOpenException>()),
      );
    });

    test('检查失败时不会执行 PRAGMA key，也不会读写数据库', () {
      final executed = <String>[];
      String plainSqlite(String sql) {
        executed.add(sql);
        return '';
      }

      expect(
        () => applyEncryptionWith(plainSqlite, "x'$testKeyHex'"),
        throwsA(
          const DatabaseOpenException(DatabaseErrorCode.cipherUnavailable),
        ),
      );
      expect(executed.where((sql) => sql.contains('key')), isEmpty);
      expect(executed.where((sql) => sql.contains('sqlite_master')), isEmpty);
    });

    test('PRAGMA cipher 非空但没有 sqlite3mc_version() → 验证密钥后仍拒绝，且没有写入', () {
      final executed = <String>[];
      String halfCipher(String sql) {
        executed.add(sql);
        if (sql.contains('sqlite3mc_version')) {
          throw SqliteException(
            extendedResultCode: 1,
            message: 'no such function',
          );
        }
        if (sql.startsWith('PRAGMA cipher')) {
          return pinnedCipher;
        }
        return sql.startsWith('PRAGMA key') ? 'ok' : '';
      }

      expect(
        () => applyEncryptionWith(halfCipher, "x'$testKeyHex'"),
        throwsA(
          const DatabaseOpenException(DatabaseErrorCode.cipherUnavailable),
        ),
      );
      expect(
        executed.where(
          (sql) => RegExp('^(CREATE|INSERT|UPDATE|DELETE)').hasMatch(sql),
        ),
        isEmpty,
      );
    });
  });

  group('applyEncryption 在真实连接上', () {
    final key = DatabaseKey.decode(testKeyHex);

    test('新库：设置密钥后写入的数据在文件里是密文，文件头不是明文 SQLite 头', () {
      final db = sqlite3.open(path);
      final info = applyEncryption(db, key.rawKeyLiteral());
      expect(info.cipher, pinnedCipher);
      db
        ..execute('CREATE TABLE t(x TEXT)')
        ..execute("INSERT INTO t VALUES ('plaintext-marker-卡序')")
        ..close();

      final bytes = File(path).readAsBytesSync();
      expect(bytes.length, greaterThan(0));
      expect(isPlaintextSqliteHeader(bytes), isFalse);
      expect(String.fromCharCodes(bytes).contains('plaintext-marker'), isFalse);
    });

    test('原始密钥跳过口令派生：改了 kdf_iter 仍能打开；同一串文本当口令则打不开', () {
      createEncryptedDatabase(path, key);

      // 若密钥经过 PBKDF2，kdf_iter 不同会派生出不同的密钥；原始密钥不受影响。
      final reopened = sqlite3.open(path);
      addTearDown(reopened.close);
      expect(_query(reopened, 'PRAGMA kdf_iter = 1'), '1');
      expect(applyEncryption(reopened, key.rawKeyLiteral()).cipher, 'chacha20');

      // 同样的 64 个十六进制字符若作为口令字节（hexkey，会经过 PBKDF2）则打不开。
      final asPassphrase = sqlite3.open(path);
      addTearDown(asPassphrase.close);
      _query(asPassphrase, "PRAGMA hexkey = '$testKeyHex'");
      expect(
        () => asPassphrase.select('SELECT count(*) FROM sqlite_master'),
        throwsA(
          isA<SqliteException>().having(
            (e) => e.resultCode,
            'resultCode',
            sqliteNotADatabase,
          ),
        ),
      );
    });

    test('密钥错误 → wrong_key（SQLITE_NOTADB）', () {
      createEncryptedDatabase(path, key);

      final db = sqlite3.open(path);
      addTearDown(db.close);
      expect(
        () => applyEncryption(
          db,
          DatabaseKey.decode(otherKeyHex).rawKeyLiteral(),
        ),
        throwsA(
          const DatabaseOpenException(
            DatabaseErrorCode.wrongKey,
            sqliteResultCode: sqliteNotADatabase,
          ),
        ),
      );
    });

    test('不设密钥直接读加密库 → SQLITE_NOTADB（不会被当成明文库打开）', () {
      createEncryptedDatabase(path, key);

      final db = sqlite3.open(path);
      addTearDown(db.close);
      expect(
        () => db.select('SELECT count(*) FROM sqlite_master'),
        throwsA(isA<SqliteException>()),
      );
    });

    test('设置密钥的语句出错时，异常里没有密钥（底层异常带着语句全文）', () {
      String failingKey(String sql) {
        if (sql.startsWith('PRAGMA key')) {
          throw SqliteException(
            extendedResultCode: 1,
            message: 'boom',
            causingStatement: sql,
          );
        }
        if (sql.contains('sqlite3mc_version')) {
          return 'SQLite3 Multiple Ciphers 2.6.1';
        }
        return sql.startsWith('PRAGMA cipher') ? 'chacha20' : '';
      }

      try {
        applyEncryptionWith(failingKey, key.rawKeyLiteral());
        fail('expected keyApplyFailed');
      } on DatabaseOpenException catch (error) {
        expect(error.code, DatabaseErrorCode.keyApplyFailed);
        expect(containsKeyMaterial(error.toString(), testKeyHex), isFalse);
      }
    });
  });

  test('DatabaseKey：64 位十六进制往返；toString 不输出内容；格式不对拒绝', () {
    final key = DatabaseKey.decode(testKeyHex);
    expect(key.encode(), testKeyHex);
    expect(key.rawKeyLiteral(), "x'$testKeyHex'");
    expect(key.toString(), 'DatabaseKey(<redacted>)');
    expect('$key', isNot(contains('0011')));
    for (final bad in <String>[
      '',
      testKeyHex.substring(2),
      testKeyHex.toUpperCase(),
      '${testKeyHex.substring(1)}g',
    ]) {
      expect(
        () => DatabaseKey.decode(bad),
        throwsA(const DatabaseOpenException(DatabaseErrorCode.keyInvalid)),
        reason: bad,
      );
    }
    final generated = DatabaseKey.generate();
    expect(generated.encode(), matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(generated.encode(), isNot(DatabaseKey.generate().encode()));
  });
}
