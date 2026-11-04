import 'dart:async';

import '../link/mav_session.dart';
import 'sd_cli_transport.dart';

/// SD flight-log CLI over the same MAVLink link as Live Log (G20 / T12).
class MavSdCliTransport implements SdCliTransport {
  MavSdCliTransport(this._session);

  final MavSession _session;
  Timer? _keepAlive;

  @override
  Stream<String> get lines => _session.sdLogLines;

  @override
  bool get isOpen => _session.isConnected;

  @override
  void beginJob() {
    _session.resetSdTunnel();
    _keepAlive?.cancel();
    // Keep the G20 UDP bridge awake during long dumps.
    _keepAlive = Timer.periodic(const Duration(seconds: 1), (_) {
      try {
        _session.send(_session.encoder.heartbeat());
      } catch (_) {}
    });
  }

  @override
  void endJob() {
    _keepAlive?.cancel();
    _keepAlive = null;
  }

  @override
  void writeAscii(String text) {
    var cmd = text.trim();
    if (cmd.startsWith('!')) {
      cmd = cmd.substring(1).trimLeft();
    }
    if (cmd.isEmpty) return;
    if (cmd.length > 50) {
      cmd = cmd.substring(0, 50);
    }
    unawaited(_session.sendStatusText(cmd));
  }
}
