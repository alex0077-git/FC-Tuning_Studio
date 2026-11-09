import 'dart:async';

import '../logs/live_log_assembler.dart';
import '../logs/sd_tunnel_assembler.dart';
import '../mavlink/mavlink_v2.dart';
import 'byte_link.dart';
import 'g20_udp_link.dart';

class MavSession {
  final encoder = MavlinkV2Encoder();
  final parser = MavlinkV2Parser();
  final _liveLogAsm = LiveLogAssembler();
  final _sdAsm = SdTunnelAssembler();

  ByteLink? _link;
  StreamSubscription<List<int>>? _sub;

  final _messages = StreamController<MavMessage>.broadcast();
  final _liveLogLines = StreamController<String>.broadcast();
  final _sdLogLines = StreamController<String>.broadcast();
  /// Motor / cruise replies (`*base …`, `*motor …`). Not Live Log or SD.
  final _starStatus = StreamController<String>.broadcast();
  final Map<String, double> params = {};
  final Map<int, String> idsByIndex = {};
  final Map<int, int> msgidCounts = {};

  Heartbeat? lastHeartbeat;
  Attitude? lastAttitude;
  String? lastLiveLogLine;
  int? expectedParamCount;
  int rxBytes = 0;
  int parsedFrames = 0;
  int paramValueSeen = 0;
  int liveLogLinesSeen = 0;
  int sdTunnelBytes = 0;
  DateTime? lastFcHeartbeatAt;

  /// No FC HEARTBEAT for this long ⇒ treat radio/MAV link as lost.
  static const linkLostAfter = Duration(seconds: 3);

  Stream<MavMessage> get messages => _messages.stream;
  Stream<String> get liveLogLines => _liveLogLines.stream;
  Stream<String> get sdLogLines => _sdLogLines.stream;
  Stream<String> get starStatusLines => _starStatus.stream;
  bool get armed => lastHeartbeat?.armed ?? false;
  bool get isConnected => _link != null;

  /// True while the FC is still sending HEARTBEAT (sys 1).
  bool get linkAlive {
    if (_link == null) return false;
    final t = lastFcHeartbeatAt;
    if (t == null) return false;
    return DateTime.now().difference(t) < linkLostAfter;
  }

  Stream<Heartbeat> get heartbeats => messages
      .where((m) => m.msgid == msgHeartbeat && m.sysid == mavSysFc)
      .map((m) => decodeHeartbeat(m.payload))
      .where((h) => h != null)
      .cast<Heartbeat>();

  Stream<Attitude> get attitudes => messages
      .where((m) => m.msgid == msgAttitude)
      .map((m) => decodeAttitude(m.payload))
      .where((a) => a != null)
      .cast<Attitude>();

  Stream<ParamValue> get paramValues => messages
      .where((m) => m.msgid == msgParamValue)
      .map((m) => decodeParamValue(m.payload))
      .where((p) => p != null)
      .cast<ParamValue>();

  Future<void> connect(ByteLink link) async {
    await disconnect();
    params.clear();
    idsByIndex.clear();
    msgidCounts.clear();
    expectedParamCount = null;
    lastHeartbeat = null;
    lastAttitude = null;
    lastLiveLogLine = null;
    lastFcHeartbeatAt = null;
    rxBytes = 0;
    parsedFrames = 0;
    paramValueSeen = 0;
    liveLogLinesSeen = 0;
    sdTunnelBytes = 0;
    parser.crcFailures = 0;
    _liveLogAsm.reset();
    _sdAsm.reset();

    _link = link;
    await link.open();
    _sub = link.bytes.listen((chunk) {
      rxBytes += chunk.length;
      for (final m in parser.addBytes(chunk)) {
        if (m.sysid == encoder.sysid) continue; // ignore own GCS echo
        parsedFrames += 1;
        msgidCounts[m.msgid] = (msgidCounts[m.msgid] ?? 0) + 1;
        _onMessage(m);
      }
    });
  }

