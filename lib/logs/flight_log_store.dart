import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'public_downloads.dart';

class SavedFlightLog {
  const SavedFlightLog({
    required this.file,
    required this.name,
    required this.bytes,
    required this.modified,
    required this.rows,
  });

  final File file;
  final String name;
  final int bytes;
  final DateTime modified;
  final int rows;
}

/// Saves reassembled STATUSTEXT live-log lines (Phase B Live Log pack).
class FlightLogStore {
  FlightLogStore();

  final List<String> _buffer = <String>[];

  int get bufferRows => _buffer.length;

  Future<Directory> _dir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/fc_flights');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  void clearBuffer() => _buffer.clear();

  void addLiveLine(String line) {
    final t = line.trim();
    if (t.isEmpty) return;
    _buffer.add(t);
  }

  Future<SavedFlightLog?> saveBuffer({String? tag}) async {
    if (_buffer.isEmpty) return null;
    final dir = await _dir();
    final stamp = DateTime.now();
    final safeTag = (tag == null || tag.trim().isEmpty)
        ? 'LIVELOG'
        : tag.trim().replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_').toUpperCase();
    final name =
        '${safeTag}_${stamp.year.toString().padLeft(4, '0')}'
        '${stamp.month.toString().padLeft(2, '0')}'
        '${stamp.day.toString().padLeft(2, '0')}_'
        '${stamp.hour.toString().padLeft(2, '0')}'
        '${stamp.minute.toString().padLeft(2, '0')}'
        '${stamp.second.toString().padLeft(2, '0')}.txt';
    final file = File('${dir.path}/$name');
    final body = StringBuffer();
    for (final row in _buffer) {
      body.writeln(row);
    }
    await file.writeAsString(body.toString());
    final rows = _buffer.length;
    _buffer.clear();
    final stat = await file.stat();
    return SavedFlightLog(
      file: file,
      name: name,
      bytes: stat.size,
      modified: stat.modified,
      rows: rows,
    );
  }

  Future<SavedFlightLog?> saveAndContinue({String? tag}) async {
    return saveBuffer(tag: tag);
  }

  Future<List<SavedFlightLog>> listSaved() async {
    final dir = await _dir();
    final files = await dir
        .list()
        .where(
          (e) =>
              e is File &&
              (e.path.toLowerCase().endsWith('.txt') ||
                  e.path.toLowerCase().endsWith('.csv')),
        )
        .cast<File>()
        .toList();
    final out = <SavedFlightLog>[];
    for (final f in files) {
      final stat = await f.stat();
      final text = await f.readAsString();
      final rows = text.split('\n').where((l) => l.trim().isNotEmpty).length;
      out.add(
        SavedFlightLog(
          file: f,
          name: f.uri.pathSegments.last,
          bytes: stat.size,
          modified: stat.modified,
          rows: rows,
        ),
      );
    }
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }

  Future<void> delete(SavedFlightLog log) async {
    if (await log.file.exists()) {
      await log.file.delete();
    }
  }

  /// One-click export into public Download/FC_Tuning (Files app visible).
  Future<String> exportToDownloads(SavedFlightLog log) async {
    final bytes = Uint8List.fromList(await log.file.readAsBytes());
    return PublicDownloads.saveFile(fileName: log.name, bytes: bytes);
  }

  /// Export every saved flight file into Download/FC_Tuning in one click.
  Future<int> exportAllToDownloads() async {
    final list = await listSaved();
    var n = 0;
    for (final log in list) {
      await exportToDownloads(log);
      n += 1;
    }
    return n;
  }
}
