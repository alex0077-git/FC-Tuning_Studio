import 'dart:async';

import 'package:flutter/material.dart';

import '../battery/battery_profile.dart';
import '../layout/g20_metrics.dart';
import '../link/mav_session.dart';
import '../logs/live_log_assembler.dart';
import '../mavlink/mavlink_v2.dart';
import '../theme/app_theme.dart';
import '../voice/fc_voice.dart';
import 'althold_3d_screen.dart';
import 'battery_screen.dart';
import 'connect_screen.dart';
import 'gps_screen.dart';
import 'logs_screen.dart';
import 'motor_screen.dart';
import 'sim_connect_screen.dart';
import 'tuning_screen.dart';
import 'view3d_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  /// 0 Connect · 1 Tuning · 2 Logs · 3 3D · 4 Motor · 5 Battery · 6 Simulation · 7 AltHold 3D · 8 GPS
  int _pageIndex = 0;
  final MavSession _session = MavSession();
  final FcVoice _voice = FcVoice();
  final BatteryProfileStore _battStore = BatteryProfileStore();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  StreamSubscription? _hbSub;
  StreamSubscription? _starSub;
  StreamSubscription? _liveSub;
  StreamSubscription? _battSub;
  StreamSubscription? _gpsSub;
  Timer? _linkWatch;
  bool _resetBusy = false;
  /// Bumped after Reset re-downloads FC RAM so Tuning editors refresh.
  int _paramsRevision = 0;

  bool _connected = false;
  bool _linkAlive = false;
  bool _armed = false;
  bool _altHoldActive = false;
  bool _magOn = false;
  SysStatus? _battery;
  FcGpsState? _gps;
  BatteryProfile _battProfile = BatteryProfile.defaults;

  bool _warn1Acked = false;
  bool _warn1Open = false;
  bool _criticalLock = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBattProfile());
  }

  Future<void> _loadBattProfile() async {
    final p = await _battStore.load();
    if (!mounted) return;
    setState(() => _battProfile = p);
    if (_battery != null) _onBattery(_battery!);
  }

  @override
  void dispose() {
    _hbSub?.cancel();
    _starSub?.cancel();
    _liveSub?.cancel();
    _battSub?.cancel();
    _gpsSub?.cancel();
    _linkWatch?.cancel();
    unawaited(_voice.dispose());
    _session.dispose();
    super.dispose();
  }

  void _openConnect() {
    _scaffoldKey.currentState?.closeDrawer();
    setState(() => _pageIndex = 0);
  }

  void _openSim() {
    _scaffoldKey.currentState?.closeDrawer();
    setState(() => _pageIndex = 6);
  }

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  void _goPage(int index) {
    _scaffoldKey.currentState?.closeDrawer();
    setState(() => _pageIndex = index);
  }

  /// Shared by G20 Connect and Simulation — does not choose the link.
  void _handleConnected({
    required String firmware,
    required String boardId,
    required int parameterCount,
    required int linkQualityPercent,
    required bool armed,
  }) {
    final becameArmed = !_armed && armed;
    final becameDisarmed = _armed && !armed;
    setState(() {
      _connected = true;
      _linkAlive = true;
      _armed = armed;
      _gps = _session.lastGps;
      _pageIndex = 1;
      // Force Tuning (kept alive in IndexedStack) to rebuild from session.params.
      _paramsRevision++;
    });
    _listenLink();
    unawaited(_voice.init());
    if (becameArmed) {
      unawaited(_voice.sayArmed());
    } else if (becameDisarmed) {
      unawaited(_voice.sayDisarmed());
    }
  }

  void _handleDisconnected({required int returnPage}) {
    _hbSub?.cancel();
    _starSub?.cancel();
    _liveSub?.cancel();
    _battSub?.cancel();
    _gpsSub?.cancel();
    _linkWatch?.cancel();
    setState(() {
      _connected = false;
      _linkAlive = false;
      _armed = false;
      _altHoldActive = false;
      _magOn = false;
      _battery = null;
      _gps = null;
      _resetBusy = false;
      _pageIndex = returnPage;
      _clearBatteryWarns();
    });
  }

  void _clearBatteryWarns() {
    _warn1Acked = false;
    _warn1Open = false;
    _criticalLock = false;
  }

  void _onBattery(SysStatus s) {
    if (!mounted) return;
    setState(() => _battery = s);
    if (!s.hasVoltage) return;
    final v = s.voltageVolts;
    final warnV = _battProfile.warnVolts;
    final critV = _battProfile.criticalVolts;

    if (v <= critV) {
      if (_warn1Open) {
        Navigator.of(context, rootNavigator: true).pop();
        _warn1Open = false;
      }
      if (!_criticalLock) {
        setState(() => _criticalLock = true);
        unawaited(_voice.sayBatterySecondWarning());
      }
      return;
    }

    if (_criticalLock) {
      setState(() => _criticalLock = false);
    }

    if (v > warnV) {
      _warn1Acked = false;
      return;
    }

    if (!_warn1Acked && !_warn1Open && !_criticalLock) {
      _showWarn1(v);
    }
  }

  Future<void> _showWarn1(double volts) async {
    _warn1Open = true;
    unawaited(_voice.sayBatteryFirstWarning());
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        var checked = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Battery warning'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${volts.toStringAsFixed(2)} V  — first warning '
                    '(${_battProfile.warnVolts.toStringAsFixed(2)} V).\n'
                    'Plan to land soon. You may continue.',
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: checked,
                    onChanged: (v) => setLocal(() => checked = v ?? false),
                    title: const Text('I understand — continue'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
                ElevatedButton(
                  onPressed: checked ? () => Navigator.pop(ctx) : null,
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
    if (!mounted) return;
    _warn1Open = false;
    _warn1Acked = true;
  }

  void _listenLink() {
    _hbSub?.cancel();
    _starSub?.cancel();
    _liveSub?.cancel();
    _battSub?.cancel();
    _gpsSub?.cancel();
    _linkWatch?.cancel();
    _battery = _session.lastSysStatus;
    _gps = _session.lastGps;
    _hbSub = _session.heartbeats.listen((hb) {
      if (!mounted) return;
      final wasArmed = _armed;
      setState(() {
        _armed = hb.armed;
        _linkAlive = true;
      });
      if (!wasArmed && hb.armed) {
        unawaited(_voice.sayArmed());
      } else if (wasArmed && !hb.armed) {
        unawaited(_voice.sayDisarmed());
      }
    });
    _gpsSub = _session.gpsStates.listen((g) {
      if (!mounted) return;
      setState(() => _gps = g);
    });
    _starSub = _session.starStatusLines.listen(_onStarStatus);
    _liveSub = _session.liveLogLines.listen((line) {
      if (!mounted) return;
      final f = LiveLogFields.parse(line);

      final act = f.ahAct;
      final ahOn = act != null && act != 0;
      if (ahOn != _altHoldActive) {
        final becameOn = ahOn && !_altHoldActive;
        final becameOff = !ahOn && _altHoldActive;
        setState(() => _altHoldActive = ahOn);
        if (becameOn) {
          unawaited(_voice.sayAltHoldOn());
        } else if (becameOff) {
          unawaited(_voice.sayAltHoldOff());
        }
      }

      // Mag light only when attitude fused mag this sample (`h1`).
      if (f.magFused != null && f.magFused != _magOn) {
        setState(() => _magOn = f.magFused!);
      }
    });
    _battSub = _session.sysStatuses.listen(_onBattery);
    if (_battery != null) {
      _onBattery(_battery!);
    }
    _linkWatch = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted || !_connected) return;
      final alive = _session.linkAlive;
      if (alive != _linkAlive) {
        setState(() {
          _linkAlive = alive;
          if (!alive) {
            _altHoldActive = false;
            _magOn = false;
            _battery = null;
            _gps = null;
          }
        });
      }
    });
  }

  void _onStarStatus(String line) {
    if (!mounted) return;
    final t = line.startsWith('*') ? line.substring(1).trim() : line.trim();
    if (t == 'reset') {
      setState(() {
        _resetBusy = false;
        // Jump to Tuning so the live RAM refresh is visible immediately.
        _pageIndex = 1;
      });
      unawaited(_voice.sayReset());
      unawaited(_reloadParamsAfterReset());
      return;
    }
    if (t == 'reset deny armed') {
      setState(() => _resetBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reset denied — disarm first')),
      );
    }
  }

  /// After soft reboot: pull RAM as soon as HEARTBEAT is up (no link-drop wait).
  Future<void> _reloadParamsAfterReset() async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    Object? lastErr;

    while (mounted && DateTime.now().isBefore(deadline)) {
      if (_session.linkAlive) {
        try {
          await _session.downloadParams(
            idle: const Duration(milliseconds: 60),
            attempts: 12,
          );
          if (!mounted) return;
          setState(() {
            _paramsRevision++;
            _pageIndex = 1;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tuning = FC RAM after reset')),
          );
          return;
        } catch (e) {
          lastErr = e;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          lastErr == null
              ? 'Reset: link did not return — Tuning → Revert'
              : 'Reset: param reload failed ($lastErr)',
        ),
      ),
    );
  }

  Future<void> _confirmReset() async {
    if (!_connected || !_linkAlive || _armed || _resetBusy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reboot FC?'),
        content: const Text(
          'Sends STATUSTEXT “reset”. Craft must be disarmed. '
          'Link may drop briefly; Tuning snaps to live FC RAM as soon as it returns.',
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
      // If FC never sends *reset, still reload when link returns.
      unawaited(_fallbackReloadIfNoStarReset());
    } catch (e) {
      if (!mounted) return;
      setState(() => _resetBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reset send failed: $e')),
      );
    }
  }

  Future<void> _fallbackReloadIfNoStarReset() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted || !_resetBusy) return;
    setState(() => _resetBusy = false);
    await _reloadParamsAfterReset();
  }

  @override
  Widget build(BuildContext context) {
    final g20 = G20Metrics.of(context);

    final pages = <Widget>[
      ConnectScreen(
        key: const ValueKey('connect'),
        session: _session,
        connected: _connected,
        voiceEnabled: _voice.enabled,
        onVoiceEnabledChanged: (on) {
          setState(() => _voice.enabled = on);
          unawaited(_voice.setEnabled(on));
        },
        onConnected: _handleConnected,
        onDisconnected: () => _handleDisconnected(returnPage: 0),
      ),
      _LockedPage(
        key: const ValueKey('tuning'),
        locked: !_connected,
        onConnectTap: _openConnect,
        child: TuningScreen(
          key: const ValueKey('tuning-screen'),
          session: _session,
          armed: _armed,
          paramsRevision: _paramsRevision,
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
      // Battery profile — usable even before connect.
      BatteryScreen(
        key: const ValueKey('battery-screen'),
        profile: _battProfile,
        onSaved: (p) {
          setState(() {
            _battProfile = p;
            _warn1Acked = false;
          });
          if (_battery != null) _onBattery(_battery!);
        },
      ),
      // Simulation — mock FC; parallel to G20 Connect (no UDP).
      SimConnectScreen(
        key: const ValueKey('sim-connect'),
        session: _session,
        connected: _connected,
        onConnected: _handleConnected,
        onDisconnected: () => _handleDisconnected(returnPage: 6),
      ),
      _LockedPage(
        key: const ValueKey('althold-3d'),
        locked: !_connected,
        onConnectTap: _openConnect,
        child: Althold3dScreen(
          key: const ValueKey('althold-3d-screen'),
          session: _connected ? _session : null,
        ),
      ),
      _LockedPage(
        key: const ValueKey('gps'),
        locked: !_connected,
        onConnectTap: _openConnect,
        child: GpsScreen(
          key: const ValueKey('gps-screen'),
          session: _connected ? _session : null,
        ),
      ),
    ];

    return PopScope(
      canPop: !_criticalLock,
      child: Scaffold(
        key: _scaffoldKey,
        drawer: _criticalLock
            ? null
            : _NavDrawer(
                selectedIndex: _pageIndex,
                connected: _connected,
                onSelect: _goPage,
                onConnect: _openConnect,
                onSim: _openSim,
              ),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _StatusBar(
                    connected: _connected,
                    linkAlive: _linkAlive,
                    armed: _armed,
                    altHoldActive: _altHoldActive,
                    magOn: _magOn,
                    battery: _battery,
                    profile: _battProfile,
                    gps: _gps,
                    compact: g20.compactChrome,
                    resetBusy: _resetBusy,
                    onMenuTap: _openDrawer,
                    onStatusTap: _openConnect,
                    onResetTap: _confirmReset,
                  ),
                  Expanded(
                    // Tight constraints so Tuning/Motor/3D Expanded layouts
                    // work on Windows desktop (loose IndexedStack breaks them).
                    child: IndexedStack(
                      index: _pageIndex,
                      sizing: StackFit.expand,
                      children: pages,
                    ),
                  ),
                ],
              ),
              if (_criticalLock)
                Positioned.fill(
                  child: _CriticalBatteryLock(
                    criticalVolts: _battProfile.criticalVolts,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CriticalBatteryLock extends StatelessWidget {
  const _CriticalBatteryLock({required this.criticalVolts});
  final double criticalVolts;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xE6000000),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: AppColors.danger, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.battery_alert, color: AppColors.danger, size: 36),
              const SizedBox(height: 10),
              Text(
                'LAND NOW',
                style: AppFonts.display(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Battery ≤ ${criticalVolts.toStringAsFixed(2)} V.\n'
                'This screen stays until voltage rises.\n\n'
                'Land with the transmitter sticks.\n'
                'Disarm, change the pack, then reconnect.',
                textAlign: TextAlign.center,
                style: AppFonts.body(fontSize: 14),
              ),
            ],
          ),
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
    required this.onSim,
  });

  final int selectedIndex;
  final bool connected;
  final ValueChanged<int> onSelect;
  final VoidCallback onConnect;
  final VoidCallback onSim;

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
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _item(
                    icon: Icons.link,
                    label: 'Connect',
                    selected: selectedIndex == 0,
                    onTap: onConnect,
                  ),
                  _item(
                    icon: Icons.science,
                    label: 'Simulation',
                    selected: selectedIndex == 6,
                    onTap: onSim,
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
                    icon: Icons.height,
                    label: 'AltHold 3D',
                    selected: selectedIndex == 7,
                    onTap: () => onSelect(7),
                  ),
                  _item(
                    icon: Icons.map,
                    label: 'GPS',
                    selected: selectedIndex == 8,
                    onTap: () => onSelect(8),
                  ),
                  _item(
                    icon: Icons.settings_input_component,
                    label: 'Motor',
                    selected: selectedIndex == 4,
                    onTap: () => onSelect(4),
                  ),
                  _item(
                    icon: Icons.battery_charging_full,
                    label: 'Battery',
                    selected: selectedIndex == 5,
                    onTap: () => onSelect(5),
                  ),
                ],
              ),
            ),
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
    required this.altHoldActive,
    required this.magOn,
    required this.battery,
    required this.profile,
    required this.gps,
    required this.compact,
    required this.resetBusy,
    required this.onMenuTap,
    required this.onStatusTap,
    required this.onResetTap,
  });

  final bool connected;
  final bool linkAlive;
  final bool armed;
  final bool altHoldActive;
  final bool magOn;
  final SysStatus? battery;
  final BatteryProfile profile;
  final FcGpsState? gps;
  final bool compact;
  final bool resetBusy;
  final VoidCallback onMenuTap;
  final VoidCallback onStatusTap;
  final VoidCallback onResetTap;

  String get _batteryLabel {
    if (!connected || !linkAlive || battery == null || !battery!.hasVoltage) {
      return '—';
    }
    return profile.labelForVolts(battery!.voltageVolts);
  }

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

    final canReset = connected && linkAlive && !armed && !resetBusy;
    final battText = _batteryLabel;
    final hasV = battery != null && battery!.hasVoltage;
    final v = hasV ? battery!.voltageVolts : null;
    final Color battColor;
    if (!hasV) {
      battColor = Colors.white54;
    } else if (v! <= profile.criticalVolts) {
      battColor = const Color(0xFFFF8A80);
    } else if (v <= profile.warnVolts) {
      battColor = const Color(0xFFFFB74D);
    } else {
      battColor = AppColors.cta;
    }

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
                              text: '  ·  Armed ${armed ? 'Yes' : 'No'}',
                            ),
                            if (altHoldActive)
                              TextSpan(
                                text: '  ·  ALTHOLD',
                                style: AppFonts.body(
                                  fontSize: compact ? 11 : 12,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFFFFD54F),
                                ),
                              ),
                            TextSpan(
                              text: connected && linkAlive
                                  ? '  ·  Fix ${gps?.fixType ?? '—'}'
                                      '  ·  Sats ${gps?.satellitesVisible ?? '—'}'
                                  : '  ·  Fix —  ·  Sats —',
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
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                battText,
                style: AppFonts.body(
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w700,
                  color: battColor,
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
            // Small green mag light — rightmost, after Reset (`h1`).
            if (magOn)
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 6),
                child: Tooltip(
                  message: 'Magnetometer on',
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFF66BB6A),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF66BB6A).withValues(alpha: 0.55),
                          blurRadius: 5,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              const SizedBox(width: 14),
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