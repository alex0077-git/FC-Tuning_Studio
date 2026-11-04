import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persists downloaded SD flight CSVs (separate from Live Log session files).
class SdFlightStore {
  Future<Directory> _dir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/fc_sd_flights');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> saveCsv({
    required int id,
    required String preferredName,
    required String csvBody,
  }) async {
    final dir = await _dir();
    var name = preferredName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (!name.toLowerCase().endsWith('.csv')) name = '$name.csv';
    if (name.isEmpty || name == '.csv') {
      name = 'LOG${id.toString().padLeft(4, '0')}.CSV';
    }
    final file = File('${dir.path}/$name');
    await file.writeAsString(csvBody);
    return file;
  }

  Future<File> exportToDownloads(File src) async {
    Directory? dest;
    for (final path in const [
      '/storage/emulated/0/Download/FC_Tuning',
      '/sdcard/Download/FC_Tuning',
    ]) {
      try {
        final d = Directory(path);
        if (!await d.exists()) await d.create(recursive: true);
        final probe = File('${d.path}/.fc_write_probe');
        await probe.writeAsString('ok');
        await probe.delete();
        dest = d;
        break;
      } catch (_) {
        continue;
      }
    }
    dest ??= await _dir();
    final out = File('${dest.path}/${src.uri.pathSegments.last}');
    await src.copy(out.path);
    return out;
  }
}
