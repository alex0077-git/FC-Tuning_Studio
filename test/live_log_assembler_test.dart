import 'dart:typed_data';

import 'package:fc_tuning_studio/logs/live_log_assembler.dart';
import 'package:fc_tuning_studio/mavlink/mavlink_v2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('STATUSTEXT +/= reassembly', () {
    final a = LiveLogAssembler();
    expect(a.pushChunk('+[DMA] s1 DIS G 0 0 0 dps | R 1 P 2 Y 3 | BP '), isNull);
    expect(a.pushChunk('+100785 Pa T 29.5 C | Z 0.4 raw 0.5 | AH en=1 '), isNull);
    final line = a.pushChunk(
      '=act=1 tgt 0.4 err 0 dU 0 i 0 | M 1000 1000 1000 1000 us | GPS 0 sats=0',
    );
    expect(line, isNotNull);
    expect(line!.contains('[DMA]'), isTrue);
    expect(line.contains('BP 100785'), isTrue);
    expect(line.contains('GPS 0 sats=0'), isTrue);
    expect(line.contains('+'), isFalse);
    expect(line.startsWith('='), isFalse);
  });

  test('ignore non chunked STATUSTEXT', () {
    final a = LiveLogAssembler();
    expect(a.pushChunk('hello'), isNull);
  });

  test('decode STATUSTEXT payload + CRC extra registered', () {
    expect(crcExtraFor(msgStatustext), 83);
    final p = Uint8List(51);
    p[0] = mavSeverityInfo;
    const text = '+hello chunk';
    for (var i = 0; i < text.length; i++) {
      p[1 + i] = text.codeUnitAt(i);
    }
    final st = decodeStatusText(p);
    expect(st, isNotNull);
    expect(st!.text, text);
  });

  test('parse live log fields', () {
    const line =
        '[DMA] s13364 DIS G -0.00 -0.00 -0.00 dps | R -0.60 P 7.70 Y 0.01 | '
        'BP 100785 Pa T 29.53 C | Z 0.48 raw 0.50 | AH en=1 act=1 tgt 0.45 '
        'err -0.03 dU -3.00 i 0.00 | M 1000 1000 1000 1000 us | GPS 0 sats=0';
    final f = LiveLogFields.parse(line);
    expect(f.mode, 'DMA');
    expect(f.seq, 13364);
    expect(f.armed, isFalse);
    expect(f.bpPa, 100785);
    expect(f.tempC, 29.53);
    expect(f.zM, 0.48);
    expect(f.ahEn, 1);
    expect(f.m1, 1000);
    expect(f.sats, 0);
  });
}
