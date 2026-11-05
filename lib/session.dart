// Vois offline peer-to-peer radio communication module
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'alerts/sos.dart';
import 'audio.dart';
import 'audio_filter.dart';
import 'codec.dart';
import 'crypto/payload_cipher.dart';
import 'field_metrics.dart';
import 'protocol.dart';
import 'radio_server.dart';

/// Minimal duplex byte channel over the native RFCOMM transport.
abstract class ByteChannel {
  Stream<Uint8List> get input;
  void add(Uint8List bytes);
  Future<void> close();
}

class RadioChannel implements ByteChannel {
  final RadioServer server;
  final int id;
  RadioChannel(this.server, this.id);

  @override
  Stream<Uint8List> get input => server.dataOf(id);

  @override
  void add(Uint8List bytes) {
    server.write(id, bytes).catchError((e) => debugPrint('RadioChannel.write: $e'));
  }

  @override
  Future<void> close() => server.close(id);
}

/// Glues microphone -> ADPCM -> byte channel and back: the raw-audio
/// walkie-talkie pipeline. A call runs over one transmit and one receive
/// channel so either can be a separate RFCOMM tunnel.
///
/// Relayed audio frames are forwarded whole without decoding, so an
/// intermediate phone costs almost no CPU. Encrypted payloads are not
/// re-encrypted onward: the AES key is per-connection (see [PayloadCipher]),
/// so a relay only propagates audio and chain metadata.
class RadioSession {
  final AudioEngine audio;
  final RadioServer server;
  ByteChannel? _txChannel;
  ByteChannel? _rxChannel;
  ByteChannel? _downstream;
  StreamSubscription<Uint8List>? _rxSub;
  StreamSubscription<Uint8List>? _downSub;
  final AdpcmEncoder _encoder = AdpcmEncoder();
  final AdpcmDecoder _decoder = AdpcmDecoder();
  final AudioFilter _filter = AudioFilter();
  final FrameAssembler _upAssembler = FrameAssembler();
  final FrameAssembler _downAssembler = FrameAssembler();
  bool _micOn = false;
  bool _disposed = false;

  /// How long an incoming SOS keeps the phone shouting before it stands down.
  static const int sosAlertDurationMs = 6000;

  final ValueNotifier<List<String>> chain = ValueNotifier(const []);
  final ValueNotifier<bool> relaying = ValueNotifier(false);
  final ValueNotifier<bool> peerLeft = ValueNotifier(false);

  PayloadCipher? _cipher;

  /// Which radio this call rides on; recorded so exported numbers are
  /// attributable without asking the tester to remember.
  final String transport;

  /// Live counters for the field-test harness.
  final FieldMetrics metrics = FieldMetrics();

  /// Non-null while an incoming SOS alert is showing — the UI treats this as
  /// non-interruptible until it clears back to null.
  final ValueNotifier<IncomingSos?> incomingAlert = ValueNotifier(null);

  RadioSession(this.audio, this.server, {this.transport = 'Bluetooth RFCOMM'});

  Future<void> start(ByteChannel txChannel, ByteChannel rxChannel,
      {required bool isInitiator}) async {
    _txChannel = txChannel;
    _rxChannel = rxChannel;
    try {
      _rxSub = rxChannel.input.listen(_onUpBytes, onDone: _onPeerGone);
      await audio.startPlayback();
      if (_disposed) return;
      final hasEarpiece = await server.isEarpieceAvailable();
      if (hasEarpiece) {
        await server.setEarpiece();
      } else {
        await server.setLoudspeaker();
      }
      if (_disposed) return;
      if (isInitiator) {
        final key = PayloadCipher.generateKey();
        _cipher = PayloadCipher(key);
        _txChannel?.add(packKeyExchange(key));
      }
    } catch (e) {
      await dispose();
      rethrow;
    }
  }

