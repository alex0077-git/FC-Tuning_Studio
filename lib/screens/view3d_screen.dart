import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../layout/g20_metrics.dart';
import '../link/mav_session.dart';
import '../logs/live_log_assembler.dart';
import 'drone_3d_host.dart';

/// Betaflight Setup → 3D: official quad_x model + instruments / GPS / system.
class View3dScreen extends StatefulWidget {
  const View3dScreen({super.key, this.session});

  final MavSession? session;

  @override
  State<View3dScreen> createState() => _View3dScreenState();
}

class _Bf {
  static const bg = Color(0xFF222222);
  static const panel = Color(0xFF2F2F2F);
  static const yellow = Color(0xFFFFBB00);
  static const text = Color(0xFFEEEEEE);
  static const muted = Color(0xFFAAAAAA);
  static const bad = Color(0xFFE33C3C);
  static const good = Color(0xFF2EAE5B);
}

class _View3dScreenState extends State<View3dScreen> {
  StreamSubscription? _attSub;
  StreamSubscription? _hbSub;
  StreamSubscription? _liveSub;
  StreamSubscription? _starSub;

  double _roll = 0;
  double _pitch = 0;
  double _yaw = 0;
  double _gx = 0;
  double _gy = 0;
  double _gz = 0;
  bool _liveFromFc = false;
  bool _armed = false;
  LiveLogFields? _fields;

  /// Cruise / base throttle (µs). Stick or slider — last mover wins.
  int _cruiseUs = 1250;
  bool _cruiseDragging = false;
  bool _altHoldOwns = false;
  bool _linkAlive = false;
  String? _cruiseNote;
  Timer? _cruiseSendTimer;
  Timer? _linkWatch;

  double get _yawLabel {
    var y = _yaw;
    while (y < 0) {
      y += 360;
    }
    while (y >= 360) {
      y -= 360;
    }
    return y;
  }

  @override
  void initState() {
    super.initState();
    _attachSession(widget.session);
  }

