import 'dart:async';
import 'dart:convert';

import '../link/byte_link.dart';
import 'sd_cli_transport.dart';

/// Splits a [ByteLink] into newline-terminated ASCII lines for SD CLI.
class ByteCliTransport implements SdCliTransport {
  ByteCliTransport(this._link);

  final ByteLink _link;
  final _lines = StreamController<String>.broadcast();
  StreamSubscription<List<int>>? _sub;
  final StringBuffer _buf = StringBuffer();
  bool _open = false;

  @override
  Stream<String> get lines => _lines.stream;

  @override
  bool get isOpen => _open;

  @override
  void beginJob() {}

  @override
  void endJob() {}

  Future<void> open() async {
    if (_open) return;
    await _link.open();
    _sub = _link.bytes.listen(_onBytes);
    _open = true;
  }

  @override
  void writeAscii(String text) {
    _link.write(utf8.encode(text));
  }

  void _onBytes(List<int> chunk) {
    _buf.write(utf8.decode(chunk, allowMalformed: true));
    var s = _buf.toString();
    while (true) {
      final n = s.indexOf('\n');
      if (n < 0) break;
      var line = s.substring(0, n);
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      if (!_lines.isClosed) _lines.add(line);
      s = s.substring(n + 1);
    }
    _buf
      ..clear()
      ..write(s);
  }

  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    _open = false;
    _buf.clear();
  }

  Future<void> dispose() async {
    await close();
    await _lines.close();
  }
}
