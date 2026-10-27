import 'package:flutter/material.dart';
import 'connect_screen.dart';
import 'tuning_screen.dart';
import 'logs_screen.dart';

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
            _pageIndex = 1; // jump to Tuning after connect
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
        child: TuningScreen(armed: _armed),
      ),
      _LockedPage(
        locked: !_connected,
        child: const LogsScreen(),
      ),
      _LockedPage(
        locked: !_connected,
        child: const _PlaceholderPage(title: '3D View'),
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
            ),
            Expanded(child: pages[_pageIndex]),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _pageIndex == 0 ? 0 : _pageIndex - 1,
        onDestinationSelected: (i) {
          setState(() => _pageIndex = i + 1);
        },
        destinations: [
          NavigationDestination(
            icon: Icon(
              Icons.tune,
              color: _connected ? null : const Color(0xFF9AA3AD),
            ),
            label: 'Tuning',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.bar_chart,
              color: _connected ? null : const Color(0xFF9AA3AD),
            ),
            label: 'Logs',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.view_in_ar,
              color: _connected ? null : const Color(0xFF9AA3AD),
            ),
            label: '3D View',
          ),
        ],
      ),
      floatingActionButton: _pageIndex != 0
          ? FloatingActionButton.extended(
              onPressed: () => setState(() => _pageIndex = 0),
              icon: const Icon(Icons.link),
              label: const Text('Connect'),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.connected,
    required this.armed,
    required this.firmware,
    required this.preset,
  });

  final bool connected;
  final bool armed;
  final String firmware;
  final String preset;

  @override
  Widget build(BuildContext context) {
    final dotColor =
        connected ? const Color(0xFF2EAE5B) : const Color(0xFFE24B4B);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: const Color(0xFF252A30),
      child: Row(
        children: [
          const Icon(Icons.menu, size: 22),
          const SizedBox(width: 10),
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Status: ${connected ? 'Connected' : 'Disconnected'}  |  '
              'Armed: ${armed ? 'Yes' : 'No'}  |  '
              'FW: $firmware  |  '
              'Preset: $preset',
              style: const TextStyle(fontSize: 12, color: Color(0xFF9AA3AD)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _LockedPage extends StatelessWidget {
  const _LockedPage({required this.locked, required this.child});

  final bool locked;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Opacity(
          opacity: locked ? 0.35 : 1,
          child: IgnorePointer(ignoring: locked, child: child),
        ),
        if (locked)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x66000000),
              child: Center(
                child: Text(
                  'Connect to FC to unlock',
                  style: TextStyle(color: Color(0xFF9AA3AD), fontSize: 14),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        title,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      ),
    );
  }
}