import 'dart:async';

import 'package:flutter/material.dart';

import '../layout/g20_metrics.dart';
import '../link/mav_session.dart';
import '../theme/app_theme.dart';
import 'connect_screen.dart';
import 'logs_screen.dart';
import 'tuning_screen.dart';
import 'view3d_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _pageIndex = 0;
  final MavSession _session = MavSession();
  StreamSubscription? _hbSub;

  bool _connected = false;
  bool _armed = false;
  String _firmware = '—';

  @override
  void dispose() {
    _hbSub?.cancel();
    _session.dispose();
    super.dispose();
  }

  void _openConnect() => setState(() => _pageIndex = 0);

  void _listenArmed() {
    _hbSub?.cancel();
    _hbSub = _session.heartbeats.listen((hb) {
      if (!mounted) return;
      if (_armed != hb.armed) setState(() => _armed = hb.armed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final g20 = G20Metrics.of(context);

    // IndexedStack keeps Tuning / Logs / 3D alive so Live Log keeps filling
    // while the user is on another tab.
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
            _armed = armed;
            _firmware = firmware;
            _pageIndex = 1;
          });
          _listenArmed();
        },
        onDisconnected: () {
          _hbSub?.cancel();
          setState(() {
            _connected = false;
            _armed = false;
            _firmware = '—';
            _pageIndex = 0;
          });
        },
      ),
      _LockedPage(
        key: const ValueKey('tuning'),
        locked: !_connected,
        onConnectTap: _openConnect,
        // Stable key: keep PID edit state across tab switches.
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
        // IndexedStack + key: Live Log / graphs keep filling off-tab.
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
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _StatusBar(
              connected: _connected,
              armed: _armed,
              firmware: _firmware,
              compact: g20.compactChrome,
              onMenuTap: _openConnect,
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
      bottomNavigationBar: NavigationBar(
        height: g20.navHeight,
        selectedIndex: _pageIndex == 0 ? 0 : _pageIndex - 1,
        onDestinationSelected: (i) => setState(() => _pageIndex = i + 1),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.tune_outlined, size: 18),
            selectedIcon: Icon(Icons.tune, size: 18),
            label: 'Tuning',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined, size: 18),
            selectedIcon: Icon(Icons.bar_chart, size: 18),
            label: 'Logs',
          ),
          NavigationDestination(
            icon: Icon(Icons.view_in_ar_outlined, size: 18),
            selectedIcon: Icon(Icons.view_in_ar, size: 18),
            label: '3D',
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.connected,
    required this.armed,
    required this.firmware,
    required this.compact,
    required this.onMenuTap,
  });

  final bool connected;
  final bool armed;
  final String firmware;
  final bool compact;
  final VoidCallback onMenuTap;

  @override
  Widget build(BuildContext context) {
    final dotColor = connected ? AppColors.success : AppColors.danger;
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onMenuTap,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: compact ? 4 : 8,
          ),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
          ),
          child: Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(
                  minWidth: compact ? 30 : 36,
                  minHeight: compact ? 30 : 36,
                ),
                onPressed: onMenuTap,
                icon: Icon(
                  Icons.menu,
                  size: compact ? 18 : 22,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(width: 2),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: dotColor.withValues(alpha: 0.55), blurRadius: 5),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: compact ? 11 : 12,
                      color: AppColors.muted,
                    ),
                    children: [
                      TextSpan(
                        text: connected ? 'Connected' : 'Disconnected',
                        style: TextStyle(
                          color: connected ? AppColors.success : AppColors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(
                        text: '  ·  Armed ${armed ? 'Yes' : 'No'}  ·  $firmware',
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
              color: const Color(0x99000000),
              child: Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 28),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.link_off, color: AppColors.muted, size: 22),
                      const SizedBox(height: 8),
                      const Text(
                        'FC not connected',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Connect to unlock this page.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
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
