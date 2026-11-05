// Vois offline peer-to-peer radio communication module
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p_vois/audio_filter.dart';
import 'package:p2p_vois/codec.dart';

void main() {
  group('AudioFilter Tests', () {
    test('HighPassFilter eliminates DC offset', () {
      final hpf = HighPassFilter();
      // Constant DC offset of 2000
      final dcSamples = List.filled(320, 2000);
      hpf.process(dcSamples);
      // After processing, DC offset should decay towards 0
      expect(dcSamples.last.abs(), lessThan(100));
    });

    test('NoiseGate suppresses low-amplitude background noise', () {
      final gate = NoiseGate(thresholdRms: 220, hangoverFrames: 2);
      // Low amplitude noise (RMS ~ 40)
      final noiseSamples = List.generate(320, (i) => (i % 2 == 0 ? 40 : -40));
      
      final speechDetected = gate.process(noiseSamples);
      expect(speechDetected, isFalse);
      // Frame should be gated to zero
      expect(noiseSamples.every((s) => s == 0), isTrue);
    });

    test('NoiseGate preserves speech and applies hangover', () {
      final gate = NoiseGate(thresholdRms: 220, hangoverFrames: 2);
      // Strong speech signal (sine wave ~4000 amplitude, RMS ~ 2828)
      final speechSamples = List.generate(
        320,
        (i) => (sin(i * 2 * pi * 440 / 16000) * 4000).round(),
      );

      final speechDetected = gate.process(speechSamples);
      expect(speechDetected, isTrue);
      expect(speechSamples.any((s) => s != 0), isTrue);

      // Now send 1 quiet frame: hangover should keep it partially audible
      final quiet1 = List.filled(320, 30);
      final hang1 = gate.process(quiet1);
      expect(hang1, isTrue); // In hangover

      // Send another quiet frame: hangover countdown
      final quiet2 = List.filled(320, 30);
      final hang2 = gate.process(quiet2);
      expect(hang2, isTrue);

      // Third quiet frame: hangover expired, should gate to zero
      final quiet3 = List.filled(320, 30);
      final hang3 = gate.process(quiet3);
      expect(hang3, isFalse);
      expect(quiet3.every((s) => s == 0), isTrue);
    });

    test('AudioFilter integration with ADPCM preserves intelligible speech', () {
      final filter = AudioFilter();
      final encoder = AdpcmEncoder();
      final decoder = AdpcmDecoder();

      // 440 Hz tone at 5000 amplitude
      final samples = List.generate(
        kFrameSamples,
        (i) => (sin(i * 2 * pi * 440 / kSampleRate) * 5000).round(),
      );

      final original = List<int>.from(samples);
      filter.process(samples);

      final encoded = encoder.encode(samples);
      expect(encoded.length, kFrameBytes);

      final decoded = decoder.decode(encoded);
      expect(decoded.length, kFrameSamples);

      // Output should correlate with input sine wave
      var dotProduct = 0;
      for (int i = 0; i < kFrameSamples; i++) {
        dotProduct += original[i] * decoded[i];
      }
      expect(dotProduct, greaterThan(0));
    });
  });
}
