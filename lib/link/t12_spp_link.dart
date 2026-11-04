import 'dart:async';

import 'byte_link.dart';

/// T12 Classic SPP placeholder for the G20-first APK.
///
/// `flutter_bluetooth_serial` is incompatible with AGP 9 (removed `jcenter()`).
/// G20 UDP works without it. Wire a modern Classic SPP plugin here later.
class BondedBtDevice {
  const BondedBtDevice({required this.name, required this.address});
  final String name;
  final String address;
}

class T12SppLink implements ByteLink {
  T12SppLink({required this.address});

  final String address;
  final _rx = StreamController<List<int>>.broadcast();

  @override
  Stream<List<int>> get bytes => _rx.stream;

  static Future<List<BondedBtDevice>> bonded() async => const [];

  @override
  Future<void> open() async {
    throw UnsupportedError(
      'T12 Bluetooth is not in this APK build. Use G20 UDP on the transmitter.',
    );
  }

  @override
  void write(List<int> data) {
    throw UnsupportedError('T12 Bluetooth is not in this APK build.');
  }

  @override
  Future<void> close() async {}
}
