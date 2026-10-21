import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../data/local/app_database.dart';
import '../../printing/receipt_data.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/date_formatter.dart';

/// Service untuk menghasilkan PDF struk belanja kasir (thermal 58 mm / 80 mm)
class ReceiptPdfService {
  /// Menghasilkan file PDF struk belanja dari entitas database Drift (kompatibilitas Prompt 9)
  static Future<Uint8List> generateReceiptPdf({
    required Store? store,
    required String cashierName,
    required Sale sale,
    required List<SaleItem> items,
    required List<Payment> payments,
    String receiptWidth = '58', // '58' | '80'
  }) async {
    final receiptData = ReceiptData(
      storeName: store?.name.toUpperCase() ?? 'POS TOKO UMKM',
      storeAddress: store?.address,
      storePhone: store?.phone,
      invoiceNo: sale.invoiceNo,
      cashierName: cashierName,
      dateTime: sale.createdAt,
      items: items.map((item) {
        return ReceiptItemData(
          name: item.productName,
          qty: item.qty,
          price: item.price,
          discount: item.discount,
          subtotal: item.subtotal,
        );
      }).toList(),
      subtotal: sale.subtotal,
      discount: sale.discount,
      total: sale.total,
      paid: sale.paid,
      change: sale.change,
      payments: payments.map((p) {
        return ReceiptPaymentData(
          method: p.method,
          amount: p.amount,
        );
      }).toList(),
    );

    return generateFromReceiptData(receiptData, receiptWidth: receiptWidth);
  }

