import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../battery/battery_profile.dart';
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Battery profile',
            style: AppFonts.display(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Pick cell type to load pack defaults, then fine-tune voltages. '
            'Need: 100% V > first warning > second warning.',
            style: AppFonts.body(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          Text(
            'Cell type',
            style: AppFonts.body(fontSize: 13, fontWeight: FontWeight.w600),
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
          const SizedBox(height: 10),
          _field(
            label: '100% voltage (V)',
            helper: 'Full pack ($_cellType → ${BatteryProfile.forCellType(_cellType).fullVolts.toStringAsFixed(2)} V suggested)',
            controller: _fullCtrl,
          ),
          const SizedBox(height: 10),
          _field(
            label: 'First warning (V)',
            helper: 'Dismissible dialog',
            controller: _warnCtrl,
          ),
          const SizedBox(height: 10),
          _field(
            label: 'Second warning (V)',
            helper: 'LAND NOW lock + 0% floor for %',
            controller: _critCtrl,
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: AppFonts.body(fontSize: 12, color: AppColors.danger)),
          ],
          const Spacer(),
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
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppFonts.body(fontSize: 13, fontWeight: FontWeight.w600)),
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