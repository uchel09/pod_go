import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:pos_me/app/core/services/scanner/hid_scanner_service.dart';
import 'package:pos_me/app/core/services/scanner/scanner_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HidScannerService Tests', () {
    late DateTime currentTime;
    late HidScannerService hid;

    setUp(() {
      currentTime = DateTime(2026, 1, 1, 12, 0, 0);
      hid = HidScannerService(
        clock: () => currentTime,
        maxIntervalMs: 50,
        minBarcodeLength: 4,
      );
    });

    tearDown(() {
      hid.dispose();
    });

    test('Deteksi barcode berhasil bila interval cepat (< 50 ms) diakhiri Enter', () async {
      final emittedCodes = <String>[];
      hid.codes.listen(emittedCodes.add);

      const barcode = '89912345';
      final results = <bool>[];

      // Simulasi scanner mengetik setiap karakter dengan interval 10 ms
      for (int i = 0; i < barcode.length; i++) {
        currentTime = currentTime.add(const Duration(milliseconds: 10));
        final consumed = hid.processKeyEvent(
          KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.digit8,
            logicalKey: LogicalKeyboardKey.digit8,
            character: barcode[i],
            timeStamp: Duration.zero,
          ),
        );
        results.add(consumed);
      }

      // Karakter pertama dilewatkan (false), karakter berikutnya ditelan (true)
      expect(results.first, false);
      for (int i = 1; i < results.length; i++) {
        expect(results[i], true);
      }

      // Scanner mengirim Enter setelah 10 ms
      currentTime = currentTime.add(const Duration(milliseconds: 10));
      final enterConsumed = hid.processKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.enter,
          logicalKey: LogicalKeyboardKey.enter,
          timeStamp: Duration.zero,
        ),
      );

      // Enter dari scanner ditelan (true)
      expect(enterConsumed, true);
      await Future<void>.delayed(Duration.zero);

      expect(emittedCodes, hasLength(1));
      expect(emittedCodes.first, '89912345');
    });

    test('Ketikan manusia lambat (> 50 ms) TIDAK dianggap barcode', () async {
      final emittedCodes = <String>[];
      hid.codes.listen(emittedCodes.add);

      const text = 'Kopi';

      // Manusia mengetik santai setiap 150 ms
      for (int i = 0; i < text.length; i++) {
        currentTime = currentTime.add(const Duration(milliseconds: 150));
        final consumed = hid.processKeyEvent(
          KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.keyK,
            logicalKey: LogicalKeyboardKey.keyK,
            character: text[i],
            timeStamp: Duration.zero,
          ),
        );
        // Semua ketikan manusia tidak boleh ditelan agar masuk TextField
        expect(consumed, false);
      }

      // Manusia menekan Enter
      currentTime = currentTime.add(const Duration(milliseconds: 200));
      final enterConsumed = hid.processKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.enter,
          logicalKey: LogicalKeyboardKey.enter,
          timeStamp: Duration.zero,
        ),
      );

      // Enter tidak ditelan dan tidak ada barcode yang dipancarkan
      expect(enterConsumed, false);
      await Future<void>.delayed(Duration.zero);
      expect(emittedCodes, isEmpty);
    });

    test('Kode kurang dari minBarcodeLength (4) ditolak', () async {
      final emittedCodes = <String>[];
      hid.codes.listen(emittedCodes.add);

      const shortCode = 'ABC'; // Hanya 3 karakter

      for (int i = 0; i < shortCode.length; i++) {
        currentTime = currentTime.add(const Duration(milliseconds: 10));
        hid.processKeyEvent(
          KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.keyA,
            logicalKey: LogicalKeyboardKey.keyA,
            character: shortCode[i],
            timeStamp: Duration.zero,
          ),
        );
      }

      currentTime = currentTime.add(const Duration(milliseconds: 10));
      final enterConsumed = hid.processKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.enter,
          logicalKey: LogicalKeyboardKey.enter,
          timeStamp: Duration.zero,
        ),
      );

      expect(enterConsumed, false);
      await Future<void>.delayed(Duration.zero);
      expect(emittedCodes, isEmpty);
    });
  });

  group('ScannerService Tests', () {
    late ScannerService scannerService;

    setUp(() {
      Get.reset();
      scannerService = ScannerService();
      Get.put<ScannerService>(scannerService);
    });

    tearDown(() {
      Get.reset();
    });

    test('Normalisasi kode: membersihkan whitespace dan karakter non-printable', () {
      expect(ScannerService.normalize('   8992753   '), '8992753');
      expect(ScannerService.normalize('BARCODE\x00\x02\x03\r\n'), 'BARCODE');
      expect(ScannerService.normalize('\x1B\x7FPROD-999\x07'), 'PROD-999');
    });

    test('Scan Consumer routing: hanya consumer aktif di puncak stack yang menerima barcode', () {
      final consumer1Logs = <String>[];
      final consumer2Logs = <String>[];

      // Daftarkan consumer 1
      scannerService.registerConsumer('pos', consumer1Logs.add);
      expect(scannerService.activeConsumer.value, 'pos');

      scannerService.simulateScan('BARCODE-1');
      expect(consumer1Logs, ['BARCODE-1']);
      expect(consumer2Logs, isEmpty);

      // Daftarkan consumer 2 (misal dialog produk terbuka)
      scannerService.registerConsumer('product_form', consumer2Logs.add);
      expect(scannerService.activeConsumer.value, 'product_form');

      scannerService.simulateScan('BARCODE-2');
      // Hanya consumer 2 yang menerima
      expect(consumer1Logs, ['BARCODE-1']);
      expect(consumer2Logs, ['BARCODE-2']);

      // Tutup dialog produk -> unregister consumer 2
      scannerService.unregisterConsumer('product_form');
      expect(scannerService.activeConsumer.value, 'pos');

      // Consumer 1 kembali aktif menerima scan
      scannerService.simulateScan('BARCODE-3');
      expect(consumer1Logs, ['BARCODE-1', 'BARCODE-3']);
      expect(consumer2Logs, ['BARCODE-2']);
    });

    test('scanWithCamera mengembalikan null di non-Android (misal Windows)', () async {
      // Di test environment (bukan Android device asli)
      if (!scannerService.isCameraSupported) {
        final result = await scannerService.scanWithCamera();
        expect(result, isNull);
      }
    });

    test('Update lastCode dan lastSource saat scan berhasil', () {
      scannerService.simulateScan('P000123', source: 'camera');

      expect(scannerService.lastCode.value, 'P000123');
      expect(scannerService.lastSource.value, 'camera');
    });
  });
}