  void _onMessage(MavMessage m) {
    if (m.msgid == msgHeartbeat) {
      final hb = decodeHeartbeat(m.payload);
      if (m.sysid == mavSysFc && hb != null) {
        lastHeartbeat = hb;
        lastFcHeartbeatAt = DateTime.now();
      }
    } else if (m.msgid == msgAttitude) {
      lastAttitude = decodeAttitude(m.payload);
    } else if (m.msgid == msgParamValue) {
      paramValueSeen += 1;
      final pv = decodeParamValue(m.payload);
      if (pv != null && looksLikeParamValue(pv)) {
        expectedParamCount = pv.count;
        params[pv.paramId] = pv.value;
        idsByIndex[pv.index] = pv.paramId;
      } else if (pv != null && expectedParamCount == null && pv.count >= 1 && pv.count <= 64) {
        // Accept count even if id decode is still settling.
        expectedParamCount = pv.count;
        if (pv.paramId.isNotEmpty) {
          params[pv.paramId] = pv.value;
          idsByIndex[pv.index] = pv.paramId;
        }
      }
    } else if (m.msgid == msgStatustext) {
      final st = decodeStatusText(m.payload);
      if (st != null) {
        final t = st.text;
        // Motor / cruise replies use leading '*'; leave Live Log / SD alone.
        if (t.isNotEmpty && t.codeUnitAt(0) == 0x2A /* * */) {
          if (!_starStatus.isClosed) {
            _starStatus.add(t);
          }
        } else {
          final line = _liveLogAsm.pushChunk(t);
          if (line != null) {
            liveLogLinesSeen += 1;
            lastLiveLogLine = line;
            if (!_liveLogLines.isClosed) {
              _liveLogLines.add(line);
            }
          }
          for (final sdLine in _sdAsm.pushChunk(t)) {
            sdTunnelBytes = _sdAsm.bytesSeen;
            if (!_sdLogLines.isClosed) {
              _sdLogLines.add(sdLine);
            }
          }
        }
      }
    }
    _messages.add(m);
  }

  /// Clear SD `#`/`$` reassembly before a new `log list` / `dump` / `wipe`.
  void resetSdTunnel() {
    _sdAsm.reset();
    sdTunnelBytes = 0;
  }

  /// App → FC SD / motor / cruise command (plain STATUSTEXT text).
  Future<void> sendStatusText(String text) async {
    final g20 = _link;
    if (g20 is G20UdpLink) {
      await g20.waitForPeer(timeout: const Duration(seconds: 2));
    }
    await sendAsync(encoder.statusText(text));
  }

  /// Cruise / base throttle (µs). Clamp 1000..2000.
  Future<void> sendCruiseBaseUs(int us) =>
      sendStatusText('base ${_clampUs(us)}');

  /// Bench motor test: `motor 1..4 N`, `motor all N`, or `motor stop`.
  Future<void> sendMotorCommand(String cmd) => sendStatusText(cmd);

  static int clampPwmUs(int us) => _clampUs(us);

  static int _clampUs(int us) {
    if (us < 1000) return 1000;
    if (us > 2000) return 2000;
    return us;
  }

  void send(List<int> frame) {
    final link = _link;
    if (link is G20UdpLink) {
      unawaited(link.writeAsync(frame));
    } else {
      link?.write(frame);
    }
  }

  Future<void> sendAsync(List<int> frame) async {
    final link = _link;
    if (link is G20UdpLink) {
      await link.writeAsync(frame);
    } else {
      link?.write(frame);
    }
  }

  String get _msgidSummary {
    if (msgidCounts.isEmpty) return 'none';
    final parts = msgidCounts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return parts.map((e) => '${e.key}:${e.value}').join(',');
  }

