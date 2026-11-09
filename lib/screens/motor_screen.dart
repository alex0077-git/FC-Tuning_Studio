import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../layout/g20_metrics.dart';
import '../link/mav_session.dart';
import '../logs/live_log_assembler.dart';
import '../theme/app_theme.dart';

/// Bench motor test — one motor (or All) at a time.
/// Landscape: left quad picker · right slider + hold Test.
class MotorScreen extends StatefulWidget {
  const MotorScreen({super.key, required this.session, required this.armed});

  final MavSession session;
  final bool armed;

  @override
  State<MotorScreen> createState() => _MotorScreenState();
}

class _MotorScreenState extends State<MotorScreen> {
  static const _idleUs = 1000;

  /// Selected motor: 1..4, or 0 = All. Null = none yet.
  int _selected = 1;
  int _us = _idleUs;
  final _usCtrl = TextEditingController(text: '$_idleUs');

  StreamSubscription? _starSub;
  StreamSubscription? _hbSub;
  StreamSubscription? _liveSub;
  Timer? _holdTimer;
  Timer? _linkWatch;

  bool _holding = false;
  bool _armed = false;
  bool _linkAlive = false;
  String _fcNote = '';
  LiveLogFields? _live;

  bool get _testsAllowed => !_armed && _linkAlive;

