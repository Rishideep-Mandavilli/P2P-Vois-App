// Vois offline peer-to-peer radio communication module
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'alerts/sos.dart';
import 'alerts/sos_relay.dart';
import 'audio.dart';
import 'call_page.dart';
import 'crypto/payload_cipher.dart';
import 'protocol.dart';
import 'power/battery_saver.dart';
import 'radio_server.dart';
import 'session.dart';
import 'tcp_channel.dart';
import 'wifi_direct_server.dart';

/// WiFi Direct (primary transport, Section 5) discovery + connect screen —
/// a separate entry point from the Bluetooth discovery flow rather than a
/// merged single device list, since WiFi P2P peers and Bluetooth devices
/// are discovered through entirely different OS mechanisms/identities with
/// no shared "same phone" signal to unify them automatically. Bluetooth
/// (DiscoveryPage) remains the fallback path when WiFi Direct isn't
/// available or the peer isn't reachable that way.
class WifiDirectPage extends StatefulWidget {
  final AudioEngine audio;
  final RadioServer btServer;
  const WifiDirectPage({super.key, required this.audio, required this.btServer});

  @override
  State<WifiDirectPage> createState() => _WifiDirectPageState();
}

class _WifiDirectPageState extends State<WifiDirectPage> {
  final WifiDirectServer _wifi = WifiDirectServer();
  final List<WifiPeer> _peers = [];
  StreamSubscription? _peersSub;
  StreamSubscription? _groupSub;
  StreamSubscription? _acceptedSub;
  bool _scanning = false;
  bool _connecting = false;

