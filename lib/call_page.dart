import 'dart:async';

import 'package:flutter/material.dart';

import 'alerts/sos.dart';
import 'radio_server.dart';
import 'session.dart';

class CallPage extends StatefulWidget {
  final String deviceName;
  final RadioSession session;
  final List<NativeDevice> relayTargets;
  const CallPage({
    super.key,
    required this.deviceName,
    required this.session,
    this.relayTargets = const [],
  });

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  bool _live = true;
  bool _talking = false;
  bool _muted = false;
  bool _relaySent = false;
  String _localName = 'You';
  List<String> _chain = [];
  bool _relaying = false;
  Timer? _timer;
  int _seconds = 0;

  IncomingSos? _alert;

  @override
  void initState() {
    super.initState();
    widget.session.server.getName().then((n) {
      if (n.isNotEmpty && mounted) setState(() => _localName = n);
    });
    _chain = widget.session.chain.value;
    widget.session.chain.addListener(_onChain);
    widget.session.relaying.addListener(_onRelaying);
    widget.session.peerLeft.addListener(_onPeerLeft);
    widget.session.incomingAlert.addListener(_onAlert);
    _relaying = widget.session.relaying.value;
    if (_live) _startLive();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.session.chain.removeListener(_onChain);
    widget.session.relaying.removeListener(_onRelaying);
    widget.session.peerLeft.removeListener(_onPeerLeft);
    widget.session.incomingAlert.removeListener(_onAlert);
    super.dispose();
  }

  void _onChain() => setState(() => _chain = widget.session.chain.value);

  void _onRelaying() => setState(() => _relaying = widget.session.relaying.value);

  void _onAlert() {
    if (mounted) setState(() => _alert = widget.session.incomingAlert.value);
  }

  Future<void> _openSosSheet() async {
    final code = await showModalBottomSheet<SosCode>(
      context: context,
      backgroundColor: Colors.grey.shade900,
      builder: (context) => SafeArea(
        child: Wrap(
          children: SosCode.values
              .map((c) => ListTile(
                    leading: const Icon(Icons.warning_amber,
                        color: Colors.redAccent),
                    title: Text(c.label,
                        style: const TextStyle(color: Colors.white)),
                    onTap: () => Navigator.pop(context, c),
                  ))
              .toList(),
        ),
      ),
    );
    if (code != null) {
      await widget.session.sendSos(code);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('SOS sent: ${code.label}')),
        );
      }
    }
  }

  void _onPeerLeft() {
    if (mounted) Navigator.of(context).pop();
  }

  String get _displayChain {
    if (_chain.isNotEmpty) {
      final display = [..._chain];
      final localIdx = display.indexWhere((n) => n == _localName);
      if (localIdx >= 0) display[localIdx] = 'You';
      return display.join(' → ');
    }
    return 'You → ${widget.deviceName}';
  }

  String get _timerText {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _startLive() async {
    setState(() => _muted = false);
    await widget.session.startCall();
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    if (_muted) {
      await widget.session.stopCall();
    } else {
      await widget.session.startCall();
    }
  }

  Future<void> _switchMode(bool live) async {
    if (live == _live) return;
    setState(() => _live = live);
    if (live) {
      await _startLive();
    } else {
      await widget.session.stopCall();
      setState(() => _muted = false);
    }
  }

  Future<void> _talk(bool start) async {
    setState(() => _talking = start);
    if (start) {
      await widget.session.startTalking();
    } else {
      await widget.session.stopTalking();
    }
  }

  void _relayTo(NativeDevice target) {
    final names = [
      _localName,
      widget.deviceName,
      target.name.isEmpty ? target.address : target.name,
    ];
    widget.session.relayTo([target.address], names);
    setState(() => _relaySent = true);
  }

  Future<void> _disconnect() async {
    await widget.session.dispose();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.warning_amber, color: Colors.redAccent),
            tooltip: 'Send SOS',
            onPressed: _openSosSheet,
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            _buildCallColumn(),
            if (_alert != null) _buildAlertBanner(_alert!),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertBanner(IncomingSos alert) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: Colors.red.shade700,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SOS: ${alert.code.label}',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    if (alert.lat != null && alert.lng != null)
                      Text(
                          '${alert.lat!.toStringAsFixed(5)}, ${alert.lng!.toStringAsFixed(5)}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCallColumn() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.phonelink_ring, size: 64, color: Colors.white70),
              const SizedBox(height: 8),
              Text(
                _displayChain,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 8),
              if (_relaying)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'RELAYING — passing audio through',
                    style: TextStyle(color: Colors.amber, fontSize: 12),
                  ),
                )
              else if (!_relaying)
                Text(
                  _live
                      ? (_muted ? 'Muted' : 'Live call in progress')
                      : (_talking ? 'Transmitting...' : 'PTT mode'),
                  style: TextStyle(
                    color: (_live && !_muted) || _talking
                        ? Colors.amber
                        : Colors.white54,
                    fontSize: 14,
                  ),
                ),
              if (!_relaying)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text('Live'),
                        icon: Icon(Icons.call, size: 16),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('PTT'),
                        icon: Icon(Icons.record_voice_over, size: 16),
                      ),
                    ],
                    selected: {_live},
                    onSelectionChanged: (s) => _switchMode(s.first),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _relaying
              ? const Center(
                  child: Icon(Icons.sync, color: Colors.white24, size: 96))
              : _live
                  ? _buildLiveBody()
                  : _buildPttBody(),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: _disconnect,
            icon: const Icon(Icons.call_end),
            label: const Text('Hang up'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.redAccent),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveBody() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _timerText,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontFeatures: [FontFeature.tabularFigures()]),
        ),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: _toggleMute,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _muted ? Colors.blueGrey.shade600 : Colors.green,
              boxShadow: [
                BoxShadow(
                  color: (_muted ? Colors.blueGrey : Colors.green)
                      .withValues(alpha: 0.4),
                  blurRadius: 30,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _muted ? Icons.mic_off : Icons.mic,
                  color: Colors.white,
                  size: 48,
                ),
                const SizedBox(height: 8),
                Text(
                  _muted ? 'TAP TO UNMUTE' : 'TAP TO MUTE',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.relayTargets.isNotEmpty && !_relaySent) _buildRelayRow(),
      ],
    );
  }

  Widget _buildPttBody() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTapDown: (_) => _talk(true),
          onTapUp: (_) => _talk(false),
          onTapCancel: () => _talk(false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _talking ? Colors.red.shade400 : Colors.green,
              boxShadow: [
                BoxShadow(
                  color:
                      (_talking ? Colors.red : Colors.green).withValues(alpha: 0.4),
                  blurRadius: 30,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _talking ? Icons.mic : Icons.mic_none,
                  color: Colors.white,
                  size: 48,
                ),
                const SizedBox(height: 8),
                Text(
                  _talking ? 'TALKING' : 'HOLD TO TALK',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.relayTargets.isNotEmpty && !_relaySent) _buildRelayRow(),
      ],
    );
  }

  Widget _buildRelayRow() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Text(
            'Extend range: relay through another phone',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.relayTargets
                .map((d) => ActionChip(
                      backgroundColor: Colors.grey.shade800,
                      label: Text(d.name.isEmpty ? d.address : d.name,
                          style: const TextStyle(color: Colors.white)),
                      avatar: const Icon(Icons.arrow_forward,
                          color: Colors.greenAccent, size: 16),
                      onPressed: () => _relayTo(d),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}