  @override
  void didUpdateWidget(covariant View3dScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      _attachSession(widget.session);
    }
  }

  void _attachSession(MavSession? session) {
    _attSub?.cancel();
    _hbSub?.cancel();
    _liveSub?.cancel();
    _starSub?.cancel();
    _cruiseSendTimer?.cancel();
    _linkWatch?.cancel();
    _attSub = null;
    _hbSub = null;
    _liveSub = null;
    _starSub = null;
    _liveFromFc = session != null;

    if (session == null) {
      if (mounted) {
        setState(() {
          _roll = 0;
          _pitch = 0;
          _yaw = 0;
          _gx = 0;
          _gy = 0;
          _gz = 0;
          _armed = false;
          _fields = null;
          _cruiseUs = 1250;
          _altHoldOwns = false;
          _linkAlive = false;
          _cruiseNote = null;
          _cruiseDragging = false;
        });
      }
      return;
    }

    _armed = session.armed;
    _linkAlive = session.linkAlive;
    _linkWatch = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final alive = session.linkAlive;
      if (alive != _linkAlive) {
        setState(() {
          _linkAlive = alive;
          if (!alive) {
            _cruiseDragging = false;
            _cruiseNote = 'Link Lost — cruise idle';
            _cruiseSendTimer?.cancel();
          } else if (_cruiseNote == 'Link Lost — cruise idle') {
            _cruiseNote = null;
          }
        });
      }
    });
    final last = session.lastAttitude;
    if (last != null) {
      _roll = last.rollDeg;
      _pitch = last.pitchDeg;
      _yaw = last.yawDeg;
      _gx = last.rollspeed * 180 / math.pi;
      _gy = last.pitchspeed * 180 / math.pi;
      _gz = last.yawspeed * 180 / math.pi;
    }
    _hbSub = session.heartbeats.listen((hb) {
      if (!mounted) return;
      setState(() => _armed = hb.armed);
    });
    _liveSub = session.liveLogLines.listen((line) {
      if (!mounted) return;
      final f = LiveLogFields.parse(line);
      setState(() {
        _fields = f;
        final act = f.ahAct;
        _altHoldOwns = act != null && act != 0;
        if (_altHoldOwns) {
          _cruiseNote = 'AltHold owns throttle';
          _cruiseDragging = false;
          _cruiseSendTimer?.cancel();
        } else if (_cruiseNote == 'AltHold owns throttle') {
          _cruiseNote = null;
        }
      });
    });
    _starSub = session.starStatusLines.listen(_onStarStatus);
    _attSub = session.attitudes.listen((a) {
      if (!mounted) return;
      setState(() {
        _roll = a.rollDeg;
        _pitch = a.pitchDeg;
        _yaw = a.yawDeg;
        _gx = a.rollspeed * 180 / math.pi;
        _gy = a.pitchspeed * 180 / math.pi;
        _gz = a.yawspeed * 180 / math.pi;
      });
    });
  }

  void _onStarStatus(String line) {
    if (!mounted) return;
    final t = line.startsWith('*') ? line.substring(1).trim() : line.trim();
    if (t == 'base deny althold') {
      setState(() {
        _altHoldOwns = true;
        _cruiseNote = 'AltHold owns throttle';
        _cruiseDragging = false;
      });
      _cruiseSendTimer?.cancel();
      return;
    }
    if (t == 'base deny') {
      setState(() => _cruiseNote = 'Cruise refused');
      return;
    }
    final m = RegExp(r'^base (\d+)$').firstMatch(t);
    if (m != null) {
      final us = MavSession.clampPwmUs(int.parse(m.group(1)!));
      setState(() {
        _cruiseUs = us;
        _cruiseNote = null;
        if (_cruiseDragging) {
          // Stick took over while dragging — snap and stop send.
          _cruiseDragging = false;
        }
      });
      _cruiseSendTimer?.cancel();
    }
  }

  Future<void> _sendCruise() async {
    final s = widget.session;
    if (s == null || _altHoldOwns || !_linkAlive) return;
    try {
      await s.sendCruiseBaseUs(_cruiseUs);
    } catch (_) {
      if (mounted) setState(() => _cruiseNote = 'Send failed');
    }
  }

  bool get _cruiseFrozen => _altHoldOwns || !_linkAlive;

  void _onCruiseChanged(double v) {
    if (_cruiseFrozen) return;
    final us = MavSession.clampPwmUs(v.round());
    setState(() {
      _cruiseUs = us;
      _cruiseNote = null;
    });
    unawaited(_sendCruise());
  }

  void _onCruiseDragStart(double _) {
    if (_cruiseFrozen) return;
    _cruiseDragging = true;
    _cruiseSendTimer?.cancel();
    _cruiseSendTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      unawaited(_sendCruise());
    });
  }

  void _onCruiseDragEnd(double _) {
    _cruiseDragging = false;
    _cruiseSendTimer?.cancel();
    unawaited(_sendCruise());
  }

  @override
  void dispose() {
    _cruiseSendTimer?.cancel();
    _linkWatch?.cancel();
    _attSub?.cancel();
    _hbSub?.cancel();
    _liveSub?.cancel();
    _starSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g20 = G20Metrics.of(context);
    final sideW = g20.compactChrome ? 230.0 : 268.0;

    if (!_liveFromFc) {
      return const ColoredBox(
        color: _Bf.bg,
        child: Center(
          child: Text(
            'Connect to stream live 3D',
            style: TextStyle(color: _Bf.muted, fontSize: 13),
          ),
        ),
      );
    }

    final heightLabel = _fields?.zM != null
        ? '${_fields!.zM!.toStringAsFixed(2)} m'
        : '—';

    final viewport = _BfViewport(
      roll: _roll,
      pitch: _pitch,
      yaw: _yaw,
      yawLabel: _yawLabel,
      heightLabel: heightLabel,
    );

    final cruise = _CruiseBar(
      us: _cruiseUs,
      frozen: _cruiseFrozen,
      note: _cruiseNote,
      onChanged: _onCruiseChanged,
      onChangeStart: _onCruiseDragStart,
      onChangeEnd: _onCruiseDragEnd,
    );

    final sidebar = _BfSidebar(
      roll: _roll,
      pitch: _pitch,
      yaw: _yawLabel,
      gx: _gx,
      gy: _gy,
      gz: _gz,
      armed: _armed,
      fields: _fields,
      heightLabel: heightLabel,
    );

    if (g20.landscape) {
      return ColoredBox(
        color: _Bf.bg,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                children: [
                  Expanded(child: viewport),
                  cruise,
                ],
              ),
            ),
            SizedBox(width: sideW, child: sidebar),
          ],
        ),
      );
    }

    return ColoredBox(
      color: _Bf.bg,
      child: Column(
        children: [
          Expanded(flex: 3, child: viewport),
          cruise,
          Expanded(flex: 2, child: sidebar),
        ],
      ),
    );
  }
}

