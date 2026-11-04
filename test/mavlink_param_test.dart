import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fc_tuning_studio/mavlink/mavlink_v2.dart';

void main() {
  test('PARAM_REQUEST_LIST roundtrips through parser', () {
    final enc = MavlinkV2Encoder();
    final frame = enc.paramRequestList();
    final parsed = MavlinkV2Parser().addBytes(frame);
    expect(parsed, hasLength(1));
    expect(parsed.first.msgid, msgParamRequestList);
    expect(parsed.first.payload, [1, 1]);
  });

  test('PARAM_REQUEST_READ index 0 roundtrips', () {
    final enc = MavlinkV2Encoder();
    final frame = enc.paramRequestRead(paramIndex: 0);
    final parsed = MavlinkV2Parser().addBytes(frame);
    expect(parsed, hasLength(1));
    expect(parsed.first.msgid, msgParamRequestRead);
    expect(parsed.first.payload.length, 20);
    expect(parsed.first.payload[0], 1);
    expect(parsed.first.payload[1], 1);
    expect(parsed.first.payload[18], 0);
    expect(parsed.first.payload[19], 0);
  });

  test('decode firmware PARAM_VALUE layout', () {
    final p = Uint8List(25);
    final id = 'ROLL_AP'.codeUnits;
    for (var i = 0; i < id.length; i++) {
      p[i] = id[i];
    }
    ByteData.sublistView(p, 16, 20).setFloat32(0, 6.0, Endian.little);
    p[20] = 9;
    p[21] = 15;
    p[22] = 0;
    p[23] = 0;
    p[24] = 0;
    final pv = decodeParamValue(p)!;
    expect(pv.paramId, 'ROLL_AP');
    expect(pv.value, closeTo(6.0, 1e-6));
    expect(pv.count, 15);
    expect(pv.index, 0);
    expect(pv.type, 9);
  });

  test('decode standard MAVLink PARAM_VALUE layout', () {
    final p = Uint8List(25);
    ByteData.sublistView(p, 0, 4).setFloat32(0, 6.0, Endian.little);
    p[4] = 15;
    p[5] = 0;
    p[6] = 0;
    p[7] = 0;
    final id = 'ROLL_AP'.codeUnits;
    for (var i = 0; i < id.length; i++) {
      p[8 + i] = id[i];
    }
    p[24] = 9;
    final pv = decodeParamValue(p)!;
    expect(pv.paramId, 'ROLL_AP');
    expect(pv.value, closeTo(6.0, 1e-6));
    expect(pv.count, 15);
    expect(pv.index, 0);
  });
}
