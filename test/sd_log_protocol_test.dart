import 'package:fc_tuning_studio/logs/sd_log_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parse LOG LIST', () {
    final r = parseLogList(const [
      'LOG LIST',
      'id,file,tag,rows,drops,dur_s',
      '1,LOG0001.CSV,-,133,0,62',
      '2,LOG0002.CSV,bench,802,0,203',
    ]);
    expect(r.outcome, SdLogOutcome.ok);
    expect(r.entries.length, 2);
    expect(r.entries[1].tag, 'bench');
    expect(r.entries[1].durS, 203);
  });

  test('parse empty list', () {
    final r = parseLogList(const ['LOG LIST', 'no logs']);
    expect(r.outcome, SdLogOutcome.empty);
  });

  test('parse dump CSV', () {
    final r = parseLogDump([
      kSdCsvHeader,
      '12345,100,1,-0.53,7.15,0.01,0,0,0,100785,0.4,0.5,1,1,0.4,0,0,0,1200,1500,1500,1000,1500,1000,1500,0,0,0,0,0,0,0,0,1000,1000,1000,1000',
    ]);
    expect(r.outcome, SdLogOutcome.ok);
    expect(r.csvBody!.startsWith('t_ms,seq,armed'), isTrue);
    expect(r.csvBody!.contains('12345,100,1'), isTrue);
  });

  test('parse dump abort', () {
    final r = parseLogDump(const ['t_ms,seq', '1,2', 'LOG ABORT']);
    expect(r.outcome, SdLogOutcome.abort);
  });

  test('collector ends on LOG END', () {
    final c = SdLogLineCollector();
    expect(c.addLine('LOG LIST'), isFalse);
    expect(c.addLine('no logs'), isFalse);
    expect(c.addLine('LOG END'), isTrue);
    expect(c.finished, isTrue);
  });
}
