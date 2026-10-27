import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

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
    final locked = widget.connected || _busy;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const Text(
          'Connect to Flight Controller',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Link through Skydroid G20 / T12 (Wi‑Fi or Bluetooth).',
          style: TextStyle(fontSize: 13, color: AppColors.muted),
        ),
        const SizedBox(height: 18),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<LinkType>(
                segments: const [
                  ButtonSegment(
                    value: LinkType.wifi,
                    label: Text('Wi‑Fi'),
                    icon: Icon(Icons.wifi, size: 18),
                  ),
                  ButtonSegment(
                    value: LinkType.bluetooth,
                    label: Text('Bluetooth'),
                    icon: Icon(Icons.bluetooth, size: 18),
                  ),
                ],
                selected: {_linkType},
                onSelectionChanged: locked
                    ? null
                    : (selected) {
                        setState(() => _linkType = selected.first);
                      },
              ),
              const SizedBox(height: 14),
              if (_linkType == LinkType.wifi) ...[
                TextField(
                  controller: _addressController,
                  enabled: !locked,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    prefixIcon: Icon(Icons.lan_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _portController,
                  enabled: !locked,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    prefixIcon: Icon(Icons.numbers, size: 20),
                  ),
                ),
              ] else
                DropdownButtonFormField<String>(
                  value: _btDevice,
                  decoration: const InputDecoration(
                    labelText: 'Device',
                    prefixIcon: Icon(Icons.phone_android, size: 20),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Skydroid T12',
                      child: Text('Skydroid T12'),
                    ),
                    DropdownMenuItem(
                      value: 'Skydroid G20',
                      child: Text('Skydroid G20'),
                    ),
                  ],
                  onChanged: locked
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _btDevice = value);
                          }
                        },
                ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _busy ? null : _toggleConnect,
                style: widget.connected
                    ? ElevatedButton.styleFrom(
                        backgroundColor: AppColors.danger,
                      )
                    : null,
                child: _busy
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Text(widget.connected ? 'Disconnect' : 'Connect'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: locked
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
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(
                  _linkType == LinkType.wifi
                      ? 'Refresh ports'
                      : 'Refresh devices',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Device info',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 10),
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

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
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
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}