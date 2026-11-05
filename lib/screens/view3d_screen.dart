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

  double _roll = 0;
  double _pitch = 0;
  double _yaw = 0;
  double _gx = 0;
  double _gy = 0;
  double _gz = 0;
  bool _liveFromFc = false;
  bool _armed = false;
  LiveLogFields? _fields;

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
    _attSub = null;
    _hbSub = null;
    _liveSub = null;
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
        });
      }
      return;
    }

    _armed = session.armed;
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
      setState(() => _fields = LiveLogFields.parse(line));
    });
    _attSub = session.attitudes.listen((a) {
      if (!mounted) return;
      setState(() {
        _roll = a.rollDeg;
        _pitch = a.pitchDeg;
        _yaw = a.yawDeg;
        // Gyro rates from ATTITUDE (rad/s → dps).
        _gx = a.rollspeed * 180 / math.pi;
        _gy = a.pitchspeed * 180 / math.pi;
        _gz = a.yawspeed * 180 / math.pi;
      });
    });
  }

  @override
  void dispose() {
    _attSub?.cancel();
    _hbSub?.cancel();
    _liveSub?.cancel();
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

    final viewport = _BfViewport(
      roll: _roll,
      pitch: _pitch,
      yaw: _yaw,
      yawLabel: _yawLabel,
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
    );

    if (g20.landscape) {
      return ColoredBox(
        color: _Bf.bg,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: viewport),
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
          Expanded(flex: 2, child: sidebar),
        ],
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
  });

  final double roll;
  final double pitch;
  final double yaw;
  final double yawLabel;

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
  });

  final double roll;
  final double pitch;
  final double yaw;
  final double gx;
  final double gy;
  final double gz;
  final bool armed;
  final LiveLogFields? fields;

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
              _row('Latitude', '—'),
              _row('Longitude', '—'),
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
              _row('Battery voltage', '—'),
              _row('Capacity drawn', '—'),
              _row('Current draw', '—'),
              _row('RSSI', '—'),
              _row('MCU', '—'),
              _row(
                'Temperature',
                fields?.tempC != null
                    ? '${fields!.tempC!.toStringAsFixed(1)} °C'
                    : '—',
              ),
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
