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
  final DateTime Function() _clock;
  final Duration cooldownDuration;
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

  String? _lastProcessedCode;
  DateTime? _lastProcessedTime;

  ScannerService({
    HidScannerService? hidScanner,
    DateTime Function()? clock,
    Duration? cooldownDuration,
  })  : hidScanner = hidScanner ?? HidScannerService(),
        _clock = clock ?? DateTime.now,
        cooldownDuration = cooldownDuration ?? const Duration(seconds: 1);

  /// Stream global untuk semua kode yang berhasil dipindai & dinormalisasi
  Stream<String> get codes => _codesController.stream;

  /// Apakah perangkat saat ini mendukung scanner kamera (Android)
  bool get isCameraSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void onInit() {
    super.onInit();
    hidScanner.start();
    _hidSubscription = hidScanner.codes.listen((rawCode) {
      _processCode(rawCode, source: 'hid', notifyConsumer: true);
    });
  }

  @override
  void onClose() {
    _hidSubscription?.cancel();
    hidScanner.stop();
    _codesController.close();
    super.onClose();
  }

  /// Memeriksa apakah barcode [code] masih dalam masa cooldown (1 detik dari scan identik sebelumnya).
  bool isCooldownActive(String code) {
    if (_lastProcessedCode == code && _lastProcessedTime != null) {
      final elapsed = _clock().difference(_lastProcessedTime!);
      if (elapsed < cooldownDuration) {
        return true;
      }
    }
    return false;
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
  /// [notifyConsumer]: jika true, meneruskan kode ke active consumer (digunakan untuk HID stream).
  /// Untuk scan kamera interaktif (await scanWithCamera), notifyConsumer bernilai false
  /// agar hasil konsumsi dikendalikan langsung oleh pemanggil secara tunggal (mencegah jalur ganda).
  bool _processCode(String rawCode, {required String source, bool notifyConsumer = true}) {
    final normalized = normalize(rawCode);
    if (normalized.length < hidScanner.minBarcodeLength) return false;

    // Cooldown untuk kode identik dalam jendela singkat (1 detik) pada level service
    if (isCooldownActive(normalized)) {
      return false;
    }

    _lastProcessedCode = normalized;
    _lastProcessedTime = _clock();

    lastCode.value = normalized;
    lastSource.value = source;
    _codesController.add(normalized);

    // Kirim hanya ke consumer yang sedang aktif jika notifyConsumer true
    if (notifyConsumer) {
      final current = activeConsumer.value;
      if (current != null && _consumers.containsKey(current)) {
        _consumers[current]!(normalized);
      }
    }
    return true;
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
      if (normalized.length < hidScanner.minBarcodeLength) return null;

      final processed = _processCode(normalized, source: 'camera', notifyConsumer: false);
      if (!processed) return null; // Terkena cooldown
      return normalized;
    }
    return null;
  }

  /// Metode simulasi manual untuk testing atau debugging
  void simulateScan(String code, {String source = 'hid', bool notifyConsumer = true}) {
    _processCode(code, source: source, notifyConsumer: notifyConsumer);
  }
}

