import 'package:flutter/material.dart';

enum Drone3dViewMode { orbit, side }

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
  void resetCamera() {}

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF222222),
      child: Center(
        child: Text(
          'Betaflight 3D runs on Android / Chrome.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF9A9A9A)),
        ),
      ),
    );
  }
}
