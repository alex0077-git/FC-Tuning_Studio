import 'package:flutter/material.dart';

enum LinkType { wifi, bluetooth }

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({
    super.key,
    required this.connected,
    required this.onConnected,
    required this.onDisconnected,
  });

  final bool connected;
  final void Function({
    required String firmware,
    required String boardId,
    required int parameterCount,
    required int linkQualityPercent,
  }) onConnected;
  final VoidCallback onDisconnected;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  LinkType _linkType = LinkType.wifi;
  bool _busy = false;

  final _addressController = TextEditingController(text: '192.168.144.1');
  final _portController = TextEditingController(text: '14550');
  String _btDevice = 'Skydroid T12';

  String _firmware = '—';
  String _boardId = '—';
  String _parameters = '—';
  String _linkQuality = '—';

  @override
  void dispose() {
    _addressController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _toggleConnect() async {
    if (widget.connected) {
      setState(() {
        _firmware = '—';
        _boardId = '—';
        _parameters = '—';
        _linkQuality = '—';
      });
      widget.onDisconnected();
      return;
    }

    setState(() => _busy = true);

    // Fake waiting for MAVLink heartbeat (mock only).
    await Future<void>.delayed(const Duration(milliseconds: 700));

    if (!mounted) return;

    const firmware = 'v1.0';
    const boardId = 'FC-MOCK-650';
    const parameterCount = 42;
    const linkQuality = 97;

    setState(() {
      _busy = false;
      _firmware = firmware;
      _boardId = boardId;
      _parameters = '$parameterCount';
      _linkQuality = '$linkQuality%';
    });

    widget.onConnected(
      firmware: firmware,
      boardId: boardId,
      parameterCount: parameterCount,
      linkQualityPercent: linkQuality,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Connect to Flight Controller',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        SegmentedButton<LinkType>(
          segments: const [
            ButtonSegment(
              value: LinkType.wifi,
              label: Text('Wi-Fi'),
              icon: Icon(Icons.wifi),
            ),
            ButtonSegment(
              value: LinkType.bluetooth,
              label: Text('Bluetooth'),
              icon: Icon(Icons.bluetooth),
            ),
          ],
          selected: {_linkType},
          onSelectionChanged: widget.connected || _busy
              ? null
              : (selected) {
                  setState(() => _linkType = selected.first);
                },
        ),
        const SizedBox(height: 16),
        if (_linkType == LinkType.wifi) ...[
          TextField(
            controller: _addressController,
            enabled: !widget.connected && !_busy,
            decoration: const InputDecoration(
              labelText: 'Address',
              filled: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _portController,
            enabled: !widget.connected && !_busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Port',
              filled: true,
            ),
          ),
        ] else
          DropdownButtonFormField<String>(
            value: _btDevice,
            decoration: const InputDecoration(
              labelText: 'Device',
              filled: true,
            ),
            items: const [
              DropdownMenuItem(value: 'Skydroid T12', child: Text('Skydroid T12')),
              DropdownMenuItem(value: 'Skydroid G20', child: Text('Skydroid G20')),
            ],
            onChanged: widget.connected || _busy
                ? null
                : (value) {
                    if (value != null) setState(() => _btDevice = value);
                  },
          ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _busy ? null : _toggleConnect,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: Text(
            _busy
                ? 'Connecting…'
                : (widget.connected ? 'Disconnect' : 'Connect'),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: widget.connected || _busy
              ? null
              : () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _linkType == LinkType.wifi
                            ? 'Ports refreshed (mock)'
                            : 'Devices refreshed (mock)',
                      ),
                    ),
                  );
                },
          icon: const Icon(Icons.refresh),
          label: Text(
            _linkType == LinkType.wifi ? 'Refresh ports' : 'Refresh devices',
          ),
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF252A30),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(label: 'Firmware', value: _firmware),
              _InfoRow(label: 'Board ID', value: _boardId),
              _InfoRow(label: 'Parameters', value: _parameters),
              _InfoRow(label: 'Link quality', value: _linkQuality),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF9AA3AD)),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}