// Vois offline peer-to-peer radio communication module
import 'dart:math' as math;
import 'dart:typed_data';

/// Numbers a two-phone field test produces while a real call runs, so the
/// measurement doesn't need a separate rig. Counters tick exactly where bytes
/// move on the wire, which keeps the reported bitrate honest about what the
/// link is actually carrying (frame bytes, not payload-only).
class FieldMetrics {
  final DateTime startedAt = DateTime.now();

  int txFrames = 0;
  int txBytes = 0;
  int rxFrames = 0;
  int rxBytes = 0;
  int pingsSent = 0;

  /// Completed round trips in milliseconds, in arrival order.
  final List<int> rttMs = [];

  int? batteryStart;
  int? batteryEnd;

  void recordTx(Uint8List frame) {
    txFrames++;
    txBytes += frame.length;
  }

  void recordRx(Uint8List frame) {
    rxFrames++;
    rxBytes += frame.length;
  }

  void recordPingSent() => pingsSent++;

  /// [echoedMicros] is the sender's own timestamp coming back, so the
  /// subtraction happens on one clock and needs no clock sync between phones.
  void recordPong(int echoedMicros, int nowMicros) {
    rttMs.add((nowMicros - echoedMicros) ~/ 1000);
  }

  double get elapsedSeconds =>
      DateTime.now().difference(startedAt).inMilliseconds / 1000;

  /// Kilobits per second sustained outbound, counting frame overhead.
  double get kbpsOut => elapsedSeconds <= 0
      ? 0
      : txBytes * 8 / 1000 / elapsedSeconds;

  double get kbpsIn => elapsedSeconds <= 0
      ? 0
      : rxBytes * 8 / 1000 / elapsedSeconds;

  int? get rttMin => rttMs.isEmpty ? null : rttMs.reduce(math.min);

  int? get rttMax => rttMs.isEmpty ? null : rttMs.reduce(math.max);

  int? get rttMedian {
    if (rttMs.isEmpty) return null;
    final sorted = [...rttMs]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : ((sorted[mid - 1] + sorted[mid]) / 2).round();
  }

  /// Percentage points lost while the call was up, or null until both
  /// readings exist.
  int? get batteryDrainPoints {
    final s = batteryStart;
    final e = batteryEnd;
    return (s == null || e == null) ? null : s - e;
  }

  String toCsv() {
    final rows = <List<String>>[
      ['metric', 'value'],
      ['started_at', startedAt.toIso8601String()],
      ['elapsed_seconds', elapsedSeconds.toStringAsFixed(1)],
      ['tx_frames', '$txFrames'],
      ['tx_bytes', '$txBytes'],
      ['rx_frames', '$rxFrames'],
      ['rx_bytes', '$rxBytes'],
      ['kbps_out', kbpsOut.toStringAsFixed(1)],
      ['kbps_in', kbpsIn.toStringAsFixed(1)],
      ['pings_sent', '$pingsSent'],
      ['ponges_received', '${rttMs.length}'],
      ['rtt_min_ms', '${rttMin ?? ''}'],
      ['rtt_median_ms', '${rttMedian ?? ''}'],
      ['rtt_max_ms', '${rttMax ?? ''}'],
      ['battery_start_pct', '${batteryStart ?? ''}'],
      ['battery_end_pct', '${batteryEnd ?? ''}'],
      ['battery_drain_points', '${batteryDrainPoints ?? ''}'],
      ['rtt_samples_ms', rttMs.join(' ')],
    ];
    return rows.map((r) => r.join(',')).join('\n');
  }
}
