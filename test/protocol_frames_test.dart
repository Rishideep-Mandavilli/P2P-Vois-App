import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:p2p_vois/protocol.dart';

void main() {
  test('key exchange frame carries the raw key bytes', () {
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    final frame = packKeyExchange(key);
    expect(frameType(frame), FrameType.keyExchange);
    expect(framePayload(frame), key);
  });

  test('sos frame carries opaque (already-encrypted) bytes', () {
    final ciphertext = Uint8List.fromList([5, 5, 5]);
    final frame = packSos(ciphertext);
    expect(frameType(frame), FrameType.sos);
    expect(framePayload(frame), ciphertext);
  });

  test('FrameAssembler handles control frames mixed with audio ones', () {
    final frames = [
      packAudio(Uint8List.fromList([1, 2, 3])),
      packKeyExchange(Uint8List.fromList(List.filled(32, 7))),
      packSos(Uint8List.fromList([8, 9])),
    ];
    final assembler = FrameAssembler();
    assembler.add(frames.expand((f) => f).toList());
    final out = <Uint8List>[];
    Uint8List? f;
    while ((f = assembler.next()) != null) {
      out.add(f!);
    }
    expect(out.map(frameType), [
      FrameType.audio,
      FrameType.keyExchange,
      FrameType.sos,
    ]);
  });
}