  /// Menghasilkan file PDF struk belanja dari model netral [ReceiptData]
  static Future<Uint8List> generateFromReceiptData(
    ReceiptData data, {
    String receiptWidth = '58',
  }) async {
    final pdf = pw.Document();

    final is80mm = receiptWidth == '80';
    final double widthInMm = is80mm ? 80.0 : 58.0;

    // Font size & line configuration
    final double headerFontSize = is80mm ? 11.0 : 9.5;
    final double bodyFontSize = is80mm ? 8.5 : 7.2;
    final double smallFontSize = is80mm ? 7.5 : 6.5;

    // Estimasi tinggi kertas roll secara dinamis agar pas dan tidak terpotong
    final double estimatedHeight = 90.0 +
        (data.items.length * (is80mm ? 12.0 : 10.5)) +
        (data.payments.length * 6.5) +
        55.0;

    final pageFormat = PdfPageFormat(
      widthInMm * PdfPageFormat.mm,
      estimatedHeight * PdfPageFormat.mm,
      marginAll: 2.5 * PdfPageFormat.mm,
    );

    final fontRegular = pw.Font.courier();
    final fontBold = pw.Font.courierBold();

    final dividerText = is80mm
        ? '--------------------------------------------'
        : '--------------------------------';

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // 1. Header Toko
              pw.Center(
                child: pw.Text(
                  data.storeName.toUpperCase(),
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    font: fontBold,
                    fontSize: headerFontSize,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              if (data.storeAddress != null && data.storeAddress!.isNotEmpty) ...[
                pw.SizedBox(height: 1),
                pw.Center(
                  child: pw.Text(
                    data.storeAddress!,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: fontRegular, fontSize: smallFontSize),
                  ),
                ),
              ],
              if (data.storePhone != null && data.storePhone!.isNotEmpty) ...[
                pw.SizedBox(height: 1),
                pw.Center(
                  child: pw.Text(
                    'Telp: ${data.storePhone!}',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: fontRegular, fontSize: smallFontSize),
                  ),
                ),
              ],

              // Divider
              pw.SizedBox(height: 3),
              pw.Center(
                child: pw.Text(dividerText, style: pw.TextStyle(font: fontRegular, fontSize: smallFontSize)),
              ),
              if (data.isReturn) ...[
                pw.SizedBox(height: 2),
                pw.Center(
                  child: pw.Text(
                    '*** BUKTI RETUR PENJUALAN ***',
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: bodyFontSize,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.Center(
                  child: pw.Text(dividerText, style: pw.TextStyle(font: fontRegular, fontSize: smallFontSize)),
                ),
              ] else if (data.isReprint) ...[
                pw.SizedBox(height: 2),
                pw.Center(
                  child: pw.Text(
                    '*** SALINAN ***',
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: bodyFontSize,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.Center(
                  child: pw.Text(dividerText, style: pw.TextStyle(font: fontRegular, fontSize: smallFontSize)),
                ),
              ],
              pw.SizedBox(height: 2),

              // 2. Metadata Invoice / Return
              if (data.isReturn) ...[
                _buildTwoCol('No. Retur', data.returnNo ?? data.invoiceNo, fontRegular, fontBold, bodyFontSize),
                if (data.originInvoiceNo != null)
                  _buildTwoCol('Nota Asal', data.originInvoiceNo!, fontRegular, fontRegular, bodyFontSize),
              ] else
                _buildTwoCol('No. Inv', data.invoiceNo, fontRegular, fontBold, bodyFontSize),
              _buildTwoCol('Kasir', data.cashierName, fontRegular, fontRegular, bodyFontSize),
              _buildTwoCol('Waktu', DateFormatter.formatDateTime(data.dateTime), fontRegular, fontRegular, bodyFontSize),

              // Divider
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(dividerText, style: pw.TextStyle(font: fontRegular, fontSize: smallFontSize)),
              ),
              pw.SizedBox(height: 2),

              // 3. Daftar Item Penjualan
              ...data.items.map((item) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 2.5),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      // Nama Produk
                      pw.Text(
                        item.name,
                        style: pw.TextStyle(font: fontBold, fontSize: bodyFontSize, fontWeight: pw.FontWeight.bold),
                        maxLines: 1,
                        overflow: pw.TextOverflow.clip,
                      ),
                      // Qty x Harga & Subtotal
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            '${item.qty} x ${formatRupiah(item.price)}',
                            style: pw.TextStyle(font: fontRegular, fontSize: bodyFontSize),
                          ),
                          pw.Text(
                            formatRupiah(item.subtotal),
                            style: pw.TextStyle(font: fontBold, fontSize: bodyFontSize),
                          ),
                        ],
                      ),
                      if (data.isReturn && !item.restock)
                        pw.Text(
                          '  (Barang Rusak - Tidak Restock)',
                          style: pw.TextStyle(font: fontRegular, fontSize: smallFontSize, fontStyle: pw.FontStyle.italic),
                        ),
                      // Diskon item jika ada
                      if (item.discount > 0)
                        pw.Text(
                          '  (Diskon: -${formatRupiah(item.discount * item.qty)})',
                          style: pw.TextStyle(font: fontRegular, fontSize: smallFontSize),
                        ),
                    ],
                  ),
                );
              }),

              // Divider
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(dividerText, style: pw.TextStyle(font: fontRegular, fontSize: smallFontSize)),
              ),
              pw.SizedBox(height: 2),

              // 4. Ringkasan Keuangan
              _buildTwoCol(
                data.isReturn ? 'Subtotal Retur' : 'Subtotal',
                formatRupiah(data.subtotal),
                fontRegular,
                fontRegular,
                bodyFontSize,
              ),
              if (data.discount > 0)
                _buildTwoCol('Diskon', '-${formatRupiah(data.discount)}', fontRegular, fontRegular, bodyFontSize),
              if (data.tax > 0)
                _buildTwoCol(
                  data.isReturn
                      ? 'Pajak Dikembalikan'
                      : '${data.taxName ?? 'PPN'}${data.taxRatePercentString.isNotEmpty ? ' (${data.taxRatePercentString})' : ''}',
                  formatRupiah(data.tax),
                  fontRegular,
                  fontRegular,
                  bodyFontSize,
                ),

              pw.SizedBox(height: 2),
              _buildTwoCol(
                data.isReturn ? 'TOTAL REFUND' : 'TOTAL',
                formatRupiah(data.total),
                fontBold,
                fontBold,
                bodyFontSize + 1.5,
              ),
              if (data.isReturn && data.returnReason != null && data.returnReason!.isNotEmpty)
                _buildTwoCol('Alasan', data.returnReason!, fontRegular, fontRegular, smallFontSize),
              if (data.tax > 0 && data.taxMode == 'inclusive' && !data.isReturn) ...[
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    '(Termasuk ${data.taxName ?? 'PPN'}${data.taxRatePercentString.isNotEmpty ? ' ${data.taxRatePercentString}' : ''})',
                    style: pw.TextStyle(font: fontRegular, fontSize: smallFontSize, fontStyle: pw.FontStyle.italic),
                  ),
                ),
              ],

              pw.SizedBox(height: 3),
              // Pembayaran
              ...data.payments.map((p) {
                final label = 'Bayar (${p.method.toUpperCase()})';
                return _buildTwoCol(label, formatRupiah(p.amount), fontRegular, fontRegular, bodyFontSize);
              }),

              _buildTwoCol('Kembalian', formatRupiah(data.change), fontBold, fontBold, bodyFontSize),

              // Divider
              pw.SizedBox(height: 3),
              pw.Center(
                child: pw.Text(dividerText, style: pw.TextStyle(font: fontRegular, fontSize: smallFontSize)),
              ),
              pw.SizedBox(height: 3),

              // 5. Footer
              pw.Center(
                child: pw.Text(
                  data.footerNotes != null && data.footerNotes!.trim().isNotEmpty
                      ? data.footerNotes!
                      : 'Terima Kasih Atas Kunjungan Anda!',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: fontBold, fontSize: smallFontSize + 0.5),
                ),
              ),
              pw.SizedBox(height: 1),
              pw.Center(
                child: pw.Text(
                  'Barang yang dibeli tidak dapat ditukar/dikembalikan',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: fontRegular, fontSize: smallFontSize - 0.5),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildTwoCol(
    String left,
    String right,
    pw.Font leftFont,
    pw.Font rightFont,
    double fontSize,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 0.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(left, style: pw.TextStyle(font: leftFont, fontSize: fontSize)),
          pw.Text(right, style: pw.TextStyle(font: rightFont, fontSize: fontSize)),
        ],
      ),
    );
  }
}
