import 'package:cardflow/app/money/amount_visibility.dart';
import 'package:cardflow/app/theme/app_theme.dart';
import 'package:cardflow/app/theme/tokens.dart';
import 'package:cardflow/app/widgets/money_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpMoney(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  List<Override> overrides = const <Override>[],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: buildCardFlowTheme(brightness),
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

Text textOf(WidgetTester tester) => tester.widget<Text>(
  find.descendant(of: find.byType(MoneyText), matching: find.byType(Text)),
);

void main() {
  testWidgets('等宽数字、默认右对齐、按币种小数位显示', (tester) async {
    await pumpMoney(tester, const MoneyText(minor: 123456, currency: 'CNY'));

    final text = textOf(tester);
    expect(text.data, '¥1,234.56');
    expect(text.textAlign, TextAlign.end);
    expect(
      text.style?.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
  });

  testWidgets('0 位与 3 位小数币种', (tester) async {
    await pumpMoney(
      tester,
      const Column(
        children: <Widget>[
          MoneyText(minor: 1235, currency: 'JPY'),
          MoneyText(minor: 1235, currency: 'KWD'),
        ],
      ),
    );

    expect(find.text('JPY 1,235'), findsOneWidget);
    expect(find.text('KWD 1.235'), findsOneWidget);
  });

  testWidgets('负数：语义词 + "−" + 语义色（不只靠符号）', (tester) async {
    await pumpMoney(
      tester,
      const MoneyText(minor: -200000, currency: 'CNY', negativeLabel: '缺口'),
    );

    final text = textOf(tester);
    expect(text.data, '缺口 −¥2,000.00');
    expect(text.style?.color, CardFlowColors.light.danger.fg);
  });

  testWidgets('深色主题下负数使用深色语义色', (tester) async {
    await pumpMoney(
      tester,
      const MoneyText(minor: -1, currency: 'CNY', negativeLabel: '超限'),
      brightness: Brightness.dark,
    );

    expect(textOf(tester).style?.color, CardFlowColors.dark.danger.fg);
  });

  testWidgets('贷方余额可用中性色调', (tester) async {
    await pumpMoney(
      tester,
      const MoneyText(
        minor: -5000,
        currency: 'CNY',
        negativeLabel: '贷方余额',
        negativeTone: MoneyTone.neutral,
        style: TextStyle(color: Color(0xFF1A1C1E)),
      ),
    );

    final text = textOf(tester);
    expect(text.data, '贷方余额 −¥50.00');
    expect(text.style?.color, const Color(0xFF1A1C1E));
  });

  testWidgets('读屏朗读完整语义', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpMoney(
      tester,
      const MoneyText(minor: 800000, currency: 'CNY', semanticsPrefix: '本期应还'),
    );

    expect(
      tester.getSemantics(find.byType(MoneyText)),
      matchesSemantics(label: '本期应还 人民币 8,000.00 元'),
    );
    handle.dispose();
  });

  testWidgets('全局金额隐藏：显示"••••"，读屏读"金额已隐藏"', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpMoney(
      tester,
      const MoneyText(minor: 123456, currency: 'CNY'),
      overrides: <Override>[amountsHiddenProvider.overrideWithValue(true)],
    );

    expect(textOf(tester).data, '••••');
    expect(find.textContaining(RegExp(r'\d')), findsNothing);
    expect(
      tester.getSemantics(find.byType(MoneyText)),
      matchesSemantics(label: '金额已隐藏'),
    );
    handle.dispose();
  });

  testWidgets('切换全局开关后立即生效；单个组件可显式覆盖', (tester) async {
    await pumpMoney(
      tester,
      const Column(
        children: <Widget>[
          MoneyText(key: Key('follow'), minor: 100, currency: 'CNY'),
          MoneyText(
            key: Key('forced'),
            minor: 100,
            currency: 'CNY',
            hidden: false,
          ),
        ],
      ),
    );
    expect(find.text('¥1.00'), findsNWidgets(2));

    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('follow'))),
    );
    container.read(amountsHiddenProvider.notifier).toggle();
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const Key('follow')),
        matching: find.text('••••'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('forced')),
        matching: find.text('¥1.00'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('没有金额时显示"—"', (tester) async {
    await pumpMoney(tester, const MoneyText(minor: null, currency: 'CNY'));

    expect(textOf(tester).data, '—');
  });
}
