// Vois offline peer-to-peer radio communication module
import 'dart:async';

import 'package:flutter/services.dart';

import 'session.dart';

class WifiPeer {
  final String name;
  final String address;
  WifiPeer({required this.name, required this.address});
}

/// Native facade over WifiDirectPlugin.kt: WiFi Direct (WiFi P2P) peer
/// discovery, connect, group-owner/broadcast mode, and the resulting TCP
/// data channel — the mandated *primary* transport (Section 5), with
/// Bluetooth Classic (RadioServer) as the fallback. Mirrors RadioServer's
/// shape so [WifiChannel] can implement the same [ByteChannel] interface
/// RadioSession already speaks, regardless of which transport carried it.
class WifiDirectServer {
  static const _method = MethodChannel('p2p_wifi/methods');
  static const _events = EventChannel('p2p_wifi/events');

  final StreamController<Map> _raw = StreamController.broadcast();
  StreamSubscription? _sub;

  Stream<Map> get events => _raw.stream;

  Stream<List<WifiPeer>> get peers => _raw.stream
      .where((e) => e['event'] == 'peers')
      .map((e) => (e['peers'] as List)
          .map((p) => WifiPeer(
                name: (p['name'] as String? ?? ''),
                address: p['address'] as String,
              ))
          .toList());

  /// Fires once the WiFi P2P group finishes forming, telling us whether
  /// we ended up as group owner (server role) or client.
  Stream<({bool isGroupOwner, String? groupOwnerAddress})> get groupFormed =>
      _raw.stream.where((e) => e['event'] == 'group_formed').map(
            (e) => (
              isGroupOwner: e['isGroupOwner'] as bool? ?? false,
              groupOwnerAddress: e['groupOwnerAddress'] as String?,
            ),
          );

  /// Incoming TCP connections accepted while we're the group owner — the
  /// mechanism behind one-to-many SOS broadcast: every
  /// peer that connects gets its own id here.
  Stream<int> get accepted =>
      _raw.stream.where((e) => e['event'] == 'accepted').map((e) => e['id'] as int);

  Stream<int> get clientConnected => _raw.stream
      .where((e) => e['event'] == 'client_connected')
      .map((e) => e['id'] as int);

  Stream<Uint8List> dataOf(int id) => _raw.stream
      .where((e) => e['event'] == 'data' && e['id'] == id)
      .map((e) => Uint8List.fromList((e['bytes'] as List).cast<int>()));

  Stream<int> closedOf(int id) => _raw.stream
      .where((e) => e['event'] == 'closed' && e['id'] == id)
      .map((e) => e['id'] as int);

  /// Every currently-open connection id, e.g. to broadcast a message to
  /// every peer already in the group.
  final Set<int> openConnections = {};

  Future<void> init() async {
    if (_sub != null) return;
    _sub = _events.receiveBroadcastStream().listen((e) {
      final map = Map<String, dynamic>.from(e as Map);
      final event = map['event'];
      if (event == 'accepted' || event == 'client_connected') {
        openConnections.add(map['id'] as int);
      } else if (event == 'closed') {
        openConnections.remove(map['id'] as int);
      }
      _raw.add(map);
    });
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await _method.invokeMethod('stop');
    openConnections.clear();
  }

  Future<bool> requestPermissions() async {
    return (await _method.invokeMethod('requestPermissions')) as bool? ?? false;
  }

  Future<void> discoverPeers() async {
    await _method.invokeMethod('discoverPeers');
  }

  Future<void> stopDiscovery() async {
    await _method.invokeMethod('stopDiscovery');
  }

  Future<void> connect(String address) async {
    await _method.invokeMethod('connect', {'address': address});
  }

  /// Becomes the group owner explicitly, so every future connection is a
  /// broadcast recipient — used for the SOS broadcast flow
  /// instead of connecting to one specific peer.
  Future<void> createGroup() async {
    await _method.invokeMethod('createGroup');
  }

  Future<void> removeGroup() async {
    await _method.invokeMethod('removeGroup');
  }

  Future<void> write(int id, Uint8List bytes) async {
    await _method.invokeMethod('write', {'id': id, 'bytes': bytes});
  }

  /// Writes to every currently-open connection — the actual broadcast
  /// mechanism for group-owner/SOS mode.
  Future<void> writeToAll(Uint8List bytes) async {
    for (final id in openConnections.toList()) {
      await write(id, bytes);
    }
  }

  Future<void> close(int id) async {
    await _method.invokeMethod('close', {'id': id});
  }
}

class WifiChannel implements ByteChannel {
  final WifiDirectServer server;
  final int id;
  bool _closed = false;
  late final StreamController<Uint8List> _controller;
  StreamSubscription? _dataSub;
  StreamSubscription? _closeSub;

  WifiChannel(this.server, this.id) {
    _controller = StreamController<Uint8List>(onCancel: () => close());
    _dataSub = server.dataOf(id).listen((data) {
      if (!_closed && !_controller.isClosed) {
        _controller.add(data);
      }
    });
    _closeSub = server.closedOf(id).listen((closedId) {
      if (closedId == id) {
        close();
      }
    });
  }

  @override
  Stream<Uint8List> get input => _controller.stream;

  @override
  void add(Uint8List bytes) {
    if (_closed) return;
    server.write(id, bytes).catchError((_) {
      close();
    });
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _dataSub?.cancel();
    _closeSub?.cancel();
    if (!_controller.isClosed) {
      await _controller.close();
    }
    try {
      await server.close(id);
    } catch (_) {}
  }
}
