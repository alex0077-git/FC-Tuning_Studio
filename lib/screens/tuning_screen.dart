import 'package:flutter/material.dart';

import '../layout/g20_metrics.dart';
import '../link/mav_session.dart';
import '../theme/app_theme.dart';

enum _Tab { outer, inner, altHold }
enum _Axis { roll, pitch, yaw }

class _Pid {
  _Pid({this.p = 0, this.i = 0, this.d = 0});
  double p;
  double i;
  double d;
  _Pid clone() => _Pid(p: p, i: i, d: d);
}

class _Gains {
  _Gains({
    this.outerRollP = 6,
    this.outerPitchP = 8,
    this.outerYawP = 0,
    _Pid? innerRoll,
    _Pid? innerPitch,
    _Pid? innerYaw,
    _Pid? altHold,
  })  : innerRoll = innerRoll ?? _Pid(p: 1.0, i: 0, d: 0.04),
        innerPitch = innerPitch ?? _Pid(p: 1.2, i: 0, d: 0.04),
        innerYaw = innerYaw ?? _Pid(p: 0.5, i: 0, d: 0.02),
        // altHold.d stores ALT_CORR_MAX (not a D term)
        altHold = altHold ?? _Pid(p: 100, i: 10, d: 200);

  double outerRollP;
  double outerPitchP;
  double outerYawP;
  _Pid innerRoll;
  _Pid innerPitch;
  _Pid innerYaw;
  _Pid altHold;

  _Gains clone() => _Gains(
        outerRollP: outerRollP,
        outerPitchP: outerPitchP,
        outerYawP: outerYawP,
        innerRoll: innerRoll.clone(),
        innerPitch: innerPitch.clone(),
        innerYaw: innerYaw.clone(),
        altHold: altHold.clone(),
      );
}

abstract final class FcParamIds {
  static const outerRoll = 'ROLL_AP';
  static const outerPitch = 'PITCH_AP';
  static const outerYaw = 'YAW_AP';
  static const rollP = 'ROLL_KP';
  static const rollI = 'ROLL_KI';
  static const rollD = 'ROLL_KD';
  static const pitchP = 'PITCH_KP';
  static const pitchI = 'PITCH_KI';
  static const pitchD = 'PITCH_KD';
  static const yawP = 'YAW_KP';
  static const yawI = 'YAW_KI';
  static const yawD = 'YAW_KD';
  static const altP = 'ALT_KP';
  static const altI = 'ALT_KI';
  static const altMax = 'ALT_CORR_MAX';
}

class TuningScreen extends StatefulWidget {
  const TuningScreen({
    super.key,
    required this.session,
    this.armed = false,
    this.paramsRevision = 0,
  });

  final MavSession session;
  final bool armed;

  /// Bumped by shell after Reset (or other bulk FC RAM reload) so editors refresh.
  final int paramsRevision;

  @override
  State<TuningScreen> createState() => _TuningScreenState();
}

