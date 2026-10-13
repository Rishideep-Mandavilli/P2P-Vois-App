import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:p2p_vois/field_metrics.dart';
import 'package:p2p_vois/protocol.dart';

Uint8List pingPayload(int micros) => framePayload(packPing(micros));

void main() {
  group('round-trip probe', () {
    test('ping payload survives framing and reads back exactly', () {
      const micros = 1727000000123456;
      final echoed = probeMicros(pingPayload(micros));
      expect(echoed, micros);
    });

    test('a short payload is rejected rather than read out of bounds', () {
      expect(probeMicros(Uint8List(7)), isNull);
    });

    test('pong keeps the sender timestamp untouched', () {
      final ping = packPing(999999);
      final pong = packPong(framePayload(ping));
      expect(frameType(pong), FrameType.pong);
      expect(probeMicros(framePayload(pong)), 999999);
    });
  });

  group('FieldMetrics', () {
    test('counts frames and bytes separately for each direction', () {
      final m = FieldMetrics();
      m.recordTx(Uint8List(323));
      m.recordTx(Uint8List(323));
      m.recordRx(Uint8List(326));
      expect(m.txFrames, 2);
      expect(m.txBytes, 646);
      expect(m.rxFrames, 1);
      expect(m.rxBytes, 326);
    });

    test('a pong becomes a millisecond round trip on one clock', () {
      final m = FieldMetrics();
      m.recordPong(1000000, 1042000); // sent at 1.000000s, back at 1.042s
      expect(m.rttMs, [42]);
    });

    test('median uses the middle of sorted samples', () {
      final m = FieldMetrics();
      for (final rtt in [30, 10, 20]) {
        m.recordPong(0, rtt * 1000);
      }
      expect(m.rttMin, 10);
      expect(m.rttMax, 30);
      expect(m.rttMedian, 20);
    });

    test('median of an even count averages the two middle samples', () {
      final m = FieldMetrics();
      for (final rtt in [10, 20, 30, 40]) {
        m.recordPong(0, rtt * 1000);
      }
      expect(m.rttMedian, 25);
    });

    test('no samples means no invented statistics', () {
      final m = FieldMetrics();
      expect(m.rttMin, isNull);
      expect(m.rttMedian, isNull);
      expect(m.rttMax, isNull);
      expect(m.batteryDrainPoints, isNull);
    });

    test('battery drain is the difference between the two readings', () {
      final m = FieldMetrics()
        ..batteryStart = 80
        ..batteryEnd = 76;
      expect(m.batteryDrainPoints, 4);
    });

    test('export carries every field a pitch or defence needs', () {
      final m = FieldMetrics()
        ..recordTx(Uint8List(323))
        ..recordPingSent()
        ..recordPong(0, 18000)
        ..batteryStart = 90
        ..batteryEnd = 89;
      final csv = m.toCsv();
      for (final field in [
        'elapsed_seconds',
        'tx_frames',
        'kbps_out',
        'pings_sent',
        'ponges_received',
        'rtt_median_ms',
        'battery_drain_points',
        'rtt_samples_ms',
      ]) {
        expect(csv, contains(field));
      }
      expect(csv.split('\n').first, 'metric,value');
    });
  });
}
