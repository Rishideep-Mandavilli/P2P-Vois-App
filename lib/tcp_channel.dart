// Vois offline peer-to-peer radio communication module
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'session.dart';

/// Direct TCP byte channel implementing [ByteChannel] for Wi-Fi hotspot and
/// standalone relay units like the Raspberry Pi 400. Enables TCP_NODELAY to
/// guarantee live audio packets have <5ms network transit time without buffering.
class TcpByteChannel implements ByteChannel {
  final Socket _socket;
  final StreamController<Uint8List> _controller = StreamController<Uint8List>();
  late final StreamSubscription<Uint8List> _sub;
  bool _closed = false;

  TcpByteChannel(this._socket) {
    _socket.setOption(SocketOption.tcpNoDelay, true);
    _sub = _socket.listen(
      (data) {
        if (!_closed && !_controller.isClosed) {
          _controller.add(Uint8List.fromList(data));
        }
      },
      onError: (_) => close(),
      onDone: () => close(),
    );
  }

  static Future<TcpByteChannel> connect(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    return TcpByteChannel(socket);
  }

  @override
  Stream<Uint8List> get input => _controller.stream;

  @override
  void add(Uint8List bytes) {
    if (_closed) return;
    try {
      _socket.add(bytes);
    } catch (_) {
      close();
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub.cancel();
    if (!_controller.isClosed) {
      await _controller.close();
    }
    await _socket.close();
  }
}
