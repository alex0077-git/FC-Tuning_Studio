// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum Drone3dViewMode { orbit, side }

/// Chrome/web: same BF quad_x inject as Android IO host (no invented model).
class Drone3dHost extends StatefulWidget {
  const Drone3dHost({
    super.key,
    required this.rollDeg,
    required this.pitchDeg,
    required this.yawDeg,
    this.viewMode = Drone3dViewMode.orbit,
    this.heightM,
    this.latchM,
    this.scaleLo,
    this.scaleHi,
  });

  final double rollDeg;
  final double pitchDeg;
  final double yawDeg;
  final Drone3dViewMode viewMode;
  final double? heightM;
  final double? latchM;
  final double? scaleLo;
  final double? scaleHi;

  @override
  State<Drone3dHost> createState() => Drone3dHostState();
}

class Drone3dHostState extends State<Drone3dHost> {
  static var _seq = 0;
  late final String _viewType;
  html.IFrameElement? _iframe;
  bool _ready = false;
  String? _blobUrl;

  @override
  void initState() {
    super.initState();
    _seq += 1;
    _viewType = 'fc-drone-3d-$_seq';
    _boot();
  }

  static String _safeJs(String js) =>
      js.replaceAll('</script>', r'<\/script>');

  Future<void> _boot() async {
    final three = _safeJs(
      await rootBundle.loadString('assets/3d/vendor/three.min.js'),
    );
    final gltfLoader = _safeJs(
      await rootBundle.loadString('assets/3d/vendor/GLTFLoader.js'),
    );
    final orbit = _safeJs(
      await rootBundle.loadString('assets/3d/vendor/OrbitControls.js'),
    );
    final gltfJson = await rootBundle.loadString('assets/3d/quad_x.gltf');
    final sceneHtml = await rootBundle.loadString('assets/3d/drone_scene.html');
    final bodyMatch = RegExp(
      r'<body[^>]*>([\s\S]*)</body>',
      caseSensitive: false,
    ).firstMatch(sceneHtml);
    final body = bodyMatch?.group(1) ?? sceneHtml;
    final mode = widget.viewMode == Drone3dViewMode.side ? 'side' : 'orbit';

    final htmlDoc = '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"/>
<style>
html,body{margin:0;height:100%;background:#141414;overflow:hidden;touch-action:none}
canvas{display:block;width:100%;height:100%}
#err{position:absolute;left:12px;bottom:12px;color:#ff8888;font:12px monospace;display:none;max-width:90%;pointer-events:none}
#hint{position:absolute;right:10px;bottom:10px;color:#888;font:11px sans-serif;pointer-events:none}
</style>
<script>$three</script>
<script>$gltfLoader</script>
<script>$orbit</script>
<script>window.__BF_QUAD_GLTF__ = $gltfJson;</script>
<script>window.__BF_VIEW_MODE__ = '$mode';</script>
</head>
<body>
$body
</body>
</html>
''';

    final blob = html.Blob([htmlDoc], 'text/html');
    _blobUrl = html.Url.createObjectUrlFromBlob(blob);
    _iframe = html.IFrameElement()
      ..src = _blobUrl!
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..onLoad.listen((_) {
        _ready = true;
        _postAll();
      });

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int id) => _iframe!,
    );
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant Drone3dHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _postAll(pushViewMode: oldWidget.viewMode != widget.viewMode);
  }

  @override
  void dispose() {
    final url = _blobUrl;
    if (url != null) html.Url.revokeObjectUrl(url);
    super.dispose();
  }

  void _postAll({bool pushViewMode = false}) {
    if (!_ready) return;
    final win = _iframe?.contentWindow;
    if (win == null) return;
    if (pushViewMode) {
      win.postMessage({
        'type': 'viewMode',
        'mode': widget.viewMode == Drone3dViewMode.side ? 'side' : 'orbit',
      }, '*');
    }
    win.postMessage({
      'type': 'attitude',
      'roll': widget.rollDeg,
      'pitch': widget.pitchDeg,
      'yaw': widget.yawDeg,
    }, '*');
    win.postMessage({
      'type': 'altitude',
      'zM': widget.heightM ?? 0.0,
      'latchM': widget.latchM,
      'lo': widget.scaleLo,
      'hi': widget.scaleHi,
    }, '*');
  }

  void resetCamera() {
    _iframe?.contentWindow?.postMessage({'type': 'resetCamera'}, '*');
  }

  @override
  Widget build(BuildContext context) {
    if (_iframe == null) {
      return const ColoredBox(
        color: Color(0xFF222222),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFFFFBB00),
            ),
          ),
        ),
      );
    }
    return HtmlElementView(viewType: _viewType);
  }
}