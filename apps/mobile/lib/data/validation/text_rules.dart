/// 通用字段校验（ui-spec §4.4 的 G2、G5，R-CARD-02）。仓库在写库前调用，界面在输入时调用同一套，
/// 文案一致；数据库另有 CHECK 兜底（`tables.dart`）。
library;

/// G2 的提示文案。
const String fullCardNumberMessage = '卡序不保存完整卡号';

/// G5：名称的最大长度（字，按 Unicode 码点计，与协议 Text 一致）。
const int maxNameLength = 20;

/// G5：说明的最大长度。
const int maxNoteLength = 200;

/// 末四位格式不对时的文案。
const String last4Message = '末四位须为 4 位数字';

final RegExp _fullWidthDigit = RegExp('[０-９]');
final RegExp _thirteenDigits = RegExp('[0-9]{13,}');
final RegExp _digitGroups = RegExp('[0-9]+(?:[ -][0-9]+)+');

/// 把全角数字换成半角（粘贴自其他 App 的文字常见全角数字）。
String normalizeDigits(String text) => text.replaceAllMapped(
  _fullWidthDigit,
  (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0xFF10 + 0x30),
);

/// G2：文本看起来含完整卡号。
///
/// - 含 13 位及以上连续数字（半角或全角）——ui-spec §4.4 的字面规则；
/// - 或者数字之间只隔单个空格/短横、合起来 13–19 位且通过 Luhn 校验（"6222 0202 0011 2233"
///   这样分组写的卡号；与服务端 `looks_like_pan` 同一判据，data-model §10 第 9 条）。
bool looksLikeFullCardNumber(String text) {
  final normalized = normalizeDigits(text);
  if (_thirteenDigits.hasMatch(normalized)) {
    return true;
  }
  for (final match in _digitGroups.allMatches(normalized)) {
    final digits = match[0]!.replaceAll(RegExp('[ -]'), '');
    if (digits.length >= 13 && digits.length <= 19 && passesLuhn(digits)) {
      return true;
    }
  }
  return false;
}

/// Luhn 校验（[digits] 只含 0–9）。
bool passesLuhn(String digits) {
  var sum = 0;
  var doubleIt = false;
  for (var i = digits.length - 1; i >= 0; i--) {
    var d = digits.codeUnitAt(i) - 0x30;
    if (doubleIt) {
      d *= 2;
      if (d > 9) {
        d -= 9;
      }
    }
    sum += d;
    doubleIt = !doubleIt;
  }
  return sum % 10 == 0;
}

/// 文本长度（Unicode 码点数；一个 emoji 算一个）。
int textLength(String text) => text.runes.length;

/// 自由文本的校验：返回错误文案，合格返回 null。
///
/// [required] 为 true 时不能为空白；长度按 [maxLength]（G5）；任何位置含完整卡号拒绝（G2）。
String? validateFreeText(
  String? text, {
  int maxLength = maxNameLength,
  bool required = false,
  String fieldName = '',
}) {
  final value = text?.trim() ?? '';
  if (value.isEmpty) {
    return required ? '请填写$fieldName' : null;
  }
  if (looksLikeFullCardNumber(value)) {
    return fullCardNumberMessage;
  }
  if (textLength(value) > maxLength) {
    return '$fieldName不超过 $maxLength 字';
  }
  return null;
}

/// 末四位：去掉首尾空白、全角换半角后必须恰好 4 位数字。含完整卡号时给 G2 文案。
/// 合格返回 null。
String? validateLast4(String? text) {
  final value = normalizeDigits(text?.trim() ?? '');
  if (looksLikeFullCardNumber(value)) {
    return fullCardNumberMessage;
  }
  return RegExp(r'^[0-9]{4}$').hasMatch(value) ? null : last4Message;
}

/// 末四位的规范写法（全角换半角、去空白）；调用前应已通过 [validateLast4]。
String normalizeLast4(String text) => normalizeDigits(text.trim());
