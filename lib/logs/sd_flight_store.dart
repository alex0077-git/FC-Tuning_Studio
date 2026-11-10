import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'public_downloads.dart';

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
    final name = PublicDownloads.csvFileName(preferredName, id: id);
    final file = File('${dir.path}/$name');
    await file.writeAsString(csvBody);
    return file;
  }

  /// One-click: copy into public **Download/FC_Tuning** (Files app visible).
  Future<String> exportToDownloads(File src) async {
    final name = PublicDownloads.csvFileName(
      src.uri.pathSegments.isNotEmpty ? src.uri.pathSegments.last : src.path,
      id: 0,
    );
    final bytes = Uint8List.fromList(await src.readAsBytes());
    return PublicDownloads.saveFile(fileName: name, bytes: bytes);
  }
}
