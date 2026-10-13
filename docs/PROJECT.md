# P2P Vois — what it is

The authoritative description of the project: what problem it solves, what is actually built,
what has been measured, and what has not. Written to be read by a judge, a contributor or a
potential partner without needing to open the source.

Facts below are current as of **v1.1.0+2** (2026-10-13). Anything not verified on real hardware
is marked.

---

## The answer in one line

**Vois turns the phones in a crowd into the network, when there isn't one** — voice calls, phone
to phone, over radio, with no cellular network, no internet, no router, no SIM, no account and
no server.

## The problem

Cell sites are a single point of failure. A cyclone, a flood, an earthquake, or 40,000 people in
one square kilometre removes a base station's power or backhaul, and every phone in the area
becomes useless for coordination. Rescue teams fall back to licensed radios that most victims do
not own. Satellite messengers cost tens of thousands of rupees per device plus a subscription.

The people affected are carrying a WiFi radio and a Bluetooth radio in their pocket. **Nothing
puts those two radios to work peer to peer.**

Concrete scenarios:

- **Flood and cyclone relief** — towers down, roads cut, NDRF/SDRF teams and separated families
  needing to talk inside a few hundred metres.
- **Crowd events** — Kumbh Mela, stadium grounds, concerts: capacity, not coverage, is the
  failure mode, so the network exists but nobody can use it.
- **Basements, tunnels, industrial sites** — places with deliberate or incidental dead zones
  where a worker or a trapped person cannot raise anyone.
- **Grid or backhaul outage** — a city-wide event where every OTT calling app fails at once
  because they all depend on the same internet connection.

## Why the existing options don't cover this

| Option | Why it fails here |
|---|---|
| Mobile voice / WhatsApp / any OTT app | Dies with the cell site or the internet; needs accounts and a phone number |
| Bluetooth Mesh, Zigbee, Thread | Roughly 10–30 kbps and 11-byte payloads; flooding saturates 2.4 GHz; no voice path at all |
| Licensed two-way radios / walkie-talkies | Hardware most victims do not own; limited range indoors |
| LoRa / Meshtastic-class devices | Text and telemetry, not voice; requires buying nodes |
| Satellite messengers | Expensive device plus subscription; message latency, no live call |
| Wi-Fi hotspot / infrastructure apps | Need an existing network or an access point to join |

Vois requires **two phones that will pair with each other.** That is the entire dependency.

## What is built today

- **Live** full-duplex call with tap-to-mute, and **PTT** hold-to-talk.
- **Two radios behind one interface**: WiFi Direct (primary) and Bluetooth Classic RFCOMM
  (fallback). Both are selectable by the user; there is no automatic failover.
- **Dual RFCOMM tunnels** — separate transmit and receive sockets, with earpiece or speaker
  routing per call.
- **Relay chain** — a third phone extends reach (`You → A → B`). Relays forward whole audio
  frames without decoding, so an intermediate phone costs almost no CPU.
- **SOS** — six preset codes (Trapped, Medical, Fire, Flood, Need Water, Safe) sent as a tiny
  coded payload with the last GPS fix. On receipt the phone forces maximum volume, vibrates,
  plays a repeating alarm-stream siren that survives Do Not Disturb, and shows a banner that
  cannot be dismissed early.
- **Broadcast SOS** — a phone becomes the WiFi Direct group owner and reaches every connected
  peer at once.
- **Store-and-forward** — an SOS sent while nobody is in range is queued and handed off the
  moment a peer connects, instead of being dropped.
- **AES-256-CBC** payload encryption with a per-call key.
- **Battery-aware duty cycling** — under 20 % charge, the discovery scan window widens from 15 s
  to 45 s.
- **Field-test harness** — in-call round-trip probes, frame and byte counters both directions,
  live kbps, battery across the call, one-tap CSV export.

## How it works

```
mic → PCM16 16 kHz mono, 20 ms frames (320 samples) → ADPCM 8 bits/sample (323 B/frame)
    → length-prefixed frame → ByteChannel → radio

radio → ByteChannel → frame → ADPCM decode → 40 ms jitter buffer (2 frames) → speaker
```

