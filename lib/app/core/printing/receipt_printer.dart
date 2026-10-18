import 'receipt_data.dart';

class PrintResult {
  final bool success;
  final String? message;
  final String? error;
  final bool isFallbackPdf;

  const PrintResult({
    required this.success,
    this.message,
    this.error,
    this.isFallbackPdf = false,
  });

  factory PrintResult.ok({String? message}) =>
      PrintResult(success: true, message: message ?? 'Pencetakan berhasil.');

  factory PrintResult.failure(String error, {bool isFallbackPdf = false}) =>
      PrintResult(success: false, error: error, isFallbackPdf: isFallbackPdf);
}

abstract class ReceiptPrinter {
  Future<PrintResult> printReceipt(ReceiptData data);
  Future<PrintResult> printTest();
  Future<void> openCashDrawer();
}