  /// Wait for FC HEARTBEAT (sys 1). Pokes the G20 UDP bridge with GCS HEARTBEAT.
  Future<Heartbeat> waitHeartbeat({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (lastHeartbeat != null) return lastHeartbeat!;

    final completer = Completer<Heartbeat>();
    late final StreamSubscription<Heartbeat> sub;
    Timer? poke;
    Timer? watchdog;

    void finishOk(Heartbeat hb) {
      if (completer.isCompleted) return;
      poke?.cancel();
      watchdog?.cancel();
      sub.cancel();
      completer.complete(hb);
    }

    void finishErr(Object e) {
      if (completer.isCompleted) return;
      poke?.cancel();
      watchdog?.cancel();
      sub.cancel();
      completer.completeError(e);
    }

    sub = heartbeats.listen(finishOk);

    void sendPoke() {
      try {
        send(encoder.heartbeat());
      } catch (_) {}
    }

    sendPoke();
    poke = Timer.periodic(const Duration(seconds: 1), (_) {
      if (lastHeartbeat != null) {
        finishOk(lastHeartbeat!);
        return;
      }
      sendPoke();
    });

    watchdog = Timer(timeout, () {
      final linkHint = _link is G20UdpLink
          ? (_link as G20UdpLink).statusLine
          : 'rx=$rxBytes frames=$parsedFrames';
      finishErr(
        TimeoutException(
          'No FC HEARTBEAT in ${timeout.inSeconds}s. '
          '$linkHint. '
          'Close QGC, confirm FC boot says "MAVLink v2 LPUART1 OK", '
          'and radio data UART is on PB6/PB7 @ 115200.',
        ),
      );
    });

    return completer.future;
  }

  Future<void> _sendParamProbes({required int targetComp}) async {
    // Await native UDP send so PARAM frames actually leave before we wait.
    await sendAsync(encoder.heartbeat());
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await sendAsync(encoder.paramRequestList(targetComp: targetComp));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await sendAsync(encoder.paramRequestRead(paramIndex: 0, targetComp: targetComp));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await sendAsync(
      encoder.paramRequestRead(
        paramId: 'ROLL_AP',
        paramIndex: -1,
        targetComp: targetComp,
      ),
    );
  }

  Future<void> downloadParams({
    Duration idle = const Duration(milliseconds: 400),
    int attempts = 25,
  }) async {
    // Learn mavlinkd peer from RX before PARAM uplink (reply-to-sender).
    final link = _link;
    if (link is G20UdpLink) {
      final ok = await link.waitForPeer();
      if (!ok) {
        // Still try configured ports; peer may appear mid-download.
      }
    }

    // Keep uplink registered with the G20 bridge the whole time.
    final keepAlive = Timer.periodic(const Duration(seconds: 1), (_) {
      try {
        send(encoder.heartbeat());
      } catch (_) {}
    });

    try {
      for (var i = 0; i < attempts && expectedParamCount == null; i++) {
        final comp = (i % 2 == 0) ? 1 : 0;
        await _sendParamProbes(targetComp: comp);
        await Future<void>.delayed(idle);
      }

      if (expectedParamCount == null) {
        final peerHint = link is G20UdpLink ? (link).statusLine : '';
        throw StateError(
          'No PARAM_VALUE after HEARTBEAT '
          '(rx=$rxBytes frames=$parsedFrames crcFail=${parser.crcFailures} '
          'msg22=$paramValueSeen ids=[$_msgidSummary]). $peerHint '
          'If tgt14552=free, nothing listens for commands (start/keep radio mavlink service).',
        );
      }

      for (var i = 0; i < attempts; i++) {
        final missing = <int>[];
        for (var idx = 0; idx < expectedParamCount!; idx++) {
          if (!idsByIndex.containsKey(idx)) missing.add(idx);
        }
        if (missing.isEmpty) return;

        await sendAsync(encoder.heartbeat());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await sendAsync(encoder.paramRequestList());
        for (final idx in missing.take(8)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await sendAsync(encoder.paramRequestRead(paramIndex: idx));
        }
        await Future<void>.delayed(idle);
      }
    } finally {
      keepAlive.cancel();
    }
  }

  /// Seed Tuning from catalog defaults when live PARAM_VALUE never arrived.
  void seedParams(Map<String, double> defaults) {
    params
      ..clear()
      ..addAll(defaults);
    idsByIndex.clear();
    var i = 0;
    for (final id in defaults.keys) {
      idsByIndex[i++] = id;
    }
    expectedParamCount = defaults.length;
  }

  Future<double> setParam(String id, double value) async {
    if (armed) {
      throw StateError('Disarm to tune — FC refuses PARAM_SET while armed');
    }

    final beforeSeen = paramValueSeen;
    final completer = Completer<ParamValue>();
    late final StreamSubscription<ParamValue> sub;
    Timer? retry;
    var attempt = 0;

    sub = paramValues.where((p) => p.paramId == id).listen((p) {
      if (!completer.isCompleted) completer.complete(p);
    });

    Future<void> poke() async {
      attempt += 1;
      try {
        await sendAsync(encoder.heartbeat());
        // Alternate firmware Phase B layout and QGC/standard layout.
        if (attempt.isOdd) {
          await sendAsync(encoder.paramSet(paramId: id, value: value));
        } else {
          await sendAsync(encoder.paramSetStandard(paramId: id, value: value));
        }
      } catch (_) {}
    }

    // Ensure we know who to reply to before SET.
    final g20 = _link;
    if (g20 is G20UdpLink) {
      await g20.waitForPeer(timeout: const Duration(seconds: 2));
    }

    await poke();
    retry = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (completer.isCompleted) return;
      if (attempt >= 10) return;
      unawaited(poke());
    });

    try {
      final stored = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          final linkHint = _link is G20UdpLink
              ? (_link as G20UdpLink).statusLine
              : 'tx unknown';
          throw TimeoutException(
            'No PARAM_VALUE echo for $id '
            '(msg22 Δ=${paramValueSeen - beforeSeen}, $linkHint). '
            'FC→app OK; uplink peer may be wrong — close QGC.',
          );
        },
      );
      params[id] = stored.value;
      return stored.value;
    } finally {
      retry?.cancel();
      await sub.cancel();
    }
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
    await _link?.close();
    _link = null;
    _liveLogAsm.reset();
    _sdAsm.reset();
  }

  Future<void> dispose() async {
    await disconnect();
    await _messages.close();
    await _liveLogLines.close();
    await _sdLogLines.close();
    await _starStatus.close();
  }
}
