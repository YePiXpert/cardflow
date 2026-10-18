// G2/G5 与末四位校验（lib/data/validation/text_rules.dart）。
import 'package:cardflow/data/validation/text_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('G2：完整卡号', () {
    test('13 位及以上连续数字拒绝，12 位可以', () {
      expect(looksLikeFullCardNumber('1234567890123'), isTrue);
      expect(looksLikeFullCardNumber('工资卡 6222020200112233445 用'), isTrue);
      expect(looksLikeFullCardNumber('123456789012'), isFalse);
      expect(looksLikeFullCardNumber('工资卡'), isFalse);
    });

    test('粘贴的全角数字同样拒绝', () {
      expect(looksLikeFullCardNumber('６２２２０２０２００１１２'), isTrue);
      expect(looksLikeFullCardNumber('卡号：６２２２０２０２００１１２２３３４４５'), isTrue);
    });

    test('分组写的卡号（空格或短横、13–19 位、Luhn 通过）拒绝；日期、电话不误判', () {
      expect(looksLikeFullCardNumber('4111 1111 1111 1111'), isTrue);
      expect(looksLikeFullCardNumber('4111-1111-1111-1111'), isTrue);
      expect(passesLuhn('4111111111111112'), isFalse);
      expect(looksLikeFullCardNumber('4111 1111 1111 1112'), isFalse);
      expect(looksLikeFullCardNumber('2026-10-18'), isFalse);
      expect(looksLikeFullCardNumber('138-0013-8000'), isFalse);
    });

    test('validateFreeText：G2 优先于长度；空白按必填处理；长度按码点计', () {
      expect(validateFreeText('6222020200112233445'), fullCardNumberMessage);
      expect(
        validateFreeText('  ', required: true, fieldName: '产品名'),
        '请填写产品名',
      );
      expect(validateFreeText(null), isNull);
      expect(validateFreeText('长' * 20), isNull);
      expect(validateFreeText('长' * 21, fieldName: '别名'), '别名不超过 20 字');
      expect(validateFreeText('😀' * 20), isNull);
      expect(validateFreeText('说' * 200, maxLength: maxNoteLength), isNull);
    });
  });

  group('末四位', () {
    test('恰好 4 位数字（全角会被换成半角）', () {
      expect(validateLast4('1234'), isNull);
      expect(validateLast4(' 0007 '), isNull);
      expect(validateLast4('１２３４'), isNull);
      expect(normalizeLast4('１２３４'), '1234');
      for (final bad in <String>['', '123', '12345', '12a4', '12 34']) {
        expect(validateLast4(bad), last4Message, reason: bad);
      }
    });

    test('粘贴完整卡号进末四位：给 G2 文案，而不是截成前 4 位', () {
      expect(validateLast4('6222020200112233445'), fullCardNumberMessage);
      expect(validateLast4('4111 1111 1111 1111'), fullCardNumberMessage);
    });
  });
}
