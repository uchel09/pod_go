import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_me/app/core/printing/esc_pos_generator.dart';
import 'package:pos_me/app/core/printing/printers/esc_pos_receipt_printer.dart';
import 'package:pos_me/app/core/printing/printers/pdf_receipt_printer.dart';
import 'package:pos_me/app/core/printing/printer_transport.dart';
import 'package:pos_me/app/core/printing/receipt_data.dart';

class MockPrinterTransport implements PrinterTransport {
  bool connectSuccess = true;
  bool writeSuccess = true;
  int connectCallCount = 0;
  int writeCallCount = 0;
  int disconnectCallCount = 0;
  List<int> lastWrittenBytes = [];
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect() async {
    connectCallCount++;
    if (!connectSuccess) {
      _connected = false;
      throw Exception('Mock connect failed: device offline');
    }
    _connected = true;
  }

  @override
  Future<void> write(List<int> bytes) async {
    writeCallCount++;
    if (!writeSuccess) {
      throw Exception('Mock write failed: device disconnected');
    }
    lastWrittenBytes = List.from(bytes);
  }

  @override
  Future<void> disconnect() async {
    disconnectCallCount++;
    _connected = false;
  }
}

void main() {
  late ReceiptData sampleReceipt;

  setUp(() {
    sampleReceipt = ReceiptData(
      storeName: 'TOKO UJI COBA',
      storeAddress: 'Jl. Ahmad Yani No. 12',
      storePhone: '081122334455',
      invoiceNo: 'INV/20261013/0099',
      cashierName: 'Siti Aminah',
      dateTime: DateTime(2026, 10, 13, 10, 15),
      items: const [
        ReceiptItemData(
          name: 'Buku Tulis Sinar Dunia 38Lbr',
          qty: 3,
          price: 4500,
          discount: 500,
          subtotal: 12000,
        ),
      ],
      subtotal: 13500,
      discount: 1500,
      total: 12000,
      paid: 20000,
      change: 8000,
      payments: const [
        ReceiptPaymentData(method: 'cash', amount: 20000),
      ],
      footerNotes: 'Terima Kasih!',
    );
  });

  group('ReceiptData Model', () {
    test('instantiates with proper totals and items', () {
      expect(sampleReceipt.storeName, equals('TOKO UJI COBA'));
      expect(sampleReceipt.invoiceNo, equals('INV/20261013/0099'));
      expect(sampleReceipt.items.length, equals(1));
      expect(sampleReceipt.total, equals(12000));
      expect(sampleReceipt.change, equals(8000));
    });
  });

  group('EscPosReceiptPrinter with MockPrinterTransport', () {
    test('successful print executes connect, writes bytes, and cuts', () async {
      final mock = MockPrinterTransport();
      final printer = EscPosReceiptPrinter(
        transport: mock,
        generator: const EscPosGenerator(charsPerLine: 32),
        cutMode: CutMode.partial,
        feedLines: 3,
        openDrawer: true,
      );

      final result = await printer.printReceipt(sampleReceipt);

      expect(result.success, isTrue);
      expect(result.error, isNull);
      expect(mock.connectCallCount, equals(1));
      expect(mock.writeCallCount, equals(1));
      expect(mock.lastWrittenBytes, isNotEmpty);
    });

    test('reconnects once and succeeds if first connection fails', () async {
      final mock = MockPrinterTransport()..connectSuccess = false;
      final printer = EscPosReceiptPrinter(
        transport: mock,
        generator: const EscPosGenerator(charsPerLine: 32),
      );

      // Ubah connectSuccess jadi true setelah upaya pertama
      Timer(const Duration(milliseconds: 50), () {
        mock.connectSuccess = true;
      });

      final result = await printer.printReceipt(sampleReceipt);
      expect(mock.connectCallCount, greaterThanOrEqualTo(2));
      expect(result.success, isTrue);
    });

    test('returns failure if connection persistently fails', () async {
      final mock = MockPrinterTransport()..connectSuccess = false;
      final printer = EscPosReceiptPrinter(
        transport: mock,
        generator: const EscPosGenerator(charsPerLine: 32),
      );

      final result = await printer.printReceipt(sampleReceipt);

      expect(result.success, isFalse);
      expect(result.error, contains('Gagal mencetak'));
      expect(mock.writeCallCount, equals(0));
    });

    test('returns failure if write throws exception', () async {
      final mock = MockPrinterTransport()..writeSuccess = false;
      final printer = EscPosReceiptPrinter(
        transport: mock,
        generator: const EscPosGenerator(charsPerLine: 32),
      );

      final result = await printer.printReceipt(sampleReceipt);

      expect(result.success, isFalse);
      expect(result.error, contains('Mock write failed'));
    });

    test('openCashDrawer sends pulse command through transport', () async {
      final mock = MockPrinterTransport();
      final printer = EscPosReceiptPrinter(
        transport: mock,
        generator: const EscPosGenerator(charsPerLine: 32),
        drawerPin: 0,
      );

      await printer.openCashDrawer();

      expect(mock.writeCallCount, equals(1));
      expect(
        mock.lastWrittenBytes,
        equals([...EscPosGenerator.cmdInit, ...EscPosGenerator.cmdOpenDrawer(pin: 0)]),
      );
    });

    test('prints test page with ruler correctly', () async {
      final mock = MockPrinterTransport();
      final printer = EscPosReceiptPrinter(
        transport: mock,
        generator: const EscPosGenerator(charsPerLine: 32),
      );

      final result = await printer.printTest();

      expect(result.success, isTrue);
      expect(mock.writeCallCount, equals(1));
      expect(mock.lastWrittenBytes, isNotEmpty);
    });

    test('queues multiple print requests sequentially without collisions', () async {
      final mock = MockPrinterTransport();
      final printer = EscPosReceiptPrinter(
        transport: mock,
        generator: const EscPosGenerator(charsPerLine: 32),
      );

      // Jalankan 3 print concurrent
      final futures = [
        printer.printReceipt(sampleReceipt),
        printer.printReceipt(sampleReceipt),
        printer.printReceipt(sampleReceipt),
      ];

      final results = await Future.wait(futures);

      for (final r in results) {
        expect(r.success, isTrue);
      }
      expect(mock.writeCallCount, equals(3));
    });
  });

  group('PdfReceiptPrinter', () {
    test('instantiates with 58mm or 80mm width', () {
      final p58 = PdfReceiptPrinter(receiptWidth: '58');
      expect(p58.receiptWidth, equals('58'));

      final p80 = PdfReceiptPrinter(receiptWidth: '80');
      expect(p80.receiptWidth, equals('80'));
    });
  });
}

