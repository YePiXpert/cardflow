// UUID v4（lib/data/ids.dart）。
import 'dart:math';

import 'package:cardflow/data/ids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('格式：小写 8-4-4-4-12，第 13 位是 4，第 17 位是 8/9/a/b', () {
    for (var i = 0; i < 200; i++) {
      final id = newUuidV4();
      expect(isUuidV4(id), isTrue, reason: id);
      expect(id[14], '4');
      expect('89ab', contains(id[19]));
    }
  });

  test('默认用安全随机数，不重复；注入随机源时可复现', () {
    final ids = <String>{for (var i = 0; i < 1000; i++) newUuidV4()};
    expect(ids, hasLength(1000));
    expect(newUuidV4(Random(1)), newUuidV4(Random(1)));
    expect(newUuidV4(Random(1)), isNot(newUuidV4(Random(2))));
  });

  test('满足规则协议 v1 的 Id 格式', () {
    expect(
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$').hasMatch(newUuidV4()),
      isTrue,
    );
    expect(isUuidV4('00000000-0000-0000-0000-000000000000'), isFalse);
    expect(isUuidV4('A0000000-0000-4000-8000-000000000000'), isFalse);
  });
}
