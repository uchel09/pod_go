import 'dart:async';
import 'package:flutter/services.dart';

import 'barcode_source.dart';

/// Service untuk mendengarkan input barcode scanner tipe HID (Human Interface Device).
/// Scanner HID bekerja seperti keyboard USB / Bluetooth yang mengetik karakter
/// dengan kecepatan tinggi (< 50 ms antar karakter) dan diakhiri dengan tombol Enter.
class HidScannerService implements BarcodeSource {
  /// Batas interval maksimal antar karakter untuk dianggap input mesin/scanner (ms).
  static const int kDefaultMaxIntervalMs = 50;

  /// Panjang minimal kode barcode yang valid.
  static const int kDefaultMinBarcodeLength = 4;

  final int maxIntervalMs;
  final int minBarcodeLength;
  final DateTime Function() clock;

  final StreamController<String> _codesController = StreamController<String>.broadcast();
  final StringBuffer _buffer = StringBuffer();
  DateTime? _lastKeystrokeTime;
  bool _isListening = false;

  HidScannerService({
    this.maxIntervalMs = kDefaultMaxIntervalMs,
    this.minBarcodeLength = kDefaultMinBarcodeLength,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  @override
  Stream<String> get codes => _codesController.stream;

  bool get isListening => _isListening;

  @override
  void start() {
    if (_isListening) return;
    _isListening = true;
    _buffer.clear();
    _lastKeystrokeTime = null;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void stop() {
    if (!_isListening) return;
    _isListening = false;
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _buffer.clear();
    _lastKeystrokeTime = null;
  }

  void dispose() {
    stop();
    _codesController.close();
  }

  /// Menangani event keyboard global dari Flutter HardwareKeyboard.
  ///
  /// TRADE-OFF PENANGANAN TEXTFIELD FOKUS:
  /// Dalam arsitektur event Flutter, [HardwareKeyboard.addHandler] mewajibkan
  /// keputusan konsumsi event (true/false) dibuat secara sinkron saat event diterima,
  /// sebelum jeda waktu atau karakter berikutnya tiba.
  /// Karakter pertama barcode tidak dapat dibedakan dari ketukan jari manusia sebelum
  /// karakter kedua tiba (kecepatan ketukan hanya dapat diukur antar-keberurutan).
  ///
  /// Trade-off yang dipilih:
  /// 1. Karakter pertama diperbolehkan lewat (return false) agar ketikan normal manusia
  ///    tidak tertelan saat mengetik santai di TextField.
  /// 2. Jika karakter berikutnya tiba dengan interval sangat cepat (< 50 ms), karakter
  ///    tersebut ditelan (return true) dan disimpan ke dalam buffer internal.
  /// 3. Tombol [Enter] penutup scan barcode ditelan (return true) bila memenuhi syarat
  ///    kecepatan dan panjang minimal, mencegah form atau dialog tersubmit tidak sengaja.
  /// 4. Layar / Consumer yang sedang aktif (misalnya dialog produk) akan menerima
  ///    kode utuh hasil normalisasi dan langsung menimpa nilai TextField dengan tepat.
  bool _handleKeyEvent(KeyEvent event) {
    if (!_isListening) return false;
    return processKeyEvent(event);
  }

  /// Metode publik untuk memproses KeyEvent agar mudah di-unit test secara deterministik.
  bool processKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return false;
    }

    final now = clock();
    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;

    if (isEnter) {
      final elapsed = _lastKeystrokeTime != null
          ? now.difference(_lastKeystrokeTime!).inMilliseconds
          : 999999;

      final currentBuffer = _buffer.toString();
      final isValidScan = elapsed <= maxIntervalMs && currentBuffer.length >= minBarcodeLength;

      _buffer.clear();
      _lastKeystrokeTime = null;

      if (isValidScan) {
        _codesController.add(currentBuffer);
        // Telan tombol Enter agar tidak men-submit form / dialog secara tidak sengaja
        return true;
      }

      // Jika bukan scan mesin yang valid (misal Enter ditekan manual oleh user), biarkan lewat
      return false;
    }

    final char = event.character;
    if (char == null || char.isEmpty) {
      return false;
    }

    if (_lastKeystrokeTime == null) {
      // Karakter pertama dari rangkaian
      _buffer.clear();
      _buffer.write(char);
      _lastKeystrokeTime = now;
      // Karakter pertama dilewatkan karena belum terbukti scan mesin
      return false;
    }

    final elapsed = now.difference(_lastKeystrokeTime!).inMilliseconds;
    if (elapsed <= maxIntervalMs) {
      // Karakter tiba sangat cepat (< 50 ms), indikasi kuat scanner HID
      _buffer.write(char);
      _lastKeystrokeTime = now;
      // Telan karakter cepat ini agar tidak membanjiri TextField
      return true;
    } else {
      // Jeda > 50 ms menunjukkan ketikan manusia biasa, reset buffer
      _buffer.clear();
      _buffer.write(char);
      _lastKeystrokeTime = now;
      // Biarkan ketikan manusia masuk ke TextField
      return false;
    }
  }
}

