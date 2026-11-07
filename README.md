# FC Tuning Studio

A Phase B ground app for the Fuselage Session-1 flight controller. Connect over Skydroid G20 (UDP) or T12 (Bluetooth), tune PID gains live, watch Live Log + graphs, pull SD flight CSVs over MAVLink, and stream attitude in 3D. Built as a Flutter app aimed at the G20 bezel.

## Why I built this

QGroundControl is fine for generic MAVLink, but this FC is a custom Phase B stack: compact G20 UI, Live Log on STATUSTEXT, SD card dumps on a separate tunnel, and param writes that must refuse while armed. I wanted one Tuning Studio that speaks that contract honestly: same radio path for telemetry, tuning, live status, and flight-log download, without treating Live Log lines as SD CSV or inventing data the FC never sent.

## Features

- **Connect**: Skydroid G20 UDP (listen `14551` → bridge `127.0.0.1:14552`) and T12 classic BT SPP. Waits for FC HEARTBEAT (sys/comp **1/1**), downloads the Phase B param catalog, shows link health.
- **Link state**: **Connected** while FC HEARTBEATs arrive; **Link Lost** after ~3 s of silence (radio drop or non-MAVLink flash); **Disconnected** when the socket is closed.
- **Tuning**: Outer / Inner / AltHold tabs, roll-pitch link, Write only when **disarmed** (FC echoes PARAM_VALUE). Compact chrome for G20 landscape.
- **Live Log**: Reassembles STATUSTEXT into full `[DMA]…` lines. Highlight chips for attitude, baro, alt-hold, motors, GPS, and counters. Optional live attitude/gyro graphs.
- **Off-tab persistence**: IndexedStack keeps Tuning / Logs / 3D alive, so the feed and graphs keep filling while you're on another tab.
- **SD flight logs**: Disarmed `log list` / `log dump N` / `log wipe` over STATUSTEXT; tunnel reassembly; saves FC CSV as-is to Downloads (`FC_Tuning`). Needs **mavsd** firmware.
- **3D**: Live ATTITUDE only (`quad_x.gltf`). Orbit / zoom / pan. Horizon + heading gauges and gyro **gx/gy/gz** (dps). GPS / System show real Live Log values or **—**, with no mock motion and no fake zeros.

## Tech Stack

- Flutter / Dart
- Custom MAVLink v2 codec (HEARTBEAT, PARAM_*, ATTITUDE, STATUSTEXT)
- G20 UDP link + Android Kotlin bridge (`G20UdpBridge`)
- T12 Bluetooth SPP link
- `fl_chart` (live graphs), `webview_flutter` + Three.js (3D scene), `path_provider` (CSV export)

## Project Structure

```
fc_tuning_studio/
├── android/
│   └── app/src/main/
│       ├── AndroidManifest.xml
│       └── kotlin/com/example/fc_tuning_studio/
│           ├── MainActivity.kt
│           └── G20UdpBridge.kt
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

1. **Link** → Connect opens the radio path. GCS HEARTBEAT keeps the G20 bridge awake; FC HEARTBEAT confirms the Session-1 stack on PB6/PB7 @ 115200. `MavSession.linkAlive` tracks the last FC HEARTBEAT; the shell shows **Link Lost** when it goes stale (~3 s).
2. **Params** → PARAM_REQUEST_LIST / READ fills Tuning. PARAM_SET is blocked in-app (and on FC) while armed.
3. **Live Log** → Status lines arrive as STATUSTEXT chunks marked `+` (more) / `=` (end). The app joins them, updates chips/graphs, and can save a **live session** (not a flight CSV).
4. **SD download** → App sends STATUSTEXT `log list` / `log dump N`. FC replies on `#` / `$` until `LOG END`. Payload is the same CSV as USB `log dump`. Needs **mavsd** firmware.
5. **3D** → ATTITUDE drives the craft and gyro rates. GLTF is injected into the WebView HTML (Android `file://` cannot XHR the asset). OrbitControls owns the camera. Leave the tab and come back, and the session stays up via the shell IndexedStack.

## Setup

### Prerequisites

- Flutter SDK (see `pubspec.yaml`, SDK `^3.12.2`)
- Android device or Skydroid G20 for radio work
- FC flashed with Phase B MAVLink (+ **mavsd** hex for SD-over-MAV)

### Run

```bash
cd fc_tuning_studio
flutter pub get
flutter run
```