  /// One call at a time: the group owner's TCP server keeps accepting after a
  /// connection closes, so without this a second peer stacking in would open a
  /// second CallPage over the same microphone.
  bool _callOpen = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _wifi.init();
    final granted = await _wifi.requestPermissions();
    if (!granted) {
      setState(() => _status = 'WiFi Direct permission denied');
      return;
    }
    _peersSub = _wifi.peers.listen((list) {
      if (mounted) setState(() => _peers.replaceRange(0, _peers.length, list));
    });
    _groupSub = _wifi.groupFormed.listen((g) {
      if (!mounted) return;
      setState(() => _status = g.isGroupOwner ? 'Group owner (broadcast mode)' : 'Connected as client');
    });
    _acceptedSub = _wifi.accepted.listen((id) {
      _flushSosQueueTo(id);
      _openCall(WifiChannel(_wifi, id), 'Incoming (WiFi Direct)', isInitiator: false);
    });
    await _scan();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    await _wifi.discoverPeers();
    // Cadence comes from the battery policy so a phone at 15% stops
    // hammering the radio on every re-scan.
    final window = BatterySaver.instance.discoveryInterval;
    Future.delayed(window, () {
      if (mounted) setState(() => _scanning = false);
    });
  }

  Future<void> _connect(WifiPeer peer) async {
    if (_connecting) return;
    setState(() => _connecting = true);
    try {
      await _wifi.connect(peer.address);
      // The actual TCP connection id arrives via clientConnected once
      // WifiP2pManager finishes negotiating the link (see WifiDirectPlugin
      // .onGroupFormed -> connectToHost).
      final id = await _wifi.clientConnected.first.timeout(const Duration(seconds: 20));
      if (!mounted) return;
      await _openCall(
        WifiChannel(_wifi, id),
        peer.name.isEmpty ? peer.address : peer.name,
        isInitiator: true,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('WiFi Direct connect failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _openCall(
    ByteChannel channel,
    String name, {
    required bool isInitiator,
  }) async {
    if (_callOpen) {
      await channel.close();
      return;
    }
    _callOpen = true;
    final session = RadioSession(widget.audio, widget.btServer,
        transport: 'Pi Wi-Fi Relay');
    await session.start(channel, channel, isInitiator: isInitiator);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallPage(deviceName: name, session: session),
      ),
    );
    await session.dispose();
    _callOpen = false;
  }

  Future<void> _connectToPiRelay([String? explicitHost, int port = 8988]) async {
    if (_connecting) return;
    setState(() {
      _connecting = true;
      _status = 'Connecting to Pi Relay...';
    });

    final candidates = explicitHost != null
        ? [explicitHost]
        : ['10.42.0.1', '10.155.221.42', '192.168.4.1'];

    TcpByteChannel? channel;
    String connectedHost = '';
    Object? lastError;

    for (final host in candidates) {
      try {
        channel = await TcpByteChannel.connect(
          host,
          port,
          timeout: const Duration(milliseconds: 1200),
        );
        connectedHost = host;
        break;
      } catch (e) {
        lastError = e;
      }
    }

    if (channel == null) {
      if (mounted) {
        setState(() => _connecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pi Relay connect failed: $lastError. Connect to Vois-Relay Wi-Fi or check IP!'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    try {
      if (!mounted) {
        await channel.close();
        return;
      }
      await _openCall(channel, 'Pi 400 Relay ($connectedHost)', isInitiator: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pi Call error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _showCustomIpDialog() async {
    final controller = TextEditingController(text: '10.42.0.1');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter Relay IP Address'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Relay IP',
            hintText: '10.42.0.1 or 10.155.221.42',
          ),
          keyboardType: TextInputType.datetime,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await _connectToPiRelay(result);
    }
  }

  Future<void> _broadcastMode() async {
    setState(() => _status = 'Starting group (broadcast mode)…');
    await _wifi.createGroup();
  }

  /// Broadcasts an SOS to every device currently connected in the group
  /// — no per-peer key exchange needed since
  /// this uses the well-known SOS broadcast key (see PayloadCipher
  /// .broadcast), by design: anyone running Vois nearby should be able
  /// to understand a public distress beacon.
  Future<void> _broadcastSos(SosCode code) async {
    final loc = await widget.btServer.getLastKnownLocation();
    final payload = jsonEncode({
      'code': code.code,
      'lat': loc?.lat,
      'lng': loc?.lng,
      'sentAt': DateTime.now().millisecondsSinceEpoch,
    });
    final frame = packSos(PayloadCipher.broadcast.encrypt(payload));
    if (_wifi.openConnections.isEmpty) {
      // Store-and-forward, scoped to single-hop — see
      // SosRelayQueue): no one's in range right now, so queue it and hand
      // it off the moment a peer connects instead of dropping it.
      SosRelayQueue.instance.enqueue(frame);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No peers in range — SOS queued, will send when one connects')),
        );
      }
      return;
    }
    await _wifi.writeToAll(frame);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('SOS broadcast sent to ${_wifi.openConnections.length} peer(s): ${code.label}')),
      );
    }
  }

  Future<void> _flushSosQueueTo(int connectionId) async {
    for (final frame in SosRelayQueue.instance.pending()) {
      await _wifi.write(connectionId, frame);
    }
    SosRelayQueue.instance.clear();
  }

  Future<void> _openBroadcastSosSheet() async {
    final code = await showModalBottomSheet<SosCode>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: SosCode.values
              .map((c) => ListTile(
                    leading: const Icon(Icons.warning_amber, color: Colors.redAccent),
                    title: Text(c.label),
                    onTap: () => Navigator.pop(context, c),
                  ))
              .toList(),
        ),
      ),
    );
    if (code != null) await _broadcastSos(code);
  }

  @override
  void dispose() {
    _peersSub?.cancel();
    _groupSub?.cancel();
    _acceptedSub?.cancel();
    _wifi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi Direct'),
        actions: [
          IconButton(
            icon: const Icon(Icons.campaign),
            tooltip: 'Become broadcast group owner',
            onPressed: _broadcastMode,
          ),
          IconButton(
            icon: const Icon(Icons.warning_amber, color: Colors.redAccent),
            tooltip: 'Broadcast SOS to group',
            onPressed: _wifi.openConnections.isEmpty ? null : _openBroadcastSosSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_status != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_status!, style: const TextStyle(color: Colors.grey)),
            ),
          Card(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.router, color: Colors.green),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Pi 400 Relay Station',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          '16kHz HD',
                          style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Direct Wi-Fi Call via Raspberry Pi 400 (TCP 8988)',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _connecting ? null : () => _connectToPiRelay(),
                          icon: const Icon(Icons.call, size: 18),
                          label: const Text('Join Pi Relay (10.42.0.1)'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.settings_ethernet, size: 18),
                        tooltip: 'Custom Relay IP',
                        onPressed: _showCustomIpDialog,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _scanning ? null : _scan,
                icon: _scanning
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_find),
                label: Text(_scanning ? 'Scanning…' : 'Scan for peers'),
              ),
            ),
          ),
          Expanded(
            child: _peers.isEmpty
                ? const Center(child: Text('No WiFi Direct peers found yet.'))
                : ListView.builder(
                    itemCount: _peers.length,
                    itemBuilder: (context, i) {
                      final peer = _peers[i];
                      return ListTile(
                        leading: const Icon(Icons.wifi_tethering),
                        title: Text(peer.name.isEmpty ? peer.address : peer.name),
                        subtitle: Text(peer.address),
                        trailing: _connecting
                            ? const SizedBox(
                                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.chevron_right),
                        onTap: () => _connect(peer),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