class _CruiseBar extends StatelessWidget {
  const _CruiseBar({
    required this.us,
    required this.frozen,
    required this.note,
    required this.onChanged,
    required this.onChangeStart,
    required this.onChangeEnd,
  });

  final int us;
  final bool frozen;
  final String? note;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _Bf.panel,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  'Cruise',
                  style: TextStyle(
                    color: _Bf.yellow,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$us µs',
                  style: const TextStyle(
                    color: _Bf.text,
                    fontSize: 13,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      note!,
                      style: TextStyle(
                        color: frozen ? _Bf.yellow : _Bf.bad,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: frozen ? _Bf.muted : _Bf.yellow,
                inactiveTrackColor: _Bf.muted.withValues(alpha: 0.35),
                thumbColor: frozen ? _Bf.muted : _Bf.yellow,
                overlayColor: _Bf.yellow.withValues(alpha: 0.2),
              ),
              child: Slider(
                min: 1000,
                max: 2000,
                divisions: 100,
                value: us.toDouble().clamp(1000, 2000),
                onChanged: frozen ? null : onChanged,
                onChangeStart: frozen ? null : onChangeStart,
                onChangeEnd: frozen ? null : onChangeEnd,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BfViewport extends StatelessWidget {
  const _BfViewport({
    required this.roll,
    required this.pitch,
    required this.yaw,
    required this.yawLabel,
    required this.heightLabel,
  });

  final double roll;
  final double pitch;
  final double yaw;
  final double yawLabel;
  final String heightLabel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: _Bf.bg,
          child: Drone3dHost(
            rollDeg: roll,
            pitchDeg: pitch,
            yawDeg: yaw,
          ),
        ),
        Positioned(
          left: 12,
          top: 10,
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.4,
              fontFamily: 'monospace',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Yaw: ${yawLabel.toStringAsFixed(0)} deg'),
                Text('Pitch: ${pitch.toStringAsFixed(1)} deg'),
                Text('Roll: ${roll.toStringAsFixed(1)} deg'),
                Text('Height: $heightLabel'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BfSidebar extends StatelessWidget {
  const _BfSidebar({
    required this.roll,
    required this.pitch,
    required this.yaw,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.armed,
    required this.fields,
    required this.heightLabel,
  });

  final double roll;
  final double pitch;
  final double yaw;
  final double gx;
  final double gy;
  final double gz;
  final bool armed;
  final LiveLogFields? fields;
  final String heightLabel;

  @override
  Widget build(BuildContext context) {
    // Only show values we actually receive (Live Log / HEARTBEAT). Else "—".
    final fix = fields?.gpsFix;
    final sats = fields?.sats;
    final has3d = fix != null && fix >= 3;
    final fixLabel = fix == null ? '—' : (has3d ? 'True' : 'False');
    final fixColor = fix == null
        ? _Bf.muted
        : (has3d ? _Bf.good : _Bf.bad);

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      children: [
        _BfCard(
          title: 'Instruments',
          child: Column(
            children: [
              SizedBox(
                height: 100,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _AttitudeGauge(roll: roll, pitch: pitch, size: 92),
                    _HeadingGauge(yaw: yaw, size: 92),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Gyro  gx ${gx.toStringAsFixed(1)}  '
                'gy ${gy.toStringAsFixed(1)}  '
                'gz ${gz.toStringAsFixed(1)} dps',
                style: const TextStyle(
                  color: _Bf.yellow,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _BfCard(
          title: 'GPS',
          child: Column(
            children: [
              _row(
                '3D Fix',
                fixLabel,
                badge: fix != null,
                valueColor: fixColor,
              ),
              _row('Number of Satellites', sats?.toString() ?? '—'),
              // Lat/Lon not in Phase B Live Log — omit (no fake zeros).
            ],
          ),
        ),
        const SizedBox(height: 8),
        _BfCard(
          title: 'System info',
          child: Column(
            children: [
              _row('Arming', armed ? 'ARMED' : 'DISARMED',
                  valueColor: armed ? _Bf.bad : _Bf.good),
              _row('Mode', fields?.mode?.toUpperCase() ?? '—'),
              _row('Height', heightLabel),
              _row(
                'Temperature',
                fields?.tempC != null
                    ? '${fields!.tempC!.toStringAsFixed(1)} °C'
                    : '—',
              ),
              _row(
                'Motors µs',
                fields?.m1 != null
                    ? '${fields!.m1} ${fields!.m2} ${fields!.m3} ${fields!.m4}'
                    : '—',
              ),
              // Battery / RSSI / MCU not on this Live Log — omit.
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(
    String k,
    String v, {
    Color? valueColor,
    bool badge = false,
  }) {
    final style = TextStyle(
      color: valueColor ?? _Bf.text,
      fontSize: 12,
      fontWeight: FontWeight.w500,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: const TextStyle(color: _Bf.text, fontSize: 12),
            ),
          ),
          if (badge)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: (valueColor ?? _Bf.bad).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(v, style: style.copyWith(fontSize: 11)),
            )
          else
            Text(v, style: style),
        ],
      ),
    );
  }
}

class _BfCard extends StatelessWidget {
  const _BfCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: _Bf.panel,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _Bf.yellow,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 14,
                height: 14,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _Bf.yellow, width: 1.2),
                ),
                child: const Text(
                  '?',
                  style: TextStyle(
                    color: _Bf.yellow,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// Artificial horizon — filled CustomPaint (SVGs were blank on G20 WebView).
class _AttitudeGauge extends StatelessWidget {
  const _AttitudeGauge({
    required this.roll,
    required this.pitch,
    required this.size,
  });

  final double roll;
  final double pitch;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _HorizonPainter(rollDeg: roll, pitchDeg: pitch),
      ),
    );
  }
}

class _HorizonPainter extends CustomPainter {
  _HorizonPainter({required this.rollDeg, required this.pitchDeg});

  final double rollDeg;
  final double pitchDeg;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 2;

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-rollDeg * math.pi / 180);
    final pitchPx = (pitchDeg.clamp(-45.0, 45.0) / 45.0) * r * 0.75;
    canvas.translate(0, pitchPx);

    canvas.drawRect(
      Rect.fromLTWH(-r * 2, -r * 2, r * 4, r * 2),
      Paint()..color = const Color(0xFF3A8FD4),
    );
    canvas.drawRect(
      Rect.fromLTWH(-r * 2, 0, r * 4, r * 2),
      Paint()..color = const Color(0xFF8B5A2B),
    );
    canvas.drawLine(
      Offset(-r, 0),
      Offset(r, 0),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2,
    );
    canvas.restore();

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = _Bf.yellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    final wing = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(c.dx - r * 0.5, c.dy), Offset(c.dx - 5, c.dy), wing);
    canvas.drawLine(Offset(c.dx + 5, c.dy), Offset(c.dx + r * 0.5, c.dy), wing);
    canvas.drawCircle(c, 3.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _HorizonPainter old) =>
      old.rollDeg != rollDeg || old.pitchDeg != pitchDeg;
}

/// Heading / compass gauge driven by yaw.
class _HeadingGauge extends StatelessWidget {
  const _HeadingGauge({required this.yaw, required this.size});

  final double yaw;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _HeadingPainter(yawDeg: yaw)),
    );
  }
}

class _HeadingPainter extends CustomPainter {
  _HeadingPainter({required this.yawDeg});

  final double yawDeg;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 2;

    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF1A1A1A));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = _Bf.yellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-yawDeg * math.pi / 180);
    final tick = Paint()
      ..color = _Bf.text
      ..strokeWidth = 1.5;
    for (var i = 0; i < 36; i++) {
      final a = i * 10 * math.pi / 180;
      final long = i % 3 == 0;
      final inner = r - (long ? 11.0 : 6.0);
      canvas.drawLine(
        Offset(math.sin(a) * inner, -math.cos(a) * inner),
        Offset(math.sin(a) * (r - 2), -math.cos(a) * (r - 2)),
        tick,
      );
    }
    final craft = Path()
      ..moveTo(0, -12)
      ..lineTo(8, 10)
      ..lineTo(0, 5)
      ..lineTo(-8, 10)
      ..close();
    canvas.drawPath(craft, Paint()..color = _Bf.bad);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HeadingPainter old) => old.yawDeg != yawDeg;
}
