/// 金额展示格式（纯 Dart，无 Flutter 依赖，全程整数，不使用 double）。
///
/// 规则来自 docs/50-ui/ui-spec.md §3.4 与 §3.6：
/// - 输入为整数最小单位 + ISO 4217 币种，按币种小数位展示，千分位；
/// - CNY 用"¥"，其他币种用 ISO 代码；
/// - 负数用"−"（U+2212）并带语义词（缺口/超限/贷方余额），不只靠符号；
/// - 金额隐藏时固定显示 4 个"•"，不随位数变化，读屏读"金额已隐藏"；
/// - 没有金额时显示"—"，不显示 0。
///
/// [minorDigits] 暂放在展示层；下一任务把 Money 移植到 lib/domain 时，
/// 这张表随之迁入领域层，本文件改为引用领域层的表（保持唯一来源）。
library;

/// 每种币种的最小单位位数（ISO 4217）。
///
/// 必须与服务端引擎 `services/api/cardflow/planner/engine/money.py` 的
/// `MINOR_DIGITS` 完全一致；test/app/money_format_test.dart 会读取该文件逐项比对。
const Map<String, int> minorDigits = <String, int>{
  'CNY': 2,
  'USD': 2,
  'EUR': 2,
  'HKD': 2,
  'GBP': 2,
  'MOP': 2,
  'TWD': 2,
  'JPY': 0,
  'KRW': 0,
  'VND': 0,
  'KWD': 3,
  'BHD': 3,
  'JOD': 3,
};

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

/// 币种的最小单位位数；未登记的币种抛出 [ArgumentError]（与 money.py 的
/// `ValueError` 对应：宁可报错，也不猜小数位）。
int minorDigitsOf(String currency) {
  final digits = minorDigits[currency];
  if (digits == null) {
    throw ArgumentError.value(currency, 'currency', '未登记最小单位位数的币种');
  }
  return digits;
}

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
MoneyDisplay describeMoney({
  required int? minor,
  required String currency,
  bool hidden = false,
  String? negativeLabel,
  String? semanticsPrefix,
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
  final number = formatMinorAbs(minor, currency);
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
