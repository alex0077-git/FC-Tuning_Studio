/// ASCII SD flight-log protocol (USB VCP today; MAV tunnel later).
/// Contract: Fuselage FC — SD Flight Logs Flutter hand-off.

const String kSdCsvHeader =
    't_ms,seq,armed,roll,pitch,yaw,gx,gy,gz,bp_pa,z_m,z_raw,ah_en,ah_act,'
    'tgt,err,dU,i_us,base_us,ch_roll,ch_pitch,ch_thr,ch_yaw,ch_arm,ch_alt,'
    'gps_fix,lat_e7,lon_e7,alt_mm,vn_cms,ve_cms,vd_cms,sats,m1,m2,m3,m4';

class SdFlightEntry {
  const SdFlightEntry({
    required this.id,
    required this.file,
    required this.tag,
    required this.rows,
    required this.drops,
    required this.durS,
  });

  final int id;
  final String file;
  final String tag;
  final int rows;
  final int drops;
  final int durS;
}

enum SdLogJobKind { list, dump, wipe, stat }

enum SdLogOutcome {
  ok,
  empty,
  busy,
  sdNone,
  disarmFirst,
  noSuchLog,
  abort,
  wipeFail,
  timeout,
  parseError,
}

class SdLogResult {
  const SdLogResult({
    required this.outcome,
    this.entries = const [],
    this.csvBody,
    this.message,
  });

  final SdLogOutcome outcome;
  final List<SdFlightEntry> entries;
  final String? csvBody;
  final String? message;

  bool get ok =>
      outcome == SdLogOutcome.ok || outcome == SdLogOutcome.empty;
}

/// Collects lines until `LOG END` (or busy/error).
class SdLogLineCollector {
  final List<String> lines = <String>[];
  bool finished = false;
  String? terminalError;

  /// Returns true when the job is complete.
  bool addLine(String raw) {
    final line = raw.trimRight();
    if (line.isEmpty && lines.isEmpty) return false;

    final low = line.toLowerCase();
    if (low == 'busy') {
      terminalError = 'busy';
      finished = true;
      return true;
    }
    if (low == 'log end') {
      finished = true;
      return true;
    }

    lines.add(line);
    return false;
  }
}

SdLogResult parseLogList(List<String> lines) {
  final body = lines
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  if (body.any((l) => l.toLowerCase() == 'busy')) {
    return const SdLogResult(outcome: SdLogOutcome.busy, message: 'busy');
  }
  if (body.any((l) => l.toLowerCase().startsWith('sd none'))) {
    return const SdLogResult(outcome: SdLogOutcome.sdNone, message: 'SD none');
  }
  if (body.any((l) => l.toLowerCase().contains('disarm first'))) {
    return const SdLogResult(
      outcome: SdLogOutcome.disarmFirst,
      message: 'disarm first',
    );
  }

  // Skip banner / header.
  final data = <String>[];
  for (final l in body) {
    final low = l.toLowerCase();
    if (low == 'log list') continue;
    if (low.startsWith('id,file')) continue;
    if (low == 'no logs') {
      return const SdLogResult(outcome: SdLogOutcome.empty, message: 'no logs');
    }
    data.add(l);
  }

  if (data.isEmpty) {
    return const SdLogResult(outcome: SdLogOutcome.empty, message: 'no logs');
  }

  final entries = <SdFlightEntry>[];
  for (final row in data) {
    final parts = row.split(',');
    if (parts.length < 6) continue;
    final id = int.tryParse(parts[0].trim());
    if (id == null) continue;
    entries.add(
      SdFlightEntry(
        id: id,
        file: parts[1].trim(),
        tag: parts[2].trim(),
        rows: int.tryParse(parts[3].trim()) ?? 0,
        drops: int.tryParse(parts[4].trim()) ?? 0,
        durS: int.tryParse(parts[5].trim()) ?? 0,
      ),
    );
  }

  if (entries.isEmpty) {
    return const SdLogResult(
      outcome: SdLogOutcome.parseError,
      message: 'Could not parse LOG LIST',
    );
  }
  return SdLogResult(outcome: SdLogOutcome.ok, entries: entries);
}

SdLogResult parseLogDump(List<String> lines) {
  final body = lines.map((l) => l.trimRight()).toList();
  final joinedLow = body.map((l) => l.toLowerCase()).toList();

  if (joinedLow.any((l) => l == 'busy')) {
    return const SdLogResult(outcome: SdLogOutcome.busy, message: 'busy');
  }
  if (joinedLow.any((l) => l.startsWith('sd none'))) {
    return const SdLogResult(outcome: SdLogOutcome.sdNone, message: 'SD none');
  }
  if (joinedLow.any((l) => l.contains('disarm first'))) {
    return const SdLogResult(
      outcome: SdLogOutcome.disarmFirst,
      message: 'disarm first',
    );
  }
  if (joinedLow.any((l) => l.contains('no such log'))) {
    return const SdLogResult(
      outcome: SdLogOutcome.noSuchLog,
      message: 'no such log',
    );
  }
  if (joinedLow.any((l) => l == 'log abort')) {
    return const SdLogResult(outcome: SdLogOutcome.abort, message: 'LOG ABORT');
  }

  // Keep everything before a possible abort; LOG END already stripped by collector.
  final csvLines = <String>[];
  for (final l in body) {
    final low = l.toLowerCase();
    if (low == 'log abort') break;
    if (low == 'log end') continue;
    if (l.trim().isEmpty) continue;
    csvLines.add(l);
  }

  if (csvLines.isEmpty) {
    return const SdLogResult(
      outcome: SdLogOutcome.parseError,
      message: 'Empty dump',
    );
  }

  return SdLogResult(
    outcome: SdLogOutcome.ok,
    csvBody: '${csvLines.join('\n')}\n',
  );
}

SdLogResult parseLogWipe(List<String> lines) {
  final body = lines.map((l) => l.trim().toLowerCase()).toList();
  if (body.any((l) => l.contains('wipe fail'))) {
    return const SdLogResult(
      outcome: SdLogOutcome.wipeFail,
      message: 'LOG wipe fail',
    );
  }
  if (body.any((l) => l.contains('disarm first'))) {
    return const SdLogResult(
      outcome: SdLogOutcome.disarmFirst,
      message: 'disarm first',
    );
  }
  if (body.any((l) => l.contains('wiped') || l == 'log wiped')) {
    return const SdLogResult(outcome: SdLogOutcome.ok, message: 'LOG wiped');
  }
  // Some firmwares only send LOG END after wipe with little text.
  if (body.isEmpty) {
    return const SdLogResult(outcome: SdLogOutcome.ok, message: 'LOG wiped');
  }
  return SdLogResult(
    outcome: SdLogOutcome.parseError,
    message: body.join(' | '),
  );
}
