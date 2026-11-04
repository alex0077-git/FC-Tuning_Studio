import 'dart:typed_data';

import 'package:fc_tuning_studio/logs/sd_tunnel_assembler.dart';
import 'package:fc_tuning_studio/mavlink/mavlink_v2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SD #/\$ reassembly into lines until LOG END', () {
    final a = SdTunnelAssembler();
    expect(
      a.pushChunk('#LOG LIST\r\nid,file,tag,rows,drops,dur_s\r\n'),
      ['LOG LIST', 'id,file,tag,rows,drops,dur_s'],
    );
    expect(a.pushChunk('#1,LOG0001.CSV,-,133,0,62\r\n'), [
      '1,LOG0001.CSV,-,133,0,62',
    ]);
    expect(a.pushChunk('\$LOG END\r\n'), ['LOG END']);
  });

  test('ignores live-log markers', () {
    final a = SdTunnelAssembler();
    expect(a.pushChunk('+[DMA] hello'), isEmpty);
    expect(a.pushChunk('=world'), isEmpty);
  });

  test('STATUSTEXT encode/decode for log list command', () {
    final enc = MavlinkV2Encoder();
    final frame = enc.statusText('log list');
    final parser = MavlinkV2Parser();
    final msgs = parser.addBytes(frame);
    expect(msgs.length, 1);
    expect(msgs.first.msgid, msgStatustext);
    final st = decodeStatusText(msgs.first.payload);
    expect(st, isNotNull);
    expect(st!.text, 'log list');
    expect(st.severity, mavSeverityInfo);
  });

  test('payload length is 51', () {
    final enc = MavlinkV2Encoder();
    final frame = enc.statusText('log dump 3');
    // STX + header(9) + payload(51) + crc(2) = 63
    expect(frame.length, 10 + 51 + 2);
    expect(frame[1], 51);
  });

  test('decode padded payload', () {
    final p = Uint8List(51);
    p[0] = mavSeverityInfo;
    const t = 'log wipe';
    for (var i = 0; i < t.length; i++) {
      p[1 + i] = t.codeUnitAt(i);
    }
    expect(decodeStatusText(p)!.text, 'log wipe');
  });
}
