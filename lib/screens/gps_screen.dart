import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../link/mav_session.dart';
import '../mavlink/mavlink_v2.dart';

/// GPS map from MAVLink GLOBAL_POSITION_INT + GPS_RAW_INT (not Live Log).
/// Street / satellite TileLayer settings match FC-Frontend [MapTileLayer].
/// Flight track records only while armed. Refresh clears the track.
class GpsScreen extends StatefulWidget {
  const GpsScreen({super.key, required this.session});

  final MavSession? session;

  @override
  State<GpsScreen> createState() => _GpsScreenState();
}

class _GpsScreenState extends State<GpsScreen> {
  StreamSubscription<FcGpsState>? _gpsSub;
  StreamSubscription<Heartbeat>? _hbSub;
  final _map = MapController();

  final List<LatLng> _route = <LatLng>[];
  LatLng? _here;
  DateTime? _lastTrackAt;

  /// Default Esri World Imagery — same satellite source as FC-Frontend.
  bool _satellite = true;
  bool _armed = false;

  /// Same URLs / UA as FC-Frontend [MapTileLayer] — network only, no cache.
  static const _streetUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const _satelliteUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const _userAgentPackage = 'fc_frontend';

  /// Standard short-range track: ~0.8 m + 300 ms (keeps pad paths, kills jitter).
  static const _minMoveM = 0.8;
  static const _minTrackInterval = Duration(milliseconds: 300);
  static const _maxPoints = 4000;
  static const _fallbackCenter = LatLng(12.9716, 77.5946);

  @override
  void initState() {
    super.initState();
    _bind(widget.session);
  }

  @override
  void didUpdateWidget(covariant GpsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      _bind(widget.session);
    }
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _hbSub?.cancel();
    _map.dispose();
    super.dispose();
  }

  void _bind(MavSession? session) {
    _gpsSub?.cancel();
    _hbSub?.cancel();
    _gpsSub = null;
    _hbSub = null;
    if (session == null) {
      setState(() {
        _here = null;
        _armed = false;
        _route.clear();
        _lastTrackAt = null;
      });
      return;
    }

    _armed = session.armed;
    _hbSub = session.heartbeats.listen((hb) {
      if (!mounted) return;
      final wasArmed = _armed;
      setState(() => _armed = hb.armed);
      if (!wasArmed && hb.armed) {
        _route.clear();
        _lastTrackAt = null;
        if (_here != null) _route.add(_here!);
      }
    });

    final last = session.lastGps;
    if (last != null) {
      _onGps(last);
    }
    _gpsSub = session.gpsStates.listen((g) {
      if (!mounted) return;
      _onGps(g);
    });
  }

  void _onGps(FcGpsState g) {
    if (!g.hasValidLatLon) return;
    final next = LatLng(g.latDeg!, g.lonDeg!);

    // Disarmed: follow the craft, do not draw a track.
    if (!_armed) {
      setState(() => _here = next);
      try {
        _map.move(next, _map.camera.zoom);
      } catch (_) {}
      return;
    }

    // Armed: always move the marker; extend the route from last track point
    // (not from _here — that updates every tick and would block the line).
    final now = DateTime.now();
    final lastTrack = _route.isNotEmpty ? _route.last : null;
    final tooSoon = _lastTrackAt != null &&
        now.difference(_lastTrackAt!) < _minTrackInterval;
    final tooClose =
        lastTrack != null && _distanceM(lastTrack, next) < _minMoveM;

    setState(() {
      _here = next;
      if (!tooSoon && !tooClose) {
        _lastTrackAt = now;
        _route.add(next);
        if (_route.length > _maxPoints) {
          _route.removeRange(0, _route.length - _maxPoints);
        }
      }
    });
    try {
      _map.move(next, _map.camera.zoom);
    } catch (_) {}
  }

  void _reloadRoute() {
    setState(() {
      _route.clear();
      _lastTrackAt = null;
      if (_armed && _here != null) _route.add(_here!);
    });
  }

  static double _distanceM(LatLng a, LatLng b) {
    const r = 6371000.0;
    final p1 = a.latitude * math.pi / 180;
    final p2 = b.latitude * math.pi / 180;
    final dP = (b.latitude - a.latitude) * math.pi / 180;
    final dL = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.sin(dP / 2) * math.sin(dP / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dL / 2) * math.sin(dL / 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  Widget _overlayBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: const Color(0x66000000),
          disabledForegroundColor: Colors.white38,
          padding: const EdgeInsets.all(10),
        ),
        icon: Icon(icon, size: 22),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = _here ?? _fallbackCenter;
    final trackPts = List<LatLng>.from(_route);

    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 16,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            backgroundColor: const Color(0xFF1A1A1A),
          ),
          children: [
            if (_satellite)
              TileLayer(
                urlTemplate: _satelliteUrl,
                userAgentPackageName: _userAgentPackage,
              )
            else
              TileLayer(
                urlTemplate: _streetUrl,
                userAgentPackageName: _userAgentPackage,
              ),
            if (trackPts.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: trackPts,
                    color: const Color(0xCC0A1628),
                    strokeWidth: 5.5,
                    borderStrokeWidth: 0,
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
                  Polyline(
                    points: trackPts,
                    color: const Color(0xFFE8F4FF),
                    strokeWidth: 2.25,
                    borderStrokeWidth: 0,
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
                ],
              ),
            if (_here != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _here!,
                    width: 40,
                    height: 40,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xE0E53935),
                        border: Border.all(
                          color: Colors.white,
                          width: 2.5,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.navigation,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        // Map style — bottom left (transparent over map).
        Positioned(
          left: 12,
          bottom: 12,
          child: _overlayBtn(
            icon: _satellite ? Icons.map : Icons.satellite_alt,
            tooltip: _satellite ? 'Street' : 'Satellite',
            onPressed: () => setState(() => _satellite = !_satellite),
          ),
        ),
        // Refresh track — top right (transparent over map).
        Positioned(
          right: 12,
          top: 12,
          child: _overlayBtn(
            icon: Icons.refresh,
            tooltip: 'Clear track',
            onPressed: _route.isEmpty ? null : _reloadRoute,
          ),
        ),
      ],
    );
  }
}
