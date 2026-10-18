import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_me/app/core/printing/esc_pos_generator.dart';
import 'package:pos_me/app/core/printing/receipt_data.dart';

void main() {
  group('EscPosGenerator - String Utilities & Sanitization', () {
    test('sanitizeAscii preserves standard ASCII and newlines', () {
      const input = 'Toko Kopi ABC 123!\nJalan Merdeka No. 45';
      final result = EscPosGenerator.sanitizeAscii(input);
      expect(result, equals(input));
    });

    test('sanitizeAscii converts common typographic characters and accents', () {
      const input = '“Toko” ‘Kopi’ • Es Téh – Rp 15.000';
      final result = EscPosGenerator.sanitizeAscii(input);
      expect(result, equals('"Toko" \'Kopi\' - Es Teh - Rp 15.000'));
    });

    test('sanitizeAscii replaces unrecognized non-ASCII characters with spaces', () {
      const input = 'Harga 🚀 Rp 5.000';
      final result = EscPosGenerator.sanitizeAscii(input);
      expect(result.contains('🚀'), isFalse);
      expect(result.contains('Rp 5.000'), isTrue);
    });

    test('wordWrap wraps text properly at word boundaries', () {
      const text = 'Nasi Goreng Spesial Telur Ceplok Pedas Manis';
      final lines = EscPosGenerator.wordWrap(text, 20);

      for (final line in lines) {
        expect(line.length, lessThanOrEqualTo(20));
      }
      expect(lines.join(' '), equals(text));
    });

    test('wordWrap splits excessively long single words', () {
      const longWord = 'Supercalifragilisticexpialidocious';
      final lines = EscPosGenerator.wordWrap(longWord, 10);

      expect(lines.length, greaterThan(1));
      for (final line in lines) {
        expect(line.length, lessThanOrEqualTo(10));
      }
      expect(lines.join(''), equals(longWord));
    });

    test('formatRow2 aligns left and right text to exact width (32 cols)', () {
      final line = EscPosGenerator.formatRow2('Kopi Susu', '15.000', 32);
      expect(line.length, equals(32));
      expect(line.startsWith('Kopi Susu'), isTrue);
      expect(line.endsWith('15.000'), isTrue);
    });

    test('formatRow2 aligns left and right text to exact width (48 cols)', () {
      final line = EscPosGenerator.formatRow2('Paket Nasi Ayam Bakar Komplit', '35.000', 48);
      expect(line.length, equals(48));
      expect(line.startsWith('Paket Nasi Ayam Bakar Komplit'), isTrue);
      expect(line.endsWith('35.000'), isTrue);
    });

    test('formatDivider produces correct length of character separator', () {
      expect(EscPosGenerator.formatDivider(32), equals('-' * 32));
      expect(EscPosGenerator.formatDivider(48, '='), equals('=' * 48));
    });
  });

  group('EscPosGenerator - Hardware Command Bytes', () {
    test('cmdOpenDrawer generates valid ESC p pulse for pin 0 and pin 1', () {
      final pin0 = EscPosGenerator.cmdOpenDrawer(pin: 0);
      expect(pin0, equals([0x1B, 0x70, 0x00, 0x19, 0xFA]));

      final pin1 = EscPosGenerator.cmdOpenDrawer(pin: 1);
      expect(pin1, equals([0x1B, 0x70, 0x01, 0x19, 0xFA]));
    });

    test('cmdFeed clamps lines and generates ESC d command', () {
      expect(EscPosGenerator.cmdFeed(3), equals([0x1B, 0x64, 3]));
      expect(EscPosGenerator.cmdFeed(0), equals([0x1B, 0x64, 1])); // clamped to 1
      expect(EscPosGenerator.cmdFeed(300), equals([0x1B, 0x64, 255])); // clamped to 255
    });

    test('constants for cut commands match standard ESC/POS', () {
      expect(EscPosGenerator.cmdCutFull, equals([0x1D, 0x56, 0x00]));
      expect(EscPosGenerator.cmdCutPartial, equals([0x1D, 0x56, 0x01]));
    });
  });

  group('EscPosGenerator - Receipt Generation', () {
    late ReceiptData sampleReceipt;

    setUp(() {
      sampleReceipt = ReceiptData(
        storeName: 'TOKO MAJU JAYA',
        storeAddress: 'Jl. Sudirman No. 10 Jakarta',
        storePhone: '08123456789',
        invoiceNo: 'INV/20261013/0001',
        cashierName: 'Budi Santoso',
        dateTime: DateTime(2026, 10, 13, 14, 30),
        items: const [
          ReceiptItemData(
            name: 'Kopi Susu Gula Aren Dingin',
            qty: 2,
            price: 18000,
            discount: 1000,
            subtotal: 34000,
          ),
          ReceiptItemData(
            name: 'Croissant Cokelat',
            qty: 1,
            price: 25000,
            discount: 0,
            subtotal: 25000,
          ),
        ],
        subtotal: 61000,
        discount: 2000,
        total: 59000,
        paid: 100000,
        change: 41000,
        payments: const [
          ReceiptPaymentData(method: 'cash', amount: 100000),
        ],
        footerNotes: 'Terima kasih telah berbelanja!',
      );
    });

    test('generates valid 32 column receipt bytes with partial cut and drawer', () {
      const generator = EscPosGenerator(charsPerLine: 32);
      final bytes = generator.generateReceipt(
        sampleReceipt,
        cutMode: CutMode.partial,
        feedLines: 4,
        openDrawer: true,
        drawerPin: 0,
      );

      expect(bytes, isNotEmpty);

      // Inisialisasi printer
      expect(bytes.sublist(0, 2), equals(EscPosGenerator.cmdInit));

      // Ada perintah drawer
      final drawerCmd = EscPosGenerator.cmdOpenDrawer(pin: 0);
      expect(latin1.decode(bytes).contains(latin1.decode(drawerCmd)), isTrue);

      // Decoding teks mengandung nama toko dan invoice
      final text = latin1.decode(bytes);
      expect(text.contains('TOKO MAJU JAYA'), isTrue);
      expect(text.contains('INV/20261013/0001'), isTrue);
      expect(text.contains('Budi Santoso'), isTrue);
      expect(text.contains('Kopi Susu Gula Aren Dingin'), isTrue);
      expect(text.contains('Croissant Cokelat'), isTrue);
      expect(text.contains('59.000'), isTrue);
      expect(text.contains('100.000'), isTrue);
      expect(text.contains('41.000'), isTrue);
      expect(text.contains('Terima kasih telah berbelanja!'), isTrue);

      // Mengandung perintah cut partial
      expect(bytes.contains(0x1D) && bytes.contains(0x56) && bytes.contains(0x01), isTrue);
    });

    test('generates valid 48 column receipt bytes with full cut without drawer', () {
      const generator = EscPosGenerator(charsPerLine: 48);
      final bytes = generator.generateReceipt(
        sampleReceipt,
        cutMode: CutMode.full,
        feedLines: 3,
        openDrawer: false,
      );

      final text = latin1.decode(bytes);
      expect(text.contains('TOKO MAJU JAYA'), isTrue);
      expect(text.contains('INV/20261013/0001'), isTrue);

      // Tidak ada perintah drawer
      final drawerCmd = EscPosGenerator.cmdOpenDrawer(pin: 0);
      expect(text.contains(latin1.decode(drawerCmd)), isFalse);

      // Mengandung perintah cut full
      expect(bytes.contains(0x1D) && bytes.contains(0x56) && bytes.contains(0x00), isTrue);
    });

    test('generates test print with ruler for 32 columns', () {
      const generator = EscPosGenerator(charsPerLine: 32);
      final bytes = generator.generateTestPrint(
        cutMode: CutMode.partial,
        feedLines: 2,
        openDrawer: false,
      );

      final text = latin1.decode(bytes);
      expect(text.contains('TES PRINTER POS'), isTrue);
      expect(text.contains('32 Kolom'), isTrue);
      expect(text.contains('PENGGARIS LEBAR:'), isTrue);

      // Ruler 1..32 digit terakhir
      final expectedRuler = List.generate(32, (i) => ((i + 1) % 10).toString()).join();
      expect(text.contains(expectedRuler), isTrue);
    });

    test('generates test print with ruler for 48 columns', () {
      const generator = EscPosGenerator(charsPerLine: 48);
      final bytes = generator.generateTestPrint(
        cutMode: CutMode.none,
        feedLines: 2,
        openDrawer: true,
        drawerPin: 1,
      );

      final text = latin1.decode(bytes);
      expect(text.contains('48 Kolom'), isTrue);

      final expectedRuler = List.generate(48, (i) => ((i + 1) % 10).toString()).join();
      expect(text.contains(expectedRuler), isTrue);
      expect(text.contains('Aktif (Pin 1)'), isTrue);
    });
  });
}

