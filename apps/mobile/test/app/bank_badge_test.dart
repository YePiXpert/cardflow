import 'dart:math' as math;

import 'package:cardflow/app/theme/app_theme.dart';
import 'package:cardflow/app/theme/tokens.dart';
import 'package:cardflow/app/widgets/bank_badge.dart';
import 'package:cardflow/data/repositories/bank_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  test('简报点名的 16 家常见银行：固定简称、徽标字与品牌色', () {
    const expected = <String, (String, String)>{
      '中国工商银行': ('工行', '工'),
      '中国建设银行': ('建行', '建'),
      '中国农业银行': ('农行', '农'),
      '中国银行': ('中行', '中'),
      '交通银行': ('交行', '交'),
      '招商银行': ('招行', '招'),
      '浦发银行': ('浦发', '浦'),
      '中国民生银行': ('民生', '民'),
      '兴业银行': ('兴业', '兴'),
      '中国光大银行': ('光大', '光'),
      '中信银行': ('中信', '信'),
      '平安银行': ('平安', '平'),
      '广发银行': ('广发', '广'),
      '华夏银行': ('华夏', '华'),
      '中国邮政储蓄银行': ('邮储', '邮'),
      '浙商银行': ('浙商', '浙'),
    };
    final colors = <Color>{};
    for (final MapEntry(key: name, value: (short, mark)) in expected.entries) {
      expect(bankShortName(name), short, reason: name);
      expect(bankMark(name), mark, reason: name);
      expect(knownBankOf(name), isNotNull, reason: name);
      colors.add(bankColor(name));
    }
    expect(knownBankNames, hasLength(16));
    // 常见银行内置名单里的 16 家都认得出来。
    for (final name in builtinBankNames.take(16)) {
      expect(knownBankOf(name), isNotNull, reason: name);
    }
    expect(colors.length, greaterThanOrEqualTo(14), reason: '品牌色基本互不相同');
    // 别称与全称同一家。
    expect(bankShortName('上海浦东发展银行'), '浦发');
    expect(bankShortName('工商银行'), '工行');
  });

  test('其余银行：去掉"银行"二字作简称，首字作徽标，按名称哈希取调色板（同名同色）', () {
    expect(bankShortName('北京银行'), '北京');
    expect(bankShortName('星海银行'), '星海');
    expect(bankMark('星海银行'), '星');
    expect(bankShortName('银行'), '银行');
    expect(bankColor('北京银行'), bankColor('北京银行'));
    expect(CfBankColors.palette, contains(bankColor('北京银行')));
  });

  test('演示空间的三家虚构银行：首字与颜色都互不相同', () {
    const demo = <String>['星海银行', '长江银行', '北辰银行'];
    expect(demo.map(bankMark).toSet(), hasLength(3));
    expect(demo.map(bankColor).toSet(), hasLength(3));
    for (final name in demo) {
      expect(knownBankOf(name), isNull);
    }
  });

  test('白字对每一种徽标颜色不低于 4.5:1；调色板不用绿色（稳妥色）', () {
    for (final color in <Color>[
      for (final bank in knownBankNames) bankColor(bank.keys.first),
      ...CfBankColors.palette,
    ]) {
      expect(
        _contrast(CfBankColors.mark, color),
        greaterThanOrEqualTo(4.5),
        reason: '$color',
      );
    }
    for (final color in CfBankColors.palette) {
      expect(color, isNot(CardFlowColors.light.robust.fg));
      expect(color, isNot(CardFlowColors.dark.robust.fg));
    }
  });

  testWidgets('徽标：34pt 方块、白字、读屏跳过（银行名由旁边的文字给出）', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCardFlowTheme(Brightness.dark),
        home: const Scaffold(
          body: Center(child: BankBadge(bankName: '招商银行')),
        ),
      ),
    );
    expect(tester.getSize(find.byType(BankBadge)), const Size(34, 34));
    final text = tester.widget<Text>(find.text('招'));
    expect(text.style?.color, CfBankColors.mark);
    expect(find.bySemanticsLabel('招'), findsNothing);
    handle.dispose();
  });
}
