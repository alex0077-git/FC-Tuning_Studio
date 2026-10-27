import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class _MockLog {
  _MockLog({
    required this.index,
    required this.startedAt,
    required this.sizeBytes,
    this.downloaded = false,
    this.localPath,
  });

  final int index;
  final DateTime startedAt;
  final int sizeBytes;
  bool downloaded;
  String? localPath;

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

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

  bool _showGraphs = false;
  double _chartX = 0;
  final Queue<FlSpot> _actual = Queue<FlSpot>();
  final Queue<FlSpot> _target = Queue<FlSpot>();
  final Queue<FlSpot> _termP = Queue<FlSpot>();
  final Queue<FlSpot> _termI = Queue<FlSpot>();
  final Queue<FlSpot> _termD = Queue<FlSpot>();
  static const int _maxPoints = 50;

  late List<_MockLog> _logs;
  int? _downloadingIndex;
  double _downloadProgress = 0;

  @override
  void initState() {
    super.initState();
    _logs = [
      _MockLog(
        index: 1,
        startedAt: DateTime.now().subtract(const Duration(hours: 5)),
        sizeBytes: 248320,
      ),
      _MockLog(
        index: 2,
        startedAt: DateTime.now().subtract(const Duration(hours: 2)),
        sizeBytes: 512000,
      ),
      _MockLog(
        index: 3,
        startedAt: DateTime.now().subtract(const Duration(minutes: 40)),
        sizeBytes: 98304,
      ),
    ];

    _timer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      _t += 0.08;
      _tick++;

      final roll = sin(_t * 1.2) * 8;
      final pitch = cos(_t * 0.9) * 5;
      final yaw = (_t * 12) % 360;
      final alt = 12.4 + sin(_t * 0.3) * 0.4;
      final battery = (15.2 - _t * 0.001).clamp(14.0, 15.2);
      final sats = 11 + _rng.nextInt(3);
      final targetRoll = sin(_t * 1.2 + 0.25) * 8;

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

        _chartX += 1;
        _push(_actual, roll);
        _push(_target, targetRoll);
        _push(_termP, roll * 0.15);
        _push(_termI, sin(_t) * 0.02);
        _push(_termD, cos(_t * 2) * 0.01);

        if (!_paused) {
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
        }
      });

      if (!_paused) _scrollToBottom();
    });
  }

  void _push(Queue<FlSpot> q, double y) {
    q.addLast(FlSpot(_chartX, y));
    while (q.length > _maxPoints) {
      q.removeFirst();
    }
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  Future<void> _download(_MockLog log) async {
    setState(() {
      _downloadingIndex = log.index;
      _downloadProgress = 0;
    });

    for (var i = 1; i <= 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      setState(() => _downloadProgress = i / 10);
    }

    setState(() {
      log.downloaded = true;
      log.localPath = 'logs/flight_${log.index}.bin';
      _downloadingIndex = null;
      _downloadProgress = 0;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloaded log #${log.index} → ${log.localPath}')),
    );
  }

  Future<void> _exportCsv(_MockLog log) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    final path = 'logs/flight_${log.index}.csv';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exported CSV → $path')),
    );
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
        SwitchListTile(
          dense: true,
          activeColor: AppColors.accent,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          title: const Text(
            'Live graphs',
            style: TextStyle(fontSize: 13, color: AppColors.text),
          ),
          value: _showGraphs,
          onChanged: (v) => setState(() => _showGraphs = v),
        ),
        if (_showGraphs) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Target vs Actual (roll)',
                style: TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ),
          ),
          SizedBox(
            height: 90,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _chart([
                (AppColors.accent, _actual),
                (Colors.white54, _target),
              ]),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'PID terms',
                style: TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ),
          ),
          SizedBox(
            height: 90,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _chart([
                (Colors.lightBlue, _termP),
                (Colors.orange, _termI),
                (Colors.greenAccent, _termD),
              ]),
            ),
          ),
        ],
        const Divider(height: 1, color: AppColors.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _paused ? AppColors.warning : AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Live feed',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_lines.length} lines',
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
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
          flex: 3,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1114),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
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
        const Divider(height: 1, color: AppColors.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: Row(
            children: [
              const Text(
                'Onboard logs',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const Spacer(),
              Text(
                '${_logs.length} files',
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
        ),
        if (_downloadingIndex != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: LinearProgressIndicator(
              value: _downloadProgress,
              color: AppColors.accent,
              backgroundColor: AppColors.surface2,
            ),
          ),
        SizedBox(
          height: 140,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            itemCount: _logs.length,
            itemBuilder: (context, i) {
              final log = _logs[i];
              final busy = _downloadingIndex == log.index;
              return Card(
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: AppColors.border),
                ),
                child: ListTile(
                  dense: true,
                  title: Text(
                    'Log #${log.index}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${log.startedAt.toLocal().toString().substring(0, 19)} · ${log.sizeLabel}'
                    '${log.downloaded ? ' · saved' : ''}',
                    style: const TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      TextButton(
                        onPressed: busy || _downloadingIndex != null
                            ? null
                            : () => _download(log),
                        child: Text(busy ? '…' : 'Download'),
                      ),
                      TextButton(
                        onPressed:
                            log.downloaded ? () => _exportCsv(log) : null,
                        child: const Text('CSV'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _chart(List<(Color, Queue<FlSpot>)> series) {
    return LineChart(
      LineChartData(
        minY: null,
        maxY: null,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          for (final (color, q) in series)
            LineChartBarData(
              spots: q.isEmpty ? [const FlSpot(0, 0)] : q.toList(),
              isCurved: true,
              color: color,
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
    );
  }

  Color _colorFor(String line) {
    if (line.contains('[GPS]')) return const Color(0xFF7DCEA0);
    if (line.contains('[MAG]')) return const Color(0xFF85C1E9);
    if (line.contains('[VE]') || line.contains('[VEK]')) {
      return const Color(0xFFF9E79F);
    }
    return const Color(0xFFB7C0C9);
  }

  Widget _mini(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}