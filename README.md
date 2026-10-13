# Vois

Offline, phone-to-peer voice. Two Android phones talk directly over radio — no cellular
network, no internet, no router, no account, no server. Push-to-talk or live full-duplex,
with a third phone able to relay, coded SOS alerts carrying GPS coordinates, and
AES-encrypted payloads.

Built for the situations where the infrastructure is gone: cyclones and floods, a stadium or
a Kumbh Mela crowd where 40,000 devices overload the cell sites, a basement with no line of
sight to a responder.

## Architecture

```
lib/
  main.dart              bootstraps audio + radio, asks permissions, starts listening
  discovery.dart         Bluetooth peer list, pair, tap-to-call, dual-tunnel role pairing
  call_page.dart         in-call UI: Live/PTT, mute, chain display, SOS sheet, relay chips
  wifi_direct_page.dart  WiFi Direct scan/connect, become group owner, broadcast SOS
  session.dart           the call: mic -> ADPCM -> channel -> speaker, plus relay + SOS
  protocol.dart          wire framing: [1B type][2B LE length][payload]
  codec.dart             ADPCM encode/decode, 8 bits per sample
  audio.dart             flutter_sound capture + playback, 20ms frames, jitter buffer
  wifi_server / wifi_direct_server / radio_server
                         Dart facades over the native transports (ByteChannel)
  crypto/payload_cipher.dart   AES-256-CBC envelopes
  alerts/                SOS preset codes + single-hop store-and-forward queue
  power/battery_saver.dart     battery-aware discovery duty cycling
android/app/src/main/kotlin/com/vois/p2p/
  P2pServerPlugin.kt     Bluetooth Classic RFCOMM, GPS, volume/vibration, battery
  WifiDirectPlugin.kt    WiFi P2P discovery, group formation, TCP sockets
  RadioService.kt        foreground service keeping the radio alive
```

## Transports

| | Primary | Fallback |
|---|---|---|
| Radio | WiFi Direct (WiFi P2P) | Bluetooth Classic RFCOMM |
| Wire | TCP port 8988 | RFCOMM SPP (UUID 00001101) |
| Channels | `p2p_wifi/methods`, `p2p_wifi/events` | `p2p_server/methods`, `p2p_server/events` |
| Range | ~50 m open air, less in a crowd | ~10 m |

The caller requests group-owner intent and listens; the callee joins and dials the group
owner. Both are behind one `ByteChannel` interface, so `RadioSession` runs unchanged over
either. The radio is chosen by the user — there is no automatic failover between them yet.

## Audio

Capture is PCM16, 16 kHz, mono, `voice_communication` source with noise suppression and echo
cancellation, delivered in 20 ms frames (320 samples). Frames are ADPCM-encoded to 8 bits per
sample: 323 bytes per frame, ~129 kbps. Receive side decodes into a 2-frame (40 ms) jitter
buffer before feeding the player. Relayed frames are forwarded whole without decoding, so an
intermediate phone costs almost no CPU.

## Protocol

| Type | Byte | Payload |
|---|---|---|
| audio | `0x01` | ADPCM frame |
| connectTo | `0x02` | JSON `{addrs, names}` — asks a peer to dial onward |
| chainInfo | `0x03` | JSON `{names}` — the relay chain for display |
| disconnect | `0x04` | empty |
| keyExchange | `0x05` | raw 32-byte AES key |
| sos | `0x06` | AES-encrypted JSON `{code, lat, lng, sentAt}` |
| ping | `0x07` | sender's 8-byte epoch microseconds |
| pong | `0x08` | the same bytes, echoed untouched |

## Feature set

- **Live** full-duplex call with tap-to-mute, and **PTT** hold-to-talk.
- **Relay chain** — extend reach through a third phone; the call screen shows `You → A → B`.
- **SOS** — six preset codes (Trapped, Medical, Fire, Flood, Need Water, Safe) sent as a tiny
  coded payload with the last GPS fix; the receiving phone forces maximum volume, vibrates,
  and shows a non-dismissible banner.
- **Broadcast SOS** — become the WiFi Direct group owner and reach every connected peer at once.
- **Store-and-forward** — an SOS sent while nobody is in range is queued and handed off when a
  peer connects.
- **Battery duty cycling** — below 20 % the discovery scan window widens from 15 s to 45 s.
- **Field test harness** — an in-call screen that probes round-trip latency once a second,
  counts frames and bytes in both directions, derives live kbps, tracks battery across the
  call, and copies it all out as CSV.

## Setup

```bash
flutter pub get
flutter analyze
flutter test
./tool/build.sh          # -> dist/vois-v<version>.apk
```

Two physical Android phones are required to test a call. WiFi Direct and Bluetooth RFCOMM both
need real radios; neither works on an emulator.

## Field test: how the numbers get produced

Every figure quoted about Vois should come from this procedure, run on two real phones.

1. Install `dist/vois-v*.apk` on both phones. Airplane mode on both — no cellular, no WiFi client.
2. Connect. Bluetooth: *Nearby Phones* → tap the peer. WiFi Direct: 📡 → tap the peer.
3. In the call, tap the ⏱ icon → **Probe once a second**.
4. Hold the call for a fixed 10 minutes. Note the distance, and whether anyone walked.
5. Tap **Copy CSV** on both phones and paste it somewhere durable before hanging up.
6. Repeat at: same room, 30 m apart, through a floor, and with a third phone relaying.

| Field | What it settles |
|---|---|
| `rtt_median_ms` | whether a live call feels interactive — you want well under 150 ms |
| `kbps_out` | what the radio really carries, and the size of the case for Opus |
| `elapsed_seconds` + `battery_drain_points` | endurance per hour on a mid-range phone |
| `tx_frames` vs `rx_frames` | loss — they should track each other closely |
| `ponges_received` / `pings_sent` | reliability under distance and movement |

## Known gaps, stated honestly

- **Bitrate is ~129 kbps.** ADPCM at 8 bits/sample halves PCM16 but is not a VoIP codec. The
  design target for this class of link is Opus at 8–12 kbps; that swap is not done.
- **Live audio rides TCP**, which head-of-line-blocks a delay-tolerant medium. Only PTT really
  wants TCP's guaranteed delivery.
- **One call at a time.** A relay request is ignored if a downstream already exists, so the
  chain is at most three phones and there is no mesh routing, TTL, or duplicate suppression.
- **Reconnection is manual.** A hangup now tells the peer explicitly (`0x04`), and the Bluetooth
  screen offers a one-tap *Reconnect to <peer>*, but there is no automatic re-dial: a link lost
  mid-call still ends the call.
- **One call per phone.** A second peer that connects during a call is refused rather than
  stacked on top of the same microphone.
- **Key exchange sends the AES key in plaintext** once the radio link is up, trusting that the
  Bluetooth pairing or WiFi Direct group is already private. SOS broadcast deliberately uses a
  fixed, publicly-known key so any nearby phone can decode a distress beacon.
- **Store-and-forward is single-hop** — a queued SOS waits on that device until it sees a peer;
  it is not relayed onward through a chain.
- **Android only.** iOS does not support Android's WiFi P2P and bans the background sockets
  this needs.
- **No measured numbers yet** for latency, effective range, hops, or battery drain per hour.