  @override
  void initState() {
    super.initState();
    _armed = widget.armed;
    _linkAlive = widget.session.linkAlive;
    _starSub = widget.session.starStatusLines.listen(_onStar);
    _hbSub = widget.session.heartbeats.listen((hb) {
      if (!mounted) return;
      final was = _armed;
      setState(() {
        _armed = hb.armed;
        _linkAlive = true;
      });
      if (!was && hb.armed) unawaited(_stop(note: 'Armed — stopped'));
    });
    _liveSub = widget.session.liveLogLines.listen((line) {
      if (!mounted) return;
      setState(() => _live = LiveLogFields.parse(line));
    });
    _linkWatch = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final alive = widget.session.linkAlive;
      if (alive != _linkAlive) {
        setState(() => _linkAlive = alive);
        if (!alive) unawaited(_stop(note: 'Link Lost — stopped'));
      }
    });
  }

  @override
  void didUpdateWidget(covariant MotorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.armed != widget.armed) {
      setState(() => _armed = widget.armed);
      if (widget.armed) unawaited(_stop(note: 'Armed — stopped'));
    }
  }

  @override
  void dispose() {
    unawaited(_stop(silent: true));
    _holdTimer?.cancel();
    _linkWatch?.cancel();
    _starSub?.cancel();
    _hbSub?.cancel();
    _liveSub?.cancel();
    _usCtrl.dispose();
    super.dispose();
  }

  void _onStar(String line) {
    if (!mounted) return;
    final t = line.startsWith('*') ? line.substring(1).trim() : line.trim();
    if (t == 'motor stop') {
      setState(() {
        _holding = false;
        _fcNote = 'FC stopped';
      });
      return;
    }
    if (t == 'motor deny armed') {
      setState(() => _fcNote = 'FC: disarm first');
      return;
    }
    if (t == 'motor deny') {
      setState(() => _fcNote = 'FC: refused');
      return;
    }
    final m = RegExp(r'^motor (all|[1-4]) (\d+)$').firstMatch(t);
    if (m != null) {
      final who = m.group(1)!;
      final us = int.parse(m.group(2)!);
      setState(() {
        _fcNote = who == 'all' ? 'FC All $us µs' : 'FC M$who $us µs';
      });
    }
  }

  void _setUs(int raw) {
    final us = MavSession.clampPwmUs(raw);
    setState(() {
      _us = us;
      _usCtrl.text = '$us';
    });
  }

  /// Switch motor only when not holding — one test at a time.
  void _select(int slot) {
    if (_holding) {
      setState(() => _fcNote = 'Release Test first');
      return;
    }
    setState(() {
      _selected = slot;
      _fcNote = '';
      // Fresh idle each pick — do not carry a hot value across motors.
      _us = _idleUs;
      _usCtrl.text = '$_idleUs';
    });
  }

  Future<void> _sendHold() async {
    if (!_holding || !_testsAllowed) return;
    final cmd = _selected == 0 ? 'motor all $_us' : 'motor $_selected $_us';
    try {
      await widget.session.sendMotorCommand(cmd);
    } catch (_) {
      if (mounted) setState(() => _fcNote = 'Send failed');
    }
  }

  Future<void> _stop({String? note, bool silent = false}) async {
    _holdTimer?.cancel();
    _holdTimer = null;
    final was = _holding;
    _holding = false;
    if (was) {
      try {
        await widget.session.sendMotorCommand('motor stop');
      } catch (_) {}
    }
    if (!silent && mounted) {
      setState(() => _fcNote = note ?? 'Stopped');
    }
  }

  void _holdStart() {
    if (_armed) {
      setState(() => _fcNote = 'Disarm first');
      return;
    }
    if (!_linkAlive) {
      setState(() => _fcNote = 'Link Lost');
      return;
    }
    setState(() {
      _holding = true;
      _fcNote = 'Testing…';
    });
    unawaited(_sendHold());
    _holdTimer?.cancel();
    _holdTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      unawaited(_sendHold());
    });
  }

  void _holdEnd() => unawaited(_stop());

  String get _selectedLabel {
    switch (_selected) {
      case 0:
        return 'All motors';
      case 1:
        return 'M1 front right';
      case 2:
        return 'M2 back left';
      case 3:
        return 'M3 front left';
      case 4:
        return 'M4 back right';
      default:
        return 'Motor';
    }
  }

  @override
  Widget build(BuildContext context) {
    final g20 = G20Metrics.of(context);
    final live = _live;
    final banner = !_linkAlive
        ? 'Link Lost'
        : _armed
            ? 'ARMED — locked'
            : (_holding ? 'HOLD · $_selectedLabel' : 'Bench · one motor at a time');

    final header = Padding(
      padding: EdgeInsets.fromLTRB(g20.pagePad, 8, g20.pagePad, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              banner,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.body(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: (!_linkAlive || _armed)
                    ? AppColors.danger
                    : (_holding ? AppColors.warning : AppColors.text),
              ),
            ),
          ),
          if (_fcNote.isNotEmpty) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _fcNote,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: AppFonts.body(fontSize: 11, color: AppColors.muted),
              ),
            ),
          ],
          const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: () => unawaited(_stop()),
              child: const Text('Stop'),
            ),
          ),
        ],
      ),
    );

    final picker = _QuadPicker(
      selected: _selected,
      holding: _holding,
      enabled: !_holding,
      onSelect: _select,
    );

    final controls = _MotorControls(
      label: _selectedLabel,
      us: _us,
      controller: _usCtrl,
      canEdit: _testsAllowed && !_holding,
      canHold: _testsAllowed,
      holding: _holding,
      liveLine: live?.m1 != null
          ? 'Live ${live!.m1} ${live.m2} ${live.m3} ${live.m4} µs'
          : null,
      onUsChanged: _setUs,
      onHoldStart: _holdStart,
      onHoldEnd: _holdEnd,
    );

    if (g20.landscape) {
      return ColoredBox(
        color: AppColors.bg,
        child: Column(
          children: [
            header,
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(g20.pagePad, 4, g20.pagePad, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 5, child: picker),
                    const SizedBox(width: 10),
                    Expanded(flex: 6, child: controls),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ColoredBox(
      color: AppColors.bg,
      child: Column(
        children: [
          header,
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(g20.pagePad, 4, g20.pagePad, 12),
              children: [
                SizedBox(height: 160, child: picker),
                const SizedBox(height: 10),
                controls,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuadPicker extends StatelessWidget {
  const _QuadPicker({
    required this.selected,
    required this.holding,
    required this.enabled,
    required this.onSelect,
  });

  final int selected;
  final bool holding;
  final bool enabled;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(
            holding ? 'Finish this test before changing motor' : 'Tap motor · Nose ↑',
            style: AppFonts.body(fontSize: 11, color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _corner(3, 'M3', 'FL'),
                    const SizedBox(width: 36),
                    _corner(1, 'M1', 'FR'),
                  ],
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _corner(2, 'M2', 'BL'),
                    const SizedBox(width: 36),
                    _corner(4, 'M4', 'BR'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 36,
            child: OutlinedButton(
              onPressed: enabled ? () => onSelect(0) : null,
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: selected == 0 ? AppColors.cta : AppColors.border,
                  width: selected == 0 ? 2 : 1,
                ),
                backgroundColor:
                    selected == 0 ? AppColors.cta.withValues(alpha: 0.2) : null,
              ),
              child: Text(
                'All motors',
                style: AppFonts.body(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected == 0 ? AppColors.forest : AppColors.text,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _corner(int id, String label, String pos) {
    final on = selected == id;
    final hot = holding && on;
    return InkWell(
      onTap: enabled ? () => onSelect(id) : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 72,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hot
              ? AppColors.warning.withValues(alpha: 0.35)
              : on
                  ? AppColors.cta.withValues(alpha: 0.3)
                  : AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hot
                ? AppColors.warning
                : on
                    ? AppColors.cta
                    : AppColors.border,
            width: on ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: AppFonts.body(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            Text(
              pos,
              style: AppFonts.body(fontSize: 10, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _MotorControls extends StatelessWidget {
  const _MotorControls({
    required this.label,
    required this.us,
    required this.controller,
    required this.canEdit,
    required this.canHold,
    required this.holding,
    required this.liveLine,
    required this.onUsChanged,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final String label;
  final int us;
  final TextEditingController controller;
  final bool canEdit;
  final bool canHold;
  final bool holding;
  final String? liveLine;
  final ValueChanged<int> onUsChanged;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: holding ? AppColors.warning : AppColors.border,
          width: holding ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppFonts.display(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              SizedBox(
                width: 72,
                height: 34,
                child: TextField(
                  controller: controller,
                  enabled: canEdit,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: AppFonts.body(fontSize: 13, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    suffixText: 'µs',
                  ),
                  onSubmitted: (t) {
                    final v = int.tryParse(t);
                    if (v != null) onUsChanged(v);
                  },
                ),
              ),
            ],
          ),
          if (liveLine != null) ...[
            const SizedBox(height: 4),
            Text(
              liveLine!,
              style: AppFonts.body(fontSize: 11, color: AppColors.muted),
            ),
          ],
          Slider(
            min: 1000,
            max: 2000,
            divisions: 100,
            value: us.toDouble().clamp(1000, 2000),
            label: '$us',
            onChanged: canEdit ? (v) => onUsChanged(v.round()) : null,
          ),
          const Spacer(),
          Text(
            'Props off · hold to spin · release to stop',
            textAlign: TextAlign.center,
            style: AppFonts.body(fontSize: 10, color: AppColors.muted),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTapDown: canHold ? (_) => onHoldStart() : null,
            onTapUp: canHold ? (_) => onHoldEnd() : null,
            onTapCancel: canHold ? onHoldEnd : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: !canHold
                    ? AppColors.border
                    : holding
                        ? AppColors.warning
                        : AppColors.forest,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
              child: Text(
                holding ? 'RELEASE TO STOP' : 'HOLD TO TEST',
                style: AppFonts.body(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: canHold ? Colors.white : AppColors.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
