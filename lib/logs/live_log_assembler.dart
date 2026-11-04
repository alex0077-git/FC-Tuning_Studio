/// Reassembles FC chunked STATUSTEXT live-log lines (`+` continue / `=` end).
class LiveLogAssembler {
  String _acc = '';

  /// Returns a complete log line when a final `=` chunk arrives; otherwise null.
  String? pushChunk(String text) {
    if (text.isEmpty) return null;
    final mark = text.codeUnitAt(0);
    final body = text.length > 1 ? text.substring(1) : '';
    if (mark == 0x2B) {
      // '+'
      _acc += body;
      return null;
    }
    if (mark == 0x3D) {
      // '='
      _acc += body;
      final line = _acc.trim();
      _acc = '';
      return line.isEmpty ? null : line;
    }
    // Ignore non-live-log STATUSTEXT.
    return null;
  }

  void reset() => _acc = '';
}

/// Parsed fields from one reassembled VCP-style status line.
class LiveLogFields {
  const LiveLogFields({
    this.mode,
    this.seq,
    this.armed,
    this.gx,
    this.gy,
    this.gz,
    this.roll,
    this.pitch,
    this.yaw,
    this.bpPa,
    this.tempC,
    this.zM,
    this.zRaw,
    this.ahEn,
    this.ahAct,
    this.tgt,
    this.err,
    this.dU,
    this.iUs,
    this.m1,
    this.m2,
    this.m3,
    this.m4,
    this.gpsFix,
    this.sats,
  });

  final String? mode;
  final int? seq;
  final bool? armed;
  final double? gx;
  final double? gy;
  final double? gz;
  final double? roll;
  final double? pitch;
  final double? yaw;
  final double? bpPa;
  final double? tempC;
  final double? zM;
  final double? zRaw;
  final int? ahEn;
  final int? ahAct;
  final double? tgt;
  final double? err;
  final double? dU;
  final double? iUs;
  final int? m1;
  final int? m2;
  final int? m3;
  final int? m4;
  final int? gpsFix;
  final int? sats;

  static final _mode = RegExp(r'\[(DMA|poll)\]');
  static final _seq = RegExp(r'\bs(\d+)\b');
  static final _arm = RegExp(r'\b(ARM|DIS)\b');
  static final _gyro = RegExp(
    r'G\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+dps',
  );
  static final _att = RegExp(
    r'R\s+(-?\d+(?:\.\d+)?)\s+P\s+(-?\d+(?:\.\d+)?)\s+Y\s+(-?\d+(?:\.\d+)?)',
  );
  static final _baro = RegExp(
    r'BP\s+(-?\d+(?:\.\d+)?)\s+Pa\s+T\s+(-?\d+(?:\.\d+)?)\s+C',
  );
  static final _z = RegExp(
    r'Z\s+(-?\d+(?:\.\d+)?)\s+raw\s+(-?\d+(?:\.\d+)?)',
  );
  static final _ah = RegExp(
    r'AH\s+en=(\d+)\s+act=(\d+)\s+tgt\s+(-?\d+(?:\.\d+)?)\s+err\s+(-?\d+(?:\.\d+)?)\s+dU\s+(-?\d+(?:\.\d+)?)\s+i\s+(-?\d+(?:\.\d+)?)',
  );
  static final _motors = RegExp(
    r'M\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+us',
  );
  static final _gps = RegExp(r'GPS\s+(\d+)\s+sats=(\d+)');

  static double? _d(String? s) => s == null ? null : double.tryParse(s);
  static int? _i(String? s) => s == null ? null : int.tryParse(s);

  static LiveLogFields parse(String line) {
    final mode = _mode.firstMatch(line)?.group(1);
    final seq = _i(_seq.firstMatch(line)?.group(1));
    final armTok = _arm.firstMatch(line)?.group(1);
    final g = _gyro.firstMatch(line);
    final a = _att.firstMatch(line);
    final b = _baro.firstMatch(line);
    final z = _z.firstMatch(line);
    final ah = _ah.firstMatch(line);
    final m = _motors.firstMatch(line);
    final gps = _gps.firstMatch(line);
    return LiveLogFields(
      mode: mode,
      seq: seq,
      armed: armTok == null ? null : armTok == 'ARM',
      gx: _d(g?.group(1)),
      gy: _d(g?.group(2)),
      gz: _d(g?.group(3)),
      roll: _d(a?.group(1)),
      pitch: _d(a?.group(2)),
      yaw: _d(a?.group(3)),
      bpPa: _d(b?.group(1)),
      tempC: _d(b?.group(2)),
      zM: _d(z?.group(1)),
      zRaw: _d(z?.group(2)),
      ahEn: _i(ah?.group(1)),
      ahAct: _i(ah?.group(2)),
      tgt: _d(ah?.group(3)),
      err: _d(ah?.group(4)),
      dU: _d(ah?.group(5)),
      iUs: _d(ah?.group(6)),
      m1: _i(m?.group(1)),
      m2: _i(m?.group(2)),
      m3: _i(m?.group(3)),
      m4: _i(m?.group(4)),
      gpsFix: _i(gps?.group(1)),
      sats: _i(gps?.group(2)),
    );
  }
}
