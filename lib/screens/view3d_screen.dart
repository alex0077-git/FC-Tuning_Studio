import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'drone_3d_host.dart';

enum _ViewMode { live, replay, preview }

class View3dScreen extends StatefulWidget {
  const View3dScreen({super.key});

  @override
  State<View3dScreen> createState() => _View3dScreenState();
}

class _View3dScreenState extends State<View3dScreen> {
  Timer? _timer;
  _ViewMode _mode = _ViewMode.live;

  double _t = 0;
  double _rawYaw = 0;

  double _roll = 0;
  double _pitch = 0;
  double _yaw = 0;

  double _yawOffset = 0;
  double _timeline = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (_mode != _ViewMode.live) return;
      _t += 0.04;
      final rawRoll = math.sin(_t * 1.2) * 18;
      final rawPitch = math.cos(_t * 0.9) * 12;
      _rawYaw = (_t * 25) % 360;

      setState(() {
        _roll += (rawRoll - _roll) * 0.35;
        _pitch += (rawPitch - _pitch) * 0.35;
        final targetYaw = _rawYaw - _yawOffset;
        _yaw += (targetYaw - _yaw) * 0.35;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              const Text(
                '3D View',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            children: [
              for (final m in _ViewMode.values)
                ChoiceChip(
                  label: Text(m.name[0].toUpperCase() + m.name.substring(1)),
                  selected: _mode == m,
                  selectedColor: const Color(0xFF2F7BFF),
                  onSelected: m == _ViewMode.preview
                      ? null
                      : (_) {
                          setState(() => _mode = m);
                          if (m == _ViewMode.replay) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Replay needs a downloaded log — next phase',
                                ),
                              ),
                            );
                          }
                        },
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Roll: ${_roll.toStringAsFixed(1)}  '
          'Pitch: ${_pitch.toStringAsFixed(1)}  '
          'Yaw: ${_yaw.toStringAsFixed(1)}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF9AA3AD)),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Stack(
            children: [
              ClipRRect(
                child: Drone3dHost(
                  rollDeg: _roll,
                  pitchDeg: _pitch,
                  yawDeg: _yaw,
                ),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: _Horizon(rollDeg: _roll, pitchDeg: _pitch),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
          child: Row(
            children: [
              const Icon(Icons.play_arrow, size: 22),
              Expanded(
                child: Slider(
                  value: _timeline,
                  onChanged: (v) => setState(() => _timeline = v),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _yawOffset = _rawYaw),
                child: const Text('Reset yaw'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Horizon extends StatelessWidget {
  const _Horizon({required this.rollDeg, required this.pitchDeg});
  final double rollDeg;
  final double pitchDeg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF9AA3AD), width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 8),
        ],
      ),
      child: ClipOval(
        child: Transform.rotate(
          angle: rollDeg * math.pi / 180,
          child: CustomPaint(painter: _HorizonPainter(pitchDeg)),
        ),
      ),
    );
  }
}

class _HorizonPainter extends CustomPainter {
  _HorizonPainter(this.pitchDeg);
  final double pitchDeg;

  @override
  void paint(Canvas canvas, Size size) {
    final cy =
        size.height / 2 + (pitchDeg.clamp(-45, 45) / 45) * (size.height / 4);
    canvas.drawRect(
      Rect.fromLTRB(0, 0, size.width, cy),
      Paint()..color = const Color(0xFF3A6EA5),
    );
    canvas.drawRect(
      Rect.fromLTRB(0, cy, size.width, size.height),
      Paint()..color = const Color(0xFF5A4632),
    );
    final cross = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.4;
    canvas.drawLine(Offset(size.width * 0.18, size.height / 2),
        Offset(size.width * 0.82, size.height / 2), cross);
    canvas.drawLine(Offset(size.width / 2, size.height * 0.32),
        Offset(size.width / 2, size.height * 0.68), cross);
  }

  @override
  bool shouldRepaint(covariant _HorizonPainter oldDelegate) =>
      oldDelegate.pitchDeg != pitchDeg;
}