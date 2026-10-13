import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'session.dart';

/// Live numbers from the link this call is actually riding, plus a CSV export.
/// Exists so a field test on two phones produces citable figures instead of a
/// screenshot — latency, bitrate, endurance and battery drain had never been
/// measured on real hardware before this screen existed.
class FieldTestPage extends StatefulWidget {
  final RadioSession session;
  const FieldTestPage({super.key, required this.session});

  @override
  State<FieldTestPage> createState() => _FieldTestPageState();
}

class _FieldTestPageState extends State<FieldTestPage> {
  Timer? _ticker;
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    _readBattery();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _readBattery() async {
    final level = await widget.session.server.getBatteryLevel();
    if (!mounted || level == null) return;
    setState(() {
      widget.session.metrics.batteryStart ??= level;
      widget.session.metrics.batteryEnd = level;
    });
  }

  void _toggleProbing() {
    _ticker?.cancel();
    setState(() => _probing = !_probing);
    if (_probing) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        widget.session.sendPing();
        _readBattery();
        setState(() {});
      });
      widget.session.sendPing();
    }
  }

  Future<void> _copyCsv() async {
    await Clipboard.setData(
      ClipboardData(text: widget.session.metrics.toCsv()),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Measurements copied as CSV')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.session.metrics;
    final totalSeconds = m.elapsedSeconds.round();
    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Field Test'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy measurements as CSV',
            onPressed: _copyCsv,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Transport: ${widget.session.transport}',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 20),
          _row('Elapsed',
              '${(totalSeconds ~/ 60).toString().padLeft(2, '0')}:${(totalSeconds % 60).toString().padLeft(2, '0')}'),
          _row(
            'Round trip',
            m.rttMs.isEmpty
                ? 'no samples yet'
                : '${m.rttMin}–${m.rttMax} ms, median ${m.rttMedian}',
          ),
          _row('Probes sent / answered', '${m.pingsSent} / ${m.rttMs.length}'),
          _row('Outbound', '${m.kbpsOut.toStringAsFixed(1)} kbps'),
          _row('Inbound', '${m.kbpsIn.toStringAsFixed(1)} kbps'),
          _row('Frames out / in', '${m.txFrames} / ${m.rxFrames}'),
          _row('Bytes out / in', '${m.txBytes} / ${m.rxBytes}'),
          _row(
            'Battery',
            m.batteryStart == null
                ? 'unavailable'
                : '${m.batteryStart}% → ${m.batteryEnd ?? m.batteryStart}%'
                    '${m.batteryDrainPoints == null || m.batteryDrainPoints == 0 ? '' : '  (−${m.batteryDrainPoints})'}',
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _toggleProbing,
            icon: Icon(_probing ? Icons.stop : Icons.play_arrow),
            label: Text(_probing ? 'Stop probing' : 'Probe once a second'),
          ),
          const SizedBox(height: 24),
          const Text(
            'Bitrate counts whole frames on the wire, including the 3-byte '
            'header, so it is what the radio really carries rather than the '
            'payload alone.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 14)),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 14,
                  fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }
}
