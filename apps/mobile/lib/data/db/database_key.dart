import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'database_errors.dart';

/// 设备数据库密钥：256 位随机数（security-privacy §5）。
///
/// 只在内存中以字节形式存在；[toString] 不输出内容，避免被意外写进日志或异常。
final class DatabaseKey {
  DatabaseKey._(this._bytes);

  /// 用 [random]（默认 [Random.secure]，即系统安全随机数）生成新密钥。
  factory DatabaseKey.generate([Random? random]) {
    final source = random ?? Random.secure();
    return DatabaseKey._(
      Uint8List.fromList(
        List<int>.generate(lengthInBytes, (_) => source.nextInt(256)),
      ),
    );
  }

  /// 从钥匙串中保存的文本（64 个小写十六进制字符）还原；格式不对抛
  /// [DatabaseErrorCode.keyInvalid]。
  factory DatabaseKey.decode(String stored) {
    if (!_storedFormat.hasMatch(stored)) {
      throw const DatabaseOpenException(DatabaseErrorCode.keyInvalid);
    }
    final bytes = Uint8List(lengthInBytes);
    for (var i = 0; i < lengthInBytes; i++) {
      bytes[i] = int.parse(stored.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return DatabaseKey._(bytes);
  }

  /// 密钥长度：32 字节（sqlite3mc 默认算法 ChaCha20-Poly1305 的密钥长度）。
  static const int lengthInBytes = 32;

  static final RegExp _storedFormat = RegExp(r'^[0-9a-f]{64}$');

  final Uint8List _bytes;

  /// 写入钥匙串的文本：64 个小写十六进制字符。
  String encode() {
    final buffer = StringBuffer();
    for (final byte in _bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// sqlite3mc 的原始密钥写法 `x'<64 位十六进制>'`：直接作为 256 位密钥使用，
  /// 跳过口令派生（PBKDF2）。只用于拼接 `PRAGMA key`，见 `encryption.dart`。
  String rawKeyLiteral() => "x'${encode()}'";

  @override
  String toString() => 'DatabaseKey(<redacted>)';
}

/// 设备数据库密钥的存放处。正式实现是 iOS 钥匙串（[SecureStorageDatabaseKeyStore]），
/// 测试用内存实现。只存一条：本机数据库的密钥。
abstract interface class DatabaseKeyStore {
  /// 读取已保存的密钥文本；没有时返回 null。
  Future<String?> read();

  /// 保存密钥文本（覆盖旧值）。
  Future<void> write(String value);

  /// 是否已保存密钥（不读出内容）。
  Future<bool> exists();
}

/// 钥匙串实现（flutter_secure_storage）。
///
/// iOS：`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`（设备解锁时可读、不随备份
/// 迁移到其他设备）、不同步到 iCloud 钥匙串、不设 access group（不需要任何
/// entitlement）。
final class SecureStorageDatabaseKeyStore implements DatabaseKeyStore {
  const SecureStorageDatabaseKeyStore([
    this._storage = const FlutterSecureStorage(iOptions: iosOptions),
  ]);

  /// 钥匙串条目名（iOS 的 kSecAttrAccount）。
  static const String entryName = 'cardflow.database_key.v1';

  /// iOS 钥匙串参数。
  static const IOSOptions iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.unlocked_this_device,
    synchronizable: false,
  );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: entryName);

  @override
  Future<void> write(String value) =>
      _storage.write(key: entryName, value: value);

  @override
  Future<bool> exists() => _storage.containsKey(key: entryName);
}

/// 取得设备数据库密钥：已有则读出；没有且数据库文件也不存在（首次启动）则生成一次并保存。
///
/// 同一个实例上的并发调用共用一次读取/生成，不会生成两把密钥。
final class DatabaseKeyManager {
  DatabaseKeyManager(this._store, {this._random});

  final DatabaseKeyStore _store;
  final Random? _random;
  Future<DatabaseKey>? _pending;

  /// 取得密钥。
  ///
  /// [databaseHasData] 为 true（数据库文件已存在且非空）而钥匙串里没有密钥时，
  /// 抛 [DatabaseErrorCode.keyMissing]，绝不新建密钥（那会让旧库永远打不开）。
  /// 钥匙串读写失败抛 [DatabaseErrorCode.keyStoreFailed]；新密钥写入后读回不一致也算失败，
  /// 此时不会建库。
  Future<DatabaseKey> obtain({required bool databaseHasData}) {
    final existing = _pending;
    if (existing != null) {
      return existing;
    }
    final pending = _obtain(databaseHasData: databaseHasData);
    _pending = pending;
    // 失败后允许重试（例如设备锁定时钥匙串暂不可读）；错误本身由调用方处理。
    unawaited(
      pending.then<void>(
        (_) {},
        onError: (Object _) {
          if (identical(_pending, pending)) {
            _pending = null;
          }
        },
      ),
    );
    return pending;
  }

  Future<DatabaseKey> _obtain({required bool databaseHasData}) async {
    final stored = await _guardStore(_store.read);
    if (stored != null) {
      return DatabaseKey.decode(stored);
    }
    if (databaseHasData) {
      throw const DatabaseOpenException(DatabaseErrorCode.keyMissing);
    }
    final key = DatabaseKey.generate(_random);
    final encoded = key.encode();
    await _guardStore(() => _store.write(encoded));
    final readBack = await _guardStore(_store.read);
    if (readBack != encoded) {
      throw const DatabaseOpenException(DatabaseErrorCode.keyStoreFailed);
    }
    return key;
  }

  /// 钥匙串是否已有密钥（诊断页只显示"已生成/未生成"）。
  Future<bool> hasKey() => _guardStore(_store.exists);

  static Future<T> _guardStore<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DatabaseOpenException {
      rethrow;
    } on Object {
      // 平台异常的正文可能含系统细节，统一换成错误码。
      throw const DatabaseOpenException(DatabaseErrorCode.keyStoreFailed);
    }
  }
}
