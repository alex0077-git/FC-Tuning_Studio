# FC Tuning Studio

A Phase B ground app for the Fuselage Session-1 flight controller. Connect over Skydroid G20 (UDP), tune PID gains live, watch Live Log + graphs, pull SD flight CSVs over MAVLink, bench-test motors, set cruise base throttle, stream attitude in 3D, check AltHold height with a dedicated 3D view, and follow the craft on a GPS map with an armed-only flight track. Built as a Flutter app aimed at the G20 bezel. A Simulation path lets you exercise UI and AltHold on a laptop before installing on the radio.

## Why I built this

QGroundControl is fine for generic MAVLink, but this FC is a custom Phase B stack: compact G20 UI, Live Log on STATUSTEXT, SD card dumps on a separate tunnel, and param writes that must refuse while armed. I wanted one Tuning Studio that speaks that contract honestly: same radio path for telemetry, tuning, live status, motor/cruise commands, flight-log download, and GPS from the FC, without treating Live Log lines as SD CSV or inventing data the FC never sent. Simulation is a parallel mock link so desk testing does not touch the G20 UDP path.

## Features

- **Connect** — G20 UDP only on the real path (listen `14551` → bridge `127.0.0.1:14552`). Waits for FC HEARTBEAT (sys/comp **1/1**), downloads the Phase B param catalog, shows link health. Optional **voice cues** on/off (default on). T12 BT is not enabled here.
- **Simulation** — Mock FC over the shared `MavSession` (no sockets / no UDP). Arm, AltHold, and live height on a laptop; iterate UI before flashing or installing on G20. Disconnect returns to the Simulation page.
- **Link state** — **Connected** while HEARTBEATs arrive; **Link Lost** after ~3 s of silence; **Disconnected** when the socket (or mock) is closed.
- **Status bar** — Connected / Link Lost, Armed, AltHold when active, **GPS Fix + Sats** (MAVLink), battery, Reset. MAVLink version text is not shown in the strip.
- **Reset** — Status-bar **Reset** (right) sends STATUSTEXT `reset` when **disarmed**. Expect `*reset` or `*reset deny armed`. Link drops briefly on a real reboot; RAM params return to firmware defaults.
- **Navigation** — ☰ left drawer (scrollable on G20): Connect, Simulation, Tuning, Logs, 3D, AltHold 3D, GPS, Motor, Battery. Full height under the status strip.
- **Tuning** — Outer / Inner / AltHold tabs, roll–pitch link, Write only when **disarmed** (FC echoes PARAM_VALUE).
- **Live Log** — Reassembles STATUSTEXT `+` / `=` into full `[DMA]…` lines. Chips + optional attitude/gyro graphs. Off-tab persistence via IndexedStack. AH / mag / height still from Live Log; GPS chips use MAVLink.
- **SD flight logs** — Disarmed `log list` / `log dump N` / `log wipe`; `#` / `$` tunnel; one-tap save as **`.csv`** into public **Downloads/FC_Tuning** (MediaStore). Needs firmware with SD-over-MAV.
- **GPS** — Full-bleed map (default **Esri World Imagery**; toggle **OSM street**). Position from MAVLink **GPS_RAW_INT (24)** + **GLOBAL_POSITION_INT (33)**, not Live Log. Transparent overlays: map style (bottom-left), **Refresh** clears the track (top-right). Flight track records **only while armed** (~0.8 m / 300 ms filters). Needs Wi-Fi for tiles.
- **Motor** — Bench page: one motor (or All) at a time, hold-to-test, STATUSTEXT `motor …` / `motor stop`. Disarmed + link alive only. Props off.
- **3D** — `quad_x.gltf` from live ATTITUDE; orbit / zoom / pan; horizon, heading, gyro gx/gy/gz; **Cruise** slider (`base N`); **Height** from Live Log `Z` (2 decimals) on the view and sidebar. GPS sidebar: Fix / sats / lat / lon from MAVLink, or **—**.
- **AltHold 3D** — Side view of the same BF craft + meter tape. Latch ring marks Target when AltHold engages; Current follows live `Z`. Right panel: Target vs Current history graph and value cards. Works on **Simulation** or real **G20** (same live-log fields). Scale is a sliding window around height (e.g. at 5 m → about 2–6 m), expanded if Target is outside that window.
- **Battery** — Drawer page for cell type (3S / 4S / 6S) and editable 100% / first-warning / second-warning voltages. Saved on device; drives status-bar % and warnings. Page scrolls for G20. First warning is a dismissible dialog; critical voltage shows a full-screen LAND NOW lock until voltage rises.
- **Voice cues** — Arm / disarm, AltHold on/off, battery warnings, reset (when voice is enabled on Connect).

