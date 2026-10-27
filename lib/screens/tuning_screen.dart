import 'package:flutter/material.dart';
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
    this.outerRollP = 4.5,
    this.outerPitchP = 4.5,
    this.outerYawP = 3.0,
    _Pid? innerRoll,
    _Pid? innerPitch,
    _Pid? innerYaw,
    _Pid? altHold,
  })  : innerRoll = innerRoll ?? _Pid(p: 0.15, i: 0.05, d: 0.02),
        innerPitch = innerPitch ?? _Pid(p: 0.15, i: 0.05, d: 0.02),
        innerYaw = innerYaw ?? _Pid(p: 0.20, i: 0.04, d: 0.00),
        altHold = altHold ?? _Pid(p: 0.80, i: 0.10, d: 0.05);

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

class TuningScreen extends StatefulWidget {
  const TuningScreen({super.key, this.armed = false});

  final bool armed;

  @override
  State<TuningScreen> createState() => _TuningScreenState();
}

class _TuningScreenState extends State<TuningScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late _Gains _fc;
  late _Gains _edited;

  _Axis _axis = _Axis.roll;
  bool _linkRollPitch = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _fc = _Gains();
    _edited = _fc.clone();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _write() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() {
      _fc = _edited.clone();
      _edited = _fc.clone();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Write verified — FC values updated')),
    );
  }

  Future<void> _saveToFc() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Save to FC?'),
        content: const Text(
          'Store current gains in non-volatile memory on the flight controller.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _write();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved to FC non-volatile memory')),
    );
  }

  void _revert() {
    setState(() => _edited = _fc.clone());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reverted to FC values')),
    );
  }

  bool get _dirty {
    // Cheap “unsaved edits” hint for the footer.
    return _edited.outerRollP != _fc.outerRollP ||
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
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: AppColors.surface,
          child: TabBar(
            controller: _tabs,
            onTap: (_) => setState(() {}),
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.muted,
            indicatorColor: AppColors.accent,
            indicatorWeight: 2.5,
            tabs: const [
              Tab(text: 'Outer loop'),
              Tab(text: 'Inner loop'),
              Tab(text: 'Alt Hold'),
            ],
          ),
        ),
        if (widget.armed)
          Container(
            width: double.infinity,
            color: AppColors.danger.withOpacity(0.15),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: const Text(
              'Armed — Write / Save disabled',
              style: TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            children: [
              if (_tabs.index != _Tab.altHold.index) ...[
                _axisChips(),
                const SizedBox(height: 12),
              ],
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(children: _buildSliders()),
              ),
              if (_tabs.index == _Tab.inner.index) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppColors.accent,
                  title: const Text(
                    'Link roll + pitch',
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Editing one axis copies values to the other',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  value: _linkRollPitch,
                  onChanged: (v) =>
                      setState(() => _linkRollPitch = v ?? true),
                ),
              ],
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            children: [
              if (_dirty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Unsaved edits — Write to push to FC',
                      style: TextStyle(fontSize: 11, color: AppColors.warning),
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.armed ? null : _write,
                      child: const Text('Write'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                      ),
                      onPressed: widget.armed ? null : _saveToFc,
                      child: const Text('Save to FC'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.surface2,
                        foregroundColor: AppColors.text,
                      ),
                      onPressed: _revert,
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
        selectedColor: AppColors.accent,
        backgroundColor: AppColors.surface2,
        labelStyle: TextStyle(
          color: on ? Colors.white : AppColors.muted,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        side: BorderSide(color: on ? AppColors.accent : AppColors.border),
        onSelected: (_) => setState(() => _axis = axis),
      );
    }

    return Wrap(
      spacing: 8,
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
          label: '$name P',
          value: _outerEdited(),
          fcValue: _outerFc(),
          min: 0,
          max: 10,
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
          max: 2,
          onChanged: (v) => setState(() => _edited.altHold.p = v),
        ),
        _slider(
          label: 'Alt I',
          value: _edited.altHold.i,
          fcValue: _fc.altHold.i,
          min: 0,
          max: 1,
          onChanged: (v) => setState(() => _edited.altHold.i = v),
        ),
        _slider(
          label: 'Alt D',
          value: _edited.altHold.d,
          fcValue: _fc.altHold.d,
          min: 0,
          max: 1,
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
        max: 1,
        onChanged: (v) => _setInner((pid) => pid.p = v),
      ),
      _slider(
        label: '$name I',
        value: editedPid.i,
        fcValue: fcPid.i,
        min: 0,
        max: 1,
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.accent,
                inactiveTrackColor: AppColors.border,
                thumbColor: AppColors.accent,
                overlayColor: AppColors.accent.withOpacity(0.15),
                trackHeight: 3,
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
            width: 78,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value.toStringAsFixed(2),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: drifted ? AppColors.warning : AppColors.text,
                  ),
                ),
                Text(
                  'FC ${fcValue.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}