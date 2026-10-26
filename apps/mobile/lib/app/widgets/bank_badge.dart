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

/// Apple Wallet 风微缩矢量卡面徽标：默认 50×34pt 圆角卡面，带银行品牌渐变、金属芯片与银行字标。
/// 装饰性：读屏跳过，银行名由旁边的文字给出。
class BankBadge extends StatelessWidget {
  const BankBadge({super.key, required this.bankName, this.size});

  final String bankName;

  /// 卡面高度；默认 [CfSize.bankBadge]（34pt），宽度按信用卡比例取 50pt。
  final double? size;

  @override
  Widget build(BuildContext context) {
    final height = size ?? CfSize.bankBadge;
    final scale = height / CfSize.bankBadge;
    final width = (50 * scale).roundToDouble();
    final base = bankColor(bankName);
    final deep = Color.lerp(base, CfBankColors.faceShade, 0.34)!;
    final radius = BorderRadius.circular(7 * scale);
    return ExcludeSemantics(
      child: MediaQuery.withNoTextScaling(
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[base, deep],
            ),
            borderRadius: radius,
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: CustomPaint(
              painter: _MiniCardArtPainter(base: base, scale: scale),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 6 * scale,
                  vertical: 4 * scale,
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    bankMark(bankName),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: CfBankColors.mark,
                      fontWeight: FontWeight.w700,
                      fontSize: height * 0.44,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 仿真 EMV 金属芯片图标（用于详情页大卡面）。
class CardChipArt extends StatelessWidget {
  const CardChipArt({super.key, required this.bankName, this.width = 34});

  final String bankName;
  final double width;

  @override
  Widget build(BuildContext context) {
    final height = (width * 0.74).roundToDouble();
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(width, height),
        painter: _ChipOnlyPainter(base: bankColor(bankName)),
      ),
    );
  }
}

class _MiniCardArtPainter extends CustomPainter {
  const _MiniCardArtPainter({required this.base, required this.scale});

  final Color base;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    // 斜向微光折射带
    final sheenPath = Path()
      ..moveTo(size.width * 0.18, 0)
      ..lineTo(size.width * 0.56, 0)
      ..lineTo(size.width * 0.24, size.height)
      ..lineTo(-size.width * 0.08, size.height)
      ..close();
    canvas.drawPath(
      sheenPath,
      Paint()..color = CfBankColors.mark.withValues(alpha: 0.10),
    );

    // 左侧金属芯片
    final chipRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(6 * scale, 10 * scale, 12 * scale, 9 * scale),
      Radius.circular(2 * scale),
    );
    canvas.drawRRect(
      chipRect,
      Paint()..color = CfBankColors.mark.withValues(alpha: 0.82),
    );
    final linePaint = Paint()
      ..color = Color.lerp(base, CfBankColors.faceShade, 0.35)!
      ..strokeWidth = 0.8 * scale
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(6 * scale, 14.5 * scale),
      Offset(18 * scale, 14.5 * scale),
      linePaint,
    );
    canvas.drawLine(
      Offset(12 * scale, 10 * scale),
      Offset(12 * scale, 19 * scale),
      linePaint,
    );

    // 左下微缩卡号点阵
    final dotPaint = Paint()..color = CfBankColors.mark.withValues(alpha: 0.55);
    for (var i = 0; i < 4; i++) {
      canvas.drawCircle(
        Offset((7.2 + i * 2.8) * scale, 26.5 * scale),
        0.85 * scale,
        dotPaint,
      );
    }

    // 细微高光内描边
    final borderRect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(7 * scale),
    ).deflate(0.5);
    canvas.drawRRect(
      borderRect,
      Paint()
        ..color = CfBankColors.mark.withValues(alpha: 0.20)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniCardArtPainter oldDelegate) =>
      oldDelegate.base != base || oldDelegate.scale != scale;
}

class _ChipOnlyPainter extends CustomPainter {
  const _ChipOnlyPainter({required this.base});

  final Color base;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height * 0.2),
    );
    canvas.drawRRect(
      rrect,
      Paint()..color = CfBankColors.mark.withValues(alpha: 0.84),
    );
    final linePaint = Paint()
      ..color = Color.lerp(base, CfBankColors.faceShade, 0.35)!
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(0, size.height * 0.5),
      Offset(size.width, size.height * 0.5),
      linePaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.35, 0),
      Offset(size.width * 0.35, size.height),
      linePaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.65, 0),
      Offset(size.width * 0.65, size.height),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ChipOnlyPainter oldDelegate) =>
      oldDelegate.base != base;
}
