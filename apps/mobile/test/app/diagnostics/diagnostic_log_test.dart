import 'package:cardflow/app/diagnostics/diagnostic_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('环形缓冲', () {
    test('默认最多保留 500 条，满了丢弃最早的', () {
      final log = DiagnosticLog();
      addTearDown(log.dispose);
      expect(log.capacity, 500);

      for (var i = 0; i < 620; i++) {
        log.info('test', i.isEven ? 'even' : 'odd');
      }

      expect(log.length, 500);
      expect(log.droppedCount, 120);
      expect(log.entries.first.event, 'even');
      expect(log.entries, hasLength(500));
    });

    test('条目按时间从早到晚，时间为 UTC', () {
      var tick = 0;
      final log = DiagnosticLog(
        capacity: 3,
        clock: () => DateTime.utc(2026, 10, 18, 8, 0, tick++),
      );
      addTearDown(log.dispose);

      log
        ..info('a', 'one')
        ..warning('a', 'two')
        ..error('a', 'three')
        ..info('a', 'four');

      expect(log.entries.map((e) => e.event), <String>['two', 'three', 'four']);
      expect(log.entries.map((e) => e.level), <LogLevel>[
        LogLevel.warning,
        LogLevel.error,
        LogLevel.info,
      ]);
      expect(log.entries.every((e) => e.time.isUtc), isTrue);
      expect(log.droppedCount, 1);
    });

    test('返回的列表不可修改', () {
      final log = DiagnosticLog();
      addTearDown(log.dispose);
      log.info('a', 'b');
      expect(() => log.entries.clear(), throwsUnsupportedError);
    });
  });

  group('不记录金额与正文', () {
    test('detail 中的所有数字（含全角）替换为 #', () {
      final log = DiagnosticLog();
      addTearDown(log.dispose);

      log.info(
        'import',
        'parsed',
        detail: '金额 8000.00 卡号 6222020200112233445 １２３',
      );

      final detail = log.entries.single.detail!;
      expect(RegExp(r'[0-9０-９]').hasMatch(detail), isFalse);
      expect(detail, '金额 ####.## 卡号 ################### ###');
    });

    test('detail 只保留首行，去掉控制字符并截断', () {
      expect(sanitizeDetail('第一行\n第二行含正文'), '第一行');
      expect(sanitizeDetail('a\tb'), 'a b');
      final long = sanitizeDetail('长' * 300);
      expect(long.runes.length, DiagnosticLog.maxDetailLength + 1);
      expect(long, endsWith('…'));
    });

    test('标识符只允许小写字母、下划线与点（debug 断言，release 兜底替换）', () {
      final log = DiagnosticLog();
      addTearDown(log.dispose);
      expect(
        () => log.info('Route', 'changed'),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => log.info('pay', 'amount_8000'),
        throwsA(isA<AssertionError>()),
      );
      expect(sanitizeIdentifier('amount_8000'), 'amount_____');
      expect(sanitizeIdentifier('Route/Changed'), 'route_changed');
      expect(sanitizeIdentifier(''), 'unknown');
    });

    test('错误只记异常类型与代码位置，不记异常正文', () {
      final log = DiagnosticLog();
      addTearDown(log.dispose);
      StackTrace? stack;
      try {
        throw const FormatException('无法解析：招商银行 张三 金额 1234.56');
      } on FormatException catch (_, s) {
        stack = s;
      }

      log.recordError('platform', const FormatException('正文 1234.56'), stack);

      final entry = log.entries.single;
      expect(entry.level, LogLevel.error);
      expect(entry.event, 'uncaught');
      expect(entry.detail, 'FormatException');
      expect(entry.frames, isNotEmpty);
      expect(
        entry.frames.every(
          (f) => f.startsWith('package:') || f.startsWith('dart:'),
        ),
        isTrue,
      );
      expect(entry.toReportText(), isNot(contains('1234')));
      expect(entry.toReportText(), isNot(contains('张三')));
    });

    test('frames 只接受代码位置，其他文字被丢弃', () {
      final log = DiagnosticLog();
      addTearDown(log.dispose);
      log.record(
        LogLevel.error,
        'test',
        'frames',
        frames: <String>[
          'package:cardflow/a.dart:12:3',
          '卡号 6222020200112233445',
          'dart:async/zone.dart:1525',
        ],
      );
      expect(log.entries.single.frames, <String>[
        'package:cardflow/a.dart:12:3',
        'dart:async/zone.dart:1525',
      ]);
    });

    test('codeLocations 只提取 package:/dart: 位置，最多 6 个', () {
      final stack = StackTrace.fromString(
        List<String>.generate(
          10,
          (i) => '#$i      secret_$i (package:cardflow/a.dart:${i + 1}:3)',
        ).join('\n'),
      );
      final frames = codeLocations(stack);
      expect(frames, hasLength(DiagnosticLog.maxFrames));
      expect(frames.first, 'package:cardflow/a.dart:1:3');
      expect(frames.join(), isNot(contains('secret')));
      expect(codeLocations(null), isEmpty);
    });
  });

  test('通知延迟到微任务里合并发出（构建期间写日志也安全）', () async {
    final log = DiagnosticLog();
    addTearDown(log.dispose);
    var notifications = 0;
    log.addListener(() => notifications++);

    log
      ..info('a', 'one')
      ..info('a', 'two');
    expect(notifications, 0);

    await Future<void>.delayed(Duration.zero);
    expect(notifications, 1);
  });

  test('释放后不再通知', () async {
    final log = DiagnosticLog();
    var notifications = 0;
    log
      ..addListener(() => notifications++)
      ..info('a', 'one')
      ..dispose();
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 0);
  });
}
