import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../battery/battery_profile.dart';
import '../layout/g20_metrics.dart';
import '../theme/app_theme.dart';

class BatteryScreen extends StatefulWidget {
  const BatteryScreen({
    super.key,
    required this.profile,
    required this.onSaved,
  });

  final BatteryProfile profile;
  final ValueChanged<BatteryProfile> onSaved;

  @override
  State<BatteryScreen> createState() => _BatteryScreenState();
}

class _BatteryScreenState extends State<BatteryScreen> {
  final _store = BatteryProfileStore();
  late BatteryCellType _cellType;
  late final TextEditingController _fullCtrl;
  late final TextEditingController _warnCtrl;
  late final TextEditingController _critCtrl;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _cellType = widget.profile.cellType;
    _fullCtrl = TextEditingController(text: widget.profile.fullVolts.toStringAsFixed(2));
    _warnCtrl = TextEditingController(text: widget.profile.warnVolts.toStringAsFixed(2));
    _critCtrl = TextEditingController(text: widget.profile.criticalVolts.toStringAsFixed(2));
  }

  @override
  void didUpdateWidget(covariant BatteryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile != widget.profile) {
      _applyProfile(widget.profile);
    }
  }

  void _applyProfile(BatteryProfile p) {
    _cellType = p.cellType;
    _fullCtrl.text = p.fullVolts.toStringAsFixed(2);
    _warnCtrl.text = p.warnVolts.toStringAsFixed(2);
    _critCtrl.text = p.criticalVolts.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _fullCtrl.dispose();
    _warnCtrl.dispose();
    _critCtrl.dispose();
    super.dispose();
  }

  double? _parse(TextEditingController c) => double.tryParse(c.text.trim());

  void _onCellTypeChanged(BatteryCellType? type) {
    if (type == null) return;
    final preset = BatteryProfile.forCellType(type);
    setState(() {
      _cellType = type;
      _fullCtrl.text = preset.fullVolts.toStringAsFixed(2);
      _warnCtrl.text = preset.warnVolts.toStringAsFixed(2);
      _critCtrl.text = preset.criticalVolts.toStringAsFixed(2);
      _error = null;
    });
  }

  Future<void> _save() async {
    final full = _parse(_fullCtrl);
    final warn = _parse(_warnCtrl);
    final crit = _parse(_critCtrl);
    if (full == null || warn == null || crit == null) {
      setState(() => _error = 'Enter valid numbers (e.g. 16.80)');
      return;
    }
    final next = BatteryProfile(
      cellType: _cellType,
      fullVolts: full,
      warnVolts: warn,
      criticalVolts: crit,
    );
    final err = next.validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await _store.save(next);
      if (!mounted) return;
      widget.onSaved(next);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Battery profile saved (${next.cellType.label})')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetDefaults() {
    final d = BatteryProfile.defaults;
    setState(() {
      _applyProfile(d);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final g20 = G20Metrics.of(context);
    final pad = g20.pagePad;
    final gap = g20.compactChrome ? 8.0 : 10.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(pad, pad, pad, pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                Text(
                  'Battery profile',
                  style: AppFonts.display(
                    fontSize: g20.titleSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: g20.compactChrome ? 2 : 4),
                Text(
                  'Pick cell type to load pack defaults, then fine-tune voltages. '
                  'Need: 100% V > first warning > second warning.',
                  style: AppFonts.body(
                    fontSize: g20.bodySize,
                    color: AppColors.muted,
                  ),
                ),
                SizedBox(height: g20.compactChrome ? 10 : 14),
                Text(
                  'Cell type',
                  style: AppFonts.body(
                    fontSize: g20.bodySize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                DropdownButtonFormField<BatteryCellType>(
                  value: _cellType,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    helperText: 'Changing type reloads suggested pack voltages',
                  ),
                  items: [
                    for (final t in BatteryCellType.values)
                      DropdownMenuItem(value: t, child: Text('${t.label} LiPo')),
                  ],
                  onChanged: _onCellTypeChanged,
                ),
                SizedBox(height: gap),
                _field(
                  label: '100% voltage (V)',
                  helper:
                      'Full pack ($_cellType → ${BatteryProfile.forCellType(_cellType).fullVolts.toStringAsFixed(2)} V suggested)',
                  controller: _fullCtrl,
                  bodySize: g20.bodySize,
                ),
                SizedBox(height: gap),
                _field(
                  label: 'First warning (V)',
                  helper: 'Dismissible dialog',
                  controller: _warnCtrl,
                  bodySize: g20.bodySize,
                ),
                SizedBox(height: gap),
                _field(
                  label: 'Second warning (V)',
                  helper: 'LAND NOW lock + 0% floor for %',
                  controller: _critCtrl,
                  bodySize: g20.bodySize,
                ),
                if (_error != null) ...[
                  SizedBox(height: gap),
                  Text(
                    _error!,
                    style: AppFonts.body(fontSize: 12, color: AppColors.danger),
                  ),
                ],
                // Extra room so keyboard / short G20 screens can scroll past last field.
                SizedBox(height: g20.compactChrome ? 12 : 16),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : _resetDefaults,
                  child: const Text('Reset defaults'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required String helper,
    required TextEditingController controller,
    required double bodySize,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppFonts.body(fontSize: bodySize, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: InputDecoration(
            hintText: '0.00',
            helperText: helper,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}