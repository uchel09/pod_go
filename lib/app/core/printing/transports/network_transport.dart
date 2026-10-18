import 'dart:async';
import 'dart:io';

import '../printer_transport.dart';
import '../../utils/app_exception.dart';

/// Transport untuk printer thermal jaringan (LAN / Wi-Fi via TCP socket port 9100)
class NetworkTransport implements PrinterTransport {
  final String host;
  final int port;
  final Duration timeout;

  Socket? _socket;
  bool _isConnected = false;

  NetworkTransport({
    required this.host,
    this.port = 9100,
    this.timeout = const Duration(seconds: 5),
  });

  @override
  bool get isConnected => _isConnected && _socket != null;

  @override
  Future<void> connect() async {
    if (host.trim().isEmpty) {
      throw const AppException('Alamat IP printer LAN belum diisi.');
    }

    try {
      await disconnect();

      _socket = await Socket.connect(
        host.trim(),
        port,
        timeout: timeout,
      );

      _isConnected = true;
    } on SocketException catch (e) {
      _isConnected = false;
      _socket = null;
      throw AppException(
        'Gagal terhubung ke printer LAN ($host:$port). '
        'Pastikan printer menyala, kabel/WiFi terhubung, dan IP benar. ($e)',
      );
    } catch (e) {
      _isConnected = false;
      _socket = null;
      throw AppException('Kesalahan koneksi printer LAN: $e');
    }
  }

  @override
  Future<void> write(List<int> bytes) async {
    if (!isConnected) {
      await connect();
    }

    try {
      _socket!.add(bytes);
      await _socket!.flush();
    } catch (e) {
      _isConnected = false;
      await disconnect();
      throw AppException('Gagal mengirim data cetak ke printer LAN ($host:$port): $e');
    }
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    try {
      await _socket?.close();
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
  }
}

