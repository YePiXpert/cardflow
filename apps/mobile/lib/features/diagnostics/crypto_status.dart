import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'crypto_status.g.dart';

/// 加密本地库的状态（ADR-001 / PoC-1，ios-first-plan I0-5）。诊断页显示 [displayText]。
sealed class CryptoLibraryStatus {
  const CryptoLibraryStatus();

  /// 诊断页与诊断报告中的文字。
  String get displayText;
}

/// 尚未接入加密库（I-0a 骨架阶段）。
final class CryptoLibraryPending extends CryptoLibraryStatus {
  const CryptoLibraryPending();

  @override
  String get displayText => '待下一阶段';
}

/// 加密库已加载并通过启动检查：`PRAGMA cipher_version` 返回非空。
final class CryptoLibraryReady extends CryptoLibraryStatus {
  const CryptoLibraryReady({required this.cipherVersion});

  /// `PRAGMA cipher_version` 的返回值。
  final String cipherVersion;

  @override
  String get displayText => '已启用（cipher_version $cipherVersion）';
}

/// 加密库不可用（ADR-001：此时拒绝打开数据库）。[reasonCode] 只放错误码，不放路径与正文。
final class CryptoLibraryUnavailable extends CryptoLibraryStatus {
  const CryptoLibraryUnavailable({required this.reasonCode});

  final String reasonCode;

  @override
  String get displayText => '不可用（$reasonCode）';
}

/// 诊断页读取的加密库状态。
///
/// 下一任务（I0-5，加密 drift）把函数体换成真实检查：打开加密库 →
/// 执行 `PRAGMA cipher_version` → 非空返回 [CryptoLibraryReady]，否则返回
/// [CryptoLibraryUnavailable]。诊断页与报告无需改动。
@Riverpod(keepAlive: true)
Future<CryptoLibraryStatus> cryptoLibraryStatus(Ref ref) async =>
    const CryptoLibraryPending();
