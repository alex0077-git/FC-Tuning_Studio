import 'dart:typed_data';

import 'mavlink_crc.dart';

const int mavStxV2 = 0xFD;
const int mavSysFc = 1;
const int mavCompFc = 1;

const int msgHeartbeat = 0;
const int msgParamRequestRead = 20;
const int msgParamRequestList = 21;
const int msgParamValue = 22;
const int msgParamSet = 23;
const int msgAttitude = 30;
const int msgStatustext = 253;

const int crcHeartbeat = 50;
const int crcParamRequestRead = 214;
const int crcParamRequestList = 159;
const int crcParamValue = 220;
const int crcParamSet = 168;
const int crcAttitude = 39;
const int crcStatustext = 83;

const int mavModeFlagArmed = 128;
const int mavParamTypeReal32 = 9;
const int mavSeverityInfo = 6;

int crcExtraFor(int msgid) => switch (msgid) {
      msgHeartbeat => crcHeartbeat,
      msgParamRequestRead => crcParamRequestRead,
      msgParamRequestList => crcParamRequestList,
      msgParamValue => crcParamValue,
      msgParamSet => crcParamSet,
      msgAttitude => crcAttitude,
      msgStatustext => crcStatustext,
      _ => 0,
    };

class MavMessage {
  MavMessage({
    required this.msgid,
    required this.payload,
    required this.sysid,
    required this.compid,
    required this.seq,
  });

  final int msgid;
  final Uint8List payload;
  final int sysid;
  final int compid;
  final int seq;
}

class Heartbeat {
  Heartbeat({
    required this.customMode,
    required this.type,
    required this.autopilot,
    required this.baseMode,
    required this.systemStatus,
    required this.mavlinkVersion,
  });
  final int customMode;
  final int type;
  final int autopilot;
  final int baseMode;
  final int systemStatus;
  final int mavlinkVersion;
  bool get armed => (baseMode & mavModeFlagArmed) != 0;
}

class Attitude {
  Attitude({
    required this.timeBootMs,
    required this.roll,
    required this.pitch,
    required this.yaw,
    required this.rollspeed,
    required this.pitchspeed,
    required this.yawspeed,
  });
  final int timeBootMs;
  final double roll; // rad
  final double pitch;
  final double yaw;
  final double rollspeed;
  final double pitchspeed;
  final double yawspeed;

  double get rollDeg => roll * 180 / 3.141592653589793;
  double get pitchDeg => pitch * 180 / 3.141592653589793;
  double get yawDeg => yaw * 180 / 3.141592653589793;
}

class ParamValue {
  ParamValue({
    required this.paramId,
    required this.value,
    required this.type,
    required this.count,
    required this.index,
  });
  final String paramId;
  final double value;
  final int type;
  final int count;
  final int index;
}

bool looksLikeParamValue(ParamValue pv) {
  if (pv.paramId.isEmpty || pv.paramId.length > 16) return false;
  if (pv.count < 1 || pv.count > 64) return false;
  if (pv.index < 0 || pv.index >= pv.count) return false;
  if (pv.type != 0 && pv.type != mavParamTypeReal32) return false;
  // IDs are ASCII gain names from the Phase B catalog.
  return RegExp(r'^[A-Z0-9_]+$').hasMatch(pv.paramId);
}

Uint8List _padPayload(Uint8List p, int minLen) {
  if (p.length >= minLen) return p;
  final out = Uint8List(minLen);
  out.setRange(0, p.length, p);
  return out;
}

ParamValue? _decodeParamValueFirmware(Uint8List p) {
  // mavlink_min.c pack: id[16], float, type, count, index
  final id = _chars(p, 0, 16);
  final value = _f32(p, 16);
  final type = p[20];
  final count = _u16(p, 21);
  final index = _u16(p, 23);
  return ParamValue(
    paramId: id,
    value: value,
    type: type,
    count: count,
    index: index,
  );
}

ParamValue? _decodeParamValueStandard(Uint8List p) {
  // common.xml / QGC: float, count, index, id[16], type
  final value = _f32(p, 0);
  final count = _u16(p, 4);
  final index = _u16(p, 6);
  final id = _chars(p, 8, 16);
  final type = p[24];
  return ParamValue(
    paramId: id,
    value: value,
    type: type,
    count: count,
    index: index,
  );
}

/// Prefer a layout that yields a sane Phase B param; try firmware then standard.
ParamValue? decodeParamValue(Uint8List raw) {
  if (raw.length < 20) return null;
  final p = _padPayload(raw, 25);

  final fw = _decodeParamValueFirmware(p);
  if (fw != null && looksLikeParamValue(fw)) return fw;

  final std = _decodeParamValueStandard(p);
  if (std != null && looksLikeParamValue(std)) return std;

  // Last resort: firmware layout even if id looks odd (still need count).
  if (fw != null && fw.count >= 1 && fw.count <= 64) return fw;
  if (std != null && std.count >= 1 && std.count <= 64) return std;
  return null;
}

