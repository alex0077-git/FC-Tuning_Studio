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
  State<Drone3dHost> createState() => Drone3dHostState();
}

class Drone3dHostState extends State<Drone3dHost> {
  void resetCamera() {}

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF222222),
      child: Center(
        child: Text(
          '3D viewer runs on Android / Chrome.\nUse a device build for the live model.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF9A9A9A)),
        ),
      ),
    );
  }
}
