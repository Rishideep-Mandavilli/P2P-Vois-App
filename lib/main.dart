import 'package:flutter/material.dart';

import 'audio.dart';
import 'discovery.dart';
import 'power/battery_saver.dart';
import 'radio_server.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VoisApp());
}

class VoisApp extends StatelessWidget {
  const VoisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'P2P Vois',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const _Bootstrap(),
    );
  }
}

class _BootstrapState extends State<_Bootstrap> {
  final AudioEngine _audio = AudioEngine();
  final RadioServer _server = RadioServer();
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _audio.requestPermissions();
      await _audio.init();
      await _server.init();
      await _server.ensureRadioService();
      await _server.requestEnable();
      await _server.startListening();
      BatterySaver.instance.startMonitoring(_server);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    BatterySaver.instance.stopMonitoring();
    _audio.dispose();
    _server.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Setup failed: $_error'),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => setState(() {
                _error = null;
                _init();
              }), child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return DiscoveryPage(audio: _audio, server: _server);
  }
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}
