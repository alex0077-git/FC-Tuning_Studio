// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

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
  static bool _registered = false;
  static html.IFrameElement? _iframe;
  static const _viewType = 'fc-drone-3d-host';

  @override
  void initState() {
    super.initState();
    if (!_registered) {
      _iframe = html.IFrameElement()
        ..src = 'drone_scene.html'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      ui_web.platformViewRegistry.registerViewFactory(
        _viewType,
        (int id) => _iframe!,
      );
      _registered = true;
    }
    _postAttitude();
  }

  @override
  void didUpdateWidget(covariant Drone3dHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _postAttitude();
  }

  void _postAttitude() {
    _iframe?.contentWindow?.postMessage({
      'type': 'attitude',
      'roll': widget.rollDeg,
      'pitch': widget.pitchDeg,
      'yaw': widget.yawDeg,
    }, '*');
  }

  @override
  Widget build(BuildContext context) {
    return const HtmlElementView(viewType: _viewType);
  }
}