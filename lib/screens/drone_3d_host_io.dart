import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  State<Drone3dHost> createState() => _Drone3dHostState();
}

class _Drone3dHostState extends State<Drone3dHost> {
  late final WebViewController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF1A1D21))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _ready = true;
            _pushAttitude();
          },
        ),
      )
      ..loadFlutterAsset('assets/3d/drone_scene.html');
  }

  @override
  void didUpdateWidget(covariant Drone3dHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _pushAttitude();
  }

  void _pushAttitude() {
    if (!_ready) return;
    _controller.runJavaScript(
      'window.setAttitude(${widget.rollDeg}, ${widget.pitchDeg}, ${widget.yawDeg});',
    );
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(
      controller: _controller,
      gestureRecognizers: {
        Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
      },
    );
  }
}