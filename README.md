# FC Tuning Studio

A Phase B ground app for the Fuselage Session-1 flight controller. Connect over Skydroid G20 (UDP), tune PID gains live, watch Live Log + graphs, pull SD flight CSVs over MAVLink, bench-test motors, set cruise base throttle, and stream attitude in 3D. Built as a Flutter app aimed at the G20 bezel.

## Why I built this

QGroundControl is fine for generic MAVLink, but this FC is a custom Phase B stack: compact G20 UI, Live Log on STATUSTEXT, SD card dumps on a separate tunnel, and param writes that must refuse while armed. I wanted one Tuning Studio that speaks that contract honestly: same radio path for telemetry, tuning, live status, motor/cruise commands, and flight-log download, without treating Live Log lines as SD CSV or inventing data the FC never sent.

## Features

- **Connect** — G20 UDP only in this build (listen `14551` → bridge `127.0.0.1:14552`). Waits for FC HEARTBEAT (sys/comp **1/1**), downloads the Phase B param catalog, shows link health. T12 BT is not enabled here.
- **Link state** — **Connected** while FC HEARTBEATs arrive; **Link Lost** after ~3 s of silence; **Disconnected** when the socket is closed.
- **Reset** — Status-bar **Reset** (right) sends STATUSTEXT `reset` when **disarmed**. Expect `*reset` or `*reset deny armed`. Link drops briefly on a real reboot; RAM params return to firmware defaults.
- **Navigation** — ☰ left drawer (no bottom bar): Connect, Tuning, Logs, 3D, Motor. Full height under the status strip.
- **Tuning** — Outer / Inner / AltHold tabs, roll–pitch link, Write only when **disarmed** (FC echoes PARAM_VALUE).
- **Live Log** — Reassembles STATUSTEXT `+` / `=` into full `[DMA]…` lines. Chips + optional attitude/gyro graphs. Off-tab persistence via IndexedStack.
- **SD flight logs** — Disarmed `log list` / `log dump N` / `log wipe`; `#` / `$` tunnel; one-tap save as **`.csv`** into public **Downloads/FC_Tuning** (MediaStore). Needs firmware with SD-over-MAV.
- **Motor** — Bench page: one motor (or All) at a time, hold-to-test, STATUSTEXT `motor …` / `motor stop`. Disarmed + link alive only. Props off.
- **3D** — `quad_x.gltf` from live ATTITUDE; orbit / zoom / pan; horizon, heading, gyro gx/gy/gz; **Cruise** slider (`base N`); **Height** from Live Log `Z` (2 decimals) on the view and sidebar. GPS/System: real fields or **—**.

## Tech Stack

- Flutter / Dart
- Custom MAVLink v2 codec (HEARTBEAT, PARAM_*, ATTITUDE, STATUSTEXT)
- G20 UDP + Android Kotlin (`G20UdpBridge`, `DownloadsBridge`)
- `fl_chart`, `webview_flutter` + Three.js, `path_provider`

## Project Structure

```
fc_tuning_studio/
├── android/
│   └── app/src/main/
│       ├── AndroidManifest.xml
│       └── kotlin/com/example/fc_tuning_studio/
│           ├── MainActivity.kt
│           ├── G20UdpBridge.kt
│           └── DownloadsBridge.kt
├── assets/
│   ├── params_catalog.json
│   ├── icon/
│   │   └── app_icon.png
│   └── 3d/
│       ├── quad_x.gltf
│       ├── drone_scene.html
│       ├── flightindicators/
│       └── vendor/
│           ├── three.min.js
│           ├── GLTFLoader.js
│           └── OrbitControls.js
├── docs/
│   └── PhaseB_LiveLog/
├── lib/
│   ├── layout/
│   │   └── g20_metrics.dart
│   ├── link/
│   │   ├── byte_link.dart
│   │   ├── g20_udp_link.dart
│   │   ├── t12_spp_link.dart
│   │   └── mav_session.dart
│   ├── logs/
│   │   ├── live_log_assembler.dart
│   │   ├── flight_log_store.dart
│   │   ├── public_downloads.dart
│   │   ├── sd_cli_transport.dart
│   │   ├── byte_cli_transport.dart
│   │   ├── mav_sd_cli_transport.dart
│   │   ├── sd_tunnel_assembler.dart
│   │   ├── sd_log_protocol.dart
│   │   ├── sd_log_client.dart
│   │   └── sd_flight_store.dart
│   ├── mavlink/
│   │   ├── mavlink_crc.dart
│   │   └── mavlink_v2.dart
│   ├── screens/
│   │   ├── shell_screen.dart
│   │   ├── connect_screen.dart
│   │   ├── tuning_screen.dart
│   │   ├── logs_screen.dart
│   │   ├── view3d_screen.dart
│   │   ├── motor_screen.dart
│   │   └── drone_3d_host*.dart
│   ├── theme/
│   │   └── app_theme.dart
│   └── main.dart
├── test/
│   ├── mavlink_param_test.dart
│   ├── live_log_assembler_test.dart
│   ├── sd_log_protocol_test.dart
│   └── sd_tunnel_assembler_test.dart
├── pubspec.yaml
└── README.md
```

## How It Works

1. **Link** — Connect opens G20 UDP. GCS HEARTBEAT keeps the bridge awake; FC HEARTBEAT (PB6/PB7 @ 115200) confirms Session-1. `linkAlive` ages out → **Link Lost**.
2. **Params** — PARAM_REQUEST_LIST / READ fill Tuning; PARAM_SET blocked while armed. Values are RAM until reboot.
3. **Live Log** — `+` / `=` chunks → full lines → chips/graphs. Optional live-session `.txt` (not a flight CSV).
4. **SD download** — `log list` / `log dump N`; `#` / `$` until `LOG END`; CSV copied to **Files → Downloads → FC_Tuning**.
5. **Motor / Cruise / Reset** — Plain STATUSTEXT (`motor …`, `base N`, `reset`). Replies use `*` so Live Log / SD ignore them.
6. **3D** — ATTITUDE + gyro; GLTF injected into WebView; OrbitControls for camera; Height from Live Log `Z` (filtered baro relative height).

## Setup

### Prerequisites

- Flutter SDK (see `pubspec.yaml`, SDK `^3.12.2`)
- Skydroid G20 (or Android) for radio work
- Phase B MAVLink firmware (+ SD-over-MAV for radio CSV download)

### Run

```bash
cd fc_tuning_studio
flutter pub get
flutter run
```