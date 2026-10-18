import 'dart:typed_data';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../data/local/app_database.dart';
import '../../utils/currency_formatter.dart';

/// Format barcode yang didukung pada label
enum LabelBarcodeFormat {
  code128,
  qr,
}

/// Template ukuran label yang disediakan
enum LabelTemplateType {
  roll3Col40x20, // 3 kolom 40x20 mm
  roll2Col50x30, // 2 kolom 50x30 mm
  a4Grid,        // A4 grid bebas (3 kolom x 8 baris)
}

/// Item produk beserta jumlah cetakan
class LabelPrintItem {
  final Product product;
  final int copies;

  const LabelPrintItem({
    required this.product,
    this.copies = 1,
  });
}

/// Service untuk menghasilkan PDF label barcode multi-halaman
class LabelPdfService {
  /// Memeriksa apakah ada barcode yang berpotensi terlalu panjang untuk template tertentu
  static List<String> checkWarnings({
    required List<LabelPrintItem> items,
    required LabelTemplateType template,
    required LabelBarcodeFormat format,
  }) {
    final warnings = <String>[];
    if (format == LabelBarcodeFormat.code128 && template == LabelTemplateType.roll3Col40x20) {
      for (final item in items) {
        if (item.copies <= 0) continue;
        final code = item.product.barcode ?? item.product.internalCode ?? '';
        if (code.length > 12) {
          warnings.add(
            'Produk "${item.product.name}" memiliki kode "$code" (${code.length} karakter). '
            'Barcode Code128 berisiko terlalu rapat pada label 40x20 mm. Disarankan memakai template 50x30 mm atau format QR.',
          );
        }
      }
    }
    return warnings;
  }

