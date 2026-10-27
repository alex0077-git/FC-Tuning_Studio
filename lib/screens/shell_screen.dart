import 'package:flutter/material.dart';
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
  // 0 = Connect, 1 = Tuning, 2 = Logs, 3 = 3D View
  int _pageIndex = 0;

  bool _connected = false;
  bool _armed = false;
  String _firmware = '—';
  String _preset = 'Default';

  void _openConnect() => setState(() => _pageIndex = 0);

  @override
  Widget build(BuildContext context) {
    final pages = [
      ConnectScreen(
        connected: _connected,
        onConnected: ({
          required firmware,
          required boardId,
          required parameterCount,
          required linkQualityPercent,
        }) {
          setState(() {
            _connected = true;
            _armed = false;
            _firmware = firmware;
            _pageIndex = 1;
          });
        },
        onDisconnected: () {
          setState(() {
            _connected = false;
            _armed = false;
            _firmware = '—';
            _pageIndex = 0;
          });
        },
      ),
      _LockedPage(
        locked: !_connected,
        onConnectTap: _openConnect,
        child: TuningScreen(armed: _armed),
      ),
      _LockedPage(
        locked: !_connected,
        onConnectTap: _openConnect,
        child: const LogsScreen(),
      ),
      _LockedPage(
        locked: !_connected,
        onConnectTap: _openConnect,
        child: const View3dScreen(),
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
              preset: _preset,
              onMenuTap: _openConnect,
            ),
            Expanded(child: pages[_pageIndex]),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 64,
        selectedIndex: _pageIndex == 0 ? 0 : _pageIndex - 1,
        onDestinationSelected: (i) {
          setState(() => _pageIndex = i + 1);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Tuning',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Logs',
          ),
          NavigationDestination(
            icon: Icon(Icons.view_in_ar_outlined),
            selectedIcon: Icon(Icons.view_in_ar),
            label: '3D View',
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
    required this.preset,
    required this.onMenuTap,
  });

  final bool connected;
  final bool armed;
  final String firmware;
  final String preset;
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.border, width: 1),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: onMenuTap,
                icon: const Icon(Icons.menu, size: 22, color: AppColors.text),
                tooltip: 'Connection',
              ),
              const SizedBox(width: 4),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: dotColor.withOpacity(0.55),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    children: [
                      const TextSpan(text: 'Status: '),
                      TextSpan(
                        text: connected ? 'Connected' : 'Disconnected',
                        style: TextStyle(
                          color: connected ? AppColors.success : AppColors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(
                        text: '  |  Armed: ${armed ? 'Yes' : 'No'}'
                            '  |  FW: $firmware'
                            '  |  Preset: $preset',
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
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.link_off, color: AppColors.muted, size: 28),
                      const SizedBox(height: 10),
                      const Text(
                        'FC not connected',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Connect to the flight controller to unlock this page.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: AppColors.muted),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: onConnectTap,
                          icon: const Icon(Icons.link, size: 18),
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