// Probe: would the tests' containsKeyMaterial() notice a key that reached the diagnostic log?
import 'package:cardflow/data/db/database_key.dart';
import 'package:cardflow/features/diagnostics/diagnostic_log.dart';
import 'package:flutter_test/flutter_test.dart';

// Same three conditions as test/data/db/db_test_support.dart containsKeyMaterial().
bool containsKeyMaterial(String text, String keyHex) =>
    text.contains(keyHex) ||
    text.contains(keyHex.toUpperCase()) ||
    text.contains(keyHex.substring(0, 16));

void main() {
  test('masked key in a log detail', () {
    const testKeyHex = '00112233445566778899aabbccddeeff102132435465768798a9bacbdcedfe0f';
    final key = DatabaseKey.decode(testKeyHex);
    final log = DiagnosticLog();
    addTearDown(log.dispose);
    // a hypothetical bug: some code puts the raw key literal into a log detail
    log.error('db', 'open_failed', detail: 'PRAGMA key = "${key.rawKeyLiteral()}"');
    final line = log.entries.single.toReportText();
    final leakedLetters = RegExp('[a-f]').allMatches(line.split('detail').last).length;
    // ignore: avoid_print
    print('report line: ${line.substring(line.indexOf(' E '))}');
    // ignore: avoid_print
    print('containsKeyMaterial(line) = ${containsKeyMaterial(line, testKeyHex)}');
    final bytes = 'Uint8List ${[for (var i = 0; i < 32; i++) int.parse(testKeyHex.substring(2 * i, 2 * i + 2), radix: 16)]}';
    // ignore: avoid_print
    print('byte-list form detected = ${containsKeyMaterial(bytes, testKeyHex)}');
    expect(leakedLetters, greaterThan(0));
  });
}
