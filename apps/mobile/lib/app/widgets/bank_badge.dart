import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 一家常见银行：简称、徽标上的字与固定的品牌色（简报 U-1 §5）。
///
/// 只用"简称首字 + 品牌色色块"，不用银行的商标图形，也不打包任何图片资源；颜色在 [CfBankColors]。
@immutable
final class KnownBank {
  const KnownBank({
    required this.short,
    required this.mark,
    required this.color,
    required this.keys,
  });

  /// 简称（列表行的名称用它）。
  final String short;

  /// 徽标上的字（一般是简称首字；"中信"与"中行"同为"中"，中信用"信"）。
  final String mark;

  /// 品牌色。
  final Color color;

  /// 银行名称里出现任一个就算这家银行。
  final List<String> keys;
}

/// 常见银行（简报 U-1 §5 点名的 16 家）。顺序有意义：先匹配名字更具体的，"中国银行"放最后。
const List<KnownBank> knownBanks = <KnownBank>[
  KnownBank(
    short: '工行',
    mark: '工',
    color: CfBankColors.icbc,
    keys: <String>['工商', '工行'],
  ),
  KnownBank(
    short: '建行',
    mark: '建',
    color: CfBankColors.ccb,
    keys: <String>['建设银行', '建行'],
  ),
  KnownBank(
    short: '农行',
    mark: '农',
    color: CfBankColors.abc,
    keys: <String>['中国农业银行', '农业银行', '农行'],
  ),
  KnownBank(
    short: '交行',
    mark: '交',
    color: CfBankColors.bocom,
    keys: <String>['交通银行', '交行'],
  ),
  KnownBank(
    short: '招行',
    mark: '招',
    color: CfBankColors.cmb,
    keys: <String>['招商银行', '招行'],
  ),
  KnownBank(
    short: '浦发',
    mark: '浦',
    color: CfBankColors.spdb,
    keys: <String>['浦发', '浦东发展'],
  ),
  KnownBank(
    short: '民生',
    mark: '民',
    color: CfBankColors.cmbc,
    keys: <String>['民生银行'],
  ),
  KnownBank(
    short: '兴业',
    mark: '兴',
    color: CfBankColors.cib,
    keys: <String>['兴业银行'],
  ),
  KnownBank(
    short: '光大',
    mark: '光',
    color: CfBankColors.ceb,
    keys: <String>['光大银行'],
  ),
  KnownBank(
    short: '中信',
    mark: '信',
    color: CfBankColors.citic,
    keys: <String>['中信银行'],
  ),
  KnownBank(
    short: '平安',
    mark: '平',
    color: CfBankColors.pingan,
    keys: <String>['平安银行'],
  ),
  KnownBank(
    short: '广发',
    mark: '广',
    color: CfBankColors.cgb,
    keys: <String>['广发银行'],
  ),
  KnownBank(
    short: '华夏',
    mark: '华',
    color: CfBankColors.hxb,
    keys: <String>['华夏银行'],
  ),
  KnownBank(
    short: '邮储',
    mark: '邮',
    color: CfBankColors.psbc,
    keys: <String>['邮政储蓄', '邮储'],
  ),
  KnownBank(
    short: '浙商',
    mark: '浙',
    color: CfBankColors.czb,
    keys: <String>['浙商银行'],
  ),
  KnownBank(
    short: '中行',
    mark: '中',
    color: CfBankColors.boc,
    keys: <String>['中国银行', '中行'],
  ),
];

/// 名称属于哪家常见银行；不是常见银行时为 null。
KnownBank? knownBankOf(String bankName) {
  final name = bankName.trim();
  for (final bank in knownBanks) {
    for (final key in bank.keys) {
      if (name.contains(key)) {
        return bank;
      }
    }
  }
  return null;
}

/// 银行简称：常见银行用习惯简称（"工行""招行"），其余去掉"银行"二字（"星海银行" → "星海"）。
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

/// 徽标颜色：常见银行用品牌色，其余按简称的 FNV-1a 哈希从 [CfBankColors.palette] 取（同名总是同色）。
Color bankColor(String bankName) {
  final known = knownBankOf(bankName);
  if (known != null) {
    return known.color;
  }
  var hash = 0x811c9dc5;
  for (final unit in bankShortName(bankName).codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return CfBankColors.palette[hash % CfBankColors.palette.length];
}

/// 银行徽标：34pt 圆角方块、白色简称首字（简报 U-1 §5）。装饰性：读屏跳过，银行名由旁边的文字给出。
class BankBadge extends StatelessWidget {
  const BankBadge({super.key, required this.bankName, this.size});

  final String bankName;

  /// 边长；默认 [CfSize.bankBadge]。
  final double? size;

  @override
  Widget build(BuildContext context) {
    final side = size ?? CfSize.bankBadge;
    return ExcludeSemantics(
      child: MediaQuery.withNoTextScaling(
        child: Container(
          width: side,
          height: side,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bankColor(bankName),
            borderRadius: BorderRadius.circular(
              CfRadius.lg * side / CfSize.bankBadge,
            ),
          ),
          child: Text(
            bankMark(bankName),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: CfBankColors.mark,
              fontSize: side * 0.47,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
