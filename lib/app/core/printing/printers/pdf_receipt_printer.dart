import 'package:printing/printing.dart';

import '../../services/pdf/receipt_pdf_service.dart';
import '../receipt_data.dart';
import '../receipt_printer.dart';

/// Implementasi ReceiptPrinter yang membungkus ReceiptPdfService sebagai fallback / opsi PDF
class PdfReceiptPrinter implements ReceiptPrinter {
  final String receiptWidth;

  const PdfReceiptPrinter({this.receiptWidth = '58'});

  @override
  Future<PrintResult> printReceipt(ReceiptData data) async {
    try {
      final pdfBytes = await ReceiptPdfService.generateFromReceiptData(
        data,
        receiptWidth: receiptWidth,
      );

      final printSuccess = await Printing.layoutPdf(
        name: 'Struk_${data.invoiceNo}.pdf',
        onLayout: (_) async => pdfBytes,
      );

      if (printSuccess) {
        return const PrintResult(
          success: true,
          message: 'Struk berhasil dicetak / disimpan via PDF.',
          isFallbackPdf: true,
        );
      } else {
        return const PrintResult(
          success: false,
          error: 'Pencetakan PDF dibatalkan oleh pengguna.',
          isFallbackPdf: true,
        );
      }
    } catch (e) {
      return PrintResult.failure(
        'Gagal memproses struk PDF: $e',
        isFallbackPdf: true,
      );
    }
  }

  @override
  Future<PrintResult> printTest() async {
    final testData = ReceiptData(
      storeName: 'TOKO UJI COBA (PDF)',
      storeAddress: 'Jl. Percobaan No. 123',
      storePhone: '081234567890',
      invoiceNo: 'INV-TEST-0001',
      cashierName: 'Kasir Uji',
      dateTime: DateTime.now(),
      items: const [
        ReceiptItemData(
          name: 'Produk Uji Coba 1',
          qty: 1,
          price: 15000,
          subtotal: 15000,
        ),
        ReceiptItemData(
          name: 'Produk Uji Coba 2',
          qty: 2,
          price: 10000,
          discount: 2000,
          subtotal: 18000,
        ),
      ],
      subtotal: 35000,
      discount: 2000,
      total: 33000,
      paid: 50000,
      change: 17000,
      payments: const [
        ReceiptPaymentData(method: 'cash', amount: 50000),
      ],
      footerNotes: 'Ini adalah cetak uji coba struk PDF.',
    );

    return printReceipt(testData);
  }

  @override
  Future<void> openCashDrawer() async {
    // Printer PDF virtual tidak memiliki port RJ11 fisik untuk laci kasir
  }
}

