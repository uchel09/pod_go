import 'package:get/get.dart';

import '../../../core/services/scanner/scanner_service.dart';

class ScanLogItem {
  final String code;
  final String source;
  final DateTime timestamp;

  ScanLogItem({
    required this.code,
    required this.source,
    required this.timestamp,
  });
}

class ScannerTestController extends GetxController {
  final ScannerService scannerService = ScannerService.to;

  final scanHistory = <ScanLogItem>[].obs;
  final lastScannedCode = ''.obs;
  final lastScannedSource = ''.obs;

  bool get isCameraSupported => scannerService.isCameraSupported;

  @override
  void onInit() {
    super.onInit();
    lastScannedCode.value = scannerService.lastCode.value;
    lastScannedSource.value = scannerService.lastSource.value;

    // Daftarkan sebagai consumer aktif
    scannerService.registerConsumer('scanner_test', _handleScan);
  }

  @override
  void onClose() {
    scannerService.unregisterConsumer('scanner_test');
    super.onClose();
  }

  void _handleScan(String code) {
    final source = scannerService.lastSource.value.isEmpty
        ? 'HID'
        : scannerService.lastSource.value.toUpperCase();

    lastScannedCode.value = code;
    lastScannedSource.value = source;

    scanHistory.insert(
      0,
      ScanLogItem(
        code: code,
        source: source,
        timestamp: DateTime.now(),
      ),
    );
  }

  Future<void> scanWithCamera() async {
    final result = await scannerService.scanWithCamera();
    if (result != null) {
      Get.snackbar(
        'Scan Kamera Berhasil',
        'Kode: $result',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  void simulateScan(String mockCode) {
    scannerService.simulateScan(mockCode, source: 'hid');
  }

  void clearHistory() {
    scanHistory.clear();
    lastScannedCode.value = '';
    lastScannedSource.value = '';
  }
}
