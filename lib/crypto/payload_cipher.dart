import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as enc;

/// AES-256-CBC encryption for text payloads sent over the P2P link
/// (differentiator 3B-7): protects the transmitted sentence/SOS text from
/// anything sniffing the RFCOMM/WiFi-Direct stream or a relay hop in the
/// middle of a mesh chain. Both sides must already be Bluetooth-bonded
/// (paired) before they can connect at all, so the underlying link is
/// already link-layer-encrypted by that pairing — that's what makes it
/// safe for the connection's initiator to generate a random AES-256 key
/// locally and hand it to the other side in the clear as the very first
/// frame on the channel (see FrameType.keyExchange in protocol.dart),
/// rather than needing a full asymmetric key-exchange handshake.
class PayloadCipher {
  final enc.Encrypter _encrypter;

  PayloadCipher(Uint8List key32)
      : _encrypter = enc.Encrypter(
          enc.AES(enc.Key(key32), mode: enc.AESMode.cbc),
        );

  static Uint8List generateKey() => enc.Key.fromSecureRandom(32).bytes;

  /// Fixed, publicly-known key for SOS broadcast: an
  /// SOS is meant to be understood by *any* nearby phone running Vois,
  /// not just a paired peer, so it can't depend on a per-pair key
  /// exchange. This keeps the wire format consistent (still a JSON+AES
  /// envelope) rather than adding a second cleartext code
  /// path — it is not meant to defend against anything beyond casual
  /// sniffing of a public distress beacon, which is the actual threat
  /// model here.
  static PayloadCipher get broadcast {
    final keyBytes = crypto.sha256.convert(utf8.encode('vois-sos-broadcast-v1')).bytes;
    return PayloadCipher(Uint8List.fromList(keyBytes));
  }

  /// [ciphertext] is IV (16 bytes) followed by the AES-CBC output.
  Uint8List encrypt(String plaintext) {
    final iv = enc.IV.fromSecureRandom(16);
    final result = _encrypter.encrypt(plaintext, iv: iv);
    return Uint8List.fromList([...iv.bytes, ...result.bytes]);
  }

  String decrypt(Uint8List ciphertext) {
    final iv = enc.IV(Uint8List.sublistView(ciphertext, 0, 16));
    final body = enc.Encrypted(Uint8List.sublistView(ciphertext, 16));
    return _encrypter.decrypt(body, iv: iv);
  }
}

/// Random per-utterance id used to correlate an utterance's send-side and
/// receive-side latency log entries across two devices' CSV exports.
String randomId() {
  final rnd = Random();
  return List.generate(8, (_) => rnd.nextInt(16).toRadixString(16)).join();
}
