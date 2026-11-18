import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../link/mav_session.dart';
import '../logs/live_log_assembler.dart';
import '../theme/app_theme.dart';
import 'drone_3d_host.dart';

/// AltHold altitude view.
///
/// Left: official Betaflight `quad_x.gltf` + meter tape.
/// Right: altitude history + Target / Current cards (reference layout).
/// Height from active [MavSession] live-log `Z` (sim or real G20).
class Althold3dScreen extends StatefulWidget {
  const Althold3dScreen({super.key, this.session});

  final MavSession? session;

  @override
  State<Althold3dScreen> createState() => _Althold3dScreenState();
}

class _HistSample {
  const _HistSample({
    required this.t,
    required this.zM,
    required this.tgtM,
  });

  final double t; // seconds since attach
  final double zM;
  final double? tgtM;
}

class _Althold3dScreenState extends State<Althold3dScreen> {
  StreamSubscription? _liveSub;
  StreamSubscription? _attSub;

  bool _live = false;
  bool _altHold = false;
  bool _prevAltHold = false;

  double _pitch = 0;
  double _roll = 0;
  double _yaw = 0;
  double _zM = 0.05;
  double? _latchM;

  final Queue<_HistSample> _hist = Queue<_HistSample>();
  DateTime? _histOrigin;
  static const _histWindowS = 30.0;

  @override
  void initState() {
    super.initState();
    _attach(widget.session);
  }

