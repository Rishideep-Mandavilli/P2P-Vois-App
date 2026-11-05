# GEMINI.md — Project Guide & Agent Context for Vois (P2P)

## Project Overview
**Vois** is an offline, phone-to-peer voice communication tool designed for disaster relief, high-density crowds, and industrial dead zones. It operates directly over radio (Wi-Fi Direct and Bluetooth Classic RFCOMM) with zero reliance on cellular networks, internet infrastructure, SIM cards, or central servers.

- **Primary Repository / Application**: `p2p-vois/` (Flutter & Android native Kotlin)
- **Deck & Presentation Generation**: `generate_deck.py`, `make_presentation.py`
- **Current Release Target**: Android (v1.1.0+2)

---

## Architecture & Transports

### Radio Transports
| Transport | Range | Implementation |
|---|---|---|
| **Wi-Fi Direct** (Primary) | ~50m open-air | TCP port 8988 via `WifiDirectPlugin.kt` & `WifiDirectServer` |
| **Bluetooth Classic RFCOMM** (Fallback) | ~10m | SPP UUID `00001101` via `P2pServerPlugin.kt` & `RadioServer` |

Both transports implement the unified `ByteChannel` abstraction, allowing `RadioSession` to operate seamlessly over either.

### Core Modules (`p2p-vois/lib/`)
- `main.dart`: App bootstrap, permission handling, background radio listener init.
- `session.dart`: Audio streaming pipeline, relay chaining, SOS handling.
- `protocol.dart`: Binary framing layer (`[1B type][2B LE length][payload]`).
- `codec.dart`: 8-bit ADPCM encode/decode.
- `audio.dart`: Audio capture, playback, and 40ms jitter buffer.
- `crypto/payload_cipher.dart`: AES-256-CBC envelope encryption for text/metadata.
- `alerts/`: SOS preset codes, GPS location bundling, and single-hop store-and-forward queue.
- `power/battery_saver.dart`: Battery-aware discovery duty cycling.
- `field_metrics.dart`: Round-trip time (RTT), throughput, and battery drain tracking.

### Native Plugins (`p2p-vois/android/app/src/main/kotlin/com/vois/p2p/`)
- `RadioService.kt`: Android Foreground Service keeping connections alive when backgrounded.
- `P2pServerPlugin.kt`: Bluetooth RFCOMM, GPS fix acquisition, volume & vibration overrides.
- `WifiDirectPlugin.kt`: Android Wi-Fi P2P discovery and TCP socket handling.

---

## Development & Testing Workflow

### Running Tests
Execute Flutter unit and widget tests from the `p2p-vois` directory:
```bash
cd p2p-vois
flutter test
```

### Static Analysis
```bash
cd p2p-vois
flutter analyze
```

### Running on Device
Ensure an Android device or emulator is connected:
```bash
cd p2p-vois
flutter run
```

### Presentation & Pitch Assets
To generate marketing and architecture slide assets:
```bash
source .venv/bin/activate
python generate_deck.py
python make_presentation.py
```

---

## Gemini Agent Instructions
- **Safety First**: Do not modify radio transport socket logic or audio buffer constraints without running `flutter test`.
- **Wire Compatibility**: Changes to frame types in `protocol.dart` or codec bitrates must ensure backward compatibility across nodes.
- **Battery & Performance**: Zero-CPU undecoded relaying is critical to preventing battery drain on relay nodes.
