// Vois offline peer-to-peer radio communication module
import 'dart:convert';
import 'dart:typed_data';

/// Frame types carried over the RFCOMM/WiFi-Direct byte channel.
class FrameType {
  static const int audio = 0x01;
  static const int connectTo = 0x02;
  static const int chainInfo = 0x03;
  static const int disconnect = 0x04;

  /// Raw 32-byte AES-256 key, sent once by the connection's initiator
  /// immediately after the channel opens. Not itself encrypted — see
  /// PayloadCipher for why that's safe here.
  static const int keyExchange = 0x05;

  /// AES-encrypted JSON: {code, lat, lng, sentAt} — a tiny coded distress
  /// payload, max-volume/non-interruptible on receipt.
  static const int sos = 0x06;

  /// Round-trip probe used by the field-test harness. Payload is the
  /// sender's 8-byte little-endian epoch microseconds; the peer echoes it
  /// back untouched as [pong], so the sender can subtract without the two
  /// devices needing synchronised clocks beyond their own wall clock.
  static const int ping = 0x07;
  static const int pong = 0x08;
}

/// Every frame = [1 type byte][2-byte little-endian length][payload].
/// Length-prefixed because control and SOS payloads vary in size and the
/// transport may deliver arbitrary chunks.

Uint8List wrapFrame(int type, List<int> payload) {
  final len = payload.length;
  final out = Uint8List(3 + len);
  out[0] = type;
  out[1] = len & 0xff;
  out[2] = (len >> 8) & 0xff;
  out.setRange(3, out.length, payload);
  return out;
}

int frameType(Uint8List frame) => frame[0];

Uint8List framePayload(Uint8List frame) => Uint8List.sublistView(frame, 3);

/// Reassembles length-prefixed frames from a raw byte stream
/// (RFCOMM may deliver arbitrary chunks).
class FrameAssembler {
  final List<int> _buf = [];

  void add(List<int> bytes) => _buf.addAll(bytes);

  Uint8List? next() {
    if (_buf.length < 3) return null;
    final len = _buf[1] | (_buf[2] << 8);
    if (_buf.length < 3 + len) return null;
    final frame = Uint8List.fromList(_buf.sublist(0, 3 + len));
    _buf.removeRange(0, 3 + len);
    return frame;
  }
}

Uint8List packAudio(Uint8List payload) => wrapFrame(FrameType.audio, payload);

Uint8List packConnectTo(List<String> addrs, List<String> names) {
  final json = jsonEncode({'addrs': addrs, 'names': names});
  return wrapFrame(FrameType.connectTo, utf8.encode(json));
}

Uint8List packChainInfo(List<String> names) {
  final json = jsonEncode({'names': names});
  return wrapFrame(FrameType.chainInfo, utf8.encode(json));
}

Uint8List packDisconnect() => wrapFrame(FrameType.disconnect, const []);

({List<String> addrs, List<String> names})? parseConnectTo(Uint8List payload) {
  final data = jsonDecode(utf8.decode(payload));
  if (data is! Map) return null;
  final addrs = (data['addrs'] as List).cast<String>();
  final names = (data['names'] as List).cast<String>();
  return (addrs: addrs, names: names);
}

List<String>? parseChainInfo(Uint8List payload) {
  final data = jsonDecode(utf8.decode(payload));
  if (data is! Map) return null;
  return (data['names'] as List).cast<String>();
}

Uint8List packKeyExchange(Uint8List key32) => wrapFrame(FrameType.keyExchange, key32);

Uint8List packSos(Uint8List encryptedJson) => wrapFrame(FrameType.sos, encryptedJson);

/// Round-trip probe. The 8-byte payload is the sender's epoch microseconds;
/// the receiver answers with [packPong] carrying the same bytes.
Uint8List packPing(int sentAtMicros) {
  final payload = ByteData(8)..setUint64(0, sentAtMicros, Endian.little);
  return wrapFrame(FrameType.ping, payload.buffer.asUint8List());
}

Uint8List packPong(Uint8List echoedPayload) => wrapFrame(FrameType.pong, echoedPayload);

/// The epoch microseconds carried by a ping/pong payload, or null if the
/// frame is too short to be one.
int? probeMicros(Uint8List payload) => payload.length < 8
    ? null
    : ByteData.sublistView(payload).getUint64(0, Endian.little);
