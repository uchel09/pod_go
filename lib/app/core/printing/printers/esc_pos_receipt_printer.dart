import 'dart:async';
import '../esc_pos_generator.dart';
import '../printer_transport.dart';
import '../receipt_data.dart';
import '../receipt_printer.dart';

/// Implementasi ReceiptPrinter untuk printer thermal ESC/POS hardware
class EscPosReceiptPrinter implements ReceiptPrinter {
  final PrinterTransport transport;
  final EscPosGenerator generator;
  final CutMode cutMode;
  final int feedLines;
  final bool openDrawer;
  final int drawerPin;
  final int copies;

  // Antrean eksekusi agar dua cetakan tidak saling bertabrakan
  static Future<void> _lastJob = Future.value();

  EscPosReceiptPrinter({
    required this.transport,
    required this.generator,
    this.cutMode = CutMode.partial,
    this.feedLines = 3,
    this.openDrawer = false,
    this.drawerPin = 0,
    this.copies = 1,
  });

  /// Mengantrekan aksi cetak secara serial
  Future<T> _enqueue<T>(Future<T> Function() job) {
    final completer = Completer<T>();
    _lastJob = _lastJob.then((_) async {
      try {
        final result = await job();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  @override
  Future<PrintResult> printReceipt(ReceiptData data) {
    return _enqueue(() async {
      final bytes = generator.generateReceipt(
        data,
        cutMode: cutMode,
        feedLines: feedLines,
        openDrawer: openDrawer,
        drawerPin: drawerPin,
      );

      return await _sendBytesWithRetry(bytes);
    });
  }

  @override
  Future<PrintResult> printTest() {
    return _enqueue(() async {
      final bytes = generator.generateTestPrint(
        cutMode: cutMode,
        feedLines: feedLines,
        openDrawer: openDrawer,
        drawerPin: drawerPin,
      );

      return await _sendBytesWithRetry(bytes);
    });
  }

  @override
  Future<void> openCashDrawer() {
    return _enqueue(() async {
      final bytes = [
        ...EscPosGenerator.cmdInit,
        ...EscPosGenerator.cmdOpenDrawer(pin: drawerPin),
      ];
      await _sendBytesWithRetry(bytes);
    });
  }

  /// Mengirim bytes ke transport dengan auto-reconnect 1x sebelum gagal
  Future<PrintResult> _sendBytesWithRetry(List<int> bytes) async {
    final effectiveCopies = copies.clamp(1, 5);
    final allBytes = <int>[];
    for (int i = 0; i < effectiveCopies; i++) {
      allBytes.addAll(bytes);
    }

    try {
      // Upaya 1: Pastikan koneksi terbuka
      if (!transport.isConnected) {
        await transport.connect();
      }
      await transport.write(allBytes);
      return PrintResult.ok(message: 'Struk berhasil dicetak ke printer thermal.');
    } catch (e1) {
      // Reconnect 1x sebelum menyerah
      try {
        await transport.disconnect();
        await Future.delayed(const Duration(milliseconds: 300));
        await transport.connect();
        await transport.write(allBytes);
        return PrintResult.ok(message: 'Struk berhasil dicetak setelah reconnect.');
      } catch (e2) {
        return PrintResult.failure(
          'Gagal mencetak ke printer thermal: $e2',
        );
      }
    }
  }
}
