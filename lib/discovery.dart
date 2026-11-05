// Vois offline peer-to-peer radio communication module
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'audio.dart';
import 'call_page.dart';
import 'radio_server.dart';
import 'session.dart';
import 'power/battery_saver.dart';
import 'wifi_direct_page.dart';

class DiscoveryPage extends StatefulWidget {
  final AudioEngine audio;
  final RadioServer server;
  const DiscoveryPage({super.key, required this.audio, required this.server});

  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage> {
  final List<NativeDevice> _devices = [];
  StreamSubscription<NativeDevice>? _scanSub;
  StreamSubscription? _incomingSub;
  bool _scanning = false;
  bool _connecting = false;
  String _version = '';

  /// One call at a time — an incoming RFCOMM pairing while a call is up would
  /// otherwise stack a second CallPage on the same microphone.
  bool _callOpen = false;

  /// Kept so a dropped call has a one-tap way back to the same peer instead of
  /// forcing a fresh scan.
  NativeDevice? _lastDevice;

  // Buffers the first incoming connection while waiting for the 2nd (dual tunnel).
  // Keyed by remote address to handle multiple simultaneous callers.
  final Map<String, int> _pendingIncomingRx = {};

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _version = 'v${p.version}');
    });
    _scanSub = widget.server.scanResults.listen((d) {
      if (!mounted) return;
      setState(() {
        if (!_devices.any((e) => e.address == d.address)) {
          _devices.add(d);
        }
      });
    });
    _incomingSub = widget.server.events.listen((e) {
      final event = e['event'] as String;
      if (event == 'closed') {
        final id = e['id'] as int;
        _pendingIncomingRx.removeWhere((_, v) => v == id);
        return;
      }
      if (event != 'accepted') return;
      final id = e['id'] as int;
      final addr = e['address'] as String;
      final role = e['role'] as String;
      if (role == 'rx') {
        _pendingIncomingRx[addr] = id;
      } else if (role == 'tx' && _pendingIncomingRx.containsKey(addr)) {
        final rxId = _pendingIncomingRx.remove(addr)!;
        _openCallDual(rxId, id, 'Incoming call', isInitiator: false);
      }
    });
    _loadBonded();
    BatterySaver.instance.lowPowerNotifier.addListener(_onBatteryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _makeDiscoverable());
  }

  void _onBatteryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _incomingSub?.cancel();
    BatterySaver.instance.lowPowerNotifier.removeListener(_onBatteryChanged);
    widget.server.dispose();
    super.dispose();
  }

  /// Android only shows a phone to scans while it is in discoverable mode.
  Future<void> _makeDiscoverable() async {
    try {
      await widget.server.requestDiscoverable(300);
    } catch (e) {
      debugPrint('Make discoverable failed: $e');
    }
  }

  Future<void> _loadBonded() async {
    final bonded = await widget.server.getBondedDevices();
    if (!mounted) return;
    setState(() {
      for (final d in bonded) {
        if (!_devices.any((e) => e.address == d.address)) {
          _devices.add(d);
        }
      }
    });
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _devices.clear();
    });
    await widget.server.startDiscovery();
    // The battery policy owns the window: a phone under 20% spends far less
    // time with the radio scanning, which is the drain this app is most
    // exposed to.
    final window = BatterySaver.instance.discoveryInterval;
    await Future.delayed(window);
    await widget.server.cancelDiscovery();
    await _loadBonded();
    if (!mounted) return;
    setState(() {
      _scanning = false;
    });
  }

  Future<void> _connect(NativeDevice device) async {
    if (_connecting) return;
    setState(() => _connecting = true);
    try {
      final bonded = await widget.server.isBonded(device.address);
      if (!bonded) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Pairing with the other phone...'),
            ),
          );
        }
        await widget.server.bond(device.address);
        await Future.delayed(const Duration(seconds: 3));
      }
      final dual = await widget.server.connectDual(device.address);
      if (!mounted) return;
      final targets = _devices
          .where((d) => d.address != device.address)
          .toList();
      _lastDevice = device;
      await _openCallDual(
        dual.rxId,
        dual.txId,
        device.name.isEmpty ? device.address : device.name,
        relayTargets: targets,
        isInitiator: true,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connect failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _connecting = false);
      }
    }
  }

  Future<void> _openCallDual(
    int rxId,
    int txId,
    String name, {
    List<NativeDevice> relayTargets = const [],
    required bool isInitiator,
  }) async {
    if (_callOpen) {
      await widget.server.close(rxId);
      await widget.server.close(txId);
      return;
    }
    _callOpen = true;
    final txCh = RadioChannel(widget.server, txId);
    final rxCh = RadioChannel(widget.server, rxId);
    final session = RadioSession(widget.audio, widget.server);
    await session.start(txCh, rxCh, isInitiator: isInitiator);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallPage(
          deviceName: name,
          session: session,
          relayTargets: relayTargets,
        ),
      ),
    );
    _callOpen = false;
    await widget.server.startListening();
  }

  @override
  Widget build(BuildContext context) {
    final paired = _devices.where((d) => d.bonded).toList();
    final found = _devices.where((d) => !d.bonded).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Phones'),
        actions: [
          if (BatterySaver.instance.lowPower)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Chip(
                avatar: Icon(Icons.battery_alert, size: 16, color: Colors.orange),
                label: Text('Battery saver', style: TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.wifi_tethering),
            tooltip: 'WiFi Direct (primary transport)',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => WifiDirectPage(audio: widget.audio, btServer: widget.server),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(_version,
                  style: const TextStyle(fontSize: 13, color: Colors.grey)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _connecting ? null : _scan,
                icon: _scanning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.radar),
                label: Text(_scanning ? 'Scanning...' : 'Scan for phones'),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _makeDiscoverable,
            icon: const Icon(Icons.visibility, size: 18),
            label: const Text('Make me visible to nearby phones'),
          ),
          if (_lastDevice != null && !_scanning)
            TextButton.icon(
              onPressed: _connecting ? null : () => _connect(_lastDevice!),
              icon: const Icon(Icons.history, size: 18),
              label: Text('Reconnect to ${switch (_lastDevice!.name) {
                '' => _lastDevice!.address,
                final n => n,
              }}'),
            ),
          const Text('Tap a phone to connect (both must have this app)'),
          const SizedBox(height: 4),
          Expanded(
            child: _devices.isEmpty
                ? const Center(child: Text('No phones found'))
                : ListView(
                    children: [
                      if (paired.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text('PAIRED (connect instantly)',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.grey)),
                        ),
                        ...paired.map((d) => _deviceTile(d, instant: true)),
                      ],
                      if (found.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text('NEARBY',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.grey)),
                        ),
                        ...found.map((d) => _deviceTile(d)),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _deviceTile(NativeDevice d, {bool instant = false}) {
    return ListTile(
      leading: Icon(instant ? Icons.link : Icons.phone_android),
      title: Text(d.name.isEmpty ? 'Unknown' : d.name),
      subtitle: Text(d.address),
      onTap: () => _connect(d),
    );
  }
}
