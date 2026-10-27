import 'package:flutter/material.dart';

class Drone3dHost extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF1A1D21),
      child: Center(
        child: Text(
          '3D viewer runs on Chrome for now.\nUse: flutter run -d chrome',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF9AA3AD)),
        ),
      ),
    );
  }
}