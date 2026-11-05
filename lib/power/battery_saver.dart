// Vois offline peer-to-peer radio communication module
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../radio_server.dart';

/// Adaptive duty-cycling: when the battery drops below [lowThreshold],
/// peer discovery slows down to cut idle CPU and radio-listening cost.
/// This is a process-wide flag rather than a per-session setting because it
/// reflects a device-level constraint, not a per-call choice.
class BatterySaver {
  static final BatterySaver instance = BatterySaver._();
  BatterySaver._();

  static const int lowThreshold = 20;

  /// Listen to this to reactively update UI (e.g. the "Battery saver" chip)
  /// the moment the threshold is crossed, instead of only on next rebuild.
  final ValueNotifier<bool> lowPowerNotifier = ValueNotifier(false);

  bool get lowPower => lowPowerNotifier.value;
  int? lastLevel;
  Timer? _timer;

  /// How often the UI/discovery layer should re-scan for peers; widened
  /// under low power to cut idle-listening CPU/radio usage.
  Duration get discoveryInterval => lowPower ? const Duration(seconds: 45) : const Duration(seconds: 15);

  Future<void> refresh(RadioServer server) async {
    final level = await server.getBatteryLevel();
    lastLevel = level;
    lowPowerNotifier.value = level != null && level <= lowThreshold;
  }

  void startMonitoring(RadioServer server, {Duration interval = const Duration(minutes: 2)}) {
    _timer?.cancel();
    refresh(server);
    _timer = Timer.periodic(interval, (_) => refresh(server));
  }

  void stopMonitoring() {
    _timer?.cancel();
    _timer = null;
  }
}
