import 'dart:async';

abstract class ByteLink {
  Stream<List<int>> get bytes;
  Future<void> open();
  void write(List<int> data);
  Future<void> close();
}