  /// Send a relay request upstream: ask the connected peer to dial the
  /// given addresses in order, forming a chain [names].
  void relayTo(List<String> addrs, List<String> names) {
    _txChannel?.add(packConnectTo(addrs, names));
  }

  void _onUpBytes(Uint8List bytes) {
    _upAssembler.add(bytes);
    while (true) {
      final frame = _upAssembler.next();
      if (frame == null) break;
      _handleUpFrame(frame);
    }
  }

  void _handleUpFrame(Uint8List frame) {
    final type = frameType(frame);
    final payload = framePayload(frame);
    switch (type) {
      case FrameType.audio:
        metrics.recordRx(frame);
        if (_downstream != null) {
          _downstream?.add(frame);
        } else if (payload.length == kFrameBytes) {
          final pcm = _decoder.decode(payload);
          audio.play(pcm.buffer.asUint8List());
        }
        break;
      case FrameType.connectTo:
        _handleRelayRequest(payload);
        break;
      case FrameType.chainInfo:
        final names = parseChainInfo(payload);
        if (names != null) chain.value = names;
        break;
      case FrameType.disconnect:
        _onPeerGone();
        break;
      case FrameType.keyExchange:
        _cipher = PayloadCipher(payload);
        break;
      case FrameType.sos:
        _handleIncomingSos(payload);
        break;
      case FrameType.ping:
        // Answer with the sender's own timestamp so it can measure the round
        // trip on its clock; nothing is timed locally here.
        _txChannel?.add(packPong(payload));
        break;
      case FrameType.pong:
        final echoed = probeMicros(payload);
        if (echoed != null) {
          metrics.recordPong(echoed, DateTime.now().microsecondsSinceEpoch);
        }
        break;
    }
  }

  /// One round-trip probe. Call this on a timer from the field-test screen;
  /// the answer arrives through [FrameType.pong].
  void sendPing() {
    final channel = _txChannel;
    if (channel == null) return;
    metrics.recordPingSent();
    channel.add(packPing(DateTime.now().microsecondsSinceEpoch));
  }

  /// Sends a preset distress code — a tiny payload that survives a badly
  /// degraded link — with the device's last-known GPS fix if available.
  Future<void> sendSos(SosCode code) async {
    final cipher = _cipher;
    if (cipher == null) return; // key exchange not complete yet
    final loc = await server.getLastKnownLocation();
    final payload = jsonEncode({
      'code': code.code,
      'lat': loc?.lat,
      'lng': loc?.lng,
      'sentAt': DateTime.now().millisecondsSinceEpoch,
    });
    _txChannel?.add(packSos(cipher.encrypt(payload)));
  }

  Future<void> _handleIncomingSos(Uint8List payload) async {
    final cipher = _cipher;
    if (cipher == null) return;
    try {
      final decoded = jsonDecode(cipher.decrypt(payload)) as Map;
      final code = SosCode.fromCode(decoded['code'] as String? ?? '');
      if (code == null) return;
      await _playAlert(
        code,
        lat: decoded['lat'] as double?,
        lng: decoded['lng'] as double?,
      );
    } catch (_) {}
  }

  /// Loud, vibrating, on-screen alert that cannot be dismissed early. The
  /// tone is what makes it work with the screen face-down; the alarm-stream
  /// volume push is what makes it work through Do Not Disturb.
  Future<void> _playAlert(SosCode code, {double? lat, double? lng}) async {
    incomingAlert.value =
        IncomingSos(code: code, lat: lat, lng: lng, receivedAt: DateTime.now());
    unawaited(server.setMaxAlertVolume());
    unawaited(server.vibrateAlert());
    // The native tone schedules itself and returns at once, so the banner
    // duration is timed here rather than by awaiting the call.
    unawaited(server.playAlertTone(ms: sosAlertDurationMs));
    await Future.delayed(const Duration(milliseconds: sosAlertDurationMs));
    incomingAlert.value = null;
  }