class _TuningScreenState extends State<TuningScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late _Gains _fc;
  late _Gains _edited;

  _Axis _axis = _Axis.roll;
  bool _linkRollPitch = false;
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    final next = _gainsFromParams(widget.session.params);
    _fc = next;
    _edited = next.clone();
    widget.session.paramsEpoch.addListener(_onParamsEpoch);
  }

  @override
  void dispose() {
    widget.session.paramsEpoch.removeListener(_onParamsEpoch);
    _tabs.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TuningScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.paramsEpoch.removeListener(_onParamsEpoch);
      widget.session.paramsEpoch.addListener(_onParamsEpoch);
      _syncEditorsFromSession(forceEdited: true);
      return;
    }
    if (oldWidget.paramsRevision != widget.paramsRevision) {
      _syncEditorsFromSession(forceEdited: true);
    }
  }

  /// Session map changed (connect download, Write, Reset reload, Revert).
  void _onParamsEpoch() {
    if (!mounted || _writing) return;
    // Snap sliders to live FC RAM immediately (no waiting for a full download).
    _syncEditorsFromSession(forceEdited: true);
  }

  void _syncEditorsFromSession({required bool forceEdited}) {
    final next = _gainsFromParams(widget.session.params);
    setState(() {
      _fc = next;
      if (forceEdited) _edited = next.clone();
    });
  }

  /// Only values present in FC/session RAM — no catalog / baked-in UI defaults.
  _Gains _gainsFromParams(Map<String, double> p) {
    double g(String id) => p[id] ?? 0.0;
    return _Gains(
      outerRollP: g(FcParamIds.outerRoll),
      outerPitchP: g(FcParamIds.outerPitch),
      outerYawP: g(FcParamIds.outerYaw),
      innerRoll: _Pid(
        p: g(FcParamIds.rollP),
        i: g(FcParamIds.rollI),
        d: g(FcParamIds.rollD),
      ),
      innerPitch: _Pid(
        p: g(FcParamIds.pitchP),
        i: g(FcParamIds.pitchI),
        d: g(FcParamIds.pitchD),
      ),
      innerYaw: _Pid(
        p: g(FcParamIds.yawP),
        i: g(FcParamIds.yawI),
        d: g(FcParamIds.yawD),
      ),
      altHold: _Pid(
        p: g(FcParamIds.altP),
        i: g(FcParamIds.altI),
        d: g(FcParamIds.altMax),
      ),
    );
  }

  bool get _hasLiveFcParams {
    const need = [
      FcParamIds.outerRoll,
      FcParamIds.outerPitch,
      FcParamIds.outerYaw,
      FcParamIds.rollP,
      FcParamIds.pitchP,
      FcParamIds.yawP,
      FcParamIds.altP,
    ];
    return need.every(widget.session.params.containsKey);
  }

  Future<void> _write() async {
    if (_writing) return;
    setState(() => _writing = true);
    final failed = <String>[];
    var wrote = 0;

    // Write only dirty params; each setParam verifies echo + RAM read-back.
    Future<void> maybe(String id, double edited, double fc) async {
      if ((edited - fc).abs() < 1e-6) return;
      try {
        await widget.session.setParam(id, edited);
        wrote += 1;
      } catch (e) {
        failed.add('$id ($e)');
      }
    }

    try {
      await maybe(FcParamIds.outerRoll, _edited.outerRollP, _fc.outerRollP);
      await maybe(FcParamIds.outerPitch, _edited.outerPitchP, _fc.outerPitchP);
      await maybe(FcParamIds.outerYaw, _edited.outerYawP, _fc.outerYawP);
      await maybe(FcParamIds.rollP, _edited.innerRoll.p, _fc.innerRoll.p);
      await maybe(FcParamIds.rollI, _edited.innerRoll.i, _fc.innerRoll.i);
      await maybe(FcParamIds.rollD, _edited.innerRoll.d, _fc.innerRoll.d);
      await maybe(FcParamIds.pitchP, _edited.innerPitch.p, _fc.innerPitch.p);
      await maybe(FcParamIds.pitchI, _edited.innerPitch.i, _fc.innerPitch.i);
      await maybe(FcParamIds.pitchD, _edited.innerPitch.d, _fc.innerPitch.d);
      await maybe(FcParamIds.yawP, _edited.innerYaw.p, _fc.innerYaw.p);
      await maybe(FcParamIds.yawI, _edited.innerYaw.i, _fc.innerYaw.i);
      await maybe(FcParamIds.yawD, _edited.innerYaw.d, _fc.innerYaw.d);
      await maybe(FcParamIds.altP, _edited.altHold.p, _fc.altHold.p);
      await maybe(FcParamIds.altI, _edited.altHold.i, _fc.altHold.i);
      await maybe(FcParamIds.altMax, _edited.altHold.d, _fc.altHold.d);

      if (!mounted) return;
      // UI always follows verified FC RAM map (successes + unchanged).
      setState(() => _writing = false);
      _syncEditorsFromSession(forceEdited: true);
      if (failed.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              wrote == 0
                  ? 'Nothing to write — already matches FC RAM'
                  : 'Write verified on FC ($wrote param${wrote == 1 ? '' : 's'})',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Write partial: ${failed.length} failed. ${failed.join('; ')}',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _writing = false);
      _syncEditorsFromSession(forceEdited: true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Write failed: $e')),
      );
    }
  }

  Future<void> _saveToFc() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Save to FC?'),
        content: const Text(
          'Phase B: params are RAM until reboot. There is no flash save yet. '
          'Write still pushes values for this power cycle.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Write anyway')),
        ],
      ),
    );
    if (ok != true) return;
    await _write();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Values on FC until reboot (not flash)')),
    );
  }

  /// Re-download current RAM params from the FC, then refresh the editors.
  Future<void> _revert() async {
    if (_writing) return;
    setState(() => _writing = true);
    try {
      await widget.session.downloadParams();
      if (!mounted) return;
      setState(() => _writing = false);
      _syncEditorsFromSession(forceEdited: true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reverted — reloaded current FC RAM values'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _writing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Revert failed: $e')),
      );
    }
  }

  /// Pull live RAM from FC, then refresh sliders (same as Revert, quieter).
  Future<void> _reloadFromFc() async {
    if (_writing) return;
    setState(() => _writing = true);
    try {
      await widget.session.downloadParams();
      if (!mounted) return;
      setState(() => _writing = false);
      _syncEditorsFromSession(forceEdited: true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reloaded from FC RAM')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _writing = false);
      // Fall back to whatever is already in the session map.
      _syncEditorsFromSession(forceEdited: true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reload failed: $e')),
      );
    }
  }

  bool get _dirty =>
      _edited.outerRollP != _fc.outerRollP ||
      _edited.outerPitchP != _fc.outerPitchP ||
      _edited.outerYawP != _fc.outerYawP ||
      _edited.innerRoll.p != _fc.innerRoll.p ||
      _edited.innerRoll.i != _fc.innerRoll.i ||
      _edited.innerRoll.d != _fc.innerRoll.d ||
      _edited.innerPitch.p != _fc.innerPitch.p ||
      _edited.innerPitch.i != _fc.innerPitch.i ||
      _edited.innerPitch.d != _fc.innerPitch.d ||
      _edited.innerYaw.p != _fc.innerYaw.p ||
      _edited.innerYaw.i != _fc.innerYaw.i ||
      _edited.innerYaw.d != _fc.innerYaw.d ||
      _edited.altHold.p != _fc.altHold.p ||
      _edited.altHold.i != _fc.altHold.i ||
      _edited.altHold.d != _fc.altHold.d;

  ButtonStyle get _compactBtn => ElevatedButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      );

  @override
  Widget build(BuildContext context) {
    final g20 = G20Metrics.of(context);
    final tabH = g20.compactChrome ? 30.0 : 34.0;
    return Column(
      children: [
        Material(
          color: AppColors.surface,
          child: TabBar(
            controller: _tabs,
            onTap: (_) => setState(() {}),
            labelColor: AppColors.forest,
            unselectedLabelColor: AppColors.muted,
            indicatorColor: AppColors.cta,
            indicatorWeight: 2,
            labelStyle: TextStyle(
              fontSize: g20.bodySize,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: TextStyle(fontSize: g20.bodySize),
            labelPadding: EdgeInsets.symmetric(horizontal: g20.pagePad),
            tabs: [
              Tab(height: tabH, text: 'Outer'),
              Tab(height: tabH, text: 'Inner'),
              Tab(height: tabH, text: 'AltHold'),
            ],
          ),
        ),
        if (widget.armed)
          Container(
            width: double.infinity,
            color: AppColors.danger.withValues(alpha: 0.15),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: const Text(
              'Armed — Write disabled',
              style: TextStyle(color: AppColors.danger, fontSize: 11),
            ),
          ),
        if (!_hasLiveFcParams)
          Container(
            width: double.infinity,
            color: AppColors.cta.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: const Text(
              'No live FC params yet — tap Revert to download RAM (no catalog fill)',
              style: TextStyle(color: AppColors.forest, fontSize: 11),
            ),
          ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(g20.pagePad, 6, g20.pagePad, 8),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _reloadFromFc,
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('Reload', style: TextStyle(fontSize: 12)),
                ),
              ),
              if (_tabs.index != _Tab.altHold.index) ...[
                _axisChips(),
                const SizedBox(height: 6),
              ],
              Container(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(children: _buildSliders()),
              ),
              if (_tabs.index == _Tab.inner.index) ...[
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  activeColor: AppColors.forest,
                  title: const Text(
                    'Link roll + pitch',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _linkRollPitch,
                  onChanged: (v) => setState(() => _linkRollPitch = v ?? false),
                ),
              ],
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            children: [
              if (_dirty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Unsaved — Write to push',
                      style: TextStyle(fontSize: 10, color: AppColors.warning),
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: (widget.armed || _writing) ? null : _write,
                      child: _writing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Write'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ElevatedButton(
                      style: _compactBtn.copyWith(
                        backgroundColor:
                            const WidgetStatePropertyAll(AppColors.cta),
                        foregroundColor:
                            const WidgetStatePropertyAll(AppColors.onCta),
                      ),
                      onPressed: (widget.armed || _writing) ? null : _saveToFc,
                      child: const Text('Save to FC'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ElevatedButton(
                      style: _compactBtn.copyWith(
                        backgroundColor:
                            const WidgetStatePropertyAll(AppColors.surface2),
                        foregroundColor:
                            const WidgetStatePropertyAll(AppColors.text),
                      ),
                      onPressed: _writing ? null : _revert,
                      child: const Text('Revert'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _axisChips() {
    Widget chip(_Axis axis, String label) {
      final on = _axis == axis;
      return ChoiceChip(
        label: Text(label),
        selected: on,
        selectedColor: AppColors.forest,
        backgroundColor: AppColors.surface2,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        labelStyle: AppFonts.body(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: on ? Colors.white : AppColors.muted,
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
        side: BorderSide(color: on ? AppColors.forest : AppColors.border),
        onSelected: (_) => setState(() => _axis = axis),
      );
    }

    return Wrap(
      spacing: 6,
      children: [
        chip(_Axis.roll, 'Roll'),
        chip(_Axis.pitch, 'Pitch'),
        chip(_Axis.yaw, 'Yaw'),
      ],
    );
  }

  List<Widget> _buildSliders() {
    final tab = _Tab.values[_tabs.index];

    if (tab == _Tab.outer) {
      final name = _axis.name[0].toUpperCase() + _axis.name.substring(1);
      return [
        _slider(
          label: '$name AP',
          value: _outerEdited(),
          fcValue: _outerFc(),
          min: 0,
          max: 40,
          onChanged: _setOuter,
        ),
      ];
    }

    if (tab == _Tab.altHold) {
      return [
        _slider(
          label: 'Alt P',
          value: _edited.altHold.p,
          fcValue: _fc.altHold.p,
          min: 0,
          max: 500,
          onChanged: (v) => setState(() => _edited.altHold.p = v),
        ),
        _slider(
          label: 'Alt I',
          value: _edited.altHold.i,
          fcValue: _fc.altHold.i,
          min: 0,
          max: 200,
          onChanged: (v) => setState(() => _edited.altHold.i = v),
        ),
        _slider(
          label: 'Alt max',
          value: _edited.altHold.d,
          fcValue: _fc.altHold.d,
          min: 10,
          max: 400,
          onChanged: (v) => setState(() => _edited.altHold.d = v),
        ),
      ];
    }

    final editedPid = _innerEdited();
    final fcPid = _innerFc();
    final name = _axis.name[0].toUpperCase() + _axis.name.substring(1);
    return [
      _slider(
        label: '$name P',
        value: editedPid.p,
        fcValue: fcPid.p,
        min: 0,
        max: 10,
        onChanged: (v) => _setInner((pid) => pid.p = v),
      ),
      _slider(
        label: '$name I',
        value: editedPid.i,
        fcValue: fcPid.i,
        min: 0,
        max: 5,
        onChanged: (v) => _setInner((pid) => pid.i = v),
      ),
      _slider(
        label: '$name D',
        value: editedPid.d,
        fcValue: fcPid.d,
        min: 0,
        max: 1,
        onChanged: (v) => _setInner((pid) => pid.d = v),
      ),
    ];
  }

  double _outerEdited() => switch (_axis) {
        _Axis.roll => _edited.outerRollP,
        _Axis.pitch => _edited.outerPitchP,
        _Axis.yaw => _edited.outerYawP,
      };

  double _outerFc() => switch (_axis) {
        _Axis.roll => _fc.outerRollP,
        _Axis.pitch => _fc.outerPitchP,
        _Axis.yaw => _fc.outerYawP,
      };

  void _setOuter(double v) {
    setState(() {
      switch (_axis) {
        case _Axis.roll:
          _edited.outerRollP = v;
          if (_linkRollPitch) _edited.outerPitchP = v;
        case _Axis.pitch:
          _edited.outerPitchP = v;
          if (_linkRollPitch) _edited.outerRollP = v;
        case _Axis.yaw:
          _edited.outerYawP = v;
      }
    });
  }

  _Pid _innerEdited() => switch (_axis) {
        _Axis.roll => _edited.innerRoll,
        _Axis.pitch => _edited.innerPitch,
        _Axis.yaw => _edited.innerYaw,
      };

  _Pid _innerFc() => switch (_axis) {
        _Axis.roll => _fc.innerRoll,
        _Axis.pitch => _fc.innerPitch,
        _Axis.yaw => _fc.innerYaw,
      };

  void _setInner(void Function(_Pid pid) update) {
    setState(() {
      switch (_axis) {
        case _Axis.roll:
          update(_edited.innerRoll);
          if (_linkRollPitch) {
            _edited.innerPitch.p = _edited.innerRoll.p;
            _edited.innerPitch.i = _edited.innerRoll.i;
            _edited.innerPitch.d = _edited.innerRoll.d;
          }
        case _Axis.pitch:
          update(_edited.innerPitch);
          if (_linkRollPitch) {
            _edited.innerRoll.p = _edited.innerPitch.p;
            _edited.innerRoll.i = _edited.innerPitch.i;
            _edited.innerRoll.d = _edited.innerPitch.d;
          }
        case _Axis.yaw:
          update(_edited.innerYaw);
      }
    });
  }

  Widget _slider({
    required String label,
    required double value,
    required double fcValue,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    final drifted = (value - fcValue).abs() > 0.0005;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.forest.withValues(alpha: 0.45),
                inactiveTrackColor: AppColors.border,
                thumbColor: AppColors.cta,
                overlayColor: AppColors.forest.withValues(alpha: 0.12),
                trackHeight: 2.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value.toStringAsFixed(2),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: drifted ? AppColors.warning : AppColors.text,
                  ),
                ),
                Text(
                  'FC ${fcValue.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 9, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}