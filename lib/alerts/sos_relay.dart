// Vois offline peer-to-peer radio communication module
import 'dart:typed_data';

/// Basic store-and-forward for SOS broadcasts: if an SOS is sent while no peers are in range, it's queued here
/// instead of silently dropped, and the caller re-sends every queued
/// frame to each newly-joined peer (see WifiDirectPage). This is
/// single-hop store-and-forward — an SOS waits locally until *this*
/// device sees a peer, then hands it off — not full multi-hop mesh
/// routing with a hop-count/path table across many devices, which is a
/// larger follow-up. Each queued frame carries its own TTL so stale SOS
/// messages eventually get dropped instead of replaying forever.
class QueuedSos {
  final Uint8List frame;
  final DateTime queuedAt;
  QueuedSos(this.frame, this.queuedAt);

  bool get expired => DateTime.now().difference(queuedAt) > const Duration(minutes: 30);
}

class SosRelayQueue {
  static final SosRelayQueue instance = SosRelayQueue._();
  SosRelayQueue._();

  final List<QueuedSos> _queue = [];

  void enqueue(Uint8List frame) {
    _queue.add(QueuedSos(frame, DateTime.now()));
  }

  /// Frames still worth forwarding; also prunes anything past its TTL.
  List<Uint8List> pending() {
    _queue.removeWhere((q) => q.expired);
    return _queue.map((q) => q.frame).toList();
  }

  void clear() => _queue.clear();
}
