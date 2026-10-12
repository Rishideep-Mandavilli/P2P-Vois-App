import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

import 'codec.dart';

/// Captures 8kHz PCM16 from the microphone in 20ms blocks and plays
/// PCM16 blocks to the speaker. Compression (ADPCM) lives in [codec.dart];
/// this class only deals with raw PCM.
class AudioEngine {
  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;
  StreamSubscription<Uint8List>? _micSub;
  final List<int> _pending = [];
  final List<Uint8List> _jitter = [];
  bool _playing = false;

  Future<void> requestPermissions() async {
    final results = await [
      Permission.microphone,
      Permission.notification,
      if (defaultTargetPlatform == TargetPlatform.android) ...[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.location,
      ],
    ].request();
    final denied = results.values
        .where((s) => s.isDenied || s.isPermanentlyDenied)
        .isNotEmpty;
    if (denied) {
      throw StateError('Permissions not granted');
    }
  }

  Future<void> init() async {
    _player = FlutterSoundPlayer();
    _recorder = FlutterSoundRecorder();
    await _player!.openPlayer();
    await _recorder!.openRecorder();
    await _recorder!.setSubscriptionDuration(
      const Duration(milliseconds: 20),
    );
  }

  /// Start capturing; [onPcm] receives exactly 160 int16 samples
  /// (20ms at 8kHz) as a byte list (320 bytes, little-endian).
  Future<void> startListening(void Function(Uint8List) onPcm) async {
    final sink = StreamController<Uint8List>();
    _micSub = sink.stream.listen((chunk) {
      _pending.addAll(chunk);
      while (_pending.length >= kFrameSamples * 2) {
        final frame = Uint8List.fromList(
          _pending.sublist(0, kFrameSamples * 2),
        );
        _pending.removeRange(0, kFrameSamples * 2);
        onPcm(frame);
      }
    });
    await _recorder!.startRecorder(
      codec: Codec.pcm16,
      toStream: sink,
      sampleRate: kSampleRate,
      numChannels: 1,
      audioSource: AudioSource.voice_communication,
      enableNoiseSuppression: true,
      enableEchoCancellation: true,
    );
  }

  Future<void> stopListening() async {
    await _recorder?.stopRecorder();
    await _micSub?.cancel();
    _micSub = null;
    _pending.clear();
  }

  Future<void> startPlayback() async {
    if (_playing) return;
    _playing = true;
    _jitter.clear();
    await _player!.startPlayerFromStream(
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: kSampleRate,
      bufferSize: kFrameSamples * 4,
      interleaved: true,
    );
  }

  /// Feed a decoded PCM frame. Holds 2 frames (40ms) before playback to
  /// smooth RFCOMM arrival jitter, then plays one frame per arrival.
  void play(Uint8List pcmBytes) {
    _jitter.add(pcmBytes);
    if (_jitter.length >= 2) {
      _player?.uint8ListSink?.add(_jitter.removeAt(0));
    }
  }

  Future<void> dispose() async {
    await _recorder?.stopRecorder();
    await _player?.stopPlayer();
    await _recorder?.closeRecorder();
    await _player?.closePlayer();
  }
}
