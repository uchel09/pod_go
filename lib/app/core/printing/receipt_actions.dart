import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'printer_manager.dart';
import 'receipt_data.dart';
import 'receipt_printer.dart';

/// Aksi struk yang dipakai bersama oleh kasir, layar sukses, dan riwayat.
///
/// Prinsip: struk hanyalah aksi TAMBAHAN setelah transaksi tersimpan. Semua fungsi di
/// sini tidak pernah melempar exception dan tidak pernah memengaruhi data transaksi;
/// kegagalan dilaporkan lewat [PrintResult] dan snackbar non-blocking (bukan dialog).
class ReceiptActions {
  ReceiptActions._();

  static PrinterManager? get _manager =>
      Get.isRegistered<PrinterManager>() ? PrinterManager.to : null;

  /// Mencetak [data] lewat printer aktif.
  ///
  /// Bila gagal dan [notifyFailure] true, tampil snackbar dengan tombol
  /// "Coba lagi" dan "Simpan PDF". Transaksi tidak terpengaruh.
  static Future<PrintResult> print(ReceiptData data, {bool notifyFailure = true}) async {
    final manager = _manager;
    PrintResult result;
    if (manager == null) {
      result = PrintResult.failure('Layanan printer belum siap.');
    } else {
      try {
        result = await manager.printReceipt(data);
      } catch (e) {
        result = PrintResult.failure('$e');
      }
    }

    if (!result.success && notifyFailure) {
      showPrintFailure(data, result.error);
    }
    return result;
  }

  /// Membuat PDF struk dan membagikan/menyimpannya. Tidak menyentuh printer thermal.
  static Future<PrintResult> savePdf(ReceiptData data, {bool notifyFailure = true}) async {
    final manager = _manager;
    PrintResult result;
    if (manager == null) {
      result = PrintResult.failure('Layanan printer belum siap.', isFallbackPdf: true);
    } else {
      try {
        result = await manager.savePdf(data);
      } catch (e) {
        result = PrintResult.failure('$e', isFallbackPdf: true);
      }
    }

    if (!result.success && notifyFailure && _canShowOverlay) {
      Get.snackbar(
        'Simpan PDF gagal',
        result.error ?? 'Struk PDF tidak dapat dibuat.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade800,
        colorText: Colors.white,
        margin: const EdgeInsets.all(16),
      );
    }
    return result;
  }

  /// Snackbar kegagalan cetak: transaksi tetap tersimpan, ada "Coba lagi" & "Simpan PDF".
  static void showPrintFailure(ReceiptData data, String? error) {
    if (!_canShowOverlay) return;
    if (Get.isSnackbarOpen) Get.closeCurrentSnackbar();

    Get.showSnackbar(
      GetSnackBar(
        titleText: const Text(
          'Struk gagal dicetak',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        messageText: Text(
          'Transaksi ${data.invoiceNo} tetap tersimpan. ${error ?? ''}'.trim(),
          style: const TextStyle(color: Colors.white),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Colors.red.shade800,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(16),
        borderRadius: 8,
        duration: const Duration(seconds: 10),
        isDismissible: true,
        mainButton: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () {
                Get.closeCurrentSnackbar();
                print(data);
              },
              child: const Text('Coba lagi', style: TextStyle(color: Colors.white)),
            ),
            TextButton(
              onPressed: () {
                Get.closeCurrentSnackbar();
                savePdf(data);
              },
              child: const Text('Simpan PDF', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  /// Snackbar mode "never": "Transaksi tersimpan" + tombol "Cetak" kecil beberapa detik.
  static void showSavedWithPrintOption(ReceiptData data, {Duration duration = const Duration(seconds: 6)}) {
    if (!_canShowOverlay) return;
    if (Get.isSnackbarOpen) Get.closeCurrentSnackbar();

    Get.showSnackbar(
      GetSnackBar(
        titleText: const Text(
          'Transaksi tersimpan',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        messageText: Text(
          data.invoiceNo,
          style: const TextStyle(color: Colors.white70),
        ),
        backgroundColor: Colors.green.shade700,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(16),
        borderRadius: 8,
        duration: duration,
        isDismissible: true,
        mainButton: TextButton(
          onPressed: () {
            Get.closeCurrentSnackbar();
            print(data);
          },
          child: const Text('Cetak', style: TextStyle(color: Colors.white)),
        ),
      ),
    );
  }

  /// Snackbar hanya aman ditampilkan bila ada overlay (tidak di unit test / saat startup).
  static bool get _canShowOverlay => Get.context != null && Get.overlayContext != null;
}

