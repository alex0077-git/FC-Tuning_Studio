import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Field tile cache — same sources as FC-Frontend [MapTileLayer].
///
/// Street: OpenStreetMap. Satellite (default cache): Esri World Imagery.
class OfflineTileStore {
  OfflineTileStore._(this._root);

  final Directory _root;

  static const _prefsLat = 'gps_field_lat';
  static const _prefsLon = 'gps_field_lon';
  static const _prefsReady = 'gps_field_tiles_ready_v2';
  static const _prefsCount = 'gps_field_tile_count_v2';

  /// Same URLs as `D:\FC-Frontend\lib\core\map\map_view.dart`.
  static const streetUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const satelliteUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

  /// Prefer Esri for cache + live map — OSM often returns 403 to app bulk fetches.
  static const tileUrlTemplate = satelliteUrl;

  /// Match FC-Frontend flutter_map User-Agent package id.
  static const userAgentPackageName = 'fc_frontend';
  static const userAgent = 'fc_frontend';

  /// Slightly over 1 km so edges stay covered at the pad.
  static const fieldRadiusM = 1200.0;
  static const minZoom = 14;
  static const maxZoom = 18;

  static final Uint8List _pngMagic =
      Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);

  static OfflineTileStore? _instance;

  static Future<OfflineTileStore> instance() async {
    if (_instance != null) return _instance!;
    final support = await getApplicationSupportDirectory();
    // New folder — old osm_tiles may hold OSM 403 error PNGs.
    final root = Directory('${support.path}/esri_tiles');
    await root.create(recursive: true);
    _instance = OfflineTileStore._(root);
    return _instance!;
  }

  File tileFile(int z, int x, int y) =>
      File('${_root.path}/$z/$x/$y.png');

  String tileUrl(int z, int x, int y) => tileUrlTemplate
      .replaceAll('{z}', '$z')
      .replaceAll('{x}', '$x')
      .replaceAll('{y}', '$y');

  Future<bool> hasTile(int z, int x, int y) => tileFile(z, x, y).exists();

  /// Disk first; if missing and online, download + save. Throws if neither works.
  Future<List<int>> loadTileBytes(int z, int x, int y) async {
    final file = tileFile(z, x, y);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      if (_looksLikePng(bytes)) return bytes;
      // Corrupt / old error body — refetch.
      try {
        await file.delete();
      } catch (_) {}
    }
    final bytes = await _download(tileUrl(z, x, y));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return bytes;
  }

  Future<List<int>> _download(String url) async {
    final res = await http.get(
      Uri.parse(url),
      headers: {'User-Agent': userAgent},
    );
    if (res.statusCode != 200) {
      throw HttpException('Tile HTTP ${res.statusCode}', uri: Uri.parse(url));
    }
    final bytes = res.bodyBytes;
    if (!_looksLikePng(bytes)) {
      throw HttpException('Tile not PNG', uri: Uri.parse(url));
    }
    // OSM 403 error tiles are tiny PNGs; real map tiles are larger.
    if (bytes.length < 500) {
      throw HttpException('Tile too small (${bytes.length} B)', uri: Uri.parse(url));
    }
    return bytes;
  }

  static bool _looksLikePng(List<int> bytes) {
    if (bytes.length < 8) return false;
    for (var i = 0; i < 4; i++) {
      if (bytes[i] != _pngMagic[i]) return false;
    }
    return true;
  }

  Future<void> rememberFieldCenter(LatLng c) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_prefsLat, c.latitude);
    await p.setDouble(_prefsLon, c.longitude);
  }

  Future<LatLng?> loadFieldCenter() async {
    final p = await SharedPreferences.getInstance();
    final lat = p.getDouble(_prefsLat);
    final lon = p.getDouble(_prefsLon);
    if (lat == null || lon == null) return null;
    return LatLng(lat, lon);
  }

  Future<bool> get isFieldCached async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_prefsReady) ?? false;
  }

  Future<int> get cachedTileCount async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_prefsCount) ?? 0;
  }

  /// Wipe disk tiles + ready flag (e.g. before Re-cache).
  Future<void> clearCachedTiles() async {
    if (await _root.exists()) {
      await _root.delete(recursive: true);
    }
    await _root.create(recursive: true);
    final p = await SharedPreferences.getInstance();
    await p.remove(_prefsReady);
    await p.remove(_prefsCount);
  }

  /// Bulk-download Esri tiles covering [center] ± [fieldRadiusM] for zoom 14–18.
  /// Returns number of tiles successfully saved (not job count).
  Future<int> cacheField(
    LatLng center, {
    void Function(int done, int total)? onProgress,
  }) async {
    await rememberFieldCenter(center);
    final jobs = <(int z, int x, int y)>[];
    for (var z = minZoom; z <= maxZoom; z++) {
      final range = _tileRangeForRadius(center, fieldRadiusM, z);
      for (var x = range.$1; x <= range.$2; x++) {
        for (var y = range.$3; y <= range.$4; y++) {
          jobs.add((z, x, y));
        }
      }
    }

    var done = 0;
    var saved = 0;
    final total = jobs.length;
    onProgress?.call(done, total);

    const workers = 4;
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= jobs.length) return;
        final (z, x, y) = jobs[i];
        final file = tileFile(z, x, y);
        try {
          if (await file.exists()) {
            final existing = await file.readAsBytes();
            if (_looksLikePng(existing) && existing.length >= 500) {
              saved++;
            } else {
              await file.delete();
              final bytes = await _download(tileUrl(z, x, y));
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes, flush: true);
              saved++;
              await Future<void>.delayed(const Duration(milliseconds: 40));
            }
          } else {
            final bytes = await _download(tileUrl(z, x, y));
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes, flush: true);
            saved++;
            await Future<void>.delayed(const Duration(milliseconds: 40));
          }
        } catch (_) {
          // Skip failed tile; neighbours / lower zoom may still show.
        }
        done++;
        onProgress?.call(done, total);
      }
    }

    await Future.wait(List.generate(workers, (_) => worker()));

    final p = await SharedPreferences.getInstance();
    final ready = saved > 0;
    await p.setBool(_prefsReady, ready);
    await p.setInt(_prefsCount, saved);
    return saved;
  }

  /// Tile x/y inclusive range for a circle approx as a lat/lon box.
  static (int minX, int maxX, int minY, int maxY) _tileRangeForRadius(
    LatLng center,
    double radiusM,
    int z,
  ) {
    final dLat = radiusM / 111320.0;
    final cosLat =
        math.cos(center.latitude * math.pi / 180).abs().clamp(0.2, 1.0);
    final dLon = radiusM / (111320.0 * cosLat);
    final sw = LatLng(center.latitude - dLat, center.longitude - dLon);
    final ne = LatLng(center.latitude + dLat, center.longitude + dLon);
    final a = latLonToTile(sw, z);
    final b = latLonToTile(ne, z);
    return (
      math.min(a.$1, b.$1),
      math.max(a.$1, b.$1),
      math.min(a.$2, b.$2),
      math.max(a.$2, b.$2),
    );
  }

  static (int x, int y) latLonToTile(LatLng ll, int z) {
    final n = math.pow(2.0, z).toDouble();
    final x = ((ll.longitude + 180.0) / 360.0 * n).floor();
    final latRad = ll.latitude * math.pi / 180.0;
    final y = ((1.0 -
                math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) /
                    math.pi) /
            2.0 *
            n)
        .floor();
    final max = n.toInt() - 1;
    return (x.clamp(0, max), y.clamp(0, max));
  }
}
