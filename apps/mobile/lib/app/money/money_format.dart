/// 金额展示格式（纯 Dart，无 Flutter 依赖，全程整数，不使用 double）。
///
/// 规则来自 docs/50-ui/ui-spec.md §3.4 与 §3.6：
/// - 输入为整数最小单位 + ISO 4217 币种，按币种小数位展示，千分位；
/// - CNY 用"¥"，其他币种用 ISO 代码；
/// - 负数用"−"（U+2212）并带语义词（缺口/超限/贷方余额），不只靠符号；
/// - 金额隐藏时固定显示 4 个"•"，不随位数变化，读屏读"金额已隐藏"；
/// - 没有金额时显示"—"，不显示 0。
///
/// 最小单位位数表 [minorDigits] 与 [minorDigitsOf] 的唯一来源是纯 Dart 领域包
/// `cardflow_domain`（packages/cardflow_domain/lib/src/money.dart，与服务端 money.py 逐项一致）；
/// 本文件只引用并转导出，不再自带一份。
library;

import 'package:cardflow_domain/cardflow_domain.dart' show minorDigitsOf;

export 'package:cardflow_domain/cardflow_domain.dart'
    show minorDigits, minorDigitsOf;

/// 读屏用的币种名称。
const Map<String, String> currencySpokenNames = <String, String>{
  'CNY': '人民币',
  'USD': '美元',
  'EUR': '欧元',
  'HKD': '港元',
  'GBP': '英镑',
  'MOP': '澳门元',
  'TWD': '新台币',
  'JPY': '日元',
  'KRW': '韩元',
  'VND': '越南盾',
  'KWD': '科威特第纳尔',
  'BHD': '巴林第纳尔',
  'JOD': '约旦第纳尔',
};

/// 负号（U+2212），不用连字符。
const String minusSign = '−';

/// 金额隐藏占位：固定 4 个"•"（U+2022）。
const String hiddenAmountText = '••••';

/// 无金额占位："—"（U+2014）。
const String noAmountText = '—';

/// 读屏：金额隐藏时的朗读文字。
const String hiddenAmountSpoken = '金额已隐藏';

/// 读屏：无金额时的朗读文字。
const String noAmountSpoken = '暂无金额';

/// 调用方漏传语义词时的兜底词（仅 release；debug 下直接断言失败）。
const String fallbackNegativeLabel = '负数';

/// 把最小单位整数格式化为不带符号、不带币种的数字串，带千分位。
///
/// 例：`formatMinorAbs(123456, 'CNY')` → `1,234.56`；
/// `formatMinorAbs(-1235, 'JPY')` → `1,235`；`formatMinorAbs(5, 'KWD')` → `0.005`。
String formatMinorAbs(int minor, String currency) {
  final digits = minorDigitsOf(currency);
  // BigInt 取绝对值，避免 64 位最小值取反溢出。
  final abs = BigInt.from(minor).abs().toString().padLeft(digits + 1, '0');
  final integerPart = _groupThousands(abs.substring(0, abs.length - digits));
  if (digits == 0) {
    return integerPart;
  }
  return '$integerPart.${abs.substring(abs.length - digits)}';
}

/// 同 [formatMinorAbs]，但小数部分为 0 时省略（"12,300"），不为 0 时照常显示全部小数位（"12,300.50"）。
/// 给卡账首页、详情页的大字金额用（设计稿：整元金额不写 .00）。
String formatMinorCompact(int minor, String currency) {
  final digits = minorDigitsOf(currency);
  final unit = BigInt.from(10).pow(digits);
  if (digits > 0 && BigInt.from(minor).remainder(unit) == BigInt.zero) {
    final full = formatMinorAbs(minor, currency);
    return full.substring(0, full.length - digits - 1);
  }
  return formatMinorAbs(minor, currency);
}

/// 币种标记：CNY 为"¥"，其他为"ISO 代码 + 空格"。
String currencyMarker(String currency) {
  minorDigitsOf(currency);
  return currency == 'CNY' ? '¥' : '$currency ';
}

/// 读屏用的金额朗读文字，如"人民币 8,000.00 元""美元 12.50"。
String spokenAmount(int minor, String currency) {
  final number = formatMinorAbs(minor, currency);
  final name = currencySpokenNames[currency] ?? currency;
  return currency == 'CNY' ? '$name $number 元' : '$name $number';
}

/// 一次金额展示的结果：屏幕文字与读屏文字。
class MoneyDisplay {
  const MoneyDisplay({
    required this.text,
    required this.semanticsLabel,
    required this.isNegative,
  });

  /// 屏幕上显示的文字。
  final String text;

  /// 读屏朗读的文字。
  final String semanticsLabel;

  /// 是否为负数（负数需要语义色）。
  final bool isNegative;
}

/// 计算一个金额的展示文字。
///
/// - [minor] 为 null：显示"—"（ui-spec §2"首次空白"金额位不显示 0）。
/// - [hidden] 为 true：显示固定 4 个"•"；负数仍保留语义词（ui-spec §5.2 ⑤）。
/// - 负数：显示"语义词 −¥2,000.00"。[negativeLabel] 必须由调用方给出
///   （如"缺口""超限""贷方余额"）；漏传时 debug 断言失败，release 用"负数"兜底。
/// - [semanticsPrefix]：读屏前缀，如"本期应还"→"本期应还 人民币 8,000.00 元"。
/// - [compact]：整元时省略小数部分（[formatMinorCompact]）；读屏照常读完整金额。
MoneyDisplay describeMoney({
  required int? minor,
  required String currency,
  bool hidden = false,
  String? negativeLabel,
  String? semanticsPrefix,
  bool compact = false,
}) {
  final marker = currencyMarker(currency);
  final prefix = semanticsPrefix == null ? '' : '$semanticsPrefix ';
  if (minor == null) {
    return MoneyDisplay(
      text: noAmountText,
      semanticsLabel: '$prefix$noAmountSpoken',
      isNegative: false,
    );
  }
  final isNegative = minor < 0;
  assert(
    !isNegative || negativeLabel != null,
    '负数金额必须带语义词（缺口/超限/贷方余额等），见 ui-spec §3.1、§3.4',
  );
  final label = isNegative ? (negativeLabel ?? fallbackNegativeLabel) : null;
  final labelPrefix = label == null ? '' : '$label ';
  if (hidden) {
    return MoneyDisplay(
      text: '$labelPrefix$hiddenAmountText',
      semanticsLabel: '$prefix$labelPrefix$hiddenAmountSpoken',
      isNegative: isNegative,
    );
  }
  final number = compact
      ? formatMinorCompact(minor, currency)
      : formatMinorAbs(minor, currency);
  final sign = isNegative ? minusSign : '';
  return MoneyDisplay(
    text: '$labelPrefix$sign$marker$number',
    semanticsLabel: '$prefix$labelPrefix${spokenAmount(minor, currency)}',
    isNegative: isNegative,
  );
}

String _groupThousands(String digits) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
