/// 银行的简称与徽标字（简报 U-1 §2、§5）：卡账首页的行名 = 银行简称 + 主卡末四位；徽标 = 简称首字 + 品牌色。
///
/// 常见银行（简报点名的 16 家）用习惯简称（"工行""招行"），其余去掉"银行"二字（"星海银行" → "星海"）。
/// 只是名称规则，不含颜色（颜色是界面 token，见 `lib/app/theme/tokens.dart` 的 `CfBankColors`）。
library;

import 'package:flutter/foundation.dart';

/// 一家常见银行。
@immutable
final class KnownBankName {
  const KnownBankName({
    required this.short,
    required this.mark,
    required this.keys,
  });

  /// 简称。
  final String short;

  /// 徽标上的字（一般是简称首字；"中信"与"中行"同为"中"，中信用"信"）。
  final String mark;

  /// 银行名称里出现任一个就算这家银行。
  final List<String> keys;
}

/// 常见银行。顺序有意义：先匹配名字更具体的，"中国银行"放最后。
const List<KnownBankName> knownBankNames = <KnownBankName>[
  KnownBankName(short: '工行', mark: '工', keys: <String>['工商', '工行']),
  KnownBankName(short: '建行', mark: '建', keys: <String>['建设银行', '建行']),
  KnownBankName(short: '农行', mark: '农', keys: <String>['农业银行', '农行']),
  KnownBankName(short: '交行', mark: '交', keys: <String>['交通银行', '交行']),
  KnownBankName(short: '招行', mark: '招', keys: <String>['招商银行', '招行']),
  KnownBankName(short: '浦发', mark: '浦', keys: <String>['浦发', '浦东发展']),
  KnownBankName(short: '民生', mark: '民', keys: <String>['民生银行']),
  KnownBankName(short: '兴业', mark: '兴', keys: <String>['兴业银行']),
  KnownBankName(short: '光大', mark: '光', keys: <String>['光大银行']),
  KnownBankName(short: '中信', mark: '信', keys: <String>['中信银行']),
  KnownBankName(short: '平安', mark: '平', keys: <String>['平安银行']),
  KnownBankName(short: '广发', mark: '广', keys: <String>['广发银行']),
  KnownBankName(short: '华夏', mark: '华', keys: <String>['华夏银行']),
  KnownBankName(short: '邮储', mark: '邮', keys: <String>['邮政储蓄', '邮储']),
  KnownBankName(short: '浙商', mark: '浙', keys: <String>['浙商银行']),
  KnownBankName(short: '中行', mark: '中', keys: <String>['中国银行', '中行']),
];

/// 名称属于哪家常见银行；不是常见银行时为 null。
KnownBankName? knownBankOf(String bankName) {
  final name = bankName.trim();
  for (final bank in knownBankNames) {
    for (final key in bank.keys) {
      if (name.contains(key)) {
        return bank;
      }
    }
  }
  return null;
}

/// 银行简称：常见银行用习惯简称，其余去掉"银行"二字。
String bankShortName(String bankName) {
  final known = knownBankOf(bankName);
  if (known != null) {
    return known.short;
  }
  final name = bankName.trim();
  final short = name.replaceAll('银行', '').trim();
  return short.isEmpty ? name : short;
}

/// 徽标上的字：常见银行固定，其余取简称首字（按字符，不拆代理对）。
String bankMark(String bankName) {
  final known = knownBankOf(bankName);
  if (known != null) {
    return known.mark;
  }
  final short = bankShortName(bankName);
  return short.isEmpty ? '?' : String.fromCharCode(short.runes.first);
}
