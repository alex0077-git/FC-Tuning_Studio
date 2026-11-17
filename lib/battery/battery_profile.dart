import 'package:shared_preferences/shared_preferences.dart';

/// LiPo cell count shown on the Battery page.
enum BatteryCellType {
  s3(3, '3S'),
  s4(4, '4S'),
  s6(6, '6S');

  const BatteryCellType(this.cells, this.label);
  final int cells;
  final String label;

  static BatteryCellType fromCells(int n) {
    for (final e in BatteryCellType.values) {
      if (e.cells == n) return e;
    }
    return BatteryCellType.s4;
  }
}

/// User pack curve for status-bar % and warning thresholds.
/// Voltage always comes from FC SYS_STATUS; % is computed in-app from this profile.
class BatteryProfile {
  const BatteryProfile({
    required this.cellType,
    required this.fullVolts,
    required this.warnVolts,
    required this.criticalVolts,
  });

  /// Per-cell defaults matching current 4S studio setpoints.
  static const double cellFullV = 4.20;
  static const double cellWarnV = 3.95;
  static const double cellCriticalV = 3.825;

  /// Default = 4S / current Tuning Studio constants.
  static final defaults = forCellType(BatteryCellType.s4);

  static BatteryProfile forCellType(BatteryCellType type) {
    final n = type.cells.toDouble();
    return BatteryProfile(
      cellType: type,
      fullVolts: _r2(cellFullV * n),
      warnVolts: _r2(cellWarnV * n),
      criticalVolts: _r2(cellCriticalV * n),
    );
  }

  static double _r2(double v) => double.parse(v.toStringAsFixed(2));

  final BatteryCellType cellType;
  final double fullVolts;
  final double warnVolts;
  final double criticalVolts;

  BatteryProfile copyWith({
    BatteryCellType? cellType,
    double? fullVolts,
    double? warnVolts,
    double? criticalVolts,
  }) {
    return BatteryProfile(
      cellType: cellType ?? this.cellType,
      fullVolts: fullVolts ?? this.fullVolts,
      warnVolts: warnVolts ?? this.warnVolts,
      criticalVolts: criticalVolts ?? this.criticalVolts,
    );
  }

  /// Require: full > warn > critical > 0
  String? validate() {
    if (fullVolts <= 0 || warnVolts <= 0 || criticalVolts <= 0) {
      return 'All voltages must be > 0';
    }
    if (!(fullVolts > warnVolts && warnVolts > criticalVolts)) {
      return 'Need 100% V > first warning > second warning';
    }
    return null;
  }

  /// % from live FC volts. Returns null if volts missing / curve invalid.
  int? percentForVolts(double volts) {
    final span = fullVolts - criticalVolts;
    if (span <= 0) return null;
    final p = ((volts - criticalVolts) / span) * 100.0;
    if (p.isNaN || p.isInfinite) return null;
    if (p <= 0) return 0;
    if (p >= 100) return 100;
    return p.round();
  }

  String labelForVolts(double? volts) {
    if (volts == null) return '—';
    final pct = percentForVolts(volts);
    if (pct == null) return '${volts.toStringAsFixed(2)}V';
    return '${volts.toStringAsFixed(2)}V  $pct%';
  }
}

class BatteryProfileStore {
  static const _kCells = 'batt_cells';
  static const _kFull = 'batt_full_v';
  static const _kWarn = 'batt_warn_v';
  static const _kCrit = 'batt_crit_v';

  Future<BatteryProfile> load() async {
    final p = await SharedPreferences.getInstance();
    final cells = p.getInt(_kCells) ?? BatteryCellType.s4.cells;
    final type = BatteryCellType.fromCells(cells);
    final preset = BatteryProfile.forCellType(type);
    return BatteryProfile(
      cellType: type,
      fullVolts: p.getDouble(_kFull) ?? preset.fullVolts,
      warnVolts: p.getDouble(_kWarn) ?? preset.warnVolts,
      criticalVolts: p.getDouble(_kCrit) ?? preset.criticalVolts,
    );
  }

  Future<void> save(BatteryProfile profile) async {
    final err = profile.validate();
    if (err != null) throw StateError(err);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kCells, profile.cellType.cells);
    await p.setDouble(_kFull, profile.fullVolts);
    await p.setDouble(_kWarn, profile.warnVolts);
    await p.setDouble(_kCrit, profile.criticalVolts);
  }
}