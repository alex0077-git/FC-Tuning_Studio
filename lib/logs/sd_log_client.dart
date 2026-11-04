import 'dart:async';

import 'sd_cli_transport.dart';
import 'sd_log_protocol.dart';

/// Runs `log list` / `log dump` / `log wipe` over an ASCII CLI transport.
class SdLogClient {
  SdLogClient(this.transport);

  final SdCliTransport? transport;

  bool get available => transport != null && transport!.isOpen;

  Future<SdLogResult> list({
    Duration idleTimeout = const Duration(seconds: 12),
  }) {
    return _run(
      command: 'log list',
      idleTimeout: idleTimeout,
      parse: parseLogList,
    );
  }

  Future<SdLogResult> dump(
    int? id, {
    Duration idleTimeout = const Duration(seconds: 30),
  }) {
    final cmd = id == null ? 'log dump' : 'log dump $id';
    return _run(
      command: cmd,
      idleTimeout: idleTimeout,
      parse: parseLogDump,
    );
  }

  Future<SdLogResult> wipe({
    Duration idleTimeout = const Duration(seconds: 12),
  }) {
    return _run(
      command: 'log wipe',
      idleTimeout: idleTimeout,
      parse: parseLogWipe,
    );
  }

  Future<SdLogResult> _run({
    required String command,
    required Duration idleTimeout,
    required SdLogResult Function(List<String> lines) parse,
  }) async {
    final t = transport;
    if (t == null || !t.isOpen) {
      return const SdLogResult(
        outcome: SdLogOutcome.parseError,
        message: 'No SD CLI transport (connect G20/T12 or USB VCP)',
      );
    }

    final collector = SdLogLineCollector();
    final completer = Completer<SdLogResult>();
    Timer? idle;
    StreamSubscription<String>? sub;

    void armIdle() {
      idle?.cancel();
      idle = Timer(idleTimeout, () {
        if (completer.isCompleted) return;
        completer.complete(
          const SdLogResult(
            outcome: SdLogOutcome.timeout,
            message: 'Idle timeout waiting for LOG END',
          ),
        );
      });
    }

    t.beginJob();
    sub = t.lines.listen((line) {
      if (completer.isCompleted) return;
      armIdle();
      if (collector.addLine(line)) {
        final err = collector.terminalError;
        if (err == 'busy') {
          completer.complete(
            const SdLogResult(outcome: SdLogOutcome.busy, message: 'busy'),
          );
        } else {
          completer.complete(parse(collector.lines));
        }
      }
    });

    try {
      armIdle();
      t.writeAscii(command);
      return await completer.future;
    } finally {
      idle?.cancel();
      await sub.cancel();
      t.endJob();
    }
  }
}