Heartbeat? decodeHeartbeat(Uint8List p) {
  if (p.length < 9) return null;
  return Heartbeat(
    customMode: _u32(p, 0),
    type: p[4],
    autopilot: p[5],
    baseMode: p[6],
    systemStatus: p[7],
    mavlinkVersion: p[8],
  );
}

Attitude? decodeAttitude(Uint8List p) {
  if (p.length < 28) return null;
  return Attitude(
    timeBootMs: _u32(p, 0),
    roll: _f32(p, 4),
    pitch: _f32(p, 8),
    yaw: _f32(p, 12),
    rollspeed: _f32(p, 16),
    pitchspeed: _f32(p, 20),
    yawspeed: _f32(p, 24),
  );
}

class StatusText {
  StatusText({required this.severity, required this.text});
  final int severity;
  final String text;
}

/// MAVLink STATUSTEXT (253): severity + char[50] (extensions ignored).
StatusText? decodeStatusText(Uint8List p) {
  if (p.length < 51) return null;
  final severity = p[0];
  final chars = <int>[];
  for (var i = 1; i < 51; i++) {
    final c = p[i];
    if (c == 0) break;
    chars.add(c);
  }
  return StatusText(
    severity: severity,
    text: String.fromCharCodes(chars),
  );
}

class MavlinkV2Parser {
  int _state = 0;
  int _len = 0;
  int _seq = 0;
  int _sys = 0;
  int _comp = 0;
  final _msgid = <int>[0, 0, 0];
  final _payload = <int>[];
  int _crc = 0xFFFF;
  int _cka = 0;
  int crcFailures = 0;

  List<MavMessage> addBytes(List<int> bytes) {
    final out = <MavMessage>[];
    for (final c in bytes) {
      final m = _feed(c);
      if (m != null) out.add(m);
    }
    return out;
  }

  MavMessage? _feed(int c) {
    switch (_state) {
      case 0:
        if (c == mavStxV2) {
          _state = 1;
          _crc = 0xFFFF;
          _payload.clear();
        }
        return null;
      case 1:
        // MAVLink v2 max payload is 255; keep a sane cap for this dialect.
        if (c > 255) {
          _state = 0;
          return null;
        }
        _len = c;
        _crc = x25CrcAccumulate(c, _crc);
        _state = 2;
        return null;
      case 2: // incompat
        _crc = x25CrcAccumulate(c, _crc);
        _state = 3;
        return null;
      case 3: // compat
        _crc = x25CrcAccumulate(c, _crc);
        _state = 4;
        return null;
      case 4:
        _seq = c;
        _crc = x25CrcAccumulate(c, _crc);
        _state = 5;
        return null;
      case 5:
        _sys = c;
        _crc = x25CrcAccumulate(c, _crc);
        _state = 6;
        return null;
      case 6:
        _comp = c;
        _crc = x25CrcAccumulate(c, _crc);
        _state = 7;
        return null;
      case 7:
        _msgid[0] = c;
        _crc = x25CrcAccumulate(c, _crc);
        _state = 8;
        return null;
      case 8:
        _msgid[1] = c;
        _crc = x25CrcAccumulate(c, _crc);
        _state = 9;
        return null;
      case 9:
        _msgid[2] = c;
        _crc = x25CrcAccumulate(c, _crc);
        _state = _len == 0 ? 11 : 10;
        return null;
      case 10:
        _payload.add(c);
        _crc = x25CrcAccumulate(c, _crc);
        if (_payload.length >= _len) {
          _state = 11;
        }
        return null;
      case 11:
        _cka = c;
        _state = 12;
        return null;
      case 12:
        final msgid = _msgid[0] | (_msgid[1] << 8) | (_msgid[2] << 16);
        final expect = x25CrcAccumulate(crcExtraFor(msgid), _crc);
        _state = 0;
        if ((_cka != (expect & 0xFF)) || (c != ((expect >> 8) & 0xFF))) {
          crcFailures += 1;
          return null;
        }
        return MavMessage(
          msgid: msgid,
          payload: Uint8List.fromList(_payload),
          sysid: _sys,
          compid: _comp,
          seq: _seq,
        );
      default:
        _state = 0;
        return null;
    }
  }
}

class MavlinkV2Encoder {
  MavlinkV2Encoder({this.sysid = 255, this.compid = 190});
  final int sysid;
  final int compid;
  int _seq = 0;

  Uint8List _finalize(int msgid, List<int> payload) {
    final len = payload.length;
    final buf = Uint8List(10 + len + 2);
    buf[0] = mavStxV2;
    buf[1] = len;
    buf[2] = 0;
    buf[3] = 0;
    buf[4] = _seq;
    buf[5] = sysid;
    buf[6] = compid;
    buf[7] = msgid & 0xFF;
    buf[8] = (msgid >> 8) & 0xFF;
    buf[9] = (msgid >> 16) & 0xFF;
    buf.setRange(10, 10 + len, payload);
    _seq = (_seq + 1) & 0xFF;

    var crc = 0xFFFF;
    for (var i = 1; i < 10 + len; i++) {
      crc = x25CrcAccumulate(buf[i], crc);
    }
    crc = x25CrcAccumulate(crcExtraFor(msgid), crc);
    buf[10 + len] = crc & 0xFF;
    buf[11 + len] = (crc >> 8) & 0xFF;
    return buf;
  }