| | Primary | Fallback |
|---|---|---|
| Radio | WiFi Direct (WiFi P2P) | Bluetooth Classic RFCOMM |
| Wire | TCP port 8988 | SPP UUID 00001101, dual tx/rx tunnels |
| Channel names | `p2p_wifi/methods`, `p2p_wifi/events` | `p2p_server/methods`, `p2p_server/events` |
| Who listens | The caller takes group-owner intent and runs the server socket | The listener accepts RFCOMM |
| Typical range | ~50 m open air, less in a crowd | ~10 m |

Both radios implement the same `ByteChannel` interface, so `RadioSession` is radio-agnostic.
That interface is also the seam anything else — a text channel, a sensor feed, someone else's
speech layer — would attach to without touching transport code.

### Wire protocol

Every frame is `[1 type byte][2-byte little-endian length][payload]`.

| Type | Byte | Payload |
|---|---|---|
| audio | `0x01` | ADPCM frame |
| connectTo | `0x02` | JSON `{addrs, names}` — asks a peer to dial onward |
| chainInfo | `0x03` | JSON `{names}` — the relay chain for display |
| disconnect | `0x04` | empty; sent explicitly on hangup |
| keyExchange | `0x05` | raw 32-byte AES key |
| sos | `0x06` | AES-encrypted JSON `{code, lat, lng, sentAt}` |
| ping | `0x07` | sender's 8-byte epoch microseconds |
| pong | `0x08` | the same bytes, echoed untouched |

The probe design is deliberate: the responder echoes the *sender's own* timestamp, so round-trip
time is computed on one clock and the two phones never need synchronised time.

## Repository facts (as of v1.1.0+2)

- 16 Dart files / ~2,600 lines in `lib/`, 4 Kotlin files / ~1,250 lines of native transport.
- 7 test files / ~380 lines; **27 tests pass**; `flutter analyze` reports no issues.
- Release APK **47 MB**, `com.vois.p2p`, no AI models, no cloud SDK, no proprietary voice
  library.
- Dependencies: `flutter_sound`, `permission_handler`, `package_info_plus`, `encrypt`, `crypto`.
  Nothing that phones home.
- Platform: **Android only.** iOS does not support Android's WiFi P2P and forbids the background
  sockets this needs.

## Numbers: what is measured and what is not

This is the honest ledger. Until the row says measured, it must not be quoted as a result.

| Claim | Status |
|---|---|
| Wire bitrate | **~129 kbps by construction** (323 B × 50 frames/s). Deterministic from the codec, not yet observed on air. |
| Round-trip latency | **Not measured.** Harness shipped in v1.1.0; needs two phones. |
| Effective range in a crowd | **Not measured.** |
| Call endurance / battery per hour | **Not measured.** |
| Relay loss behaviour | **Not measured.** |
| Works on two physical phones | **Not yet verified on hardware in this repo's history.** |

How each number gets produced: `README.md` → *"Field test: how the numbers get produced"* — a
six-step procedure that ends with a CSV from each phone.

## Where it fits the Tata Imagination Challenge

The challenge's rounds run Quiz → Game Plan → **Video Pitch** → Defence → Finale; the deliverable
is a recorded pitch, and **registration for the 2026 cycle closed in August 2026**. Confirm the
edition and deadline you are entered in before planning submission work — the build matters for
the Defence round either way, but the video is the gate.

Positioning for that audience:

- **Disaster resilience and public safety** — deployable the hour a cyclone or a stampede
  happens, using phones people already hold. No procurement, no rollout, no training beyond a
  tap.
- **Network resilience** — a device-to-device fallback path is the complement to
  infrastructure-hardening work, not a competitor to it: it operates precisely in the window
  where the network is down.
- **Industrial and event safety** — construction sites, tunnels, plants and venues with known
  dead zones where a worker's phone is already in their pocket.
- **Rural and last-mile reach** — runs on low and mid-range Android, the devices actually
  present, with no subscription and no data plan.
- **Open and auditable** — free and open source, indigenous build, distress traffic never leaves
  the radios between the two phones.

## Differentiators worth defending

