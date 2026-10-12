import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:p2p_vois/codec.dart';
import 'package:p2p_vois/protocol.dart';

void main() {
  test('ADPCM round-trip preserves a sine wave', () {
    final encoder = AdpcmEncoder();
    final decoder = AdpcmDecoder();
    final samples = <int>[];
    final n = kFrameSamples * 10;
    for (int i = 0; i < n; i++) {
      // Fade in to give the codec time to converge from predictor 0.
      final fade = (i / (kFrameSamples * 3)).clamp(0.0, 1.0);
      samples.add((sin(i * 2 * pi * 440 / kSampleRate) * 8000 * fade).round());
    }

    final decoded = <int>[];
    for (int f = 0; f < samples.length ~/ kFrameSamples; f++) {
      final frame = samples.sublist(f * kFrameSamples, (f + 1) * kFrameSamples);
      final encoded = encoder.encode(frame);
      expect(encoded.length, kFrameBytes);
      decoded.addAll(decoder.decode(encoded));
    }

    // Skip the first few frames while the codec converges from predictor 0.
    final skip = 4 * kFrameSamples;
    var maxError = 0;
    for (int i = skip; i < decoded.length; i++) {
      final err = (decoded[i] - samples[i]).abs();
      if (err > maxError) maxError = err;
    }
    // 8-bit ADPCM (~32dB SNR) on a sine stays under ~100 LSB. A logic bug
    // produces thousands, so 150 is the sanity bound.
    expect(maxError, lessThan(150));
  });

  test('full wire path: encode -> frame -> assemble -> decode', () {
    final encoder = AdpcmEncoder();
    final decoder = AdpcmDecoder();
    final assembler = FrameAssembler();
    final samples = <int>[];
    final n = kFrameSamples * 6;
    for (int i = 0; i < n; i++) {
      final fade = (i / (kFrameSamples * 3)).clamp(0.0, 1.0);
      samples.add((sin(i * 2 * pi * 500 / kSampleRate) * 6000 * fade).round());
    }

    // Send in random-sized chunks like RFCOMM does, and interleave an
    // unrelated frame type (chainInfo) to prove framing stays aligned.
    final decoded = <int>[];
    for (int f = 0; f < samples.length ~/ kFrameSamples; f++) {
      final frame = samples.sublist(f * kFrameSamples, (f + 1) * kFrameSamples);
      final wire = packAudio(encoder.encode(frame));
      if (f == 2) assembler.add(packChainInfo(['A', 'B']));
      final chunked = <int>[];
      for (int i = 0; i < wire.length; i += 7) {
        chunked.addAll(wire.sublist(i, min(i + 7, wire.length)));
      }
      assembler.add(chunked);
    }

    while (true) {
      final frame = assembler.next();
      if (frame == null) break;
      if (frameType(frame) == FrameType.audio) {
        final payload = framePayload(frame);
        if (payload.length == kFrameBytes) {
          decoded.addAll(decoder.decode(payload));
        }
      }
    }

    final skip = 4 * kFrameSamples;
    var maxError = 0;
    for (int i = skip; i < decoded.length; i++) {
      final err = (decoded[i] - samples[i]).abs();
      if (err > maxError) maxError = err;
    }
    expect(maxError, lessThan(150));
  });

  test('pcmToSamples yields signed values (regression: unsigned = noise)', () {
    final pcm = Uint8List(4);
    pcm[0] = 0xfe; // -2 as little-endian int16
    pcm[1] = 0xff;
    pcm[2] = 0x02; // 2
    pcm[3] = 0x00;
    final s = pcmToSamples(pcm);
    expect(s, [-2, 2]);

    // Quiet signed audio (-2) must NOT encode as a full-scale sample.
    final enc = AdpcmEncoder();
    final dec = AdpcmDecoder();
    final quiet = List.filled(kFrameSamples, -2);
    final round = dec.decode(enc.encode(quiet));
    for (final v in round) {
      expect((v - (-2)).abs(), lessThan(150));
    }
  });
}