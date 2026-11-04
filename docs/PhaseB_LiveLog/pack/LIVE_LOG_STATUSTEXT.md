# App live log from MAVLink STATUSTEXT

FC pushes the same ASCII status line used on ST-LINK VCP over MAVLink as **chunked `STATUSTEXT` (msg id 253)**, at the same rate as the VCP stream (~1 s armed / ~2 s disarmed).

## Chunk rules

Each `STATUSTEXT.text` (50 chars):

| Byte 0 | Meaning |
|--------|---------|
| `+` | More chunks follow — append `text[1..]` to a buffer |
| `=` | Last chunk — append `text[1..]`, then flush one full log line to the UI |

Ignore other STATUSTEXT (or show separately).

## Example line (after reassembly)

```text
[DMA] s13364 DIS G -0.00 -0.00 -0.00 dps | R -0.60 P 7.70 Y 0.01 | BP 100785 Pa T 29.53 C | Z 0.48 raw 0.50 | AH en=1 act=1 tgt 0.45 err -0.03 dU -3.00 i 0.00 | M 1000 1000 1000 1000 us | GPS 0 sats=0
```

`GPS 0 sats=0` is a placeholder (no GPS module in Session 1).

## Flutter sketch

```dart
String _logAcc = '';

void onStatusText(String text) {
  if (text.isEmpty) return;
  final mark = text[0];
  final body = text.length > 1 ? text.substring(1) : '';
  if (mark == '+') {
    _logAcc += body;
  } else if (mark == '=') {
    _logAcc += body;
    appendLiveLogLine(_logAcc.trim());
    _logAcc = '';
  }
}
```

Keep HEARTBEAT / ATTITUDE for Connect + 3D; use this for the Serial-Monitor-style live log.
