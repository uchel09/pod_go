import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'camera_scanner_page.dart';
import 'hid_scanner_service.dart';

typedef ScanCallback = void Function(String code);

/// ScannerService terpadu (GetxService singleton) yang mengelola input barcode
/// dari scanner fisik HID (keyboard USB/Bluetooth) dan kamera ponsel (Android).
class ScannerService extends GetxService {
  static ScannerService get to => Get.find<ScannerService>();

  final HidScannerService hidScanner;
  final StreamController<String> _codesController = StreamController<String>.broadcast();
  StreamSubscription<String>? _hidSubscription;

  /// Kode barcode terakhir yang berhasil dipindai
  final lastCode = ''.obs;

  /// Sumber pindaian terakhir: 'hid', 'camera', atau ''
  final lastSource = ''.obs;

  /// ID consumer pemindaian yang sedang aktif (misal: 'pos', 'products', 'opname', 'scanner_test')
  final activeConsumer = Rxn<String>();

  final Map<String, ScanCallback> _consumers = {};
  final List<String> _consumerStack = [];

  ScannerService({HidScannerService? hidScanner})
      : hidScanner = hidScanner ?? HidScannerService();

  /// Stream global untuk semua kode yang berhasil dipindai & dinormalisasi
  Stream<String> get codes => _codesController.stream;

  /// Apakah perangkat saat ini mendukung scanner kamera (Android)
  bool get isCameraSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void onInit() {
    super.onInit();
    hidScanner.start();
    _hidSubscription = hidScanner.codes.listen((rawCode) {
      _processCode(rawCode, source: 'hid');
    });
  }

  @override
  void onClose() {
    _hidSubscription?.cancel();
    hidScanner.stop();
    _codesController.close();
    super.onClose();
  }

  /// Normalisasi kode barcode:
  /// - Menghilangkan spasi awal/akhir
  /// - Menghilangkan karakter kontrol / non-printable (ASCII 0x00-0x1F, 0x7F-0x9F)
  static String normalize(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[\x00-\x1F\x7F-\x9F]'), '');
    return cleaned.trim();
  }

  /// Mendaftarkan consumer pemindaian.
  /// Consumer yang baru didaftarkan secara otomatis menjadi consumer aktif di puncak stack.
  void registerConsumer(String consumerId, ScanCallback onScan) {
    _consumers[consumerId] = onScan;
    _consumerStack.remove(consumerId);
    _consumerStack.add(consumerId);
    activeConsumer.value = consumerId;
  }

  /// Melepas pendaftaran consumer.
  /// Consumer aktif akan dikembalikan ke consumer sebelumnya di stack (jika ada).
  void unregisterConsumer(String consumerId) {
    _consumers.remove(consumerId);
    _consumerStack.remove(consumerId);
    activeConsumer.value = _consumerStack.isNotEmpty ? _consumerStack.last : null;
  }

  /// Menetapkan consumer aktif secara manual
  void setActiveConsumer(String? consumerId) {
    activeConsumer.value = consumerId;
  }

  /// Memproses kode mentah yang diterima dari sumber manapun (HID atau kamera).
  void _processCode(String rawCode, {required String source}) {
    final normalized = normalize(rawCode);
    if (normalized.length < hidScanner.minBarcodeLength) return;

    lastCode.value = normalized;
    lastSource.value = source;
    _codesController.add(normalized);

    // Kirim hanya ke consumer yang sedang aktif
    final current = activeConsumer.value;
    if (current != null && _consumers.containsKey(current)) {
      _consumers[current]!(normalized);
    }
  }

  /// Membuka kamera scanner (khusus Android).
  /// Mengembalikan kode hasil normalisasi atau null jika dibatalkan / non-Android.
  Future<String?> scanWithCamera() async {
    if (!isCameraSupported) {
      return null;
    }

    final result = await Get.to<String>(() => const CameraScannerPage());
    if (result != null && result.isNotEmpty) {
      final normalized = normalize(result);
      _processCode(normalized, source: 'camera');
      return normalized;
    }
    return null;
  }

  /// Metode simulasi manual untuk testing atau debugging
  void simulateScan(String code, {String source = 'hid'}) {
    _processCode(code, source: source);
  }
}

