import 'dart:async';

import 'package:flutter/material.dart';

import '../layout/g20_metrics.dart';
import '../link/mav_session.dart';
import '../theme/app_theme.dart';
import 'connect_screen.dart';
import 'logs_screen.dart';
import 'motor_screen.dart';
import 'tuning_screen.dart';
import 'view3d_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  /// 0 Connect · 1 Tuning · 2 Logs · 3 3D · 4 Motor
  int _pageIndex = 0;
  final MavSession _session = MavSession();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  StreamSubscription? _hbSub;
  StreamSubscription? _starSub;
  Timer? _linkWatch;
  bool _resetBusy = false;

  bool _connected = false;
  bool _linkAlive = false;
  bool _armed = false;
  String _firmware = '—';

  @override
  void dispose() {
    _hbSub?.cancel();
    _starSub?.cancel();
    _linkWatch?.cancel();
    _session.dispose();
    super.dispose();
  }

  void _openConnect() {
    _scaffoldKey.currentState?.closeDrawer();
    setState(() => _pageIndex = 0);
  }

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  void _goPage(int index) {
    _scaffoldKey.currentState?.closeDrawer();
    setState(() => _pageIndex = index);
  }

  void _listenLink() {
    _hbSub?.cancel();
    _starSub?.cancel();
    _linkWatch?.cancel();
    _hbSub = _session.heartbeats.listen((hb) {
      if (!mounted) return;
      setState(() {
        _armed = hb.armed;
        _linkAlive = true;
      });
    });
    _starSub = _session.starStatusLines.listen(_onStarStatus);
    _linkWatch = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted || !_connected) return;
      final alive = _session.linkAlive;
      if (alive != _linkAlive) {
        setState(() => _linkAlive = alive);
      }
    });
  }

  void _onStarStatus(String line) {
    if (!mounted) return;
    final t = line.startsWith('*') ? line.substring(1).trim() : line.trim();
    if (t == 'reset') {
      setState(() => _resetBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('FC resetting… wait for HEARTBEAT')),
      );
      return;
    }
    if (t == 'reset deny armed') {
      setState(() => _resetBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reset denied — disarm first')),
      );
    }
  }

  Future<void> _confirmReset() async {
    if (!_connected || !_linkAlive || _armed || _resetBusy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reboot FC?'),
        content: const Text(
          'Sends STATUSTEXT “reset”. Craft must be disarmed. '
          'Link drops briefly; RAM params return to firmware defaults.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _resetBusy = true);
    try {
      await _session.sendReset();
    } catch (e) {
      if (!mounted) return;
      setState(() => _resetBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reset send failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final g20 = G20Metrics.of(context);

    final pages = <Widget>[
      ConnectScreen(
        key: const ValueKey('connect'),
        session: _session,
        connected: _connected,
        onConnected: ({
          required firmware,
          required boardId,
          required parameterCount,
          required linkQualityPercent,
          required armed,
        }) {
          setState(() {
            _connected = true;
            _linkAlive = true;
            _armed = armed;
            _firmware = firmware;
            _pageIndex = 1;
          });
          _listenLink();
        },
        onDisconnected: () {
          _hbSub?.cancel();
          _starSub?.cancel();
          _linkWatch?.cancel();
          setState(() {
            _connected = false;
            _linkAlive = false;
            _armed = false;
            _firmware = '—';
            _resetBusy = false;
            _pageIndex = 0;
          });
        },
      ),
      _LockedPage(
        key: const ValueKey('tuning'),
        locked: !_connected,
        onConnectTap: _openConnect,
        child: TuningScreen(
          key: const ValueKey('tuning-screen'),
          session: _session,
          armed: _armed,
        ),
      ),
      _LockedPage(
        key: const ValueKey('logs'),
        locked: !_connected,
        onConnectTap: _openConnect,
        child: LogsScreen(
          key: const ValueKey('logs-screen'),
          session: _connected ? _session : null,
        ),
      ),
      _LockedPage(
        key: const ValueKey('view3d'),
        locked: !_connected,
        onConnectTap: _openConnect,
        child: View3dScreen(
          key: const ValueKey('view3d-screen'),
          session: _connected ? _session : null,
        ),
      ),
      _LockedPage(
        key: const ValueKey('motor'),
        locked: !_connected,
        onConnectTap: _openConnect,
        child: MotorScreen(
          key: const ValueKey('motor-screen'),
          session: _session,
          armed: _armed,
        ),
      ),
    ];

    return Scaffold(
      key: _scaffoldKey,
      drawer: _NavDrawer(
        selectedIndex: _pageIndex,
        connected: _connected,
        onSelect: _goPage,
        onConnect: _openConnect,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StatusBar(
              connected: _connected,
              linkAlive: _linkAlive,
              armed: _armed,
              firmware: _firmware,
              compact: g20.compactChrome,
              resetBusy: _resetBusy,
              onMenuTap: _openDrawer,
              onStatusTap: _openConnect,
              onResetTap: _confirmReset,
            ),
            Expanded(
              child: IndexedStack(
                index: _pageIndex,
                children: pages,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavDrawer extends StatelessWidget {
  const _NavDrawer({
    required this.selectedIndex,
    required this.connected,
    required this.onSelect,
    required this.onConnect,
  });

  final int selectedIndex;
  final bool connected;
  final ValueChanged<int> onSelect;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 220,
      backgroundColor: AppColors.forest,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'FC Tuning Studio',
                style: AppFonts.display(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                connected ? 'Link up' : 'Not connected',
                style: AppFonts.body(
                  fontSize: 11,
                  color: connected ? AppColors.cta : Colors.white54,
                ),
              ),
            ),
            const Divider(color: Colors.white24, height: 1),
            _item(
              icon: Icons.link,
              label: 'Connect',
              selected: selectedIndex == 0,
              onTap: onConnect,
            ),
            _item(
              icon: Icons.tune,
              label: 'Tuning',
              selected: selectedIndex == 1,
              onTap: () => onSelect(1),
            ),
            _item(
              icon: Icons.bar_chart,
              label: 'Logs',
              selected: selectedIndex == 2,
              onTap: () => onSelect(2),
            ),
            _item(
              icon: Icons.view_in_ar,
              label: '3D',
              selected: selectedIndex == 3,
              onTap: () => onSelect(3),
            ),
            _item(
              icon: Icons.settings_input_component,
              label: 'Motor',
              selected: selectedIndex == 4,
              onTap: () => onSelect(4),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '☰ closes after pick · full screen content',
                style: AppFonts.body(fontSize: 10, color: Colors.white38),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: selected ? AppColors.cta : Colors.white70),
      title: Text(
        label,
        style: AppFonts.body(
          fontSize: 14,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? AppColors.cta : Colors.white,
        ),
      ),
      selected: selected,
      selectedTileColor: Colors.white12,
      onTap: onTap,
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.connected,
    required this.linkAlive,
    required this.armed,
    required this.firmware,
    required this.compact,
    required this.resetBusy,
    required this.onMenuTap,
    required this.onStatusTap,
    required this.onResetTap,
  });

  final bool connected;
  final bool linkAlive;
  final bool armed;
  final String firmware;
  final bool compact;
  final bool resetBusy;
  final VoidCallback onMenuTap;
  final VoidCallback onStatusTap;
  final VoidCallback onResetTap;

  @override
  Widget build(BuildContext context) {
    final String status;
    final Color statusColor;
    final Color dotColor;
    if (!connected) {
      status = 'Disconnected';
      statusColor = const Color(0xFFFF8A80);
      dotColor = AppColors.danger;
    } else if (!linkAlive) {
      status = 'Link Lost';
      statusColor = const Color(0xFFFFB74D);
      dotColor = const Color(0xFFFFB74D);
    } else {
      status = 'Connected';
      statusColor = AppColors.cta;
      dotColor = AppColors.cta;
    }

    // Contract: Reset only while connected, link alive, and disarmed.
    final canReset = connected && linkAlive && !armed && !resetBusy;

    return Material(
      color: AppColors.forest,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 8,
          vertical: compact ? 2 : 4,
        ),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.forest, width: 1)),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Menu',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(
                minWidth: compact ? 36 : 40,
                minHeight: compact ? 36 : 40,
              ),
              onPressed: onMenuTap,
              icon: Icon(
                Icons.menu,
                size: compact ? 22 : 24,
                color: Colors.white,
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: onStatusTap,
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: dotColor.withValues(alpha: 0.55),
                            blurRadius: 5,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: AppFonts.body(
                            fontSize: compact ? 11 : 12,
                            color: Colors.white70,
                          ),
                          children: [
                            TextSpan(
                              text: status,
                              style: AppFonts.body(
                                fontSize: compact ? 11 : 12,
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                              ),
                            ),
                            TextSpan(
                              text:
                                  '  ·  Armed ${armed ? 'Yes' : 'No'}  ·  $firmware',
                            ),
                          ],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: compact ? 30 : 34,
              child: TextButton(
                onPressed: canReset ? onResetTap : null,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.cta,
                  disabledForegroundColor: Colors.white38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: resetBusy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.cta,
                        ),
                      )
                    : Text(
                        'Reset',
                        style: AppFonts.body(
                          fontSize: compact ? 12 : 13,
                          fontWeight: FontWeight.w700,
                          color: canReset ? AppColors.cta : Colors.white38,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LockedPage extends StatelessWidget {
  const _LockedPage({
    super.key,
    required this.locked,
    required this.child,
    required this.onConnectTap,
  });
  final bool locked;
  final Widget child;
  final VoidCallback onConnectTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Opacity(
          opacity: locked ? 0.28 : 1,
          child: IgnorePointer(ignoring: locked, child: child),
        ),
        if (locked)
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.overlay,
              child: Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 28),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.link_off, color: AppColors.muted, size: 22),
                      const SizedBox(height: 8),
                      Text(
                        'FC not connected',
                        style: AppFonts.display(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Connect to unlock this page.',
                        textAlign: TextAlign.center,
                        style: AppFonts.body(fontSize: 12, color: AppColors.muted),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 36,
                        child: ElevatedButton.icon(
                          onPressed: onConnectTap,
                          icon: const Icon(Icons.link, size: 16),
                          label: const Text('Go to Connect'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
