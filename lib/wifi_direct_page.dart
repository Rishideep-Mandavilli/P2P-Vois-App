import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'alerts/sos.dart';
import 'alerts/sos_relay.dart';
import 'audio.dart';
import 'call_page.dart';
import 'crypto/payload_cipher.dart';
import 'protocol.dart';
import 'radio_server.dart';
import 'session.dart';
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
    Future.delayed(const Duration(seconds: 12), () {
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
    final session = RadioSession(widget.audio, widget.btServer);
    await session.start(channel, channel, isInitiator: isInitiator);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallPage(deviceName: name, session: session),
      ),
    );
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
