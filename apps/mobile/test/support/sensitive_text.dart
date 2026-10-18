// 测试辅助：判断日志、诊断报告或异常文本里是否出现了敏感内容（审查 R-03）。
//
// 诊断日志把 detail 中的所有数字（含全角）换成 `#`（lib/app/diagnostics/diagnostic_log.dart），
// 所以"按原样查数字"在日志上永远查不到。这里的每个检查都同时匹配：
// - 原样形态（报告、异常消息不做掩码）；
// - 掩码形态（数字 → `#`，与日志相同）；
// - 密钥另查大写十六进制、base64 与十进制字节列表。
// 匹配用滑动窗口（密钥 ≥8 个字符；卡号 ≥5 位），只泄露一部分也能发现。
import 'dart:convert';

import 'package:cardflow/app/money/money_format.dart';
import 'package:cardflow_domain/cardflow_domain.dart' show fromMinorText;

/// 与诊断日志相同的数字掩码：0–9 与全角 ０–９ 都换成 `#`。
String maskDigits(String text) => text.replaceAll(RegExp('[0-9０-９]'), '#');

/// 密钥匹配的窗口长度（字符）。
const int keyMaterialWindow = 8;

/// 文本里是否出现了密钥材料（[keyHex] 为 64 个小写十六进制字符）。
///
/// 检查：十六进制原样与大写的任意 8 字符窗口；掩码形态的窗口（只用至少含 2 个非 `#` 字符的
/// 窗口——全是 `#` 的窗口与任何被掩码的数字都相同，没有区分度）；标准与 URL 安全 base64
/// （含去掉补齐符）的窗口；十进制字节列表中连续 4 个字节（`0, 17, 34, 51`、`0,17,34,51`、
/// 空格分隔）。
bool containsKeyMaterial(String text, String keyHex) {
  final bytes = <int>[
    for (var i = 0; i + 2 <= keyHex.length; i += 2)
      int.parse(keyHex.substring(i, i + 2), radix: 16),
  ];
  final forms = <String>{
    keyHex,
    keyHex.toUpperCase(),
    base64Encode(bytes),
    base64Url.encode(bytes),
    base64Encode(bytes).replaceAll('=', ''),
  };
  for (final form in forms) {
    if (_containsAnyWindow(text, form, keyMaterialWindow)) {
      return true;
    }
  }

  final maskedText = maskDigits(text);
  for (final form in forms) {
    final masked = maskDigits(form);
    for (var i = 0; i + keyMaterialWindow <= masked.length; i++) {
      final window = masked.substring(i, i + keyMaterialWindow);
      final distinctive = window.replaceAll('#', '').length >= 2;
      if (distinctive && maskedText.contains(window)) {
        return true;
      }
    }
  }

  for (final separator in const <String>[', ', ',', ' ']) {
    for (var i = 0; i + 4 <= bytes.length; i++) {
      if (text.contains(bytes.sublist(i, i + 4).join(separator))) {
        return true;
      }
    }
  }
  return false;
}

/// 文本里是否出现了金额 [minor]（币种 [currency]）：
/// 原样的最小单位整数、带千分位与不带千分位的十进制写法，以及它们的掩码形态
/// （例如 12,345.67 → `##,###.##`）。0 不检查（没有区分度）。
bool containsAmount(String text, int minor, String currency) {
  if (minor == 0) {
    return false;
  }
  final plain = fromMinorText(minor.abs(), currency);
  final grouped = formatMinorAbs(minor, currency);
  final raw = <String>{'${minor.abs()}', plain, grouped};
  if (raw.any(text.contains)) {
    return true;
  }
  final maskedText = maskDigits(text);
  return <String>{
    maskDigits(plain),
    maskDigits(grouped),
  }.where((form) => form.length >= 4).any(maskedText.contains);
}

/// 末四位以外的卡片数字：[fullNumber] 中任意 5 位连续数字（原样），或掩码后 5 个及以上连续
/// 的 `#`（日志里任何 5 位以上的数字都不应该出现）。只出现末四位不算。
bool containsCardDigits(String text, String fullNumber) {
  final digits = fullNumber.replaceAll(RegExp('[^0-9]'), '');
  if (_containsAnyWindow(text, digits, 5)) {
    return true;
  }
  return maskDigits(text).contains('#####');
}

/// 别名（或其他用户自由文本）是否出现：原样，或别名含数字时的掩码形态。
bool containsUserText(String text, String value) {
  if (text.contains(value)) {
    return true;
  }
  final masked = maskDigits(value);
  return masked != value && maskDigits(text).contains(masked);
}

bool _containsAnyWindow(String text, String source, int window) {
  if (source.length < window) {
    return text.contains(source);
  }
  for (var i = 0; i + window <= source.length; i++) {
    if (text.contains(source.substring(i, i + window))) {
      return true;
    }
  }
  return false;
}
