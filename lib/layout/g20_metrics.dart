import 'package:flutter/material.dart';

/// Skydroid G20 sits in a transmitter bezel — treat it like a compact landscape PC.
class G20Metrics {
  G20Metrics._(this.size, this.orientation);

  factory G20Metrics.of(BuildContext context) {
    final mq = MediaQuery.of(context);
    return G20Metrics._(mq.size, mq.orientation);
  }

  final Size size;
  final Orientation orientation;

  bool get landscape => orientation == Orientation.landscape;

  /// Short controller screens need a thin chrome strip.
  bool get compactChrome => size.height < 720 || landscape;

  double get navHeight => compactChrome ? 44 : 52;

  double get statusPadV => compactChrome ? 4 : 8;

  double get pagePad => compactChrome ? 8 : 12;

  double get titleSize => compactChrome ? 15 : 18;

  double get bodySize => compactChrome ? 12 : 13;

  double get feedHeight {
    final h = size.height * (compactChrome ? 0.22 : 0.28);
    return h.clamp(110.0, 200.0);
  }

  double get chartHeight => compactChrome ? 72 : 90;
}
