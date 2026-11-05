import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p_vois/tcp_channel.dart';

void main() {
  test('TcpByteChannel connects, transmits, receives, and closes cleanly', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;

    final receivedOnServer = <int>[];
    server.listen((sock) {
      sock.listen((data) {
        receivedOnServer.addAll(data);
        sock.add(Uint8List.fromList([0xAA, 0xBB]));
      });
    });

    final channel = await TcpByteChannel.connect('127.0.0.1', port);
    channel.add(Uint8List.fromList([0x01, 0x02, 0x03]));

    final response = await channel.input.first;
    expect(response, equals(Uint8List.fromList([0xAA, 0xBB])));
    expect(receivedOnServer, equals([0x01, 0x02, 0x03]));

    await channel.close();
    await server.close();
  });
}
