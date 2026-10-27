import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  Timer? _timer;
  final _rng = Random();
  final _scrollController = ScrollController();

  double _t = 0;
  int _tick = 0;

  double _roll = 0;
  double _pitch = 0;
  double _yaw = 0;
  double _alt = 12.4;
  double _battery = 15.2;
  int _gpsSats = 12;

  final List<String> _lines = <String>[];
  static const int _maxLines = 300;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (_paused) return;

      _t += 0.08;
      _tick++;

      final roll = sin(_t * 1.2) * 8;
      final pitch = cos(_t * 0.9) * 5;
      final yaw = (_t * 12) % 360;
      final alt = 12.4 + sin(_t * 0.3) * 0.4;
      final battery = (15.2 - _t * 0.001).clamp(14.0, 15.2);
      final sats = 11 + _rng.nextInt(3);

      final gx = -2.5 + _rng.nextDouble() * 0.8;
      final gy = -1.5 + _rng.nextDouble() * 0.6;
      final gz = -0.5 + _rng.nextDouble() * 0.4;
      final bp = 200800 + _rng.nextInt(120);
      final temp = 31.5 + _rng.nextDouble();
      final m1 = 1100 + _rng.nextInt(100);
      final m2 = 1100 + _rng.nextInt(100);
      final m3 = 1000 + _rng.nextInt(80);
      final m4 = 1000 + _rng.nextInt(80);

      setState(() {
        _roll = roll;
        _pitch = pitch;
        _yaw = yaw;
        _alt = alt;
        _battery = battery;
        _gpsSats = sats;

        // Bridge idea: don't print every sample — only selected lines.
        // Poll ~5 Hz (every 2–3 ticks) so the feed stays readable.
        if (_tick % 3 == 0) {
          _addLine(
            '[poll] s${230000 + _tick} ARM '
            'G ${gx.toStringAsFixed(2)} ${gy.toStringAsFixed(2)} ${gz.toStringAsFixed(2)} dps | '
            'R ${roll.toStringAsFixed(2)} P ${pitch.toStringAsFixed(2)} Y ${yaw.toStringAsFixed(2)} | '
            'BP $bp Pa T ${temp.toStringAsFixed(2)} C | '
            'Z ${alt.toStringAsFixed(2)} | '
            'AH en=0 act=0 | '
            'M $m1 $m2 $m3 $m4 us | pos=off',
          );
        }

        // Slower companion messages (like bridge GPS-focus prints)
        if (_tick % 8 == 0) {
          _addLine(
            '[MAG] ist ${140 + _rng.nextInt(10)} '
            '${-210 + _rng.nextInt(10)} ${-80 + _rng.nextInt(20)} mG ok',
          );
        }
        if (_tick % 8 == 2) {
          _addLine(
            '[VE] z=${(-2.2 - _rng.nextDouble() * 0.3).toStringAsFixed(2)} '
            'vz=${(-0.15 + _rng.nextDouble() * 0.1).toStringAsFixed(2)} '
            'a=${(-0.02 + _rng.nextDouble() * 0.02).toStringAsFixed(2)} '
            'age=${50 + _rng.nextInt(30)} h=1',
          );
        }
        if (_tick % 8 == 4) {
          _addLine(
            '[VEK] inn=${(0.08 + _rng.nextDouble() * 0.05).toStringAsFixed(2)} '
            'Pzz=0.08 Pvv=0.50 Pbb=0.03 '
            'ba=${(-0.05 + _rng.nextDouble() * 0.02).toStringAsFixed(2)} ok=1',
          );
        }
        if (_tick % 8 == 6) {
          _addLine(
            '[GPS] FIX lat_e7=100558525 lon_e7=763552685 '
            'sats=$sats hacc_mm=${4000 + _rng.nextInt(800)} '
            'vn=${-50 + _rng.nextInt(20)} ve=${20 + _rng.nextInt(20)} baud=230400',
          );
        }
      });

      _scrollToBottom();
    });
  }

  String _stamp() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    final ms = now.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  void _addLine(String body) {
    _lines.add('${_stamp()} -> $body');
    while (_lines.length > _maxLines) {
      _lines.removeAt(0);
    }
  }

  void _scrollToBottom() {
    if (_paused) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Compact telemetry strip (small on purpose)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _mini('Roll', '${_roll.toStringAsFixed(1)}°'),
              _mini('Pitch', '${_pitch.toStringAsFixed(1)}°'),
              _mini('Yaw', '${_yaw.toStringAsFixed(1)}°'),
              _mini('Alt', '${_alt.toStringAsFixed(1)} m'),
              _mini('Bat', '${_battery.toStringAsFixed(1)} V'),
              _mini('GPS', '$_gpsSats'),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 4),
          child: Row(
            children: [
              const Text(
                'Live feed',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Text(
                '${_lines.length} lines',
                style: const TextStyle(fontSize: 11, color: Color(0xFF9AA3AD)),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _paused = !_paused),
                child: Text(_paused ? 'Resume' : 'Pause'),
              ),
              TextButton(
                onPressed: () => setState(() => _lines.clear()),
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1114),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2E343C)),
            ),
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _lines.length,
              itemBuilder: (context, index) {
                final line = _lines[index];
                return Text(
                  line,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.35,
                    color: _colorFor(line),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Color _colorFor(String line) {
    if (line.contains('[GPS]')) return const Color(0xFF7DCEA0);
    if (line.contains('[MAG]')) return const Color(0xFF85C1E9);
    if (line.contains('[VE]') || line.contains('[VEK]')) {
      return const Color(0xFFF9E79F);
    }
    if (line.contains('[poll]')) return const Color(0xFFB7C0C9);
    return const Color(0xFFB7C0C9);
  }

  Widget _mini(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF252A30),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(fontSize: 11, color: Color(0xFF9AA3AD)),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}