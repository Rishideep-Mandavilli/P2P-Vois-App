// Vois offline peer-to-peer radio communication module
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:p2p_vois/alerts/sos_relay.dart';

void main() {
  setUp(() => SosRelayQueue.instance.clear());

  test('enqueued frame is returned by pending()', () {
    final frame = Uint8List.fromList([1, 2, 3]);
    SosRelayQueue.instance.enqueue(frame);
    expect(SosRelayQueue.instance.pending(), [frame]);
  });

  test('clear empties the queue', () {
    SosRelayQueue.instance.enqueue(Uint8List.fromList([1]));
    SosRelayQueue.instance.clear();
    expect(SosRelayQueue.instance.pending(), isEmpty);
  });

  test('multiple frames preserve insertion order', () {
    final a = Uint8List.fromList([1]);
    final b = Uint8List.fromList([2]);
    SosRelayQueue.instance.enqueue(a);
    SosRelayQueue.instance.enqueue(b);
    expect(SosRelayQueue.instance.pending(), [a, b]);
  });
}
