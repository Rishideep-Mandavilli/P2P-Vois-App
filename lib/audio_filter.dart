// Vois offline peer-to-peer radio communication module
import 'dart:math';

/// Audio preprocessing filter for raw PCM16 samples:
/// 1. High-Pass Filter (~180 Hz cutoff) to eliminate DC offset, wind pop,
///    and device handling rumble.
/// 2. Adaptive Noise Gate with hangover smoothing to suppress background
///    ambient hiss and microphone floor noise during speech pauses.
class AudioFilter {
  final HighPassFilter _highPass;
  final NoiseGate _noiseGate;

  AudioFilter({
    double sampleRate = 16000,
    double cutoffFreq = 180,
    int thresholdRms = 80,
    int hangoverFrames = 15,
  })  : _highPass = HighPassFilter(sampleRate: sampleRate, cutoffFreq: cutoffFreq),
        _noiseGate = NoiseGate(thresholdRms: thresholdRms, hangoverFrames: hangoverFrames);

  /// Filters samples in-place. Returns true if speech was detected.
  bool process(List<int> samples) {
    _highPass.process(samples);
    return _noiseGate.process(samples);
  }

  void reset() {
    _highPass.reset();
    _noiseGate.reset();
  }
}

/// 1st-order IIR High-Pass Filter:
/// y[n] = alpha * (y[n-1] + x[n] - x[n-1])
class HighPassFilter {
  final double alpha;
  double _prevInput = 0;
  double _prevOutput = 0;

  HighPassFilter({double sampleRate = 16000, double cutoffFreq = 180})
      : alpha = (1 / (2 * pi * cutoffFreq)) /
            ((1 / (2 * pi * cutoffFreq)) + (1 / sampleRate));

  void process(List<int> samples) {
    for (int i = 0; i < samples.length; i++) {
      final input = samples[i].toDouble();
      final output = alpha * (_prevOutput + input - _prevInput);
      _prevInput = input;
      _prevOutput = output;
      samples[i] = output.round().clamp(-32768, 32767);
    }
  }

  void reset() {
    _prevInput = 0;
    _prevOutput = 0;
  }
}

/// Noise Gate with RMS calculation and hangover frames to avoid clipping
/// word ends.
class NoiseGate {
  final int thresholdRms;
  final int hangoverFrames;
  int _hangoverCount = 0;

  NoiseGate({this.thresholdRms = 80, this.hangoverFrames = 15});

  /// Calculates RMS energy. If below threshold and hangover expired, silences frame.
  /// Returns true if frame contains active speech.
  bool process(List<int> samples) {
    if (samples.isEmpty) return false;

    int sumSq = 0;
    for (int i = 0; i < samples.length; i++) {
      final s = samples[i];
      sumSq += s * s;
    }
    final rms = sqrt(sumSq / samples.length);

    if (rms >= thresholdRms) {
      _hangoverCount = hangoverFrames;
      return true;
    }

    if (_hangoverCount > 0) {
      _hangoverCount--;
      // Smoothly scale down during hangover using half-cosine window to eliminate pops
      final progress = (_hangoverCount + 1) / (hangoverFrames + 1);
      final gain = 0.5 * (1.0 - cos(pi * progress));
      for (int i = 0; i < samples.length; i++) {
        samples[i] = (samples[i] * gain).round();
      }
      return true;
    }

    // Silence below noise threshold: zeros eliminate ADPCM idle quantization hiss
    for (int i = 0; i < samples.length; i++) {
      samples[i] = 0;
    }
    return false;
  }

  void reset() {
    _hangoverCount = 0;
  }
}
