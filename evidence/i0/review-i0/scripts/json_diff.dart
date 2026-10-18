// Reads lines of base64 JSON byte strings; prints, per line, OK <base64 canonical> or ERR <message>.
import 'dart:convert';
import 'dart:io';

import 'package:cardflow_domain/cardflow_domain.dart';

void main(List<String> args) {
  final lines = File(args[0]).readAsLinesSync();
  final out = StringBuffer();
  for (final line in lines) {
    final bytes = base64.decode(line);
    try {
      final value = parseJson(bytes);
      final canon = canonicalJson(value);
      out.writeln('OK ${base64.encode(canon)}');
    } on ProtocolError catch (e) {
      out.writeln('ERR ${e.message}');
    } catch (e) {
      out.writeln('CRASH ${e.runtimeType}');
    }
  }
  File(args[1]).writeAsStringSync(out.toString());
}
