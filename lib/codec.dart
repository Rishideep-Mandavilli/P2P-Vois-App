// Vois offline peer-to-peer radio communication module
import 'dart:typed_data';

const _stepTable = [
  7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41,
  45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190,
  209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724,
  796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2273,
  2500, 2750, 3025, 3328, 3661, 4027, 4430, 4873, 5361, 5896, 6486, 7134,
  7847, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500,
  20350, 22385, 24623, 27086, 29794, 32767,
];

const _indexTable = [-1, -1, -1, -1, 2, 4, 6, 8];

// 16kHz (proven working on the test devices), 8 bits/sample = 128kbps.
const int kSampleRate = 16000;
const int kFrameSamples = 320;
const int kPayloadBytes = kFrameSamples;
const int kFrameBytes = kPayloadBytes + 3;

/// Little-endian PCM16 bytes -> signed samples. Uint16List.view alone is
/// UNSIGNED and would make quiet audio look like full-scale positive
/// samples, which saturates the ADPCM predictor into noise.
List<int> pcmToSamples(Uint8List pcm) =>
    Uint16List.view(pcm.buffer).map((e) => e.toSigned(16)).toList();

/// 8-bit ADPCM: sign(1) + magnitude(7) quantized against a step that
/// adapts like IMA ADPCM. Half the quantization error of the old 4-bit
/// version, same frame layout.
class AdpcmEncoder {
  int _predictor = 0;
  int _stepIndex = 0;

  void reset() {
    _predictor = 0;
    _stepIndex = 0;
  }

  Uint8List encode(List<int> samples) {
    final out = Uint8List(kFrameBytes);
    out[0] = _predictor & 0xff;
    out[1] = (_predictor >> 8) & 0xff;
    out[2] = _stepIndex;
    for (int i = 0; i < kFrameSamples; i++) {
      out[3 + i] = _encodeSample(samples[i]);
    }
    return out;
  }

  int _encodeSample(int sample) {
    var delta = sample - _predictor;
    final neg = delta < 0;
    if (neg) delta = -delta;
    final step = _stepTable[_stepIndex];
    var mag = (delta * 64 + (step >> 1)) ~/ step;
    if (mag > 127) mag = 127;
    final q = neg ? -((mag * step + 32) >> 6) : ((mag * step + 32) >> 6);
    _predictor += q;
    if (_predictor < -32768) {
      _predictor = -32768;
    } else if (_predictor > 32767) {
      _predictor = 32767;
    }
    _stepIndex += _indexTable[mag >> 4];
    if (_stepIndex < 0) {
      _stepIndex = 0;
    } else if (_stepIndex > 88) {
      _stepIndex = 88;
    }
    return (neg ? 0x80 : 0) | mag;
  }
}

class AdpcmDecoder {
  int _predictor = 0;
  int _stepIndex = 0;

  Int16List decode(Uint8List frame) {
    _predictor = frame[0] | (frame[1] << 8);
    if (_predictor > 32767) {
      _predictor -= 65536;
    }
    _stepIndex = frame[2].clamp(0, 88);
    final out = Int16List(kFrameSamples);
    for (int i = 0; i < kFrameSamples; i++) {
      out[i] = _decodeSample(frame[3 + i]);
    }
    return out;
  }

  int _decodeSample(int byte) {
    final neg = (byte & 0x80) != 0;
    final mag = byte & 0x7f;
    final step = _stepTable[_stepIndex];
    final q = neg ? -((mag * step + 32) >> 6) : ((mag * step + 32) >> 6);
    _predictor += q;
    if (_predictor < -32768) {
      _predictor = -32768;
    } else if (_predictor > 32767) {
      _predictor = 32767;
    }
    _stepIndex += _indexTable[mag >> 4];
    if (_stepIndex < 0) {
      _stepIndex = 0;
    } else if (_stepIndex > 88) {
      _stepIndex = 88;
    }
    return _predictor;
  }
}