import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Saves bytes into public **Download/FC_Tuning** (visible in the Files app).
class PublicDownloads {
  PublicDownloads._();

  static const _channel = MethodChannel('fc_tuning_studio/downloads');

  /// Returns a human path like `Download/FC_Tuning/LOG0001.csv`.
  static Future<String> saveFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Public Downloads not supported on web');
    }
    if (!Platform.isAndroid) {
      // Desktop/dev: write next to a local Downloads-style folder when possible.
      final home = Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          '.';
      final dir = Directory('$home${Platform.pathSeparator}Downloads'
          '${Platform.pathSeparator}FC_Tuning');
      if (!await dir.exists()) await dir.create(recursive: true);
      final out = File('${dir.path}${Platform.pathSeparator}$fileName');
      await out.writeAsBytes(bytes, flush: true);
      return out.path;
    }
    final path = await _channel.invokeMethod<String>('saveToDownloads', {
      'fileName': fileName,
      'bytes': bytes,
    });
    if (path == null || path.isEmpty) {
      throw StateError('Downloads bridge returned empty path');
    }
    return path;
  }

  /// Force a CSV file name (replaces .txt / missing extension).
  static String csvFileName(String preferred, {required int id}) {
    var name = preferred.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final lower = name.toLowerCase();
    if (lower.endsWith('.txt') || lower.endsWith('.log')) {
      name = '${name.substring(0, name.lastIndexOf('.'))}.csv';
    } else if (!lower.endsWith('.csv')) {
      name = '$name.csv';
    }
    if (name.isEmpty || name == '.csv') {
      name = 'LOG${id.toString().padLeft(4, '0')}.csv';
    }
    return name;
  }
}
