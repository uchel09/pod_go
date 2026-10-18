import 'dart:async';

/// Abstraksi sumber barcode (Hardware HID, Kamera Android, dll.)
abstract class BarcodeSource {
  /// Stream stream kode yang terbaca
  Stream<String> get codes;

  /// Memulai mendengarkan input barcode
  void start();

  /// Menghentikan mendengarkan input barcode
  void stop();
}