## Tech Stack

- Flutter / Dart
- Custom MAVLink v2 codec (HEARTBEAT, PARAM_*, ATTITUDE, SYS_STATUS, STATUSTEXT, GPS_RAW_INT, GLOBAL_POSITION_INT)
- G20 UDP + Android Kotlin (`G20UdpBridge`, `DownloadsBridge`)
- Mock FC link for Simulation (`MockFcLink`)
- `flutter_map`, `latlong2`, `fl_chart`, `webview_flutter` / WebView2 + Three.js, `path_provider`, `shared_preferences`, `flutter_tts`, `http`

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
│   ├── voice/                  # optional cue assets / TTS wiring
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
│   ├── battery/
│   │   └── battery_profile.dart
│   ├── layout/
│   │   └── g20_metrics.dart
│   ├── link/
│   │   ├── byte_link.dart
│   │   ├── g20_udp_link.dart
│   │   ├── mock_fc_link.dart
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
│   ├── maps/
│   │   ├── caching_tile_provider.dart
│   │   └── offline_tile_store.dart
│   ├── mavlink/
│   │   ├── mavlink_crc.dart
│   │   └── mavlink_v2.dart
│   ├── screens/
│   │   ├── shell_screen.dart
│   │   ├── connect_screen.dart
│   │   ├── sim_connect_screen.dart
│   │   ├── tuning_screen.dart
│   │   ├── logs_screen.dart
│   │   ├── view3d_screen.dart
│   │   ├── althold_3d_screen.dart
│   │   ├── gps_screen.dart
│   │   ├── motor_screen.dart
│   │   ├── battery_screen.dart
│   │   └── drone_3d_host*.dart
│   ├── theme/
│   │   └── app_theme.dart
│   ├── voice/
│   │   └── fc_voice.dart
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

1. **Link** — Connect opens G20 UDP. GCS HEARTBEAT keeps the bridge awake; FC HEARTBEAT (PB6/PB7 @ 115200) confirms Session-1. `linkAlive` ages out → **Link Lost**. Simulation attaches `MockFcLink` to the same `MavSession` instead.
2. **Params** — PARAM_REQUEST_LIST / READ fill Tuning; PARAM_SET blocked while armed. Values are RAM until reboot.
3. **Live Log** — `+` / `=` chunks → full lines → chips/graphs / AltHold 3D. Optional live-session `.txt` (not a flight CSV). Mag fused (`h1`) drives the status mag light.
4. **GPS** — FC emits GPS_RAW_INT / GLOBAL_POSITION_INT; `MavSession` merges into `FcGpsState` (fix/sats from RAW, lat/lon from GLOBAL when valid). Map, status bar, Logs, and 3D use that stream, not Live Log GPS text. Track appends only while armed; Refresh clears it.
5. **SD download** — `log list` / `log dump N`; `#` / `$` until `LOG END`; CSV copied to **Files → Downloads → FC_Tuning**.
6. **Motor / Cruise / Reset** — Plain STATUSTEXT (`motor …`, `base N`, `reset`). Replies use `*` so Live Log / SD ignore them.
7. **3D** — ATTITUDE + gyro; GLTF in WebView; OrbitControls for camera; Height from Live Log `Z`; GPS sidebar from MAVLink.
8. **AltHold 3D** — Side ortho locked to a meter span shared by the tape and Target/Current graph; latch ring from AltHold rising edge; Current from live `Z`.
9. **Battery** — `SYS_STATUS` voltage vs saved profile thresholds → status %, first-warning dialog, critical lock.

## Setup

### Prerequisites

- Flutter SDK (see `pubspec.yaml`, SDK `^3.12.2`)
- Skydroid G20 (or Android) for radio work
- Phase B MAVLink firmware (+ SD-over-MAV for radio CSV download)
- Wi-Fi (or data) on the tablet for map tiles
- Laptop Flutter run is enough for Simulation / UI work

### Run

```bash
cd fc_tuning_studio
flutter pub get
flutter run
```
