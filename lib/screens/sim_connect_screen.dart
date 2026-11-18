import 'package:flutter/material.dart';

import '../layout/g20_metrics.dart';
import '../link/mav_session.dart';
import '../link/mock_fc_link.dart';
import '../theme/app_theme.dart';

/// Laptop-only mock connect. Parallel to real G20 [ConnectScreen] — no UDP.
class SimConnectScreen extends StatefulWidget {
  const SimConnectScreen({
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
  State<SimConnectScreen> createState() => _SimConnectScreenState();
}

class _SimConnectScreenState extends State<SimConnectScreen> {
  bool _busy = false;
  MockFcLink? _mock;

  Future<void> _toggle() async {
    if (widget.connected) {
      await widget.session.disconnect();
      _mock = null;
      widget.onDisconnected();
      return;
    }
    setState(() => _busy = true);
    try {
      final mock = MockFcLink();
      _mock = mock;
      await widget.session.connect(mock);
      await widget.session.waitHeartbeat(
        timeout: const Duration(seconds: 3),
      );
      await widget.session.downloadParams(
        idle: const Duration(milliseconds: 80),
        attempts: 8,
      );
      final count = widget.session.params.length;
      final armed = widget.session.armed;
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onConnected(
        firmware: 'SIM mock',
        boardId: 'sys 1 / comp 1',
        parameterCount: count,
        linkQualityPercent: 100,
        armed: armed,
      );
    } catch (e) {
      await widget.session.disconnect();
      _mock = null;
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sim connect failed: $e')),
      );
    }
  }

  void _bump() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final g20 = G20Metrics.of(context);
    final m = _mock;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        g20.pagePad + 4,
        g20.pagePad,
        g20.pagePad + 4,
        16,
      ),
      children: [
        Text(
          'Simulation Connect',
          style: AppFonts.display(
            fontSize: g20.compactChrome ? 18 : 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Mock FC on this device — no G20 / UDP / radio.',
          style: AppFonts.body(fontSize: g20.bodySize, color: AppColors.muted),
        ),
        SizedBox(height: g20.compactChrome ? 10 : 18),
        Container(
          padding: EdgeInsets.all(g20.compactChrome ? 10 : 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Uses the same MavSession as real flights. '
                'G20 Connect page is unchanged.',
                style: AppFonts.body(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _busy ? null : _toggle,
                style: ElevatedButton.styleFrom(
                  // Avoid Size.fromHeight (infinite min width) on desktop.
                  minimumSize: Size(64, g20.compactChrome ? 42 : 48),
                  backgroundColor:
                      widget.connected ? AppColors.danger : AppColors.cta,
                  foregroundColor:
                      widget.connected ? Colors.white : AppColors.onCta,
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
                        widget.connected ? 'Disconnect sim' : 'Connect mock FC',
                        style: AppFonts.body(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: widget.connected
                              ? Colors.white
                              : AppColors.onCta,
                        ),
                      ),
              ),
            ],
          ),
        ),
        if (widget.connected && m != null) ...[
          const SizedBox(height: 14),
          Text(
            'Sim controls',
            style: AppFonts.body(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () {
                  m.setArmed(!m.armed);
                  _bump();
                },
                child: Text(m.armed ? 'Disarm' : 'Arm'),
              ),
              OutlinedButton(
                onPressed: () {
                  m.setAltHold(!m.altHoldActive);
                  _bump();
                },
                child: Text(m.altHoldActive ? 'AltHold off' : 'AltHold on'),
              ),
              Text(
                'Mock Z: ${m.simHeightM.toStringAsFixed(2)} m'
                '${m.altHoldActive ? '  (AltHold)' : (m.armed ? '  (armed)' : '')}',
                style: AppFonts.body(fontSize: 12, color: AppColors.muted),
              ),
              OutlinedButton(
                onPressed: () {
                  m.voltageMv = 15800;
                  m.batteryRemaining = 40;
                  _bump();
                },
                child: const Text('Batt warn'),
              ),
              OutlinedButton(
                onPressed: () {
                  m.voltageMv = 15200;
                  m.batteryRemaining = 15;
                  _bump();
                },
                child: const Text('Batt critical'),
              ),
              OutlinedButton(
                onPressed: () {
                  m.voltageMv = 16800;
                  m.batteryRemaining = 95;
                  _bump();
                },
                child: const Text('Batt full'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
