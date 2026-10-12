import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:p2p_vois/protocol.dart';

void main() {
  test('connectTo and chainInfo round-trip', () {
    final frame = packConnectTo(
      ['AA:BB:CC:DD:EE:FF'],
      ['Phone A', 'Phone B', 'Phone C'],
    );
    expect(frameType(frame), FrameType.connectTo);
    final parsed = parseConnectTo(framePayload(frame));
    expect(parsed!.addrs, ['AA:BB:CC:DD:EE:FF']);
    expect(parsed.names, ['Phone A', 'Phone B', 'Phone C']);

    final chain = packChainInfo(['Phone A', 'Phone B', 'Phone C']);
    expect(frameType(chain), FrameType.chainInfo);
    expect(parseChainInfo(framePayload(chain)),
        ['Phone A', 'Phone B', 'Phone C']);
  });

  test('names survive commas and newlines', () {
    final frame = packChainInfo(['Red,mi', 'note\n10']);
    expect(parseChainInfo(framePayload(frame)), ['Red,mi', 'note\n10']);
  });

  test('FrameAssembler reassembles partial and coalesced chunks', () {
    final a = packAudio(Uint8List.fromList(List.filled(50, 7)));
    final b = packChainInfo(['X']);
    final c = packConnectTo(['11:22'], ['Y']);

    // Feed byte-by-byte in awkward split points.
    final assembler = FrameAssembler();
    final all = [...a, ...b, ...c];
    final out = <Uint8List>[];
    for (int i = 0; i < all.length; i += 3) {
      assembler.add(all.sublist(i, i + 3 > all.length ? all.length : i + 3));
      Uint8List? f;
      while ((f = assembler.next()) != null) {
        out.add(f!);
      }
    }

    expect(out.length, 3);
    expect(frameType(out[0]), FrameType.audio);
    expect(frameType(out[1]), FrameType.chainInfo);
    expect(frameType(out[2]), FrameType.connectTo);
    expect(framePayload(out[0]), List.filled(50, 7));
  });
}