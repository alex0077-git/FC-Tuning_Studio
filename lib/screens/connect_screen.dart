import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../layout/g20_metrics.dart';
import '../link/g20_udp_link.dart';
import '../link/mav_session.dart';
import '../link/t12_spp_link.dart';
import '../theme/app_theme.dart';

enum LinkType { g20, t12 }

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({
    super.key,
    required this.session,
    required this.connected,
    required this.onConnected,
    required this.onDisconnected,
  });

  final MavSession session;
  final bool connected;
  final void Function({
    required String firmware,
    required String boardId,
    required int parameterCount,
    required int linkQualityPercent,
    required bool armed,
  }) onConnected;
  final VoidCallback onDisconnected;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  LinkType _linkType = LinkType.g20;
  bool _busy = false;

  List<BondedBtDevice> _btDevices = [];
  String? _btAddress;

  String _firmware = '—';
  String _boardId = '—';
  String _parameters = '—';
  String _linkQuality = '—';

  Future<void> _refreshBt() async {
    try {
      final list = await T12SppLink.bonded();
      setState(() {
        _btDevices = list;
        if (_btAddress == null || !list.any((d) => d.address == _btAddress)) {
          _btAddress = list.isEmpty ? null : list.first.address;
        }
      });
      if (!mounted) return;
      if (list.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'T12 BT not in this APK — use G20 UDP. T12 SPP comes in a later build.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('BT refresh failed: $e')),
      );
    }
  }

  Future<void> _toggleConnect() async {
    if (widget.connected) {
      await widget.session.disconnect();
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
    try {
      if (_linkType == LinkType.g20) {
        await widget.session.connect(G20UdpLink());
      } else {
        final addr = _btAddress;
        if (addr == null) {
          throw StateError(
            'T12 Bluetooth is not in this APK build. Switch to G20 Wi‑Fi.',
          );
        }
        await widget.session.connect(T12SppLink(address: addr));
      }

      await widget.session.waitHeartbeat();

      var usedCatalogFallback = false;
      try {
        await widget.session.downloadParams();
      } catch (e) {
        // HEARTBEAT/ATTITUDE already prove the link. If PARAM_VALUE never
        // arrives, seed catalog defaults so Tuning/3D still open (QGC-proven FC).
        final defaults = await _catalogDefaults();
        if (defaults.isEmpty) rethrow;
        widget.session.seedParams(defaults);
        usedCatalogFallback = true;
        if (mounted) {
          final link = widget.session;
          final hint = link.msgidCounts.isEmpty
              ? ''
              : ' msgs=${link.msgidCounts}';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 5),
              content: Text(
                'Linked (HB OK) — live params missing, catalog defaults.$hint '
                'Close QGC. Write needs app→FC uplink.',
              ),
            ),
          );
        }
      }

      final count = widget.session.params.length;
      final armed = widget.session.armed;

      setState(() {
        _busy = false;
        _firmware = 'MAVLink v2';
        _boardId = 'sys 1 / comp 1';
        _parameters = usedCatalogFallback ? '$count (catalog)' : '$count';
        _linkQuality = armed ? 'armed' : 'disarmed';
      });

      widget.onConnected(
        firmware: _firmware,
        boardId: _boardId,
        parameterCount: count,
        linkQualityPercent: 100,
        armed: armed,
      );
    } catch (e) {
      await widget.session.disconnect();
      if (!mounted) return;
      setState(() => _busy = false);
      final msg = e is TimeoutException
          ? e.message ?? e.toString()
          : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(msg),
        ),
      );
    }
  }

  Future<Map<String, double>> _catalogDefaults() async {
    try {
      final raw = await rootBundle.loadString('assets/params_catalog.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final list = json['params'] as List<dynamic>? ?? [];
      final out = <String, double>{};
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        final id = m['id'] as String?;
        final def = m['default'];
        if (id == null || def == null) continue;
        out[id] = (def as num).toDouble();
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.connected || _busy;
    final g20 = G20Metrics.of(context);

    return ListView(
      padding: EdgeInsets.fromLTRB(g20.pagePad + 4, g20.pagePad, g20.pagePad + 4, 16),
      children: [
        Text(
          'Connect to Flight Controller',
          style: AppFonts.display(
            fontSize: g20.compactChrome ? 18 : 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'G20 UDP 14551 → 127.0.0.1:14552  ·  MAVLink v2',
          style: AppFonts.body(fontSize: g20.bodySize, color: AppColors.muted),
        ),
        SizedBox(height: g20.compactChrome ? 10 : 18),
        Container(
          padding: EdgeInsets.all(g20.compactChrome ? 10 : 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: AppColors.forest.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<LinkType>(
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: const [
                  ButtonSegment(
                    value: LinkType.g20,
                    label: Text('G20 Wi‑Fi'),
                    icon: Icon(Icons.wifi, size: 16),
                  ),
                  ButtonSegment(
                    value: LinkType.t12,
                    label: Text('T12 BT'),
                    icon: Icon(Icons.bluetooth, size: 16),
                  ),
                ],
                selected: {_linkType},
                onSelectionChanged: locked
                    ? null
                    : (s) {
                        setState(() => _linkType = s.first);
                        if (_linkType == LinkType.t12) _refreshBt();
                      },
              ),
              const SizedBox(height: 10),
              if (_linkType == LinkType.g20)
                const Text(
                  'Install and run this APK on the G20 itself.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                )
              else ...[
                const Text(
                  'T12 Classic SPP is stubbed in this APK (AGP 9). Use G20 for bench test.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _btAddress,
                  decoration: const InputDecoration(
                    labelText: 'Paired device',
                    prefixIcon: Icon(Icons.phone_android, size: 20),
                  ),
                  items: [
                    for (final d in _btDevices)
                      DropdownMenuItem(
                        value: d.address,
                        child: Text(d.name.isNotEmpty ? d.name : d.address),
                      ),
                  ],
                  onChanged:
                      locked ? null : (v) => setState(() => _btAddress = v),
                ),
              ],
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _busy ? null : _toggleConnect,
                style: ElevatedButton.styleFrom(
                  minimumSize: Size.fromHeight(g20.compactChrome ? 42 : 48),
                  backgroundColor:
                      widget.connected ? AppColors.danger : AppColors.cta,
                  foregroundColor:
                      widget.connected ? Colors.white : AppColors.onCta,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  ),
                ),
                child: _busy
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: widget.connected
                              ? Colors.white
                              : AppColors.onCta,
                        ),
                      )
                    : Text(
                        widget.connected ? 'Disconnect' : 'Connect',
                        style: AppFonts.body(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: widget.connected
                              ? Colors.white
                              : AppColors.onCta,
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: locked
                    ? null
                    : () {
                        if (_linkType == LinkType.t12) {
                          _refreshBt();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'G20 uses fixed UDP ports (Phase B)',
                              ),
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(
                  _linkType == LinkType.t12
                      ? 'Refresh devices'
                      : 'G20 ports locked',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              _row('Firmware', _firmware),
              _row('Board ID', _boardId),
              _row('Parameters', _parameters),
              _row('Link', _linkQuality),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              child: Text(
                label,
                style: AppFonts.body(fontSize: 13, color: AppColors.muted),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: AppFonts.body(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}
