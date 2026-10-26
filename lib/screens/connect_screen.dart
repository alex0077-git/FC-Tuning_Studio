import 'package:flutter/material.dart';

enum LinkType { wifi, bluetooth }

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  LinkType _linkType = LinkType.wifi;

  final _addressController = TextEditingController(text: '192.168.144.1');
  final _portController = TextEditingController(text: '14550');
  String _btDevice = 'Skydroid T12';

  @override
  void dispose() {
    _addressController.dispose();
    _portController.dispose();
    super.dispose();
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
          onSelectionChanged: (selected) {
            setState(() => _linkType = selected.first);
          },
        ),
        const SizedBox(height: 16),
        if (_linkType == LinkType.wifi) ...[
          TextField(
            controller: _addressController,
            decoration: const InputDecoration(
              labelText: 'Address',
              filled: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _portController,
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
            onChanged: (value) {
              if (value != null) setState(() => _btDevice = value);
            },
          ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () {
            // Step 4 will do real mock connect. For now just a snackbar.
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Connect will work in Step 4')),
            );
          },
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: const Text('Connect'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _linkType == LinkType.wifi
                      ? 'Refresh ports (UI only)'
                      : 'Refresh devices (UI only)',
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
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(label: 'Firmware', value: '—'),
              _InfoRow(label: 'Board ID', value: '—'),
              _InfoRow(label: 'Parameters', value: '—'),
              _InfoRow(label: 'Link quality', value: '—'),
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