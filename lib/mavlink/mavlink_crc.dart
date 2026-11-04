int x25CrcAccumulate(int data, int crcAccum) {
  var tmp = (data ^ (crcAccum & 0xFF)) & 0xFF;
  tmp = (tmp ^ ((tmp << 4) & 0xFF)) & 0xFF;
  crcAccum = (crcAccum >> 8) ^ (tmp << 8) ^ (tmp << 3) ^ (tmp >> 4);
  return crcAccum & 0xFFFF;
}

int x25Crc(List<int> data) {
  var crc = 0xFFFF;
  for (final b in data) {
    crc = x25CrcAccumulate(b, crc);
  }
  return crc;
}