  /// GCS HEARTBEAT — wakes UDP bridges that only forward after seeing GCS traffic.
  Uint8List heartbeat({
    int type = 6, // MAV_TYPE_GCS
    int autopilot = 8, // MAV_AUTOPILOT_GENERIC
    int baseMode = 0,
    int customMode = 0,
    int systemStatus = 4, // MAV_STATE_ACTIVE
  }) {
    final p = List<int>.filled(9, 0);
    p[0] = customMode & 0xFF;
    p[1] = (customMode >> 8) & 0xFF;
    p[2] = (customMode >> 16) & 0xFF;
    p[3] = (customMode >> 24) & 0xFF;
    p[4] = type;
    p[5] = autopilot;
    p[6] = baseMode;
    p[7] = systemStatus;
    p[8] = 3; // mavlink_version field
    return _finalize(msgHeartbeat, p);
  }

  /// Firmware layout: target_system, target_component
  Uint8List paramRequestList({int targetSys = 1, int targetComp = 1}) =>
      _finalize(msgParamRequestList, [targetSys, targetComp]);

  /// Firmware layout: sys, comp, param_id[16], int16 index
  Uint8List paramRequestRead({
    int targetSys = 1,
    int targetComp = 1,
    String paramId = '',
    int paramIndex = -1,
  }) {
    final p = List<int>.filled(20, 0);
    p[0] = targetSys;
    p[1] = targetComp;
    final id = paramId.codeUnits;
    for (var i = 0; i < 16 && i < id.length; i++) {
      p[2 + i] = id[i];
    }
    final idx = paramIndex & 0xFFFF;
    p[18] = idx & 0xFF;
    p[19] = (idx >> 8) & 0xFF;
    return _finalize(msgParamRequestRead, p);
  }

  /// Firmware Phase B layout: sys, comp, param_id[16], float, type
  Uint8List paramSet({
    required String paramId,
    required double value,
    int targetSys = 1,
    int targetComp = 1,
    int type = mavParamTypeReal32,
  }) {
    final p = List<int>.filled(23, 0);
    p[0] = targetSys;
    p[1] = targetComp;
    final id = paramId.codeUnits;
    for (var i = 0; i < 16 && i < id.length; i++) {
      p[2 + i] = id[i];
    }
    final bd = ByteData(4)..setFloat32(0, value, Endian.little);
    p[18] = bd.getUint8(0);
    p[19] = bd.getUint8(1);
    p[20] = bd.getUint8(2);
    p[21] = bd.getUint8(3);
    p[22] = type;
    return _finalize(msgParamSet, p);
  }

  /// common.xml / QGC layout: float, sys, comp, param_id[16], type
  Uint8List paramSetStandard({
    required String paramId,
    required double value,
    int targetSys = 1,
    int targetComp = 1,
    int type = mavParamTypeReal32,
  }) {
    final p = List<int>.filled(23, 0);
    final bd = ByteData(4)..setFloat32(0, value, Endian.little);
    p[0] = bd.getUint8(0);
    p[1] = bd.getUint8(1);
    p[2] = bd.getUint8(2);
    p[3] = bd.getUint8(3);
    p[4] = targetSys;
    p[5] = targetComp;
    final id = paramId.codeUnits;
    for (var i = 0; i < 16 && i < id.length; i++) {
      p[6 + i] = id[i];
    }
    p[22] = type;
    return _finalize(msgParamSet, p);
  }

  /// STATUSTEXT (253): severity + char[50]. Used for SD `log …` commands.
  Uint8List statusText(
    String text, {
    int severity = mavSeverityInfo,
  }) {
    final p = List<int>.filled(51, 0);
    p[0] = severity & 0xFF;
    final units = text.codeUnits;
    final n = units.length > 50 ? 50 : units.length;
    for (var i = 0; i < n; i++) {
      p[1 + i] = units[i];
    }
    return _finalize(msgStatustext, p);
  }
}

int _u16(Uint8List p, int o) => p[o] | (p[o + 1] << 8);
int _u32(Uint8List p, int o) =>
    p[o] | (p[o + 1] << 8) | (p[o + 2] << 16) | (p[o + 3] << 24);
double _f32(Uint8List p, int o) =>
    ByteData.sublistView(p, o, o + 4).getFloat32(0, Endian.little);

String _chars(Uint8List p, int o, int n) {
  final end = o + n;
  final zero = p.indexOf(0, o);
  final slice = p.sublist(o, (zero >= o && zero < end) ? zero : end);
  return String.fromCharCodes(slice);
}
