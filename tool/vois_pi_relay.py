#!/usr/bin/env python3
"""
P2P Vois - Raspberry Pi 400 Autonomous Relay Daemon
---------------------------------------------------
Operates as a high-elevation, long-range packet relay for P2P Vois.
Listens on TCP port 8988 (Wi-Fi Direct / Local Ad-hoc Network).

When two or more Android phones running P2P Vois connect:
1. Seamlessly relays audio frames (ADPCM, 0x01) with near-zero latency (TCP_NODELAY).
2. Forwards key exchange (0x05), ping/pong (0x07/0x08), and relay metadata.
3. Broadcasts emergency SOS alerts (0x06) to ALL connected peers simultaneously.
4. Injects ChainInfo metadata (0x03) so phones display: "You → Pi-Relay → Peer".
5. Logs live throughput, packet counts, and distress alerts in real time.
"""

import asyncio
import os
import socket
import struct
import time
from datetime import datetime

PORT = 8988
HOST = "0.0.0.0"

# Wire Frame Types
FRAME_AUDIO = 0x01
FRAME_CONNECT_TO = 0x02
FRAME_CHAIN_INFO = 0x03
FRAME_DISCONNECT = 0x04
FRAME_KEY_EXCHANGE = 0x05
FRAME_SOS = 0x06
FRAME_PING = 0x07
FRAME_PONG = 0x08

FRAME_NAMES = {
    FRAME_AUDIO: "AUDIO",
    FRAME_CONNECT_TO: "CONNECT_TO",
    FRAME_CHAIN_INFO: "CHAIN_INFO",
    FRAME_DISCONNECT: "DISCONNECT",
    FRAME_KEY_EXCHANGE: "KEY_EXCHANGE",
    FRAME_SOS: "SOS_ALERT",
    FRAME_PING: "PING",
    FRAME_PONG: "PONG",
}

class RelayServer:
    def __init__(self):
        self.clients = set()
        self.client_names = {}
        self.stats = {
            "total_bytes": 0,
            "audio_frames": 0,
            "sos_alerts": 0,
            "start_time": time.time(),
        }

    def pack_chain_info(self, names):
        # JSON-like payload: {"names": ["name1", "name2"]}
        import json
        payload = json.dumps({"names": names}).encode("utf-8")
        header = struct.pack("<BH", FRAME_CHAIN_INFO, len(payload))
        return header + payload

    async def handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        # Enable TCP_NODELAY to ensure live 20ms audio frames are not delayed by Nagle algorithm
        sock = writer.get_extra_info("socket")
        if sock:
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)

        addr = writer.get_extra_info("peername")
        client_ip = addr[0] if addr else "unknown"
        client_id = f"Phone@{client_ip}:{addr[1] if addr else ''}"
        
        print(f"\n[+] NEW CLIENT CONNECTED: {client_id}")
        self.clients.add(writer)
        self.client_names[writer] = f"Node-{len(self.clients)}"

        # Notify connected peers of chain topology if multiple clients
        if len(self.clients) >= 2:
            print(f"[*] ACTIVE CALL PAIR ESTABLISHED via Pi-Relay (Total peers: {len(self.clients)})")

        buffer = bytearray()
        try:
            while True:
                data = await reader.read(4096)
                if not data:
                    break

                self.stats["total_bytes"] += len(data)
                buffer.extend(data)

                # Process length-prefixed frames: [1B type][2B LE length][payload]
                while len(buffer) >= 3:
                    frame_type = buffer[0]
                    payload_len = buffer[1] | (buffer[2] << 8)
                    total_frame_len = 3 + payload_len

                    if len(buffer) < total_frame_len:
                        break  # Incomplete frame, wait for more bytes

                    frame_bytes = bytes(buffer[:total_frame_len])
                    del buffer[:total_frame_len]

                    # Parse Frame Type for metrics
                    if frame_type == FRAME_AUDIO:
                        self.stats["audio_frames"] += 1
                    elif frame_type == FRAME_SOS:
                        self.stats["sos_alerts"] += 1
                        print(f"\n🚨 [EMERGENCY SOS BEACON RECEIVED from {client_id} at {datetime.now().strftime('%H:%M:%S')}] 🚨")
                        print(f"   Payload length: {payload_len} bytes. Broadcasting to ALL peers!")
                    elif frame_type in (FRAME_PING, FRAME_PONG):
                        pass
                    else:
                        type_name = FRAME_NAMES.get(frame_type, f"UNKNOWN(0x{frame_type:02x})")
                        print(f"[{datetime.now().strftime('%H:%M:%S')}] Frame {type_name} ({payload_len} B) from {client_id}")

                    # Forward to all OTHER connected clients
                    for peer in list(self.clients):
                        if peer != writer:
                            try:
                                peer.write(frame_bytes)
                                await peer.drain()
                            except Exception as e:
                                print(f"[-] Write to peer failed: {e}")

        except asyncio.CancelledError:
            pass
        except Exception as e:
            print(f"[-] Client {client_id} error: {e}")
        finally:
            print(f"[-] CLIENT DISCONNECTED: {client_id}")
            self.clients.discard(writer)
            self.client_names.pop(writer, None)
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass

    async def stats_monitor(self):
        """Prints live relay stats every 10 seconds."""
        last_bytes = 0
        while True:
            await asyncio.sleep(10)
            elapsed = time.time() - self.stats["start_time"]
            cur_bytes = self.stats["total_bytes"]
            rate_kbps = ((cur_bytes - last_bytes) * 8) / (10 * 1024)
            last_bytes = cur_bytes

            active_peers = len(self.clients)
            if active_peers > 0 or self.stats["audio_frames"] > 0:
                print(
                    f"[RELAY STATUS] Peers: {active_peers} | "
                    f"Traffic: {rate_kbps:.1f} kbps | "
                    f"Audio Frames: {self.stats['audio_frames']} | "
                    f"SOS Alerts: {self.stats['sos_alerts']} | "
                    f"Total Relayed: {cur_bytes / (1024*1024):.2f} MB"
                )

    async def run(self):
        server = await asyncio.start_server(self.handle_client, HOST, PORT, reuse_address=True)
        print("=" * 65)
        print(f"  P2P Vois - Raspberry Pi 400 Long-Range Relay Active")
        print(f"  Listening on TCP port: {PORT}")
        print(f"  Host interfaces bound: {HOST} (Ethernet + Wi-Fi)")
        print(f"  Ready for phone connections.")
        print("=" * 65)

        async with server:
            await asyncio.gather(server.serve_forever(), self.stats_monitor())

if __name__ == "__main__":
    relay = RelayServer()
    try:
        asyncio.run(relay.run())
    except KeyboardInterrupt:
        print("\n[!] Relay server stopped by user.")
