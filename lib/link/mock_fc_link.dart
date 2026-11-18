import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../mavlink/mavlink_crc.dart';
import '../mavlink/mavlink_v2.dart';
import 'byte_link.dart';

/// Laptop mock FC. Emits/accepts the same MAVLink v2 frames as the real FC.
/// Does not open sockets — never touches [G20UdpLink] or UDP ports.
class MockFcLink implements ByteLink {
  MockFcLink();

  final _rx = StreamController<List<int>>.broadcast();
  final _parser = MavlinkV2Parser();
  final _fcTx = MavlinkV2Encoder(sysid: mavSysFc, compid: mavCompFc);

  Timer? _hb;
  Timer? _att;
  Timer? _live;
  bool _open = false;
  int _seq = 0;
  final _boot = DateTime.now();

  /// Mutable sim state (tweak from Simulation Connect UI).
  bool armed = false;
  bool altHoldActive = false;
  int voltageMv = 16200;
  int batteryRemaining = 74;
  int baseUs = 1400;

  /// Simulated altitude (meters) — drives AltHold page.
  double simHeightM = 0.05;
  double _altHoldTgtM = 2.0;
  /// Mock hover height when armed (free flight).
  static const double mockArmedHeightM = 1.5;

  late final List<_SimParam> _params = [
    _SimParam('ROLL_AP', 6.0),
    _SimParam('PITCH_AP', 8.0),
    _SimParam('YAW_AP', 0.0),
    _SimParam('ROLL_KP', 1.0),
    _SimParam('PITCH_KP', 1.2),
    _SimParam('YAW_KP', 0.5),
    _SimParam('ROLL_KI', 0.0),
    _SimParam('PITCH_KI', 0.0),
    _SimParam('YAW_KI', 0.0),
    _SimParam('ROLL_KD', 0.04),
    _SimParam('PITCH_KD', 0.04),
    _SimParam('YAW_KD', 0.02),
    _SimParam('ALT_KP', 100.0),
    _SimParam('ALT_KI', 10.0),
    _SimParam('ALT_CORR_MAX', 200.0),
  ];

  @override
  Stream<List<int>> get bytes => _rx.stream;

