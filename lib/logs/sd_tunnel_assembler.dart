/// Reassembles FC SD-over-MAV STATUSTEXT chunks (`#` more / `$` flush).
///
/// Unlike Live Log (`+`/`=`), the SD tunnel completes when a `LOG END` line
/// appears in the reassembled ASCII — `$` only flushes the last partial chunk.
class SdTunnelAssembler {
  String _buf = '';
  int bytesSeen = 0;

  /// Feed one STATUSTEXT `text` field. Returns newly completed lines
  /// (CR stripped). Ignores non-`#`/`$` markers.
  List<String> pushChunk(String text) {
    if (text.isEmpty) return const [];
    final mark = text.codeUnitAt(0);
    if (mark != 0x23 /* # */ && mark != 0x24 /* $ */) {
      return const [];
    }
    final body = text.length > 1 ? text.substring(1) : '';
    if (body.isEmpty) return const [];
    _buf += body;
    bytesSeen += body.length;

    final out = <String>[];
    while (true) {
      final n = _buf.indexOf('\n');
      if (n < 0) break;
      var line = _buf.substring(0, n);
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      out.add(line);
      _buf = _buf.substring(n + 1);
    }
    return out;
  }

  void reset() {
    _buf = '';
    bytesSeen = 0;
  }
}
