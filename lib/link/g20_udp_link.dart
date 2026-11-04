import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'byte_link.dart';

/// G20 UDP — match QGC: listen :14551, send to 127.0.0.1:14552 first.
class G20UdpLink implements ByteLink {
  G20UdpLink({
    this.listenPort = 14551,
    this.targetHost = '127.0.0.1',
    this.targetPort = 14552,
  });

  final int listenPort;
  final String targetHost;
  final int targetPort;

  static const _method = MethodChannel('fc_tuning_studio/g20_udp');
  static const _events = EventChannel('fc_tuning_studio/g20_udp_rx');

  final _rx = StreamController<List<int>>.broadcast();
  StreamSubscription? _eventSub;

  RawDatagramSocket? _dartSocket;
  StreamSubscription<RawSocketEvent>? _dartSub;
  InternetAddress? _dartPeerHost;
  int? _dartPeerPort;

  bool _native = false;
  int rxBytes = 0;
  int txBytes = 0;
  int rxDatagrams = 0;
  int txDatagrams = 0;
  int txFail = 0;
  String bindMode = '—';
  String peer = '';
  String configured = '';
  String lastTxError = '';
  String targetListen = '?'; // busy = mavlinkd present; free = nobody on 14552

  @override
  Stream<List<int>> get bytes => _rx.stream;

  bool get hasPeer => peer.isNotEmpty || _dartPeerPort != null;

  @override
  Future<void> open() async {
    await close();
    rxBytes = 0;
    txBytes = 0;
    rxDatagrams = 0;
    txDatagrams = 0;
    txFail = 0;
    peer = '';
    configured = '$targetHost:$targetPort';
    _dartPeerHost = null;
    _dartPeerPort = null;

    if (Platform.isAndroid) {
      try {
        final info = await _method.invokeMapMethod<String, dynamic>('open', {
          'listenPort': listenPort,
          'targetHost': targetHost,
          'targetPort': targetPort,
        });
        bindMode = (info?['bindMode'] as String?) ?? 'native';
        targetListen = (info?['targetListen'] as String?) ?? '?';
        _native = true;
        _eventSub = _events.receiveBroadcastStream().listen((event) {
          if (event is! Uint8List || event.isEmpty) return;
          rxBytes += event.length;
          rxDatagrams += 1;
          _rx.add(event);
          if (rxDatagrams == 1 || rxDatagrams % 25 == 0) {
            unawaited(_refreshNativeStats());
          }
        });
        return;
      } catch (_) {
        _native = false;
      }
    }

    await _openDart();
  }

  Future<void> _openDart() async {
    // Match native/QGC: bind anyIPv4 on listen port.
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      listenPort,
      reuseAddress: true,
    );
    bindMode = 'dart-any:$listenPort';
    socket.readEventsEnabled = true;
    _dartSocket = socket;
    _dartSub = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = socket.receive();
      if (dg == null || dg.data.isEmpty) return;
      _dartPeerHost = dg.address;
      _dartPeerPort = dg.port;
      peer = '${dg.address.address}:${dg.port}';
      rxBytes += dg.data.length;
      rxDatagrams += 1;
      _rx.add(Uint8List.fromList(dg.data));
    });
  }

  @override
  void write(List<int> data) => unawaited(writeAsync(data));

  Future<void> writeAsync(List<int> data) async {
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    if (_native) {
      try {
        final n = await _method.invokeMethod<int>('send', {'data': bytes});
        if (n != null && n > 0) {
          txBytes += n;
          txDatagrams += 1;
        } else {
          txFail += 1;
        }
      } catch (_) {
        txFail += 1;
      }
      return;
    }

    final s = _dartSocket;
    if (s == null) throw StateError('G20 UDP not open');
    final target =
        InternetAddress.tryParse(targetHost) ?? InternetAddress.loopbackIPv4;
    var n = s.send(bytes, target, targetPort);
    if (n <= 0) {
      txFail += 1;
      return;
    }
    txBytes += n;
    txDatagrams += 1;
    // Fallback peer only if different.
    if (_dartPeerHost != null &&
        _dartPeerPort != null &&
        _dartPeerPort != targetPort) {
      s.send(bytes, _dartPeerHost!, _dartPeerPort!);
    }
  }

  Future<void> _refreshNativeStats() async {
    if (!_native) return;
    try {
      final s = await _method.invokeMapMethod<String, dynamic>('stats');
      if (s == null) return;
      rxBytes = (s['rxBytes'] as num?)?.toInt() ?? rxBytes;
      txBytes = (s['txBytes'] as num?)?.toInt() ?? txBytes;
      rxDatagrams = (s['rxPkts'] as num?)?.toInt() ?? rxDatagrams;
      txDatagrams = (s['txPkts'] as num?)?.toInt() ?? txDatagrams;
      txFail = (s['txFail'] as num?)?.toInt() ?? txFail;
      bindMode = (s['bindMode'] as String?) ?? bindMode;
      peer = (s['peer'] as String?) ?? peer;
      configured = (s['configured'] as String?) ?? configured;
      lastTxError = (s['lastTxError'] as String?) ?? lastTxError;
      targetListen = (s['targetListen'] as String?) ?? targetListen;
    } catch (_) {}
  }

  Future<bool> waitForPeer({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await _refreshNativeStats();
      if (hasPeer || rxDatagrams > 0) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await _refreshNativeStats();
    return hasPeer || rxDatagrams > 0;
  }

  @override
  Future<void> close() async {
    await _eventSub?.cancel();
    _eventSub = null;
    await _dartSub?.cancel();
    _dartSub = null;
    _dartSocket?.close();
    _dartSocket = null;
    if (_native) {
      try {
        await _method.invokeMethod<void>('close');
      } catch (_) {}
      _native = false;
    }
  }

  String get statusLine {
    unawaited(_refreshNativeStats());
    final peerPart = peer.isEmpty ? 'peer=?' : 'peer=$peer';
    final err = lastTxError.isEmpty ? '' : ' err=$lastTxError';
    return 'UDP $bindMode →$configured $peerPart '
        'tgt14552=$targetListen '
        'rx=$rxBytes/$rxDatagrams tx=$txBytes/$txDatagrams fail=$txFail$err';
  }
}
