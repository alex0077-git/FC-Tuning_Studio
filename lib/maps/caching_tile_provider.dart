import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

import 'offline_tile_store.dart';

/// Serves tiles from [OfflineTileStore] (disk), downloading when online.
class CachingTileProvider extends TileProvider {
  CachingTileProvider(this.store, {super.headers});

  final OfflineTileStore store;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _OfflineTileImage(
      store: store,
      z: coordinates.z,
      x: coordinates.x,
      y: coordinates.y,
      url: getTileUrl(coordinates, options),
    );
  }
}

class _OfflineTileImage extends ImageProvider<_OfflineTileImage> {
  const _OfflineTileImage({
    required this.store,
    required this.z,
    required this.x,
    required this.y,
    required this.url,
  });

  final OfflineTileStore store;
  final int z;
  final int x;
  final int y;
  final String url;

  /// 1×1 transparent PNG — used when offline and tile was never cached.
  static final Uint8List _emptyPng = Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  @override
  Future<_OfflineTileImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _OfflineTileImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _load(decode),
      scale: 1,
      debugLabel: 'tile/$z/$x/$y',
      informationCollector: () => [
        DiagnosticsProperty('url', url),
        DiagnosticsProperty('tile', '$z/$x/$y'),
      ],
    );
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    List<int> bytes;
    try {
      bytes = await store.loadTileBytes(z, x, y);
    } catch (_) {
      bytes = _emptyPng;
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    );
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) {
    return other is _OfflineTileImage &&
        other.z == z &&
        other.x == x &&
        other.y == y &&
        other.url == url;
  }

  @override
  int get hashCode => Object.hash(z, x, y, url);
}
