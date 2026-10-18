// Reads a file of base64 JSON documents (one per line); prints, per line, the adapter's verdict:
// OK <hash> | ERR <path> | <message> | PARSE <message> | CRASH <type>.
import 'dart:convert';
import 'dart:io';

import 'package:cardflow_domain/cardflow_domain.dart';

void main(List<String> args) {
  final out = StringBuffer();
  for (final line in File(args[0]).readAsLinesSync()) {
    final Object? doc;
    try {
      doc = parseJson(base64.decode(line));
    } on ProtocolError catch (e) {
      out.writeln('PARSE ${e.message}');
      continue;
    }
    try {
      inputsFromProtocol(doc);
      out.writeln('OK ${protocolInputHash(doc)}');
    } on ProtocolError catch (e) {
      out.writeln('ERR ${e.path} | ${e.message}');
    } catch (e) {
      out.writeln('CRASH ${e.runtimeType}');
    }
  }
  File(args[1]).writeAsStringSync(out.toString());
}
