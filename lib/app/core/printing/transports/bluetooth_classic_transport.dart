import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../printer_transport.dart';
import '../../utils/app_exception.dart';

/// Transport untuk printer Bluetooth Classic SPP (Android)
class BluetoothClassicTransport implements PrinterTransport {
  final String macAddress;
  final Duration timeout;
  bool _isConnected = false;

  BluetoothClassicTransport({
    required this.macAddress,
    this.timeout = const Duration(seconds: 8),
  });

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect() async {
    if (kIsWeb || !Platform.isAndroid) {
      throw const AppException('Koneksi Bluetooth Classic SPP hanya didukung di platform Android.');
    }

    if (macAddress.trim().isEmpty) {
      throw const AppException('Alamat MAC Bluetooth printer belum dikonfigurasi.');
    }

    try {
      final isAlreadyConnected = await PrintBluetoothThermal.connectionStatus;
      if (isAlreadyConnected) {
        _isConnected = true;
        return;
      }

      final connectFuture = PrintBluetoothThermal.connect(macPrinterAddress: macAddress.trim());
      final success = await connectFuture.timeout(timeout, onTimeout: () {
        throw AppException('Batas waktu koneksi Bluetooth terlampaui (${timeout.inSeconds} detik).');
      });

      if (!success) {
        _isConnected = false;
        throw AppException('Gagal terhubung ke printer Bluetooth ($macAddress). Pastikan printer menyala dan dipasangkan.');
      }

      _isConnected = true;
    } catch (e) {
      _isConnected = false;
      if (e is AppException) rethrow;
      throw AppException('Terjadi kesalahan koneksi Bluetooth: $e');
    }
  }

  @override
  Future<void> write(List<int> bytes) async {
    if (!_isConnected) {
      await connect();
    }

    try {
      final success = await PrintBluetoothThermal.writeBytes(bytes);
      if (!success) {
        _isConnected = false;
        throw const AppException('Gagal mengirim data cetak ke printer Bluetooth.');
      }
    } catch (e) {
      _isConnected = false;
      if (e is AppException) rethrow;
      throw AppException('Gagal menulis data ke printer Bluetooth: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (_) {
      // Abaikan error saat disconnect
    } finally {
      _isConnected = false;
    }
  }
}

