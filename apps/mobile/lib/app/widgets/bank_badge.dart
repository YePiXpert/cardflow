import 'package:flutter/material.dart';

import '../../data/banks/bank_names.dart';
import '../theme/tokens.dart';

export '../../data/banks/bank_names.dart';

/// 常见银行（简称）的品牌色。
const Map<String, Color> _brandColors = <String, Color>{
  '工行': CfBankColors.icbc,
  '建行': CfBankColors.ccb,
  '农行': CfBankColors.abc,
  '交行': CfBankColors.bocom,
  '招行': CfBankColors.cmb,
  '浦发': CfBankColors.spdb,
  '民生': CfBankColors.cmbc,
  '兴业': CfBankColors.cib,
  '光大': CfBankColors.ceb,
  '中信': CfBankColors.citic,
  '平安': CfBankColors.pingan,
  '广发': CfBankColors.cgb,
  '华夏': CfBankColors.hxb,
  '邮储': CfBankColors.psbc,
  '浙商': CfBankColors.czb,
  '中行': CfBankColors.boc,
};

/// 徽标颜色：常见银行用品牌色，其余按简称的 FNV-1a 哈希从 [CfBankColors.palette] 取（同名总是同色）。
Color bankColor(String bankName) {
  final known = knownBankOf(bankName);
  if (known != null) {
    return _brandColors[known.short]!;
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