  @override
  void didUpdateWidget(covariant Althold3dScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      _attach(widget.session);
    }
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    _attSub?.cancel();
    super.dispose();
  }

  void _attach(MavSession? session) {
    _liveSub?.cancel();
    _attSub?.cancel();
    _live = session != null;
    _hist.clear();
    _histOrigin = session == null ? null : DateTime.now();

    if (session == null) {
      if (mounted) {
        setState(() {
          _altHold = false;
          _prevAltHold = false;
          _zM = 0.05;
          _latchM = null;
          _pitch = 0;
          _roll = 0;
          _yaw = 0;
        });
      }
      return;
    }

    final last = session.lastAttitude;
    if (last != null) {
      _pitch = last.pitchDeg;
      _roll = last.rollDeg;
      _yaw = last.yawDeg;
    }

    _attSub = session.attitudes.listen((a) {
      if (!mounted) return;
      setState(() {
        _pitch = a.pitchDeg;
        _roll = a.rollDeg;
        _yaw = a.yawDeg;
      });
    });

    _liveSub = session.liveLogLines.listen((line) {
      if (!mounted) return;
      final f = LiveLogFields.parse(line);
      final act = f.ahAct != null && f.ahAct != 0;
      setState(() {
        if (f.zM != null) _zM = f.zM!;
        _altHold = act;
        if (act && !_prevAltHold) {
          _latchM = f.tgt ?? f.zM ?? _zM;
        } else if (!act) {
          _latchM = null;
        }
        _prevAltHold = act;
        _pushHist();
      });
    });
  }

  void _pushHist() {
    final origin = _histOrigin;
    if (origin == null) return;
    final t = DateTime.now().difference(origin).inMilliseconds / 1000.0;
    _hist.addLast(
      _HistSample(
        t: t,
        zM: _zM,
        tgtM: _altHold ? _latchM : null,
      ),
    );
    while (_hist.isNotEmpty && t - _hist.first.t > _histWindowS) {
      _hist.removeFirst();
    }
  }

  (double, double) _span() {
    var hi = 4.0;
    hi = math.max(hi, _zM + 1.0);
    if (_latchM != null) hi = math.max(hi, _latchM! + 1.0);
    return (0.0, hi);
  }

  @override
  Widget build(BuildContext context) {
    if (!_live) {
      return const ColoredBox(
        color: Color(0xFF141414),
        child: Center(
          child: Text(
            'Connect to stream AltHold view',
            style: TextStyle(color: Color(0xFF9A9A9A), fontSize: 13),
          ),
        ),
      );
    }

    final span = _span();
    final targetM = _altHold ? _latchM : null;

    return ColoredBox(
      color: const Color(0xFF0E0E0E),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Left — BF craft + meter (unchanged scene).
            Expanded(
              flex: 11,
              child: _panel(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Drone3dHost(
                        key: const ValueKey('althold-bf-quad'),
                        rollDeg: _roll,
                        pitchDeg: _pitch,
                        yawDeg: _yaw,
                        viewMode: Drone3dViewMode.side,
                        heightM: _zM,
                        latchM: targetM,
                        scaleLo: span.$1,
                        scaleHi: span.$2,
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _AltitudeScalePainter(
                            lo: span.$1,
                            hi: span.$2,
                            heightM: _zM,
                            latchM: targetM,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Right — history + Target/Current cards.
            Expanded(
              flex: 9,
              child: Column(
                children: [
                  Expanded(
                    flex: 5,
                    child: _panel(
                      child: _AltitudeHistoryChart(
                        samples: _hist.toList(growable: false),
                        windowS: _histWindowS,
                        hiM: span.$2,
                        currentM: _zM,
                        targetM: targetM,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        Expanded(
                          child: _ValueCard(
                            label: 'TARGET',
                            valueM: targetM,
                            color: AppColors.cta,
                            icon: Icons.gps_fixed_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ValueCard(
                            label: 'CURRENT',
                            valueM: _zM,
                            color: AppColors.success,
                            icon: Icons.graphic_eq_rounded,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: child,
      ),
    );
  }
}

class _ValueCard extends StatelessWidget {
  const _ValueCard({
    required this.label,
    required this.valueM,
    required this.color,
    required this.icon,
  });

  final String label;
  final double? valueM;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final text = valueM == null ? '—' : valueM!.toStringAsFixed(2);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color.withValues(alpha: 0.9)),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.85),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: text,
                      style: TextStyle(
                        color: color,
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (valueM != null)
                      TextSpan(
                        text: ' m',
                        style: TextStyle(
                          color: color.withValues(alpha: 0.7),
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AltitudeHistoryChart extends StatelessWidget {
  const _AltitudeHistoryChart({
    required this.samples,
    required this.windowS,
    required this.hiM,
    required this.currentM,
    required this.targetM,
  });

  final List<_HistSample> samples;
  final double windowS;
  final double hiM;
  final double currentM;
  final double? targetM;

  @override
  Widget build(BuildContext context) {
    final nowT = samples.isEmpty ? 0.0 : samples.last.t;
    final minX = nowT - windowS;
    final actual = <FlSpot>[
      for (final s in samples)
        if (s.t >= minX) FlSpot(s.t - nowT, s.zM),
    ];
    final target = <FlSpot>[
      for (final s in samples)
        if (s.t >= minX && s.tgtM != null) FlSpot(s.t - nowT, s.tgtM!),
    ];
    if (actual.isEmpty) actual.add(const FlSpot(0, 0));

    final tgtLabel = targetM == null ? '—' : targetM!.toStringAsFixed(2);
    final curLabel = currentM.toStringAsFixed(2);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ALTITUDE HISTORY',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
          Text(
            'Height vs time',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LineChart(
              LineChartData(
                minX: -windowS,
                maxX: 0,
                minY: 0,
                maxY: hiM,
                clipData: const FlClipData.all(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: 1,
                  verticalInterval: 5,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: Colors.white.withValues(alpha: 0.06),
                    strokeWidth: 1,
                  ),
                  getDrawingVerticalLine: (_) => FlLine(
                    color: Colors.white.withValues(alpha: 0.05),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: const Color(0xFF2A2A2A)),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 1,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toStringAsFixed(0)}m',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: 10,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toStringAsFixed(0)}s',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ),
                ),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  if (target.length >= 2)
                    LineChartBarData(
                      spots: target,
                      isCurved: false,
                      color: AppColors.cta,
                      barWidth: 2.2,
                      dotData: const FlDotData(show: false),
                    ),
                  LineChartBarData(
                    spots: actual,
                    isCurved: true,
                    curveSmoothness: 0.25,
                    color: AppColors.success,
                    barWidth: 2.4,
                    dotData: const FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _legendDot(AppColors.cta),
              const SizedBox(width: 6),
              Text(
                'Target $tgtLabel m',
                style: TextStyle(
                  color: AppColors.cta.withValues(alpha: 0.9),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 16),
              _legendDot(AppColors.success),
              const SizedBox(width: 6),
              Text(
                'Actual $curLabel m',
                style: TextStyle(
                  color: AppColors.success.withValues(alpha: 0.9),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color c) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );
}

/// Left meter + Target/Current marks only — craft comes from BF WebView.
/// Pads + meter mapping must stay identical to `drone_scene.html` side ortho.
class _AltitudeScalePainter extends CustomPainter {
  _AltitudeScalePainter({
    required this.lo,
    required this.hi,
    required this.heightM,
    this.latchM,
  });

  final double lo;
  final double hi;
  final double heightM;
  final double? latchM;

  static const _targetColor = AppColors.cta;
  static const _currentColor = AppColors.success;

  /// Keep in sync with drone_scene.html TOP_PAD / BOT_PAD.
  static const topPad = 56.0;
  static const botPad = 52.0;
  static const mToScene = 20.0;
  static const sideYawDeg = 30.0;
  static const sideElevDeg = 22.0;
  /// Where guides end — angled BF camera places craft slightly right of panel center.
  static const guideEndFrac = 0.58;

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 70.0;
    final usable = size.height - topPad - botPad;
    final guideEndX = size.width * guideEndFrac;
    final sx = leftPad - 16;
    final h = size.height;

    double yOf(double m) {
      final t = ((m - lo) / (hi - lo)).clamp(0.0, 1.0);
      return topPad + usable * (1.0 - t);
    }

    /// Screen Y under the same ortho yaw/elev as drone_scene.html (T/C only).
    double yMark(double m) {
      final yLo = lo * mToScene;
      final yHi = math.max(hi, lo + 0.5) * mToScene;
      final usableW = math.max(yHi - yLo, mToScene * 0.5);
      final usablePx = math.max(h - topPad - botPad, 1.0);
      final fullH = usableW * (h / usablePx);
      final worldBottom = yLo - (botPad / h) * fullH;
      final worldTop = yHi + (topPad / h) * fullH;
      final midY = (worldBottom + worldTop) * 0.5;
      final halfH = (worldTop - worldBottom) * 0.5;

      final yaw = sideYawDeg * math.pi / 180;
      final elev = sideElevDeg * math.pi / 180;
      final sy = math.sin(yaw);
      final cy = math.cos(yaw);
      final ce = math.cos(elev);

      final zx = sy * ce;
      final zz = cy * ce;
      var xx = zz;
      var xz = -zx;
      final xLen = math.sqrt(xx * xx + xz * xz);
      if (xLen > 1e-9) {
        xx /= xLen;
        xz /= xLen;
      }
      final yy = zz * xx - zx * xz;
      final camY = (m * mToScene - midY) * yy;
      return (h * 0.5) * (1.0 - camY / halfH);
    }

    // Soft vignette so BF canvas edges blend with the card.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(leftPad + 8, 0),
          const [Color(0xE0141414), Color(0x00141414)],
        ),
    );

    canvas.drawLine(
      Offset(sx, topPad),
      Offset(sx, size.height - botPad),
      Paint()
        ..color = const Color(0xFFF0F0F0)
        ..strokeWidth = 1.7,
    );

    final tp = TextPainter(textDirection: TextDirection.ltr);
    final first = lo.ceilToDouble();
    for (var m = first; m <= hi + 1e-6; m += 1.0) {
      final y = yOf(m);
      canvas.drawLine(
        Offset(sx - 12, y),
        Offset(sx, y),
        Paint()
          ..color = const Color(0xFFE8E8E8)
          ..strokeWidth = 1.4,
      );
      tp.text = TextSpan(
        text: '${m.toStringAsFixed(0)} m',
        style: const TextStyle(
          color: Color(0xFFE8E8E8),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(10, y - tp.height / 2));
    }

    void mark({
      required double y,
      required Color color,
      required String label,
      required bool diamond,
      required double labelBias,
    }) {
      // Guide runs out to the visible BF craft (angled view sits right of center).
      canvas.drawLine(
        Offset(sx, y),
        Offset(guideEndX, y),
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..strokeWidth = 1.3,
      );
      canvas.drawCircle(
        Offset(guideEndX, y),
        3.2,
        Paint()..color = color.withValues(alpha: 0.95),
      );
      if (diamond) {
        final path = Path()
          ..moveTo(sx, y - 6)
          ..lineTo(sx + 6, y)
          ..lineTo(sx, y + 6)
          ..lineTo(sx - 6, y)
          ..close();
        canvas.drawPath(path, Paint()..color = color);
      } else {
        canvas.drawCircle(Offset(sx, y), 5.0, Paint()..color = color);
        canvas.drawCircle(
          Offset(sx, y),
          5.0,
          Paint()
            ..color = const Color(0xFF141414)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
      }
      tp.text = TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      );
      tp.layout();
      var ly = y + labelBias;
      if (ly < topPad) ly = y + 6;
      if (ly + tp.height > size.height - botPad) ly = y - tp.height - 4;
      tp.paint(canvas, Offset(sx + 10, ly));
    }

    if (latchM != null) {
      mark(
        y: yMark(latchM!),
        color: _targetColor,
        label: 'T ${latchM!.toStringAsFixed(2)} m',
        diamond: true,
        labelBias: -16,
      );
    }
    mark(
      y: yMark(heightM),
      color: _currentColor,
      label: 'C ${heightM.toStringAsFixed(2)} m',
      diamond: false,
      labelBias: 6,
    );
  }

  @override
  bool shouldRepaint(covariant _AltitudeScalePainter old) =>
      old.lo != lo ||
      old.hi != hi ||
      old.heightM != heightM ||
      old.latchM != latchM;
}
