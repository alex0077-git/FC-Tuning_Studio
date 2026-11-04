/// ASCII SD CLI: USB VCP today, STATUSTEXT `#`/`$` tunnel on radio.
abstract class SdCliTransport {
  Stream<String> get lines;
  bool get isOpen;

  /// Clear reassembly state before a new `log …` job.
  void beginJob() {}

  /// End of job (cancel keepalives, etc.).
  void endJob() {}

  /// Send a CLI command. May include a trailing newline (stripped on MAV).
  void writeAscii(String text);
}
