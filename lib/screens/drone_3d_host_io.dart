import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as win;

/// Camera mode for the existing Betaflight `quad_x` WebView scene.
/// Does not change the model — only orbit vs locked side camera.
enum Drone3dViewMode {
  orbit,
  side,
}

/// Official BF `quad_x.gltf` host (same model as Setup → 3D).
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
  /// AltHold meter tape span — must match Flutter scale when set.
  final double? scaleLo;
  final double? scaleHi;

  @override
  State<Drone3dHost> createState() => Drone3dHostState();
}

class Drone3dHostState extends State<Drone3dHost> {
  WebViewController? _mobileController;
  win.WebviewController? _winController;
  StreamSubscription? _winLoadSub;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _winLoadSub?.cancel();
    final winC = _winController;
    _winController = null;
    if (winC != null) {
      unawaited(winC.dispose());
    }
    super.dispose();
  }

  static String _safeJs(String js) =>
      js.replaceAll('</script>', r'<\/script>');

  String get _modeJs =>
      widget.viewMode == Drone3dViewMode.side ? 'side' : 'orbit';

  Future<String> _buildHtml() async {
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

    return '''
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
<script>window.__BF_VIEW_MODE__ = '$_modeJs';</script>
</head>
<body>
$body
</body>
</html>
''';
  }

  Future<void> _boot() async {
    try {
      final html = await _buildHtml();
      final dir = await getTemporaryDirectory();
      final suffix =
          widget.viewMode == Drone3dViewMode.side ? 'side' : 'orbit';
      // Bump name when scene HTML framing changes so WebView does not keep a stale file.
      final file = File('${dir.path}/bf_quad_x_view_${suffix}_v16.html');
      await file.writeAsString(html, flush: true);

      if (!kIsWeb && Platform.isWindows) {
        await _bootWindows(file);
      } else {
        await _bootMobile(file);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'BF 3D load failed: $e');
    }
  }

  Future<void> _bootWindows(File file) async {
    final ver = await win.WebviewController.getWebViewVersion();
    if (ver == null) {
      if (!mounted) return;
      setState(() {
        _error =
            'Exact Betaflight model needs WebView2 Runtime.\n'
            'Install it, or run: flutter run -d chrome';
      });
      return;
    }

    final controller = win.WebviewController();
    await controller.initialize();
    await controller.setBackgroundColor(const Color(0xFF141414));
    _winLoadSub = controller.loadingState.listen((state) {
      if (state == win.LoadingState.navigationCompleted) {
        _ready = true;
        // Boot HTML already applied __BF_VIEW_MODE__; keep pushing attitude only.
        _pushAll();
      }
    });
    await controller.loadUrl(Uri.file(file.path).toString());
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _winController = controller;
      _error = null;
    });
  }

  Future<void> _bootMobile(File file) async {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF141414))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _ready = true;
            _pushAll();
          },
        ),
      );

    await controller.loadFile(file.path);
    if (!mounted) return;
    setState(() {
      _mobileController = controller;
      _error = null;
    });
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
    // Do not re-apply setViewMode every telemetry tick — that resets orbit zoom.
    _pushAll(pushViewMode: oldWidget.viewMode != widget.viewMode);
  }

  void _pushAll({bool pushViewMode = false}) {
    if (!_ready) return;
    final latch = widget.latchM;
    final latchJs = latch == null ? 'null' : latch.toString();
    final zJs = (widget.heightM ?? 0).toString();
    final lo = widget.scaleLo;
    final hi = widget.scaleHi;
    final loHiJs = (lo != null && hi != null) ? ', $lo, $hi' : '';
    final viewJs = pushViewMode
        ? "window.setViewMode && window.setViewMode('$_modeJs');\n"
        : '';
    final js = '''
$viewJs
window.setAttitude && window.setAttitude(${widget.rollDeg}, ${widget.pitchDeg}, ${widget.yawDeg});
window.setAltitude && window.setAltitude($zJs, $latchJs$loHiJs);
''';

    final mobile = _mobileController;
    if (mobile != null) {
      mobile.runJavaScript(js);
      return;
    }
    final winC = _winController;
    if (winC != null && winC.value.isInitialized) {
      unawaited(winC.executeScript(js));
    }
  }

  void resetCamera() {
    if (!_ready) return;
    const js = 'window.resetCamera && window.resetCamera();';
    final mobile = _mobileController;
    if (mobile != null) {
      mobile.runJavaScript(js);
      return;
    }
    final winC = _winController;
    if (winC != null && winC.value.isInitialized) {
      unawaited(winC.executeScript(js));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return ColoredBox(
        color: const Color(0xFF141414),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 13),
            ),
          ),
        ),
      );
    }

    final winC = _winController;
    if (winC != null) {
      return win.Webview(winC);
    }

    final c = _mobileController;
    if (c == null) {
      return const ColoredBox(
        color: Color(0xFF141414),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFFF5C518),
            ),
          ),
        ),
      );
    }

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