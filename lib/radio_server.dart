// Vois offline peer-to-peer radio communication module
import 'dart:async';

import 'package:flutter/services.dart';

class NativeDevice {
  final String name;
  final String address;
  final bool bonded;
  NativeDevice({
    required this.name,
    required this.address,
    required this.bonded,
  });
}

/// Native facade over the RFCOMM plugin (P2pServerPlugin.kt): server accept,
/// client connect, discovery, bonding, discoverable mode, and the foreground
/// service keep-alive. All socket I/O happens on native background threads;
/// events arrive on this broadcast stream.
class RadioServer {
  static const _method = MethodChannel('p2p_server/methods');
  static const _events = EventChannel('p2p_server/events');

  final StreamController<Map> _raw = StreamController.broadcast();
  StreamSubscription? _sub;

  /// All native events.
  Stream<Map> get events => _raw.stream;

  /// Connections that appeared on our server (incoming calls).
  Stream<int> get accepted => _raw.stream
      .where((e) => e['event'] == 'accepted')
      .map((e) => e['id'] as int);

  /// Same as [accepted], but also carries the remote device's address, so
  /// callers can derive a per-pair encryption key (see PayloadCipher).
  Stream<({int id, String? address})> get acceptedWithAddress => _raw.stream
      .where((e) => e['event'] == 'accepted')
      .map((e) => (id: e['id'] as int, address: e['address'] as String?));

  /// Carries connection id, address, and role ("tx"/"rx") for parallel tunneling.
  Stream<({int id, String address, String role})> get acceptedWithRole => _raw.stream
      .where((e) => e['event'] == 'accepted')
      .map((e) => (id: e['id'] as int, address: e['address'] as String, role: e['role'] as String));

  Stream<NativeDevice> get scanResults => _raw.stream
      .where((e) => e['event'] == 'scan_found')
      .map((e) => NativeDevice(
            name: (e['name'] as String? ?? ''),
            address: e['address'] as String,
            bonded: e['bondState'] == 12, // BluetoothDevice.BOND_BONDED
          ));

  Stream<Map> get bondChanges => _raw.stream
      .where((e) => e['event'] == 'bond_state')
      .map((e) => e);

  /// Raw data bytes for a specific connection id.
  Stream<Uint8List> dataOf(int id) => _raw.stream
      .where((e) => e['event'] == 'data' && e['id'] == id)
      .map((e) => Uint8List.fromList((e['bytes'] as List).cast<int>()));

  /// Connection closed for a specific id.
  Stream<int> closedOf(int id) => _raw.stream
      .where((e) => e['event'] == 'closed' && e['id'] == id)
      .map((e) => e['id'] as int);

  Future<void> init() async {
    if (_sub != null) return;
    _sub = _events.receiveBroadcastStream().listen((e) {
      _raw.add(Map<String, dynamic>.from(e as Map));
    });
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await _method.invokeMethod('stop');
  }

  Future<void> ensureRadioService() async {
    await _method.invokeMethod('ensureRadioService');
  }

  Future<void> requestEnable() async {
    await _method.invokeMethod('requestEnable');
  }

  Future<void> requestDiscoverable(int seconds) async {
    await _method.invokeMethod('requestDiscoverable', {'seconds': seconds});
  }

  Future<String> getName() async {
    return (await _method.invokeMethod('getName')) as String? ?? '';
  }

  Future<List<NativeDevice>> getBondedDevices() async {
    final list = (await _method.invokeMethod('getBondedDevices')) as List;
    return list
        .map((m) {
          final map = Map<String, dynamic>.from(m as Map);
          return NativeDevice(
            name: map['name'] as String? ?? '',
            address: map['address'] as String,
            bonded: map['bondState'] == 12,
          );
        })
        .toList();
  }

  Future<bool> isBonded(String address) async {
    return (await _method.invokeMethod('isBonded', {'address': address}))
        as bool? ??
        false;
  }

  Future<void> startDiscovery() async {
    await _method.invokeMethod('startDiscovery');
  }

  Future<void> cancelDiscovery() async {
    await _method.invokeMethod('cancelDiscovery');
  }

  Future<void> bond(String address) async {
    await _method.invokeMethod('bond', {'address': address});
  }

  Future<int> connect(String address) async {
    return (await _method.invokeMethod('connect', {'address': address})) as int;
  }

  /// Opens two RFCOMM connections (TX + RX) to [address].
  /// Returns (txId, rxId) — caller writes to txId, reads from rxId.
  Future<({int txId, int rxId})> connectDual(String address) async {
    final map = await _method.invokeMethod('connectDual', {'address': address});
    final m = Map<String, dynamic>.from(map as Map);
    return (txId: m['txId'] as int, rxId: m['rxId'] as int);
  }

  Future<void> write(int id, Uint8List bytes) async {
    await _method.invokeMethod('write', {'id': id, 'bytes': bytes});
  }

  Future<void> close(int id) async {
    await _method.invokeMethod('close', {'id': id});
  }

  Future<void> startListening() async {
    await _method.invokeMethod('startListening');
  }

  /// Last cached GPS/network location, or null if unavailable/denied.
  /// Uses plain LocationManager on the native side — no Play Services,
  /// no internet lookup (SOS payload GPS coordinates).
  Future<({double lat, double lng})?> getLastKnownLocation() async {
    final map = await _method.invokeMethod('getLastKnownLocation');
    if (map == null) return null;
    final m = Map<String, dynamic>.from(map as Map);
    return (lat: m['lat'] as double, lng: m['lng'] as double);
  }

  /// Pushes the media + alarm streams to max volume (alert
  /// messages play at max volume).
  Future<void> setMaxAlertVolume() async {
    await _method.invokeMethod('setMaxAlertVolume');
  }

  /// Haptic pattern for incoming alerts.
  Future<void> vibrateAlert() async {
    await _method.invokeMethod('vibrateAlert');
  }

  /// Repeating two-tone siren on the alarm stream for [ms]. An alert has to
  /// be audible, not just visible — the phone is usually in a pocket.
  Future<void> playAlertTone({int ms = 6000}) async {
    await _method.invokeMethod('playAlertTone', {'ms': ms});
  }

  Future<void> stopAlertTone() async {
    await _method.invokeMethod('stopAlertTone');
  }

  /// Battery percentage (0-100), or null if unavailable. Drives adaptive
  /// duty-cycling — see lib/power/battery_saver.dart.
  Future<int?> getBatteryLevel() async {
    return (await _method.invokeMethod('getBatteryLevel')) as int?;
  }

  Future<bool> setEarpiece() async {
    return (await _method.invokeMethod('setEarpiece')) as bool? ?? false;
  }

  Future<bool> setLoudspeaker() async {
    return (await _method.invokeMethod('setLoudspeaker')) as bool? ?? false;
  }

  Future<void> resetAudioMode() async {
    await _method.invokeMethod('resetAudioMode');
  }

  Future<bool> isEarpieceAvailable() async {
    return (await _method.invokeMethod('isEarpieceAvailable')) as bool? ?? false;
  }
}
