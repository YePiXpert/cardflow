import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/db/database_errors.dart';
import '../../data/db/database_providers.dart';

part 'crypto_status.g.dart';

/// 加密本地库的状态（ADR-001 / PoC-1，ios-first-plan I0-5）。诊断页显示 [displayText]，
/// 诊断报告用 [reportText]。
sealed class CryptoLibraryStatus {
  const CryptoLibraryStatus();

  /// 诊断页上的文字。
  String get displayText;

  /// 诊断报告里的文字（可以比页面更详细）。
  String get reportText => displayText;
}

/// 加密库已加载、数据库已用设备密钥打开并通过检查。
final class CryptoLibraryReady extends CryptoLibraryStatus {
  const CryptoLibraryReady({
    required this.library,
    required this.cipher,
    this.cipherVersionPragma = '',
  });

  /// 加密库名称与版本：`SELECT sqlite3mc_version()`，如 `SQLite3 Multiple Ciphers 2.6.1`。
  final String library;

  /// 加密算法：`PRAGMA cipher`，如 `chacha20`。
  final String cipher;

  /// `PRAGMA cipher_version` 的原始结果（SQLCipher 的 PRAGMA；sqlite3mc 不提供，为空）。
  final String cipherVersionPragma;

  @override
  String get displayText => '已启用（$library，算法 $cipher）';

  @override
  String get reportText {
    final cipherVersion = cipherVersionPragma.isEmpty
        ? '（空，sqlite3mc 不提供此 PRAGMA）'
        : cipherVersionPragma;
    return '$displayText；PRAGMA cipher=$cipher；'
        'sqlite3mc_version()=$library；PRAGMA cipher_version=$cipherVersion';
  }
}

/// 加密库不可用或数据库打不开（ADR-001：此时拒绝使用数据库）。[reasonCode] 只放错误码，
/// 不放路径与正文。
final class CryptoLibraryUnavailable extends CryptoLibraryStatus {
  const CryptoLibraryUnavailable({required this.reasonCode});

  final String reasonCode;

  @override
  String get displayText => '不可用（$reasonCode）';
}

/// 诊断页读取的加密库状态：打开本机加密数据库（`openedDatabaseProvider`）的结果。
@Riverpod(keepAlive: true)
Future<CryptoLibraryStatus> cryptoLibraryStatus(Ref ref) async {
  try {
    final opened = await ref.watch(openedDatabaseProvider.future);
    return CryptoLibraryReady(
      library: opened.cipher.library,
      cipher: opened.cipher.cipher,
      cipherVersionPragma: opened.cipher.cipherVersionPragma,
    );
  } on DatabaseOpenException catch (error) {
    return CryptoLibraryUnavailable(reasonCode: error.code.code);
  }
}
