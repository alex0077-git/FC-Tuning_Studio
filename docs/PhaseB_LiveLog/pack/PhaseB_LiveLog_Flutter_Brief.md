# Fuselage FC — Live Log over MAVLink (for Flutter Tuning Studio)

**Audience:** Flutter app developers  
**Firmware:** Session 1 MAVLink on LPUART1 (PB6/PB7 @ 115200)  
**Related:** Phase B brief (HEARTBEAT / PARAM / ATTITUDE) + this live-log add-on  

---

## 1. Goal

Show the **same full status line** the pilot sees on ST-LINK Serial Monitor inside the app **Live Log** screen, over G20/T12 MAVLink (not USB).

Example (after reassembly):

```text
[DMA] s13364 DIS G -0.00 -0.00 -0.00 dps | R -0.60 P 7.70 Y 0.01 | BP 100785 Pa T 29.53 C | Z 0.48 raw 0.50 | AH en=1 act=1 tgt 0.45 err -0.03 dU -3.00 i 0.00 | M 1000 1000 1000 1000 us | GPS 0 sats=0
```

---

## 2. How data reaches the app

```
FC builds ASCII status line (same as VCP)
  -> chunked STATUSTEXT (MAV id 253) on PB6 TX
  -> radio -> G20 UDP listen 14551 (or T12 SPP)
  -> app joins chunks -> one Live Log line
```

| Channel | Use in app |
|---------|------------|
| HEARTBEAT (0) | Connect / armed bit |
| ATTITUDE (30) | 3D view @ 10 Hz |
| PARAM_* (20-23) | Tuning gains |
| **STATUSTEXT (253)** | **Serial-style Live Log** |
| SD `log list/dump` | Flight file download (separate feature) |

Do **not** treat ATTITUDE as the live log, and do **not** mix Live Log with SD card flight downloads.

---

## 3. Transport (unchanged from Phase B)

| Item | Value |
|------|--------|
| MAVLink | v2 clear, sys/comp **1/1** |
| UART | PB6 TX / PB7 RX @ **115200** |
| G20 (app on remote) | UDP listen **14551**, send **127.0.0.1:14552** |
| T12 | Classic BT SPP after normal pair |
| Conflict | **Do not** wire ESP32 on PB6/PB7 while MAV is used |

---

## 4. STATUSTEXT chunk protocol (mandatory)

MAVLink `STATUSTEXT` text field is **50 characters**. The FC splits long lines.

| `text[0]` | Meaning | App action |
|-----------|---------|------------|
| `+` | More chunks follow | Append `text.substring(1)` to accumulator |
| `=` | Final chunk | Append `text.substring(1)`, then **flush** one complete log line to UI; clear accumulator |

- `severity` = `MAV_SEVERITY_INFO` (6)  
- Rate: same as VCP stream (~**1 s** armed, ~**2 s** disarmed)  
- Ignore STATUSTEXT that does not start with `+` or `=` (or show elsewhere)

### Dart reassembly

```dart
String _logAcc = '';

void onStatusText(String text) {
  if (text.isEmpty) return;
  final mark = text.codeUnitAt(0);
  final body = text.length > 1 ? text.substring(1) : '';
  if (mark == 0x2B) { // '+'
    _logAcc += body;
  } else if (mark == 0x3D) { // '='
    _logAcc += body;
    appendLiveLogLine(_logAcc.trim());
    _logAcc = '';
  }
}
```

---

## 5. Field guide (what each part means)

| Segment | Example | Meaning |
|---------|---------|---------|
| Sample mode | `[DMA]` / `[poll]` | IMU read path |
| Sequence | `s13364` | IMU sample counter |
| Arm state | `DIS` / `ARM` | Disarmed / armed |
| Gyro | `G gx gy gz dps` | Body gyro deg/s |
| Attitude | `R P Y` | Roll / pitch / yaw **degrees** |
| Baro | `BP … Pa T … C` | Pressure Pa, temperature C |
| Altitude | `Z … raw …` | Filtered Z m, raw Z m |
| AltHold | `AH en= act= tgt err dU i` | Enable, active, target m, error m, throttle corr us, I us |
| Motors | `M m1 m2 m3 m4 us` | PWM outputs microseconds |
| GPS | `GPS 0 sats=0` | **Placeholder** — no GPS in Session 1; always 0 |

If a sensor is missing later: prefer **omit** that segment, or keep a stable `0` placeholder like GPS.

---

## 6. UI recommendations

1. **Live Log** tab: scrolling list, newest at bottom (or top); keep last N lines (e.g. 300).  
2. Optional **timestamp** from phone clock when the full line is flushed.  
3. **Pause / Clear / Share** controls.  
4. Show **GPS** tile or trailing `GPS 0 sats=0` from the line (or parse it); do not invent fix quality.  
5. Keep **3D** on ATTITUDE; Live Log is for the dense ASCII status.  
6. Still use PARAM download for Tuning; Live Log does not replace gains.

---

## 7. Acceptance checklist (props off)

- [ ] Connect G20 UDP (or T12); see HEARTBEAT + ATTITUDE  
- [ ] Live Log shows full reassembled lines including `BP`, `Z`, `AH`, `M`, `GPS 0 sats=0`  
- [ ] No `+` / `=` markers visible in the final UI line  
- [ ] Rate roughly matches serial monitor (~1–2 s)  
- [ ] ESP not sharing PB6/PB7  
- [ ] SD log download UI remains a separate feature  

---

## 8. One-liner for chat

> Live Log: FC sends VCP-identical status via chunked MAVLink **STATUSTEXT (253)** (`+` continue / `=` end). Reassemble in app. GPS slot is `GPS 0 sats=0` until a module exists. Still use HB/ATTITUDE/PARAM as before on UDP 14551 / 127.0.0.1:14552.

---

*End of Live Log Flutter brief.*
