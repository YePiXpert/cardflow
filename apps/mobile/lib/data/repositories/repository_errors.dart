import 'package:sqlite3/common.dart' show SqliteException;

import '../db/database_platform.dart';
import 'ledger_models.dart';
import 'models.dart';

/// 仓库拒绝一次写入或查不到对象。[message] 是可以直接显示给用户的中文说明，**不含任何用户数据**
/// （不含金额、卡号、别名），所以也可以安全地进日志的 detail（数字会被掩码）。
sealed class RepositoryException implements Exception {
  const RepositoryException();

  String get message;

  @override
  String toString() => '$runtimeType($message)';
}

/// 字段校验不通过。[field] 是字段标识（如 `last4`、`alias`），界面据此把错误显示在对应输入框下。
final class ValidationException extends RepositoryException {
  const ValidationException(this.field, this.message);

  final String field;

  @override
  final String message;
}

/// 对象不存在（或不属于当前工作空间——两者对调用方不可区分，ui-spec §2 "已不存在"）。
final class NotFoundException extends RepositoryException {
  const NotFoundException(this.what);

  /// 对象种类，如"卡片""信用账户"。
  final String what;

  @override
  String get message => '$what已不存在';
}

/// 卡片状态机不允许的转移（PRD §6.1）。
final class IllegalCardTransitionException extends RepositoryException {
  const IllegalCardTransitionException(this.from, this.to);

  final CardStatus from;
  final CardStatus to;

  @override
  String get message => '卡片不能从「${from.label}」变为「${to.label}」';
}

/// 还款状态机不允许的转移（PRD §6.3）。
final class IllegalRepaymentTransitionException extends RepositoryException {
  const IllegalRepaymentTransitionException(this.from, this.to);

  final RepaymentStatus from;
  final RepaymentStatus to;

  @override
  String get message => '还款不能从「${from.label}」变为「${to.label}」';
}

/// 操作与现有数据冲突（如主子账户不可删、规则区间重叠）。
final class ConflictException extends RepositoryException {
  const ConflictException(this.message);

  @override
  final String message;
}

/// 数据库约束或触发器拒绝了写入（仓库自己的校验应已先拦下，走到这里说明有遗漏）。
final class StorageRejectedException extends RepositoryException {
  const StorageRejectedException(this.sqliteResultCode);

  final int? sqliteResultCode;

  @override
  String get message => '保存失败：数据不符合本地库的约束';
}

/// 把 drift/sqlite 的约束错误换成 [StorageRejectedException]（丢弃底层消息：它带着语句与取值）。
Never rethrowAsRepositoryException(Object error, StackTrace stack) {
  final cause = unwrapRemoteError(error);
  if (cause is RepositoryException) {
    Error.throwWithStackTrace(cause, stack);
  }
  if (cause is SqliteException) {
    Error.throwWithStackTrace(
      StorageRejectedException(cause.extendedResultCode),
      stack,
    );
  }
  Error.throwWithStackTrace(error, stack);
}
