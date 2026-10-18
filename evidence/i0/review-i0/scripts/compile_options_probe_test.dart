// Probe: compile options of the sqlite3mc library loaded by the build hook (TEMP_STORE etc.).
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('compile options', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final options = [for (final row in db.select('PRAGMA compile_options')) row.values.first.toString()];
    final interesting = options.where((o) => o.startsWith('TEMP_STORE') || o.contains('OMIT_FOREIGN') || o.startsWith('DEFAULT_JOURNAL') || o.contains('WAL')).toList();
    // ignore: avoid_print
    print('library: ${db.select('SELECT sqlite3mc_version()').first.values.first}; '
        'temp_store pragma: ${db.select('PRAGMA temp_store').first.values.first}; '
        'selected compile options: $interesting');
  });
}