  @override
  Future<void> open() async {
    await close();
    _open = true;
    _emit(_packHeartbeat());
    _emit(_packSysStatus());
    _hb = Timer.periodic(const Duration(seconds: 1), (_) {
      _emit(_packHeartbeat());
      _emit(_packSysStatus());
    });
    _att = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _emit(_packAttitude());
    });
    _live = Timer.periodic(const Duration(seconds: 1), (_) {
      _emitLiveLog();
    });
  }

  @override
  void write(List<int> data) {
    if (!_open) return;
    for (final m in _parser.addBytes(Uint8List.fromList(data))) {
      _onGcs(m);
    }
  }

  @override
  Future<void> close() async {
    _open = false;
    _hb?.cancel();
    _att?.cancel();
    _live?.cancel();
    _hb = null;
    _att = null;
    _live = null;
  }

  void _emit(Uint8List frame) {
    if (!_open || _rx.isClosed) return;
    _rx.add(frame);
  }

  void _onGcs(MavMessage m) {
    if (m.msgid == msgParamRequestList) {
      for (var i = 0; i < _params.length; i++) {
        _emit(_packParamValue(i));
      }
      return;
    }
    if (m.msgid == msgParamRequestRead) {
      final idx = _readParamIndex(m.payload);
      final id = _readParamId(m.payload, idAt: 2);
      final i = idx >= 0 ? idx : _indexOfId(id);
      if (i != null) _emit(_packParamValue(i));
      return;
    }
    if (m.msgid == msgParamSet) {
      if (armed) return; // refuse while armed — no echo
      final parsed = _parseParamSet(m.payload);
      if (parsed == null) return;
      final i = _indexOfId(parsed.$1);
      if (i == null) return;
      _params[i] = _SimParam(parsed.$1, parsed.$2);
      _emit(_packParamValue(i));
      return;
    }
    if (m.msgid == msgStatustext) {
      final st = decodeStatusText(m.payload);
      if (st == null) return;
      _handleText(st.text.trim());
    }
  }

  void _handleText(String t) {
    if (t.isEmpty) return;
    final c0 = t.codeUnitAt(0);
    // Log markers are not commands (same as FW brief).
    if (c0 == 0x2B /* + */ ||
        c0 == 0x3D /* = */ ||
        c0 == 0x23 /* # */ ||
        c0 == 0x24 /* $ */ ||
        c0 == 0x2A /* * */) {
      return;
    }
    final lower = t.toLowerCase();
    if (lower == 'reset' || lower == 'reboot') {
      if (armed) {
        _emitStar('*reset deny armed');
      } else {
        _emitStar('*reset');
        armed = false;
        altHoldActive = false;
      }
      return;
    }
    if (lower.startsWith('base ')) {
      if (altHoldActive) {
        _emitStar('*base deny althold');
        return;
      }
      final n = int.tryParse(lower.substring(5).trim());
      if (n == null) {
        _emitStar('*base deny');
        return;
      }
      baseUs = n.clamp(1000, 2000);
      _emitStar('*base $baseUs');
      return;
    }
    if (lower.startsWith('motor')) {
      if (armed) {
        _emitStar('*motor deny armed');
        return;
      }
      _emitStar('*motor ok');
      return;
    }
    if (lower.startsWith('log ')) {
      _emit(_fcTx.statusText('#SIM log stub'));
      _emit(_fcTx.statusText('\$LOG END'));
    }
  }

  void _emitStar(String text) => _emit(_fcTx.statusText(text));

  void _stepSimAltitude() {
    final t = DateTime.now().difference(_boot).inMilliseconds / 1000.0;
    if (!armed) {
      simHeightM += (0.05 - simHeightM) * 0.35;
      if (simHeightM < 0.08) simHeightM = 0.05;
      altHoldActive = false;
      return;
    }
    if (altHoldActive) {
      // Visible bob so Current moves while Target/ring stay fixed.
      final bob = 0.18 * math.sin(t * 1.4);
      final want = _altHoldTgtM + bob;
      simHeightM += (want - simHeightM) * 0.45;
      return;
    }
    // Armed free flight: go to mock height with a little bob.
    final want = mockArmedHeightM + 0.12 * math.sin(t * 0.8);
    simHeightM += (want - simHeightM) * 0.4;
  }

  void _emitLiveLog() {
    _stepSimAltitude();
    final arm = armed ? 'ARM' : 'DIS';
    final act = altHoldActive ? 1 : 0;
    final tgt = altHoldActive ? _altHoldTgtM : simHeightM;
    final z = simHeightM;
    final err = z - tgt;
    // STATUSTEXT is only 50 chars — long VCP lines were truncated and lost Z.
    // Chunk with + / = so LiveLogAssembler still gets Z + AH.
    final p1 =
        '+$arm Z ${z.toStringAsFixed(2)} raw ${z.toStringAsFixed(2)} ';
    final p2 =
        '=AH en=$act act=$act tgt ${tgt.toStringAsFixed(2)} err ${err.toStringAsFixed(2)}';
    _emit(_fcTx.statusText(p1.length > 50 ? p1.substring(0, 50) : p1));
    _emit(_fcTx.statusText(p2.length > 50 ? p2.substring(0, 50) : p2));
  }

  /// Call when Arm is toggled from Sim UI.
  void setArmed(bool on) {
    armed = on;
    if (on) {
      // Immediate mock height so AltHold page jumps off the ground.
      simHeightM = mockArmedHeightM;
    } else {
      altHoldActive = false;
      simHeightM = 0.05;
    }
  }

  /// Call when toggling AltHold from the Sim UI so tgt latches at current Z.
  /// That latch height is the cyan ring target on the AltHold page.
  void setAltHold(bool on) {
    if (on) {
      if (!armed) {
        // Auto-arm into hover so AltHold has a height to lock.
        setArmed(true);
      }
      // Freeze target at the height when AltHold was clicked.
      _altHoldTgtM = simHeightM.clamp(0.3, 6.0);
      altHoldActive = true;
    } else {
      altHoldActive = false;
    }
  }

  Uint8List _packHeartbeat() {
    final p = List<int>.filled(9, 0);
    p[4] = 2; // MAV_TYPE_QUADROTOR
    p[5] = 8;
    p[6] = armed ? mavModeFlagArmed : 0;
    p[7] = 4;
    p[8] = 3;
    return _pack(msgHeartbeat, p);
  }

  Uint8List _packSysStatus() {
    final p = List<int>.filled(31, 0);
    final mv = voltageMv.clamp(0, 65534);
    p[14] = mv & 0xFF;
    p[15] = (mv >> 8) & 0xFF;
    p[16] = 0xFF; // current = -1
    p[17] = 0xFF;
    final rem = batteryRemaining;
    p[30] = rem < 0 ? 0xFF : (rem & 0xFF);
    return _pack(msgSysStatus, p);
  }

  Uint8List _packAttitude() {
    final t = DateTime.now().difference(_boot).inMilliseconds;
    final w = t / 1000.0;
    final bd = ByteData(28);
    bd.setUint32(0, t & 0xFFFFFFFF, Endian.little);
    bd.setFloat32(4, 0.05 * math.sin(w), Endian.little);
    bd.setFloat32(8, 0.04 * math.cos(w * 0.9), Endian.little);
    bd.setFloat32(12, w % (2 * math.pi), Endian.little);
    bd.setFloat32(16, 0.01, Endian.little);
    bd.setFloat32(20, 0.01, Endian.little);
    bd.setFloat32(24, 0.02, Endian.little);
    return _pack(msgAttitude, bd.buffer.asUint8List());
  }

  Uint8List _packParamValue(int index) {
    final sp = _params[index];
    final p = List<int>.filled(25, 0);
    final id = sp.id.codeUnits;
    for (var i = 0; i < 16 && i < id.length; i++) {
      p[i] = id[i];
    }
    final bd = ByteData(4)..setFloat32(0, sp.value, Endian.little);
    p[16] = bd.getUint8(0);
    p[17] = bd.getUint8(1);
    p[18] = bd.getUint8(2);
    p[19] = bd.getUint8(3);
    p[20] = mavParamTypeReal32;
    final count = _params.length;
    p[21] = count & 0xFF;
    p[22] = (count >> 8) & 0xFF;
    p[23] = index & 0xFF;
    p[24] = (index >> 8) & 0xFF;
    return _pack(msgParamValue, p);
  }

  Uint8List _pack(int msgid, List<int> payload) {
    final len = payload.length;
    final buf = Uint8List(10 + len + 2);
    buf[0] = mavStxV2;
    buf[1] = len;
    buf[2] = 0;
    buf[3] = 0;
    buf[4] = _seq & 0xFF;
    _seq = (_seq + 1) & 0xFF;
    buf[5] = mavSysFc;
    buf[6] = mavCompFc;
    buf[7] = msgid & 0xFF;
    buf[8] = (msgid >> 8) & 0xFF;
    buf[9] = (msgid >> 16) & 0xFF;
    buf.setRange(10, 10 + len, payload);
    var crc = 0xFFFF;
    for (var i = 1; i < 10 + len; i++) {
      crc = x25CrcAccumulate(buf[i], crc);
    }
    crc = x25CrcAccumulate(crcExtraFor(msgid), crc);
    buf[10 + len] = crc & 0xFF;
    buf[11 + len] = (crc >> 8) & 0xFF;
    return buf;
  }

  int? _indexOfId(String id) {
    if (id.isEmpty) return null;
    for (var i = 0; i < _params.length; i++) {
      if (_params[i].id == id) return i;
    }
    return null;
  }

  static int _readParamIndex(Uint8List p) {
    if (p.length < 20) return -1;
    final u = p[18] | (p[19] << 8);
    return u > 32767 ? u - 65536 : u;
  }

  static String _readParamId(Uint8List p, {required int idAt}) {
    if (p.length < idAt + 16) return '';
    final end = idAt + 16;
    final zero = p.indexOf(0, idAt);
    final slice = p.sublist(idAt, (zero >= idAt && zero < end) ? zero : end);
    return String.fromCharCodes(slice);
  }

  static (String, double)? _parseParamSet(Uint8List raw) {
    if (raw.length < 23) return null;
    final idFw = _readParamId(raw, idAt: 2);
    final vFw =
        ByteData.sublistView(raw, 18, 22).getFloat32(0, Endian.little);
    if (idFw.isNotEmpty && RegExp(r'^[A-Z0-9_]+$').hasMatch(idFw)) {
      return (idFw, vFw);
    }
    final vStd =
        ByteData.sublistView(raw, 0, 4).getFloat32(0, Endian.little);
    final idStd = _readParamId(raw, idAt: 6);
    if (idStd.isNotEmpty && RegExp(r'^[A-Z0-9_]+$').hasMatch(idStd)) {
      return (idStd, vStd);
    }
    return null;
  }
}

class _SimParam {
  _SimParam(this.id, this.value);
  final String id;
  final double value;
}