  void _onDownBytes(Uint8List bytes) {
    _downAssembler.add(bytes);
    while (true) {
      final frame = _downAssembler.next();
      if (frame == null) break;
      final type = frameType(frame);
      final payload = framePayload(frame);
      switch (type) {
        case FrameType.audio:
          metrics.recordTx(frame);
          _txChannel?.add(frame);
          break;
        case FrameType.chainInfo:
          final names = parseChainInfo(payload);
          if (names != null) chain.value = names;
          _txChannel?.add(frame);
          break;
        case FrameType.disconnect:
          _onPeerGone();
          break;
      }
    }
  }

  Future<void> _handleRelayRequest(Uint8List payload) async {
    if (_downstream != null) return;
    final req = parseConnectTo(payload);
    if (req == null || req.addrs.isEmpty) return;
    final addrs = [...req.addrs];
    final names = [...req.names];
    final nextAddr = addrs.removeAt(0);
    try {
      final id = await server.connect(nextAddr);
      if (_disposed) {
        server.close(id);
        return;
      }
      _downstream = RadioChannel(server, id);
      _downSub = _downstream!.input.listen(_onDownBytes);
      relaying.value = true;
      chain.value = names;
      if (addrs.isNotEmpty) {
        _downstream!.add(packConnectTo(addrs, names));
      }
      _downstream!.add(packChainInfo(names));
      _txChannel?.add(packChainInfo(names));
      if (_micOn) await _setMic(false, onPcm: _send);
    } catch (e) {
      final failed = [...names]..[names.length - 1] = '${names.last} ✗';
      _txChannel?.add(packChainInfo(failed));
    }
  }

  /// Live call: microphone stays on continuously (full-duplex, raw audio).
  Future<void> startCall() => _setMic(true, onPcm: _send);
  Future<void> stopCall() => _setMic(false, onPcm: _send);

  /// Push-to-talk: microphone on only while held (raw audio).
  Future<void> startTalking() => _setMic(true, onPcm: _send);
  Future<void> stopTalking() => _setMic(false, onPcm: _send);

  Future<void> _setMic(bool on, {required void Function(Uint8List) onPcm}) async {
    if (_disposed || on == _micOn) return;
    _micOn = on;
    if (on) {
      _filter.reset();
      _encoder.reset();
      await audio.startListening(onPcm);
    } else {
      await audio.stopListening();
    }
  }

  void _send(Uint8List pcm) {
    final samples = pcmToSamples(pcm);
    _filter.process(samples);
    final encoded = _encoder.encode(samples);
    final frame = packAudio(encoded);
    metrics.recordTx(frame);
    _txChannel?.add(frame);
  }

  void _onPeerGone() {
    if (_disposed) return;
    peerLeft.value = true;
    dispose();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // Say goodbye explicitly. Without this the peer only learns the call ended
    // when the socket close surfaces, which can lag by seconds. The channel may
    // already be dead when dispose runs (that is one of the reasons we get
    // here), so the notification is best-effort.
    try {
      _txChannel?.add(packDisconnect());
    } catch (e) {
      debugPrint('RadioSession: disconnect notify failed: $e');
    }
    await _setMic(false, onPcm: _send);
    await server.resetAudioMode();
    await _rxSub?.cancel();
    _rxSub = null;
    await _downSub?.cancel();
    _downSub = null;
    try {
      await _txChannel?.close();
    } catch (e) {
      debugPrint('RadioSession.dispose close: $e');
    }
    try {
      await _rxChannel?.close();
    } catch (e) {
      debugPrint('RadioSession.dispose close: $e');
    }
    try {
      await _downstream?.close();
    } catch (e) {
      debugPrint('RadioSession.dispose close: $e');
    }
    _txChannel = null;
    _rxChannel = null;
    _downstream = null;
  }
}

class IncomingSos {
  final SosCode code;
  final double? lat;
  final double? lng;
  final DateTime receivedAt;
  IncomingSos({required this.code, this.lat, this.lng, required this.receivedAt});
}
