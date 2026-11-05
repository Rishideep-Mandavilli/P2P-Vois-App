// Vois offline peer-to-peer radio communication module
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
    await _player?.startPlayerFromStream(
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: kSampleRate,
      bufferSize: 2048,
      interleaved: true,
    );
  }

  /// Stop playback immediately and flush any queued audio in the hardware buffer.
  Future<void> stopPlayback() async {
    _playing = false;
    _jitter.clear();
    try {
      await _player?.stopPlayer();
    } catch (_) {}
  }

  /// Feed a decoded PCM frame into the playback stream.
  /// Strictly drops older frames if the hardware queue has not consumed them yet,
  /// preventing latency backlog buildup.
  void play(Uint8List pcmBytes) {
    if (!_playing || _player == null) return;
    _jitter.add(pcmBytes);
    while (_jitter.length > 1) {
      _jitter.removeAt(0);
    }
    try {
      _player?.uint8ListSink?.add(_jitter.removeAt(0));
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stopPlayback();
    await stopListening();
    await _recorder?.closeRecorder();
    await _player?.closePlayer();
  }
}
