import 'dart:async';
import 'dart:collection';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../layout/g20_metrics.dart';
import '../link/mav_session.dart';
import '../logs/byte_cli_transport.dart';
import '../logs/flight_log_store.dart';
import '../logs/live_log_assembler.dart';
import '../logs/mav_sd_cli_transport.dart';
import '../logs/sd_cli_transport.dart';
import '../logs/sd_flight_store.dart';
import '../logs/sd_log_client.dart';
import '../logs/sd_log_protocol.dart';
import '../mavlink/mavlink_v2.dart';
import '../theme/app_theme.dart';

class _ChartSeries {
  const _ChartSeries(this.label, this.color, this.spots);
  final String label;
  final Color color;
  final Queue<FlSpot> spots;
}

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key, this.session, this.cliTransport});

  final MavSession? session;

  /// Optional USB VCP CLI. When null, radio uses STATUSTEXT `#`/`$` tunnel.
  final ByteCliTransport? cliTransport;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  StreamSubscription<String>? _liveSub;
  StreamSubscription<Heartbeat>? _hbSub;
  StreamSubscription<Attitude>? _attSub;
  final _scrollController = ScrollController();
  final _feedController = ScrollController();
  final _liveStore = FlightLogStore();
  final _sdStore = SdFlightStore();
  late SdLogClient _sdClient;

  bool _armed = false;
  bool _live = false;
  bool _paused = false;
  bool _showGraphs = true;
  LiveLogFields? _fields;

  final List<String> _lines = <String>[];
  static const int _maxLines = 300;

  double _chartX = 0;
  final Queue<FlSpot> _rollQ = Queue<FlSpot>();
  final Queue<FlSpot> _pitchQ = Queue<FlSpot>();
  final Queue<FlSpot> _yawQ = Queue<FlSpot>();
  final Queue<FlSpot> _gxQ = Queue<FlSpot>();
  final Queue<FlSpot> _gyQ = Queue<FlSpot>();
  final Queue<FlSpot> _gzQ = Queue<FlSpot>();
  static const int _maxPoints = 60;
  DateTime _lastGraphAt = DateTime.fromMillisecondsSinceEpoch(0);

  List<SavedFlightLog> _sessions = [];
  List<SdFlightEntry> _sdEntries = [];
  bool _busy = false;
  bool _sdBusy = false;
  String? _busyName;
  int _liveCount = 0;
  String? _sdStatus;

  bool get _sdAvailable => _sdClient.available;

  SdCliTransport? _buildSdTransport() {
    if (widget.cliTransport != null) return widget.cliTransport;
    final s = widget.session;
    if (s != null && s.isConnected) return MavSdCliTransport(s);
    return null;
  }

  void _rebuildSdClient() {
    _sdClient = SdLogClient(_buildSdTransport());
  }

  @override
  void initState() {
    super.initState();
    _rebuildSdClient();
    _attach(widget.session);
    _refreshSessions();
    if (_sdAvailable) {
      unawaited(_refreshSdList());
    } else {
      _sdStatus = 'Connect to list / download SD flights';
    }
  }

  @override
  void didUpdateWidget(covariant LogsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session ||
        oldWidget.cliTransport != widget.cliTransport) {
      _rebuildSdClient();
      if (oldWidget.session != widget.session) {
        _attach(widget.session);
      }
      if (_sdAvailable) {
        unawaited(_refreshSdList());
      } else {
        setState(() {
          _sdStatus = 'Connect to list / download SD flights';
        });
      }
    }
  }

  Future<void> _refreshSessions() async {
    try {
      final list = await _liveStore.listSaved();
      if (!mounted) return;
      setState(() => _sessions = list);
    } catch (_) {}
  }

  void _attach(MavSession? session) {
    _liveSub?.cancel();
    _hbSub?.cancel();
    _attSub?.cancel();
    _liveSub = null;
    _hbSub = null;
    _attSub = null;
    _live = session != null;
    if (session == null) {
      if (mounted) setState(() {});
      return;
    }

    _hbSub = session.heartbeats.listen((hb) {
      _armed = hb.armed;
      if (mounted) setState(() {});
    });

    _attSub = session.attitudes.listen((a) {
      if (!mounted || !_showGraphs) return;
      final now = DateTime.now();
      if (now.difference(_lastGraphAt) < const Duration(milliseconds: 80)) {
        return;
      }
      _lastGraphAt = now;
      _chartX += 1;
      _push(_rollQ, a.rollDeg);
      _push(_pitchQ, a.pitchDeg);
      _push(_yawQ, a.yawDeg);
      _push(_gxQ, a.rollspeed * 180 / 3.141592653589793);
      _push(_gyQ, a.pitchspeed * 180 / 3.141592653589793);
      _push(_gzQ, a.yawspeed * 180 / 3.141592653589793);
      setState(() {});
    });

    _liveSub = session.liveLogLines.listen((line) {
      if (!mounted) return;
      _liveCount += 1;
      _fields = LiveLogFields.parse(line);
      _liveStore.addLiveLine(line);
      if (!_paused) {
        _addLine(line);
        _scrollFeed();
      }
      setState(() {});
    });
  }

  void _push(Queue<FlSpot> q, double y) {
    q.addLast(FlSpot(_chartX, y));
    while (q.length > _maxPoints) {
      q.removeFirst();
    }
  }

  String _stamp() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:'
        '${n.minute.toString().padLeft(2, '0')}:'
        '${n.second.toString().padLeft(2, '0')}.'
        '${n.millisecond.toString().padLeft(3, '0')}';
  }

  void _addLine(String body) {
    _lines.add('${_stamp()}  $body');
    while (_lines.length > _maxLines) {
      _lines.removeAt(0);
    }
  }

  void _scrollFeed() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_feedController.hasClients) return;
      _feedController.jumpTo(_feedController.position.maxScrollExtent);
    });
  }

  Future<void> _saveLiveSession() async {
    if (_liveStore.bufferRows == 0) {
      _toast('No Live Log lines buffered');
      return;
    }
    setState(() => _busy = true);
    try {
      final saved = await _liveStore.saveAndContinue(tag: 'LIVESESS');
      await _refreshSessions();
      if (!mounted) return;
      _toast(
        saved == null
            ? 'Nothing saved'
            : 'Saved live session ${saved.name} (${saved.rows} lines)',
      );
    } catch (e) {
      _toast('Save failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadLiveSession(SavedFlightLog log) async {
    setState(() {
      _busy = true;
      _busyName = log.name;
    });
    try {
      final out = await _liveStore.exportToDownloads(log);
      await Clipboard.setData(ClipboardData(text: out.path));
      if (!mounted) return;
      _toast('Live session → ${out.path}');
    } catch (e) {
      _toast('Download failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyName = null;
        });
      }
    }
  }

  Future<void> _refreshSdList() async {
    if (_armed) {
      _toast('Disarm first');
      return;
    }
    _rebuildSdClient();
    if (!_sdAvailable) {
      setState(() => _sdStatus = 'Connect to list / download SD flights');
      return;
    }
    setState(() {
      _sdBusy = true;
      _sdStatus = 'Listing…';
    });
    final r = await _sdClient.list();
    if (!mounted) return;
    setState(() {
      _sdBusy = false;
      if (r.outcome == SdLogOutcome.ok) {
        _sdEntries = r.entries;
        _sdStatus = '${r.entries.length} flight(s)';
      } else if (r.outcome == SdLogOutcome.empty) {
        _sdEntries = [];
        _sdStatus = 'no logs';
      } else {
        _sdStatus = r.message ?? r.outcome.name;
      }
    });
  }

  Future<void> _downloadSd(SdFlightEntry e) async {
    if (_armed) {
      _toast('Disarm first');
      return;
    }
    _rebuildSdClient();
    if (!_sdAvailable) {
      _toast('Connect first');
      return;
    }
    setState(() {
      _sdBusy = true;
      _sdStatus = 'Downloading ${e.file.isNotEmpty ? e.file : 'id ${e.id}'}…';
    });
    final r = await _sdClient.dump(e.id);
    if (!mounted) return;
    if (!r.ok || r.csvBody == null) {
      setState(() {
        _sdBusy = false;
        _sdStatus = r.message ?? r.outcome.name;
      });
      _toast('Download failed: ${r.message ?? r.outcome.name}');
      return;
    }
    try {
      // Keep FC CSV as-is (header + rows from log dump).
      final file = await _sdStore.saveCsv(
        id: e.id,
        preferredName: e.file.isNotEmpty
            ? e.file
            : 'LOG${e.id.toString().padLeft(4, '0')}.CSV',
        csvBody: r.csvBody!,
      );
      final out = await _sdStore.exportToDownloads(file);
      await Clipboard.setData(ClipboardData(text: out.path));
      if (!mounted) return;
      setState(() {
        _sdBusy = false;
        _sdStatus = 'Saved ${out.uri.pathSegments.last}';
      });
      _toast('Flight CSV → ${out.path}');
    } catch (err) {
      setState(() {
        _sdBusy = false;
        _sdStatus = 'Save failed';
      });
      _toast('Save failed: $err');
    }
  }

  Future<void> _wipeSd() async {
    if (_armed) {
      _toast('Disarm first');
      return;
    }
    _rebuildSdClient();
    if (!_sdAvailable) {
      _toast('Connect first');
      return;
    }
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Wipe all SD logs?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Type WIPE to confirm. This erases every flight on the card.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(hintText: 'WIPE'),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (ctrl.text.trim() == 'WIPE') {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Wipe'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (ok != true) return;

    setState(() {
      _sdBusy = true;
      _sdStatus = 'Wiping…';
    });
    final r = await _sdClient.wipe();
    if (!mounted) return;
    setState(() => _sdBusy = false);
    if (r.ok) {
      _sdEntries = [];
      _sdStatus = 'LOG wiped';
      _toast('All SD logs wiped');
    } else {
      _sdStatus = r.message ?? r.outcome.name;
      _toast('Wipe failed: $_sdStatus');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    _hbSub?.cancel();
    _attSub?.cancel();
    _scrollController.dispose();
    _feedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g20 = G20Metrics.of(context);
    final f = _fields;
    final sdActionsEnabled = !_armed && !_sdBusy && _sdAvailable;

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(g20.pagePad, 6, g20.pagePad, 12),
      children: [
        // ---- Live Log (STATUSTEXT) ----
        Text(
          'Live Log',
          style: TextStyle(
            fontSize: g20.titleSize,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        const Text(
          'STATUSTEXT +/= stream — not SD flight files',
          style: TextStyle(fontSize: 10.5, color: AppColors.muted),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _mini(
              'Armed',
              _armed ? 'Yes' : (f?.armed == true ? 'Yes' : 'No'),
            ),
            _mini('Mode', f?.mode ?? '—'),
            _mini('Seq', f?.seq?.toString() ?? '—'),
            _mini('R', _fmt(f?.roll, '°')),
            _mini('P', _fmt(f?.pitch, '°')),
            _mini('Y', _fmt(f?.yaw, '°')),
            _mini(
              'G',
              f?.gx == null
                  ? '—'
                  : '${f!.gx!.toStringAsFixed(2)} '
                      '${f.gy!.toStringAsFixed(2)} '
                      '${f.gz!.toStringAsFixed(2)}',
            ),
            _mini(
              'BP',
              f?.bpPa != null ? '${f!.bpPa!.toStringAsFixed(0)} Pa' : '—',
            ),
            _mini('T', _fmt(f?.tempC, ' C')),
            _mini('Z', _fmt(f?.zM, ' m')),
            _mini('Zraw', _fmt(f?.zRaw, ' m')),
            _mini(
              'AH',
              f == null ? '—' : 'en=${f.ahEn ?? 0} act=${f.ahAct ?? 0}',
            ),
            _mini('tgt', _fmt(f?.tgt)),
            _mini('err', _fmt(f?.err)),
            _mini('dU', _fmt(f?.dU)),
            _mini('i', _fmt(f?.iUs)),
            _mini(
              'M',
              f?.m1 == null
                  ? '—'
                  : '${f!.m1} ${f.m2} ${f.m3} ${f.m4}',
            ),
            _mini(
              'GPS',
              f == null ? '—' : '${f.gpsFix ?? 0} sats=${f.sats ?? 0}',
            ),
            _mini('Lines', '$_liveCount'),
            _mini('Buf', '${_liveStore.bufferRows}'),
            _mini('Src', _live ? 'STATUSTEXT' : '—'),
          ],
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          activeThumbColor: AppColors.accent,
          title: Text(
            'Live graphs',
            style: TextStyle(fontSize: g20.bodySize, color: AppColors.text),
          ),
          value: _showGraphs,
          onChanged: (v) => setState(() => _showGraphs = v),
        ),
        if (_showGraphs) ...[
          _chartBlock('Attitude °', [
            _ChartSeries('Roll', AppColors.accent, _rollQ),
            _ChartSeries('Pitch', Colors.orange, _pitchQ),
            _ChartSeries('Yaw', Colors.lightBlue, _yawQ),
          ], g20.chartHeight),
          _chartBlock('Gyro dps', [
            _ChartSeries('gx', const Color(0xFFE57373), _gxQ),
            _ChartSeries('gy', const Color(0xFF81C784), _gyQ),
            _ChartSeries('gz', const Color(0xFF64B5F6), _gzQ),
          ], g20.chartHeight),
        ],
        Row(
          children: [
            Icon(
              Icons.circle,
              size: 8,
              color: _paused
                  ? AppColors.warning
                  : (_live ? AppColors.success : AppColors.muted),
            ),
            const SizedBox(width: 8),
            Text(
              'Feed',
              style: TextStyle(
                fontSize: g20.bodySize,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
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
        Container(
          height: g20.feedHeight.clamp(120.0, 200.0),
          width: double.infinity,
          margin: const EdgeInsets.only(top: 2, bottom: 8),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF0E1114),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: !_live
              ? const Center(
                  child: Text(
                    'Connect for Live Log',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                )
              : _lines.isEmpty
                  ? const Center(
                      child: Text(
                        'Waiting for STATUSTEXT…',
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    )
                  : ListView.builder(
                      controller: _feedController,
                      itemCount: _lines.length,
                      itemBuilder: (_, i) => Text(
                        _lines[i],
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10.5,
                          height: 1.35,
                          color: Color(0xFFB7C0C9),
                        ),
                      ),
                    ),
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: (!_live || _busy) ? null : _saveLiveSession,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Save live session', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _refreshSessions,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Refresh sessions', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
        if (_sessions.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final s in _sessions.take(5))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(s.name, style: const TextStyle(fontSize: 12)),
              subtitle: Text(
                '${s.rows} lines (live session)',
                style: const TextStyle(fontSize: 10, color: AppColors.muted),
              ),
              trailing: TextButton(
                onPressed: _busy ? null : () => _downloadLiveSession(s),
                child: Text(_busyName == s.name ? '…' : 'Export'),
              ),
            ),
        ],

        const SizedBox(height: 14),
        const Divider(color: AppColors.border),
        const SizedBox(height: 6),

        // ---- SD flight logs ----
        Text(
          'SD flight logs',
          style: TextStyle(
            fontSize: g20.titleSize,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        Text(
          _sdStatus ??
              'On-card arm→disarm CSV over radio (mavsd) — separate from Live Log',
          style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: (_sdBusy || _armed || !_sdAvailable)
                    ? null
                    : _refreshSdList,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: Text(_sdBusy ? '…' : 'Refresh'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: sdActionsEnabled ? _wipeSd : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  visualDensity: VisualDensity.compact,
                  foregroundColor: AppColors.danger,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('Wipe all'),
              ),
            ),
          ],
        ),
        if (_armed)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Disarm to list / download / wipe',
              style: TextStyle(fontSize: 11, color: AppColors.danger),
            ),
          ),
        const SizedBox(height: 8),
        if (_sdEntries.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              !_sdAvailable
                  ? 'Connect (mavsd firmware) to list SD flights.'
                  : 'No flights listed — tap Refresh when disarmed.',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          )
        else
          for (final e in _sdEntries)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: AppColors.border),
              ),
              child: ListTile(
                dense: true,
                title: Text(
                  '#${e.id}  ${e.file}${e.tag != '-' && e.tag.isNotEmpty ? '  (${e.tag})' : ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                subtitle: Text(
                  'rows ${e.rows} · drops ${e.drops} · ${e.durS}s',
                  style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
                ),
                trailing: TextButton(
                  onPressed: sdActionsEnabled ? () => _downloadSd(e) : null,
                  child: const Text('Download'),
                ),
              ),
            ),
      ],
    );
  }

  Widget _chartBlock(String title, List<_ChartSeries> series, double height) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 2),
          child: Row(
            children: [
              Text(title, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              const Spacer(),
              for (final s in series) ...[
                Container(width: 10, height: 3, color: s.color),
                const SizedBox(width: 3),
                Text(s.label, style: const TextStyle(fontSize: 10, color: AppColors.text)),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        SizedBox(
          height: height,
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                for (final s in series)
                  LineChartBarData(
                    spots: s.spots.isEmpty ? const [FlSpot(0, 0)] : s.spots.toList(),
                    isCurved: true,
                    color: s.color,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _fmt(double? v, [String suffix = '']) {
    if (v == null) return '—';
    return '${v.toStringAsFixed(2)}$suffix';
  }

  Widget _mini(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.border),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(fontSize: 10, color: AppColors.muted),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                fontSize: 11,
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
