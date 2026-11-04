import 'dart:async';

import 'package:flutter/material.dart';

import '../link/mav_session.dart';
import '../theme/app_theme.dart';
import 'drone_3d_host.dart';

/// Live FC attitude only — model fills the page.
class View3dScreen extends StatefulWidget {
  const View3dScreen({super.key, this.session});

  final MavSession? session;

  @override
  State<View3dScreen> createState() => _View3dScreenState();
}

class _View3dScreenState extends State<View3dScreen> {
  StreamSubscription? _attSub;

  double _roll = 0;
  double _pitch = 0;
  double _yaw = 0;
  bool _liveFromFc = false;

  @override
  void initState() {
    super.initState();
    _attachSession(widget.session);
  }

  @override
  void didUpdateWidget(covariant View3dScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      _attachSession(widget.session);
    }
  }

  void _attachSession(MavSession? session) {
    _attSub?.cancel();
    _attSub = null;
    _liveFromFc = session != null;

    if (session == null) {
      if (mounted) {
        setState(() {
          _roll = 0;
          _pitch = 0;
          _yaw = 0;
        });
      }
      return;
    }

    _attSub = session.attitudes.listen((a) {
      if (!mounted) return;
      setState(() {
        _roll = a.rollDeg;
        _pitch = a.pitchDeg;
        _yaw = a.yawDeg;
      });
    });
  }

  @override
  void dispose() {
    _attSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_liveFromFc) {
      return const Center(
        child: Text(
          'Connect to stream live 3D',
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Drone3dHost(
          rollDeg: _roll,
          pitchDeg: _pitch,
          yawDeg: _yaw,
        ),
        Positioned(
          left: 10,
          top: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xCC0E1114),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              'R ${_roll.toStringAsFixed(1)}°  '
              'P ${_pitch.toStringAsFixed(1)}°  '
              'Y ${_yaw.toStringAsFixed(1)}°',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