1. **Zero infrastructure, zero cost, zero accounts.** The dependency is a phone the victim owns.
2. **Voice, not text.** For panicked, injured or low-literacy users, which every text-only mesh
   tool excludes.
3. **Relay that barely costs the relayer.** Frames are forwarded undecoded, so a helping phone
   is not punished with battery drain — the failure mode of volunteer-relay designs.
4. **Two independent radios.** If WiFi P2P negotiation fails on a given device pair, Bluetooth
   still forms a link.
5. **SOS engineered for the pocket.** Alarm-stream siren plus vibration plus a non-dismissible
   banner works with the screen face-down and Do Not Disturb on.
6. **A measurement harness in the product itself.** Numbers come from the shipping app, so a
   claim can be re-derived by anyone with two phones.

## Honest gaps and risks

State these before anyone finds them.

- **Bitrate is 129 kbps.** ADPCM halves PCM16 but is not a VoIP codec. The design target for this
  class of link is Opus at 8–12 kbps. That swap is not done, and it is the single biggest
  available win for range, battery and relay depth.
- **Live audio rides TCP**, which head-of-line-blocks a delay-tolerant medium. Only PTT genuinely
  wants TCP's guaranteed delivery.
- **It is a relay, not a mesh.** One call at a time per phone, at most three devices, and a relay
  request is ignored if a downstream already exists. No routing tables, TTL or duplicate
  suppression. Store-and-forward is single-hop.
- **Reconnection is manual.** A hangup now announces itself and the Bluetooth screen offers
  one-tap reconnect to the last peer, but a link lost mid-call still ends the call.
- **Key exchange sends the AES key in plaintext**, trusting that the Bluetooth pairing or WiFi
  Direct group is already private. SOS broadcast deliberately uses a fixed, publicly-known key so
  any nearby phone can decode a distress beacon — it is a beacon, not a confidential message.
- **No hardware verification yet**, and no test coverage on `RadioSession`, relay, discovery or
  any Kotlin. The pure logic (codec, framing, cipher, metrics, SOS queue) is covered.
- **Android only**, so a mixed-iOS group cannot use it.
- **The launcher icon and app name are still placeholder-grade**, and permission failures surface
  as a raw exception string. Not yet product polish.
- **Regulatory and operational reality** — who is authorised to broadcast a distress beacon, and
  what a false SOS does to a responder — is unaddressed.

## Roadmap

| Phase | Work | Exit gate |
|---|---|---|
| **1 · Measure** | Two-phone field runs at four distances plus a relay; collect RTT, kbps, endurance, drain | A CSV per scenario, archived |
| **2 · Survive** | Automatic re-dial with key re-exchange, heartbeat and dead-peer detection, foreground service verified under Android 14+ Doze | A 30-minute walk test with no drop |
| **3 · Bitrate** | Opus at 8–12 kbps replacing ADPCM; live audio on UDP, control frames on TCP | ≥10× traffic reduction with intelligible speech |
| **4 · Depth** | Either true multi-hop with TTL and duplicate caching, or stop saying "mesh" and own "relay" | A decision backed by Phase 1 data |
| **5 · Product** | Real icon and identity, onboarding and permission UX, human error states, localised SOS labels, a test seam for `RadioSession` | A stranger can pair two phones unaided |
| **6 · Pitch** | Numbers table, 90-second demo, honest-gap slide, deployment story | Submittable video |

Phase 3 is deliberately sequenced after Phase 1: **do not replace a codec you have never
measured.** The baseline tells you whether the limiter is bitrate or TCP head-of-line blocking,
and guessing wrong costs the working audio path.

## The demo to record

Ninety seconds, unfakeable:

1. Both phones in airplane mode, SIM trays out, shown on camera.
2. Install and open Vois on both; pair over Bluetooth; live call established.
3. Walk 100 m apart; call still up. Cut to the field-test screen showing probes answering.
4. A third phone joins; the chain reads `You → A → B`.
5. SOS from the far end; camera stays on the middle phone so its screen lights up and the siren
   is audible.
6. End on the exported CSV with the latency and kbps rows visible.