  /// Menghasilkan file PDF dalam bentuk [Uint8List]
  static Future<Uint8List> generatePdf({
    required List<LabelPrintItem> items,
    required LabelTemplateType template,
    required LabelBarcodeFormat format,
    bool showPrice = true,
  }) async {
    final pdf = pw.Document();

    // Flatten daftar produk sesuai jumlah salinan masing-masing
    final flatProducts = <Product>[];
    for (final item in items) {
      if (item.copies > 0) {
        for (int i = 0; i < item.copies; i++) {
          flatProducts.add(item.product);
        }
      }
    }

    if (flatProducts.isEmpty) {
      // Buat dokumen kosong dengan pesan
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) => pw.Center(
            child: pw.Text('Tidak ada produk yang dipilih untuk dicetak.'),
          ),
        ),
      );
      return pdf.save();
    }

    switch (template) {
      case LabelTemplateType.roll3Col40x20:
        _buildRoll3Col40x20(pdf, flatProducts, format, showPrice);
        break;
      case LabelTemplateType.roll2Col50x30:
        _buildRoll2Col50x30(pdf, flatProducts, format, showPrice);
        break;
      case LabelTemplateType.a4Grid:
        _buildA4Grid(pdf, flatProducts, format, showPrice);
        break;
    }

    return pdf.save();
  }

  /// Template 1: 3 Kolom 40x20 mm (Roll 3-up continuous)
  static void _buildRoll3Col40x20(
    pw.Document pdf,
    List<Product> products,
    LabelBarcodeFormat format,
    bool showPrice,
  ) {
    const double labelWidth = 40 * PdfPageFormat.mm;
    const double labelHeight = 20 * PdfPageFormat.mm;
    const double colGap = 2 * PdfPageFormat.mm;
    const double sideMargin = 2 * PdfPageFormat.mm;
    const double pageWidth = (labelWidth * 3) + (colGap * 2) + (sideMargin * 2);
    const double pageHeight = labelHeight + (1 * PdfPageFormat.mm);

    final pageFormat = PdfPageFormat(
      pageWidth,
      pageHeight,
      marginAll: 0,
    );

    const int cols = 3;
    final totalRows = (products.length / cols).ceil();

    for (int r = 0; r < totalRows; r++) {
      final startIndex = r * cols;
      final rowProducts = products.sublist(
        startIndex,
        (startIndex + cols > products.length) ? products.length : startIndex + cols,
      );

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          build: (context) {
            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: sideMargin,
                vertical: 0.5 * PdfPageFormat.mm,
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: List.generate(cols, (colIndex) {
                  if (colIndex < rowProducts.length) {
                    return _buildSingleLabel(
                      product: rowProducts[colIndex],
                      width: labelWidth,
                      height: labelHeight,
                      format: format,
                      showPrice: showPrice,
                      isCompact: true,
                    );
                  }
                  return pw.SizedBox(width: labelWidth, height: labelHeight);
                }),
              ),
            );
          },
        ),
      );
    }
  }

  /// Template 2: 2 Kolom 50x30 mm (Roll 2-up continuous)
  static void _buildRoll2Col50x30(
    pw.Document pdf,
    List<Product> products,
    LabelBarcodeFormat format,
    bool showPrice,
  ) {
    const double labelWidth = 50 * PdfPageFormat.mm;
    const double labelHeight = 30 * PdfPageFormat.mm;
    const double colGap = 3 * PdfPageFormat.mm;
    const double sideMargin = 2 * PdfPageFormat.mm;
    const double pageWidth = (labelWidth * 2) + colGap + (sideMargin * 2);
    const double pageHeight = labelHeight + (1.5 * PdfPageFormat.mm);

    final pageFormat = PdfPageFormat(
      pageWidth,
      pageHeight,
      marginAll: 0,
    );

    const int cols = 2;
    final totalRows = (products.length / cols).ceil();

    for (int r = 0; r < totalRows; r++) {
      final startIndex = r * cols;
      final rowProducts = products.sublist(
        startIndex,
        (startIndex + cols > products.length) ? products.length : startIndex + cols,
      );

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          build: (context) {
            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: sideMargin,
                vertical: 0.75 * PdfPageFormat.mm,
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: List.generate(cols, (colIndex) {
                  if (colIndex < rowProducts.length) {
                    return _buildSingleLabel(
                      product: rowProducts[colIndex],
                      width: labelWidth,
                      height: labelHeight,
                      format: format,
                      showPrice: showPrice,
                      isCompact: false,
                    );
                  }
                  return pw.SizedBox(width: labelWidth, height: labelHeight);
                }),
              ),
            );
          },
        ),
      );
    }
  }

  /// Template 3: A4 Grid Bebas (3 kolom x 8 baris = 24 label per halaman)
  static void _buildA4Grid(
    pw.Document pdf,
    List<Product> products,
    LabelBarcodeFormat format,
    bool showPrice,
  ) {
    const int cols = 3;
    const int rows = 8;
    const int labelsPerPage = cols * rows;

    const double labelWidth = 60 * PdfPageFormat.mm;
    const double labelHeight = 32 * PdfPageFormat.mm;

    final totalPages = (products.length / labelsPerPage).ceil();

    for (int p = 0; p < totalPages; p++) {
      final pageStartIndex = p * labelsPerPage;
      final pageProducts = products.sublist(
        pageStartIndex,
        (pageStartIndex + labelsPerPage > products.length)
            ? products.length
            : pageStartIndex + labelsPerPage,
      );

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(10 * PdfPageFormat.mm),
          build: (context) {
            return pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.start,
              children: List.generate(rows, (rowIndex) {
                final rowStartIndex = rowIndex * cols;
                return pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 2.5 * PdfPageFormat.mm),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: List.generate(cols, (colIndex) {
                      final itemIndex = rowStartIndex + colIndex;
                      if (itemIndex < pageProducts.length) {
                        return _buildSingleLabel(
                          product: pageProducts[itemIndex],
                          width: labelWidth,
                          height: labelHeight,
                          format: format,
                          showPrice: showPrice,
                          isCompact: false,
                          hasBorder: true,
                        );
                      }
                      return pw.SizedBox(width: labelWidth, height: labelHeight);
                    }),
                  ),
                );
              }),
            );
          },
        ),
      );
    }
  }

  /// Membangun 1 kotak label individual
  static pw.Widget _buildSingleLabel({
    required Product product,
    required double width,
    required double height,
    required LabelBarcodeFormat format,
    required bool showPrice,
    required bool isCompact,
    bool hasBorder = false,
  }) {
    final code = product.barcode ?? product.internalCode ?? '-';

    // Pengaturan font & dimensi berdasarkan ukuran label
    final double titleFontSize = isCompact ? 6.5 : 8.5;
    final double priceFontSize = isCompact ? 6.0 : 8.0;
    final double codeFontSize = isCompact ? 5.5 : 7.0;

    final double barcodeHeight = isCompact ? (showPrice ? 7.5 * PdfPageFormat.mm : 9.5 * PdfPageFormat.mm) : (showPrice ? 12.0 * PdfPageFormat.mm : 14.5 * PdfPageFormat.mm);
    final double qrSize = isCompact ? (showPrice ? 9.0 * PdfPageFormat.mm : 11.0 * PdfPageFormat.mm) : (showPrice ? 14.0 * PdfPageFormat.mm : 17.0 * PdfPageFormat.mm);

    return pw.Container(
      width: width,
      height: height,
      padding: pw.EdgeInsets.symmetric(
        horizontal: isCompact ? 2.5 * PdfPageFormat.mm : 3.5 * PdfPageFormat.mm,
        vertical: 1.5 * PdfPageFormat.mm,
      ),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: hasBorder ? pw.Border.all(color: PdfColors.grey300, width: 0.5) : null,
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Nama Produk (Dipotong rapi)
          pw.Text(
            product.name,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: titleFontSize,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),

          // Harga Produk (opsional)
          if (showPrice)
            pw.Text(
              formatRupiah(product.sellPrice),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: priceFontSize,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),

          // Barcode / QR Code dengan Quiet Zone kiri-kanan
          if (format == LabelBarcodeFormat.code128) ...[
            pw.Container(
              height: barcodeHeight,
              width: width - (isCompact ? 6.0 * PdfPageFormat.mm : 8.0 * PdfPageFormat.mm),
              child: pw.BarcodeWidget(
                barcode: Barcode.code128(),
                data: code,
                color: PdfColors.black,
                drawText: false,
              ),
            ),
          ] else ...[
            pw.Container(
              height: qrSize,
              width: qrSize,
              child: pw.BarcodeWidget(
                barcode: Barcode.qrCode(),
                data: code,
                color: PdfColors.black,
                drawText: false,
              ),
            ),
          ],

          // Teks Kode di bawah barcode
          pw.Text(
            code,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: pw.Font.courier(),
              fontSize: codeFontSize,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }
}
