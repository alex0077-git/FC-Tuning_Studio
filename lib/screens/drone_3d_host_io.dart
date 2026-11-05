import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

// Eager + scale/drag so OrbitControls gets full 3D gestures on G20.

class Drone3dHost extends StatefulWidget {
  const Drone3dHost({
    super.key,
    required this.rollDeg,
    required this.pitchDeg,
    required this.yawDeg,
  });

  final double rollDeg;
  final double pitchDeg;
  final double yawDeg;

  @override
  State<Drone3dHost> createState() => Drone3dHostState();
}

class Drone3dHostState extends State<Drone3dHost> {
  WebViewController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  static String _safeJs(String js) =>
      js.replaceAll('</script>', r'<\/script>');

  Future<void> _boot() async {
    // Bundle THREE + GLTFLoader + official BF quad_x.gltf into one HTML file.
    // Android WebView blocks XHR to flutter_assets for .gltf — inject instead.
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
    final body = _extractBody(sceneHtml);

    final html = '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"/>
<style>
html,body{margin:0;height:100%;background:#222;overflow:hidden;touch-action:none}
canvas{display:block;width:100%;height:100%}
#err{position:absolute;left:12px;bottom:12px;color:#ff8888;font:12px monospace;display:none;max-width:90%;pointer-events:none}
#hint{position:absolute;right:10px;bottom:10px;color:#888;font:11px sans-serif;pointer-events:none}
</style>
<script>$three</script>
<script>$gltfLoader</script>
<script>$orbit</script>
<script>window.__BF_QUAD_GLTF__ = $gltfJson;</script>
</head>
<body>
$body
</body>
</html>
''';

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/bf_quad_x_view.html');
    await file.writeAsString(html, flush: true);

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF222222))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _ready = true;
            _pushAttitude();
          },
        ),
      );

    await controller.loadFile(file.path);
    if (!mounted) return;
    setState(() => _controller = controller);
  }

  static String _extractBody(String fullHtml) {
    final bodyMatch = RegExp(
      r'<body[^>]*>([\s\S]*)</body>',
      caseSensitive: false,
    ).firstMatch(fullHtml);
    return bodyMatch?.group(1) ?? fullHtml;
  }

  @override
  void didUpdateWidget(covariant Drone3dHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _pushAttitude();
  }

  void _pushAttitude() {
    final c = _controller;
    if (!_ready || c == null) return;
    c.runJavaScript(
      'window.setAttitude && window.setAttitude(${widget.rollDeg}, ${widget.pitchDeg}, ${widget.yawDeg});',
    );
  }

  void resetCamera() {
    final c = _controller;
    if (!_ready || c == null) return;
    c.runJavaScript('window.resetCamera && window.resetCamera();');
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) {
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
    // Claim all touch sequences so OrbitControls can orbit / pinch-zoom / pan
    // without the parent scroll views stealing the gesture.
    return WebViewWidget(
      controller: c,
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<EagerGestureRecognizer>(EagerGestureRecognizer.new),
        Factory<ScaleGestureRecognizer>(ScaleGestureRecognizer.new),
        Factory<HorizontalDragGestureRecognizer>(
          HorizontalDragGestureRecognizer.new,
        ),
        Factory<VerticalDragGestureRecognizer>(
          VerticalDragGestureRecognizer.new,
        ),
      },
    );
  }
}
