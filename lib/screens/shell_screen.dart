import 'package:flutter/material.dart';
import 'connect_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  // 0 = Connect, 1 = Tuning, 2 = Logs, 3 = 3D View
  int _pageIndex = 0;

  static const _pages = [
  ConnectScreen(),
  _PlaceholderPage(title: 'Gain Tuning'),
  _PlaceholderPage(title: 'Logs'),
  _PlaceholderPage(title: '3D View'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _StatusBar(
              connected: false,
              armed: false,
              firmware: '—',
              preset: 'Default',
            ),
            Expanded(child: _pages[_pageIndex]),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        // Bottom bar has 3 tabs; they map to pages 1, 2, 3.
        selectedIndex: _pageIndex == 0 ? 0 : _pageIndex - 1,
        onDestinationSelected: (i) {
          setState(() => _pageIndex = i + 1);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.tune), label: 'Tuning'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Logs'),
          NavigationDestination(icon: Icon(Icons.view_in_ar), label: '3D View'),
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
    final dotColor = connected ? const Color(0xFF2EAE5B) : const Color(0xFFE24B4B);

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